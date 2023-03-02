#property copyright "Xefino"
#property version   "1.24"

#include <order-send-common-mt4/ServerSocket.mqh>
#include <order-send-common-mt4/TradeRequest.mqh>
#include <mql-http/Request.mqh>
#include <mql5-json/Json.mqh>

#define ERR_SOCKET_NOT_CREATED (2000)

#define HEARTBEAT_SECONDS (600)

// OrderReceiver
// Helper object that can be used to receive trade requests that were dispersed from a master node.
class OrderReceiver {
private:
   ServerSocket   *m_socket;        // The index of the socket we'll use to retrieve updates
   string         m_register_addr;  // The endpoint of the server we'll use to register the slave
   string         m_heartbeat_addr; // The endpoint of the server we'll send heartbeat requests to
   string         m_auth_header;    // The Authorization header to send with the request
   uint           m_port;           // The port number on which to receive data from the server
   string         m_partial;        // Partial payload received from previous calls
   datetime       m_last;           // The last time we sent an update to the heartbeat server

   // Helper function that updates the registry associated with this client
   //    enable:     Whether or not the registration should enabled or disabled
   int UpdateRegistry(const bool enable) const;

   // Helper function that splits the payload received into a number of segments that correspond to JSON
   // payloads. This function also updates the partial payload based off of what was left over. Note that
   // this function assumes the payload contains single-depth JSON.
   //    raw:        The raw data we received
   //    substrings: The list of strings that will contain our full payloads
   int SplitJSONPayload(const string raw, string &substrings[]);

public:

   // Creates a new order receiver object with the web address of the webserver from which we want to retrieve
   // trade requests and the port on which we should expect to receive such requests
   //    registerAddr:  The URL which will be used to register the slave
   //    heartbeatAddr: The URL format which will be used to send heartbeat requests
   //    port:          The port that should be opened to allow retrieval of trade requests (should not be port 80 or 443)
   OrderReceiver(const string registerAddr, const string heartbeatAddr, const ushort port, const string password);
   
   // Destroys this instance of the order receiver by deregistering the slave with the webserver and closing the
   // associated socket connection
   ~OrderReceiver();
   
   // Receive polls against the socket for trade request data and then populates that data into a number of trade
   // requests. This function will return 0 if it succeeded, or an error code otherwise
   //    requests:   The array of trade requests that should be populated
   int Receive(TradeRequest &requests[]);
   
   // Send an update to the server, letting them know that we're still there. This function will return zero if
   // the no error occurs, or a non-zero error code otherwise
   int Heartbeat();
};

// Creates a new order receiver object with the web address of the webserver from which we want to retrieve
// trade requests and the port on which we should expect to receive such requests
//    registerAddr:  The URL which will be used to register the slave
//    heartbeatAddr: The URL format which will be used to send heartbeat requests
//    port:          The port that should be opened to allow retrieval of trade requests (should not be port 80 or 443)
OrderReceiver::OrderReceiver(const string registerAddr, const string heartbeatAddr, const ushort port, const string password) {
   
   // First, create the base fields on the receiver
   m_register_addr = registerAddr;
   m_heartbeat_addr = StringFormat(heartbeatAddr, AccountInfoInteger(ACCOUNT_LOGIN), "MT4");
   m_port = port;
   m_auth_header = StringFormat("Bearer %s", password);
   m_partial = "";
   
   // Next, attempt to register the slave with the system; if this fails then log and return
   uint errCode = UpdateRegistry(true);
   if (errCode != 0) {
      Print("Failed to register client, error code: ", errCode);
      SetUserError((ushort)errCode);
      return;
   }
   
   // Now, attempt to create a server socket; if this fails then log and return. Otherwise,
   // check for a 4051 error. This is an artifact of some parameter-mismatch between our sockets
   // code and the winsock.h code and should be ignored as socket creation is verified by the
   // IsCreated function.
   m_socket = new ServerSocket(port, false);
   if (!m_socket.IsCreated()) {
      SetUserError(ERR_SOCKET_NOT_CREATED);
      Print("Failed to create socket to receive master trades");
      return;
   } else {
      int sockErrCode = GetLastError();
      if (sockErrCode == ERR_INVALID_FUNCTION_PARAMVALUE) {
         ResetLastError();
      }
   }
   
   // Finally, update the heartbeat time so we don't request a heartbeat immediately after starting
   m_last = TimeLocal();
}

