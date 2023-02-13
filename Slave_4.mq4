#property copyright "Xefino"
#property version   "1.15"

#include "OrderDuplicator.mqh"

// Describes the possible environments allowed for the master EA
enum ENUM_ENVIRONMENT {
   ENVIRONMENT_TEST = 0x0, // Test
   ENVIRONMENT_PROD = 0x1  // Production
};

// Inputs
input ENUM_ENVIRONMENT Environment = ENVIRONMENT_PROD;   // Environment
input ushort Port = 8001;                                // Port
input string Password = "";                              // Password
input string SaveFile = "tickets_cache.txt";             // Save File Name
input ulong Magic = 0;                                   // Magic Number
input color Arrow = CLR_NONE;                            // Arrow Color
input ulong Slippage = 5;                                // Slippage (Pts)

OrderDuplicator *Receiver;

int OnInit() {

   // First, determine the URL to which the slave should register itself
   string url;
   switch (Environment) {
   case ENVIRONMENT_TEST:
      url = "https://qh7g3o0ypc.execute-api.ap-northeast-1.amazonaws.com/register";
      break;
   case ENVIRONMENT_PROD:
      url = "https://rurdtoe916.execute-api.ap-southeast-1.amazonaws.com/register";
      break;
   default:
      Print("Invalid environment selected. Exiting.");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   Receiver = new OrderDuplicator(url, Port, Password, Magic, SaveFile, Slippage, Arrow);
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