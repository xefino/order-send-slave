#property copyright "Xefino"
#property version   "1.15"
#property strict

#include "Receiver_4.mqh"

#include <order-send-common-mt4/TicketCache.mqh>
#include <order-send-common-mt4/TradeRequest.mqh>

#define ERR_TICKET_MAPPING_FILE_CORRUPT (1000)

// OrderDuplicator
// Helper type that allows for the receipt and submission of copied orders
class OrderDuplicator {
private:
   TicketCache    *m_cache;      // An object we'll use to cache ticket numbers of received orders
   OrderReceiver  *m_receiver;   // Receiver for orders that need to be copied
   string         m_file;        // The name of the file that should be used to store ticket mappings
   ulong          m_magic;       // The magic number for this EA
   double         m_slippage;    // The slippage to allow when pushing new orders
   color          m_arrow;       // The arrow color to use for this EA
   
   // Helper function that reads the cache data from our slave EA's save file. This function will
   // return an error if the read fails
   int ReadTickets();
   
   // Helper function that writes the cache data to our slave EA's save file. This function will overwrite
   // the contents of the save file and return an error if the write fails
   int WriteTickets() const;
   
public:
   
   // Creates a new instance of the order duplicator from our address, port, magic number, save file name,
   // slippage and chart color. This function will attempt to read the contents of the save file if it exists
   //    addr:       The URL that should be used to register this slave expert
   //    port:       The port number that should be used to receive copied orders
   //    password:   The password that should be used when authenticating this EA for use with the webserver
   //    magic:      The magic number to use for the duplicator
   //    file:       The name of the save file that the cache data should be written to
   //    slippage:   The slippage that should be applied to received orders
   //    arrow:      The color of the arrow that should be written to chart
   OrderDuplicator(const string addr, const ushort port, const string password, const ulong magic, 
      const string file, const double slippage, const color arrow = CLR_NONE);
   
   // Destructor that releases the resources assorted with this duplicator. This function also attempts to
   // write the cached data to the save file so it can be reloaded next time
   ~OrderDuplicator();
   
   // DuplicateAll attempts to duplicate all orders received by this EA. This function will return zero if
   // the function succeeded or will return an error code otherwise
   int DuplicateAll();
};

// Creates a new instance of the order duplicator from our address, port, magic number, save file name,
// slippage and chart color. This function will attempt to read the contents of the save file if it exists
//    addr:       The URL that should be used to register this slave expert
//    port:       The port number that should be used to receive copied orders
//    password:   The password that should be used when authenticating this EA for use with the webserver
//    magic:      The magic number to use for the duplicator
//    file:       The name of the save file that the cache data should be written to
//    slippage:   The slippage that should be applied to received orders
//    arrow:      The color of the arrow that should be written to chart
OrderDuplicator::OrderDuplicator(const string addr, const ushort port, const string password,
   const ulong magic, const string file, const double slippage, const color arrow = CLR_NONE) {
   
   // First, create the ticket cache and order receiver
   m_cache = new TicketCache();
   m_receiver = new OrderReceiver(addr, port, password);
   
   // Next, set the base fields on the order duplicator
   m_file = file;
   m_slippage = slippage;
   m_magic = magic;
   m_arrow = arrow;
   
   // Finally, attempt to read the cache file if we have one
   int errCode = ReadTickets();
   if (errCode != 0) {
      SetUserError((ushort)errCode);
   }
}

// Destructor that releases the resources assorted with this duplicator. This function also attempts to
// write the cached data to the save file so it can be reloaded next time
OrderDuplicator::~OrderDuplicator() {

   // First, save the data in our tickets cache to a file so it can be reloaded later
   int errCode = WriteTickets();
   if (errCode != 0) {
      SetUserError((ushort)errCode);
   }
   
   // Next, delete the cache and set its pointer to NULL
   delete m_cache;
   m_cache = NULL;
   
   // Finally, delete the receiver and set its pointer to NULL
   delete m_receiver;
   m_receiver = NULL;
}