// Destroys this instance of the order receiver by deregistering the slave with the webserver and closing the
// associated socket connection
OrderReceiver::~OrderReceiver() {
   UpdateRegistry(false);
   delete m_socket;
   m_socket = NULL;
}

// Receive polls against the socket for trade request data and then populates that data into a number of trade
// requests. This function will return 0 if it succeeded, or an error code otherwise
//    requests:   The array of trade requests that should be populated
int OrderReceiver::Receive(TradeRequest &requests[]) {
   do {
      ClientSocket *client = m_socket.Accept();
      if (client) {
         
         // First, attempt to receive data on the socket
         string result = client.Receive();
         
         // Next, attempt to split the payload based on our expected payload structure; if this fails then
         // print an error message and return
         string payloads[];
         int errCode = SplitJSONPayload(result, payloads);
         if (errCode != 0) {
            PrintFormat("Failed to split response into JSON payloads, error code: %d", errCode);
            return errCode;
         }
         
         // Finally, resize the list of requests so it is the same as the size of payloads and then iterate
         // over each request and convert the associated payload from JSON to a trade request; if this fails
         // then print an error message and return
         int numRequests = ArraySize(requests);
         ArrayResize(requests, numRequests + ArraySize(payloads));
         for (int i = 0; i < ArraySize(payloads); i++) {
            errCode = ConvertFromJSON(payloads[i], requests[i + numRequests]);
            if (errCode != 0) {
               PrintFormat("Failed to convert payload %d to JSON, error code: %d", i, errCode);
               return errCode;
            }
         }
      } else {
         break;
      }
      
      delete client;
      client = NULL;
   } while (true);
   return 0;
}

// Send an update to the server, letting them know that we're still there. This function will return zero if
// the no error occurs, or a non-zero error code otherwise
int OrderReceiver::Heartbeat() {

   // First, check if the current local time is less than the heartbeat window. If it
   // is then we have nothing to do. Otherwise, we'll send the request
   datetime now = TimeLocal();
   if (m_last - now < HEARTBEAT_SECONDS) {
      return 0;
   }

   // Next, create a new HTTP request and add the appropriate headers
   HttpRequest req("GET", m_heartbeat_addr);
   req.AddHeader("Accept", "application/json");
   req.AddHeader("Authorization", m_auth_header);
   
   // Finally, send the HTTP request; if this fails or returns a non-200 response
   // code then return an error; otherwise, return 0
   HttpResponse resp;
   int errCode = req.Send(resp);
   if (errCode != 0) {
      return errCode;
   } else if (resp.StatusCode != 200) {
      return resp.StatusCode;
   }
   
   // Finally, update the last heartbeat time to now and return
   m_last = now;
   return 0;
}

// Helper function that updates the registry associated with this client
//    enable:     Whether or not the registration should enabled or disabled
int OrderReceiver::UpdateRegistry(const bool enable) const {

   // First, convert the trade request to JSON and write that to our buffer
   JSONNode *js = new JSONNode();
   js["account"] = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   js["enabled"] = enable;
   js["port"] = (int)m_port;
   js["version"] = "MT4";
   
   // Next, serialize it into a string, then delete the serializer
   string json = js.Serialize();
   delete js;
   js = NULL;
   
   // Now, create a new HTTP request and add the appropriate headers
   HttpRequest req("POST", m_register_addr, json);
   req.AddHeader("Accept", "application/json");
   req.AddHeader("Authorization", m_auth_header);
   
   // Finally, post the HTTP request; if this fails or returns a non-200 response
   // code then return an error; otherwise, return 0
   HttpResponse resp;
   int errCode = req.Send(resp);
   if (errCode != 0) {
      return errCode;
   } else if (resp.StatusCode != 200) {
      return resp.StatusCode;
   } else {
      return 0;
   }
}

