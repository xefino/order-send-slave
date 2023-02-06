#property copyright "Xefino"
#property version   "1.00"

// OrderSendSlave
// Helper object that can be used to receive trade requests that were dispersed from a master node.
class OrderSendSlave {
private:
   int      m_socket;   // The index of the socket we'll use to retrieve updates
   string   m_addr;     // The endpoint of the server we'll send trade requests to
   uint     m_port;     // The port number on which to receive data from the server
   string   m_partial;  // Partial payload received from previous calls

   // Helper function that splits the payload received into a number of segments that correspond to JSON
   // payloads. This function also updates the partial payload based off of what was left over. Note that
   // this function assumes the payload contains single-depth JSON.
   //    raw:        The raw data we received
   //    substrings: The list of strings that will contain our full payloads
   uint SplitJSONPayload(const string raw, string &substrings[]);

public:

   // Creates a new order-send slave object with the web address of the webserver from which we want to retrieve
   // trade requests and the port on which we should expect to receive such requests
   //    addr:    The URL which will be used to register the slave
   //    port:    The port that should be opened to allow retrieval of trade requests (should not be port 80 or 443)
   OrderSendSlave(const string addr, const uint port);
   
   // Destroys this instance of the order-send slave by deregistering the slave with the webserver and closing the
   // associated socket connection
   ~OrderSendSlave();
   
   // Receive polls against the socket for trade request data and then populates that data into a number of trade
   // requests. This function will return true if it succeeded or false otherwise. If an error occurred, then it will
   // be stored in _LastError.
   //    requests:   The array of trade requests that should be populated
   bool Receive(MqlTradeRequest &requests[]);
};

// Creates a new order-send slave object with the web address of the webserver from which we want to retrieve
// trade requests and the port on which we should expect to receive such requests
//    addr:    The URL which will be used to register the slave
//    port:    The port that should be opened to allow retrieval of trade requests (should not be port 80 or 443)
OrderSendSlave::OrderSendSlave(const string addr, const uint port) {
   m_addr = addr;
   m_port = port;
   m_partial = "";
   
   uint errCode = UpdateRegistry(m_addr, m_port, true);
   if (errCode != 0) {
      Print("Failed to register client, error code: ", errCode);
      SetUserError((ushort)errCode);
      return;
   }
   
   m_socket = SocketCreate();
   if (m_socket == INVALID_HANDLE) {
      Print("Failed to create socket to receive master trades");
      return;
   }
}

// Destroys this instance of the order-send slave by deregistering the slave with the webserver and closing the
// associated socket connection
OrderSendSlave::~OrderSendSlave() {
   UpdateRegistry(m_addr, m_port, false);
   SocketClose(m_socket);
}

// Receive polls against the socket for trade request data and then populates that data into a number of trade
// requests. This function will return true if it succeeded or false otherwise. If an error occurred, then it will
// be stored in _LastError.
//    requests:   The array of trade requests that should be populated
bool OrderSendSlave::Receive(MqlTradeRequest &requests[]) {

   // First, check that the socket is connected and, if it isn't then attempt to connect
   // to the socket. If this fails then print a message and return
   if (!(SocketIsConnected(m_socket) || SocketConnect(m_socket, m_addr, m_port, 1000))) {
      PrintFormat("Failed to retrieve data from socket at %s:%d", m_addr, m_port);
      return false;
   }
   
   // Check if the socket is readable; if it isn't then return here as we have nothing to do
   uint len = SocketIsReadable(m_socket);
   if (!len) {
      return false;
   }
   
   // Next, read data from the socket; if this fails or returns no data then we'll return now
   char resp[];
   uint rspLen = SocketRead(m_socket, resp, len, 1000);
   if (rspLen == 0) {
      return false;
   }
   
   // Convert the response data we received to a string and print the headers we received
   string result = CharArrayToString(resp, 0, rspLen);
   int headerEnd = StringFind(result, "\r\n\r\n");
   if(headerEnd > 0) {
      Print("HTTP answer header received: ", StringSubstr(result, 0, headerEnd));
   }
   
   // Now, attempt to split the payload based on our expected payload structure; if this fails then
   // print an error message and return
   string payloads[];
   uint errCode = SplitJSONPayload(StringSubstr(result, headerEnd), payloads);
   if (errCode != 0) {
      PrintFormat("Failed to split response into JSON payloads, error code: %d", errCode);
      return false;
   }
   
   // Finally, resize the list of requests so it is the same as the size of payloads and then iterate
   // over each request and convert the associated payload from JSON to a trade request; if this fails
   // then print an error message and return
   ArrayResize(requests, ArraySize(payloads));
   for (int i = 0; i < ArraySize(payloads); i++) {
      errCode = ConvertFromJson(payloads[i], requests[i]);
      if (errCode != 0) {
         PrintFormat("Failed to convert payload %d to JSON, error code: %d", i, errCode);
         return false;
      }
   }
   
   // If we've reached this point then return true to indicate that no problems occurred
   return true;
}