// DuplicateAll attempts to duplicate all orders received by this EA. This function will return zero if
// the function succeeded or will return an error code otherwise
int OrderDuplicator::DuplicateAll() {

   // Attempt to receive any outgoing requests; if this fails then log the error and return
   TradeRequest requests[];
   if (!m_receiver.Receive(requests)) {
      int errCode = GetLastError();
      Print("Failed to retrieve orders, error: ", errCode);
      return errCode;
   }
   
   // Iterate over all the requests we retrieved...
   for (int i = 0; i < ArraySize(requests); i++) {
      TradeRequest request = requests[i];
      PrintFormat("Received Copy Order (%d, %s, %d, %f, %f, %f, %f, %s, %d)", request.Order, request.Symbol, request.Type, 
         request.Volume, request.Price, request.StopLoss, request.TakeProfit, request.Comment, request.Expiration);
         
      // If we already have the key then we have to either update or close the order. Otherwise,
      // we have a new order so send it
      ResetLastError();
      if (m_cache.ContainsKey(request.Order) != request.ToClose) {
         PrintFormat("Order %d was already received and will be ignored", request.Order);
      } else {
         if (request.ToClose) {
      
            // First, attempt to retrieve the local ticket associated with this order. If we don't find it
            // then we probably received a double-send on an order that was already closed so log and continue
            ulong ticket;
            if (!m_cache.TryGetValue(request.Order, ticket)) {
               PrintFormat("Failed to retrieve ticket number for closed order %d", request.Order);
               continue;
            }
         
            // Next, attempt to close the order associated with the request. If this fails
            // then log the error and continue
            if (!OrderClose((int)ticket, request.Volume, request.Price, (int)m_slippage, m_arrow)) {
               int errCode = GetLastError();
               PrintFormat("Failed to copy close order for ticket (master: %d, slave: %d), error: %d",
                  request.Order, ticket, errCode);
               continue;
            }
            
            // Finally, attempt to remove the order from the cache so we don't try to resend it later
            // If this fails then log the error and continue
            if (!m_cache.Remove(request.Order)) {
               int errCode = GetLastError();
               PrintFormat("Failed to update order cache (master: %d, slave: %d), error: %d",
                  request.Order, ticket, errCode);
               continue;
            }
         } else {
            
            // First, attempt to send the order we received to the trade server; if this fails then
            // log the error and return the code
            int ticket = OrderSend(request.Symbol, request.Type, request.Volume, request.Price, (int)m_slippage, 
               0, 0, request.Comment, (int)m_magic, request.Expiration, m_arrow);
            if (ticket == -1) {
               int errCode = GetLastError();
               PrintFormat("Failed to copy order for ticket %d, error: %d", request.Order, errCode);
               continue;
            }
            
            // Next, attempt to modify the order with stop-loss and take-profit levels; if this fails
            // then log the error. We'll go ahead and cache the order any, though, as we don't want to
            // duplicate an order we've already received and updated
            if (!OrderModify(ticket, request.Price, request.StopLoss, request.TakeProfit, request.Expiration, m_arrow)) {
               int errCode = GetLastError();
               PrintFormat("Failed to modify order for ticket (master: %d, slave: %d), error: %d", 
                  request.Order, ticket, errCode);
            }
            
            // Finally, attempt to map the master order ticket to our slave ticket; if this fails then log
            // the error and return the code
            if (!m_cache.Add(request.Order, ticket)) {
               int errCode = GetLastError();
               PrintFormat("Failed to cache order (master: %d, slave: %d), error: %d",
                  request.Order, ticket, errCode);
               continue;
            }
         }
      }
   }
   
   return 0;
}

// Helper function that reads the cache data from our slave EA's save file. This function will
// return an error if the read fails
int OrderDuplicator::ReadTickets() {

   // First, check if the file exists; if it doesn't then we'll log and exit
   if (!FileIsExist(m_file, FILE_COMMON)) {
      PrintFormat("Ticket-mapping file, %s, not detected. This file will be created.", m_file);
      int errCode = GetLastError();
      return errCode == ERR_FILE_NOT_EXIST ? 0 : errCode;
   }
   
   // Next, attempt to open the file; if this fails then log and return the error code
   int handle = FileOpen(m_file, FILE_READ | FILE_TXT | FILE_COMMON);
   if (handle == INVALID_HANDLE) {
      int errCode = GetLastError();
      PrintFormat("Failed to open ticket-mapping file, %s, error: %d", m_file, errCode);
      return errCode;
   }
   
   // Now, iterate over each line in the file and attempt to parse it to a ticket mapping entry
   for (int i = 0; !FileIsEnding(handle); i++) {
   
      // First, read the line; if it is empty then ignore it and continue on
      string line = FileReadString(handle);
      if (line == "") {
         continue;
      }
      
      // Next, check the line for a colon; if we don't find it then the file is likely
      // corrupt so return an error in that case
      int colonIndex = StringFind(line, ":");
      if (colonIndex == -1) {
         PrintFormat("Line %d of ticket-mapping file, %s, was corrupted", i + 1, m_file);
         return ERR_TICKET_MAPPING_FILE_CORRUPT;
      }
      
      // Now, extract the source ticket and destination ticket from the file
      ulong key = StringToInteger(StringSubstr(line, 0, colonIndex));
      ulong value = StringToInteger(StringSubstr(line, colonIndex));
      
      // Finally, attempt to add the key and value to the cache; if this fails then log the error
      // and return it
      if (!m_cache.Add(key, value)) {
         int errCode = GetLastError();
         PrintFormat("Failed to load cached order from %s (master: %d, slave: %d), error: %d",
            m_file, key, value, errCode);
         return errCode;
      }
   };
   
   // Finally, close the file and return
   FileClose(handle);
   return 0;
}

// Helper function that writes the cache data to our slave EA's save file. This function will overwrite
// the contents of the save file and return an error if the write fails
int OrderDuplicator::WriteTickets() const {

   // First, attempt to delete the file if it exists (for overwriting purposes)
   // If this fails then return an error
   if (FileIsExist(m_file, FILE_COMMON) && !FileDelete(m_file, FILE_COMMON)) {
      int errCode = GetLastError();
      PrintFormat("Failed to delete old ticket-mapping file, %s, error: %d", m_file, errCode);
      return errCode;
   }
   
   // Next, attempt to open the file so we can write data to it; if this fails
   // then return an error
   int handle = FileOpen(m_file, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if (handle == INVALID_HANDLE) {
      int errCode = GetLastError();
      PrintFormat("Failed to open ticket-mapping file, %s, error: %d", m_file, errCode);
      return errCode;
   }
   
   // Now, copy the data from the cache into a list of keys and values that we can write
   ulong keys[], values[];
   int length = m_cache.CopyTo(keys, values);
   
   // Finally, iterate over our list of keys and values and attempt to write each to the file
   // If this fails then return an error
   for (int i = 0; i < length; i++) {
      string line = StringFormat("%d:%d\n", keys[i], values[i]);
      if (FileWriteString(handle, line) == 0) {
         int errCode = GetLastError();
         PrintFormat("Failed to write entry %d to ticket-mapping file, %s, error: %d",
            i + 1, m_file, errCode);
         return errCode;
      }
   }
   
   // Close the file when we're done
   FileFlush(handle);
   FileClose(handle);
   return 0;
}
   