// Helper function that splits the payload received into a number of segments that correspond to JSON
// payloads. This function also updates the partial payload based off of what was left over. Note that
// this function assumes the payload contains single-depth JSON.
//    raw:        The raw data we received
//    substrings: The list of strings that will contain our full payloads
int OrderReceiver::SplitJSONPayload(const string raw, string &substrings[]) {

   // First, attempt to split the raw string by the opening bracket; if this fails then
   // retrieve the error code and return it. If the string was empty then return now. Otherwise,
   // if there was only one string then we have only a partial payload so set the start substring
   // and return
   string splits[];
   int code = StringSplit(raw, '{', splits);
   if (code == -1) {
      return GetLastError();
   } else if (code == 0) {
      return 0;
   } else if (code == 1) {
      m_partial = raw;
      return 0;
   }
   
   // Next, since we expect JSON payloads, the string should start with an opening bracket. Therefore,
   // splitting by the opening-bracket should result in an array where the first index contains no data.
   // If this isn't the case then we probably received the end of a previous payload so save that data
   bool partialStart = false;
   if (StringLen(splits[0]) > 0) {
      m_partial += splits[0];
      partialStart = true;
   }
   
   // Now, determine whether the last substring was a full payload (i.e. ending in a closing brace). If this
   // was the case then we'll go to the end of the list; otherwise, we'll save the last string in the list as
   // the next partial payload
   string end = "";
   bool lastFull = StringSubstr(splits[code - 1], StringLen(splits[code - 1]) - 1) == "}";
   uint endIndex = lastFull ? code : code - 1;
   if (!lastFull) {
      end = splits[code - 1];
   }
   
   // Finally, resize the output array to the proper size. There are two possibilities here: either we have a
   // response structured across two payloads that we need to add or we don't.
   uint offset = 0;
   if (partialStart) {
      ArrayResize(substrings, endIndex);
      substrings[0] = m_partial;
   } else {
      ArrayResize(substrings, endIndex - 1);
      offset = 1;
   }
   
   // Iterate over all the payloads and add them to our output list
   for (uint i = 1; i < endIndex; i++) {
      substrings[i - offset] = "{" + splits[i];
   }
   
   // Update the partial payload and return
   m_partial = end;
   return 0;
}

// Helper function that converts the JSON payload into a trade request. This function will
// return 0 if it was successful or will return a non-zero value in the case of an error
int ConvertFromJSON(const string json, TradeRequest &request) {
   
   // First, write our data to the JSON serializer
   JSONNode *js = new JSONNode();
   if (!js.Deserialize(json)) {
      return -1;
   }
   
   // Next, extract the values of the various fields from the JSON payload
   request.Action = (ENUM_TRADE_REQUEST_ACTIONS)js["action"].ToInteger();
   request.Comment = js["comment"].ToString();
   request.Expiration = (datetime)js["expiration"].ToInteger();
   request.Magic = js["magic"].ToInteger();
   request.Order = js["order"].ToInteger();
   request.Price = js["price"].ToDouble();
   request.StopLoss = js["stop_loss"].ToDouble();
   request.StopLimit = js["stop_limit"].ToDouble();
   request.Symbol = js["symbol"].ToString();
   request.TakeProfit = js["take_profit"].ToDouble();
   request.ToClose = js["to_close"].ToBool();
   request.Type = (ENUM_ORDER_TYPE)js["type"].ToInteger();
   request.TypeFilling = (ENUM_ORDER_TYPE_FILLING)js["fill_type"].ToInteger();
   request.TypeTime = (ENUM_ORDER_TYPE_TIME)js["expiration_type"].ToInteger();
   request.Volume = js["volume"].ToDouble();
   
   // Finally, delete the JSON serializer
   delete js;
   js = NULL;
   
   return 0;
}