// Helper function that splits the payload received into a number of segments that correspond to JSON
// payloads. This function also updates the partial payload based off of what was left over. Note that
// this function assumes the payload contains single-depth JSON.
//    raw:        The raw data we received
//    substrings: The list of strings that will contain our full payloads
uint OrderSendSlave::SplitJSONPayload(const string raw, string &substrings[]) {

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
int ConvertFromJson(const string json, MqlTradeRequest &request) {
   
   // Remove the starting and ending braces from the JSON payload and split it into 
   // field-value pairs; if this fails or returns no data then return from the function
   // immediately as there's nothing else to do
   string fieldValues [];
   int len = StringSplit(StringSubstr(json, 1, StringLen(json) - 2), ',', fieldValues);
   if (len < 0) {
      return GetLastError();
   } else if (len == 0) {
      return 0;
   }
   
   // Iterate over all the field-value pairs and write each to the trade request
   for (int i = 0; i < ArraySize(fieldValues); i++) {
   
      // First, get the index of the colon separating the field from the value; if we don't
      // find one then the payload is corrupt so return an error
      int colonIndex = StringFind(fieldValues[i], ":");
      if (colonIndex < 0) {
         return -1;
      }
      
      // Next, extract the field and value from the field-value pair and strip starting and ending
      // quotes from the results
      string field = StringSubstr(fieldValues[i], 1, colonIndex - 2);
      string value = StringSubstr(fieldValues[i], colonIndex);
      if (value[0] == '\"' && value[StringLen(value) - 1] == '\"') {
         value = StringSubstr(value, 1, StringLen(value) - 2);
      }
      
      // Finally, convert the value to its proper type and assign it to the appropriate field on the
      // trade request based on the value of the JSON field
      if (field == "action") {
         request.action = (ENUM_TRADE_REQUEST_ACTIONS)StringToInteger(value);
      } else if (field == "comment") {
         request.comment = value;
      } else if (field == "deviation") {
         request.deviation = StringToInteger(value);
      } else if (field == "expiration") {
         request.expiration = (datetime)StringToInteger(value);
      } else if (field == "magic") {
         request.magic = StringToInteger(value);
      } else if (field == "order_id") {
         request.order = StringToInteger(value);
      } else if (field == "position_id") {
         request.position = StringToInteger(value);
      } else if (field == "opposite_position_id") {
         request.position_by = StringToInteger(value);
      } else if (field == "price") {
         request.price = StringToDouble(value);
      } else if (field == "stop_loss") {
         request.sl = StringToDouble(value);
      } else if (field == "stop_limit") {
         request.stoplimit = StringToDouble(value);
      } else if (field == "symbol") {
         request.symbol = value;
      } else if (field == "take_profit") {
         request.tp = StringToDouble(value);
      } else if (field == "type") {
         request.type = (ENUM_ORDER_TYPE)StringToInteger(value);
      } else if (field == "fill_type") {
         request.type_filling = (ENUM_ORDER_TYPE_FILLING)StringToInteger(value);
      } else if (field == "expiration_type") {
         request.type_time = (ENUM_ORDER_TYPE_TIME)StringToInteger(value);
      } else if (field == "volume") {
         request.volume = StringToDouble(value);
      }
   }
   
   return 0;
}

// Helper function that updates the registry associated with this client
uint UpdateRegistry(const string addr, const uint port, const bool enable) {

   // First, convert the trade request to JSON and write that to our buffer
   char req[];
   string json = StringFormat("{\"enabled\":%s,\"port\":%d}", BoolToString(enable), port);
   int len = StringToCharArray(json, req) - 1;
   
   // Next, attempt to send the JSON data to our web server; if this fails then return an error
   Print("Attempting send...");
   char result[];
   string headers;
   int res = WebRequest("POST", addr, "", "", 1000, req, len, result, headers);
   if (res == -1) {
      res = GetLastError();
   }
   
   PrintFormat("Response Code: %d, Headers: %s, Response: %s", res, headers, CharArrayToString(result));

   // Finally, return 0 to indicate that all the operations succeeded if we got a 200 response code
   // Otherwise, return the response code we received
   return res == 200 ? 0 : res;
}

// Converts a Boolean value to a string
string BoolToString(const bool in) {
   return in ? "true" : "false";
}