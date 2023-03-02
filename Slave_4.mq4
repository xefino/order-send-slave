#property copyright "Xefino"
#property version   "1.24"

#include "OrderDuplicator.mqh"

// Inputs
input string ConfigFile = "oss_config.json";             // Configuration File
input ulong Magic = 0;                                   // Magic Number
input color Arrow = CLR_NONE;                            // Arrow Color
input ulong Slippage = 5;                                // Slippage (Pts)

OrderDuplicator *Receiver;

int OnInit() {
   Receiver = new OrderDuplicator(Magic, ConfigFile, Slippage, Arrow);
   int errCode = GetLastError();
   if (errCode != 0) {
      return errCode;
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   delete Receiver;
   Receiver = NULL;
}

void OnTick() {
   ResetLastError();

   int errCode = Receiver.DuplicateAll();
   if (errCode != 0) {
      Print("Failed to duplicate orders, error: ", errCode);
   }
}