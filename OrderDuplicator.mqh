#property copyright "Xefino"
#property version   "1.03"
#property strict

#include "Receiver_4.mqh"
#include "TicketCache_4.mqh"

#include <order-send-common-mt4/TradeRequest.mqh>

class OrderDuplicator {
private:
   TicketCache    *m_cache;      // An object we'll use to cache ticket numbers of received orders
   OrderReceiver  *m_receiver;   // Receiver for orders that need to be copied
   
   ulong          m_magic;       // The magic number for this EA
   double         m_slippage;    // The slippage to allow when pushing new orders
   color          m_arrow;       // The arrow color to use for this EA
   
public:
   
   OrderDuplicator(const string addr, const ushort port, const ulong magic, 
      const double slippage, const color arrow = CLR_NONE);
   
   ~OrderDuplicator();
   
   int DuplicateAll();
};

OrderDuplicator::OrderDuplicator(const string addr, const ushort port, 
   const ulong magic, const double slippage, const color arrow = CLR_NONE) {
   m_cache = new TicketCache();
   m_receiver = new OrderReceiver(addr, port);
   m_slippage = slippage;
   m_magic = magic;
   m_arrow = arrow;
}

OrderDuplicator::~OrderDuplicator() {
   delete m_cache;
   m_cache = NULL;
   delete m_receiver;
   m_receiver = NULL;
}

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
   
      // If we already have the key then we have to either update or close the order. Otherwise,
      // we have a new order so send it
      if (m_cache.ContainsKey(request.Order)) {
         // Order exists already; we need to update or close
      } else {
      
         // Attempt to send the order we received to the trade server; if this fails then
         // log the error and return the code
         int ticket = OrderSend(request.Symbol, request.Type, request.Volume, request.Price, (int)m_slippage, 
            request.StopLoss, request.TakeProfit, request.Comment, (int)m_magic, request.Expiration, m_arrow);
         if (ticket == -1) {
            int errCode = GetLastError();
            PrintFormat("Failed to copy order for ticket %d, error: %d", request.Order, errCode);
            return errCode;
         }
         
         // Attempt to map the master order ticket to our slave ticket; if this fails then log
         // the error and return the code
         if (!m_cache.Add(request.Order, ticket)) {
            int errCode = GetLastError();
            PrintFormat("Failed to cache order (master: %d, slave: %d), error: %d",
               request.Order, ticket, errCode);
            return errCode;   
         }
      }
   }
   
   return 0;
}