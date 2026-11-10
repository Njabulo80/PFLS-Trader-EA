
#ifndef PFLS_EXECUTION_MQH
#define PFLS_EXECUTION_MQH

//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| EXECUTION SAFETY MODULE                                          |
//| Version 2.00.2                                                   |
//|                                                                  |
//| PURPOSE:                                                         |
//| - Inspect account and terminal permissions                      |
//| - Identify demo versus real accounts                             |
//| - Check emergency-stop status                                    |
//| - Validate selected market symbol                                |
//| - Permanently deny order execution in this research build       |
//|                                                                  |
//| IMPORTANT:                                                       |
//| NO ORDER SEND, MODIFY OR CLOSE FUNCTIONS ARE PROVIDED.           |
//+------------------------------------------------------------------+

#define PFLS_EXECUTION_MODULE_VERSION "2.00.2"

//====================================================================
// EXECUTION STATES
//====================================================================

enum PFLS_EXECUTION_STATE
{
   PFLS_EXECUTION_LOCKED = 0,
   PFLS_EXECUTION_DISABLED,
   PFLS_EXECUTION_EMERGENCY_STOP,
   PFLS_EXECUTION_REAL_ACCOUNT_BLOCKED,
   PFLS_EXECUTION_TERMINAL_BLOCKED,
   PFLS_EXECUTION_ACCOUNT_BLOCKED,
   PFLS_EXECUTION_SYMBOL_INVALID,
   PFLS_EXECUTION_RESEARCH_ONLY,
   PFLS_EXECUTION_CONNECTION_BLOCKED
};

//====================================================================
// EXECUTION STATUS
//====================================================================

struct PFLS_ExecutionStatus
{
   PFLS_EXECUTION_STATE state;

   bool account_is_demo;
   bool terminal_permission;
   bool account_permission;
   bool expert_permission;
   bool terminal_connected;

   bool execution_requested;
   bool emergency_stop;

   bool safety_checks_passed;
   bool order_execution_allowed;

   string symbol;
   string message;
};

//====================================================================
// RESET EXECUTION STATUS
//====================================================================

void PFLS_ResetExecutionStatus(
   PFLS_ExecutionStatus &status
)
{
   status.state = PFLS_EXECUTION_LOCKED;

   status.account_is_demo = false;
   status.terminal_permission = false;
   status.account_permission = false;
   status.expert_permission = false;
   status.terminal_connected = false;

   status.execution_requested = false;
   status.emergency_stop = false;

   status.safety_checks_passed = false;
   status.order_execution_allowed = false;

   status.symbol = "";
   status.message = "RESEARCH BUILD - EXECUTION LOCKED";
}

//====================================================================
// ACCOUNT TYPE CHECK
//====================================================================

bool PFLS_IsDemoAccount()
{
   ENUM_ACCOUNT_TRADE_MODE account_mode =
      (ENUM_ACCOUNT_TRADE_MODE)
      AccountInfoInteger(ACCOUNT_TRADE_MODE);

   return (account_mode == ACCOUNT_TRADE_MODE_DEMO);
}

//====================================================================
// EXECUTION SAFETY INSPECTION
//====================================================================

void PFLS_CheckExecutionSafety(
   string symbol,
   bool enable_execution,
   bool emergency_stop,
   PFLS_ExecutionStatus &status
)
{
   PFLS_ResetExecutionStatus(status);

   status.symbol = symbol;
   status.execution_requested = enable_execution;
   status.emergency_stop = emergency_stop;

   // Account inspection.
   status.account_is_demo = PFLS_IsDemoAccount();

   // Terminal inspection.
   status.terminal_connected =
      (bool)TerminalInfoInteger(TERMINAL_CONNECTED);

   status.terminal_permission =
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);

   // Account inspection.
   status.account_permission =
      (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);

   // EA permission inspection.
   status.expert_permission =
      (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);

   //===============================================================
   // PRIORITY 1: EMERGENCY STOP
   //===============================================================

   if(emergency_stop)
   {
      status.state = PFLS_EXECUTION_EMERGENCY_STOP;
      status.message = "EMERGENCY STOP ACTIVE";
      return;
   }

   //===============================================================
   // PRIORITY 2: EXECUTION DISABLED
   //===============================================================

   if(!enable_execution)
   {
      status.state = PFLS_EXECUTION_DISABLED;
      status.message = "EXECUTION DISABLED BY DEFAULT";
      return;
   }

   //===============================================================
   // PRIORITY 3: CONNECTION CHECK
   //===============================================================

   if(!status.terminal_connected)
   {
      status.state = PFLS_EXECUTION_CONNECTION_BLOCKED;
      status.message = "BLOCKED: TERMINAL NOT CONNECTED";
      return;
   }

   //===============================================================
   // PRIORITY 4: DEMO ACCOUNT CHECK
   //===============================================================

   if(!status.account_is_demo)
   {
      status.state = PFLS_EXECUTION_REAL_ACCOUNT_BLOCKED;
      status.message = "BLOCKED: DEMO ACCOUNT REQUIRED";
      return;
   }

   //===============================================================
   // PRIORITY 5: TERMINAL PERMISSION
   //===============================================================

   if(!status.terminal_permission)
   {
      status.state = PFLS_EXECUTION_TERMINAL_BLOCKED;
      status.message = "BLOCKED: TERMINAL TRADE PERMISSION";
      return;
   }

   //===============================================================
   // PRIORITY 6: ACCOUNT AND EA PERMISSIONS
   //===============================================================

   if(!status.account_permission ||
      !status.expert_permission)
   {
      status.state = PFLS_EXECUTION_ACCOUNT_BLOCKED;
      status.message = "BLOCKED: ACCOUNT OR EA PERMISSION";
      return;
   }

   //===============================================================
   // PRIORITY 7: SYMBOL VALIDATION
   //===============================================================

   if(StringLen(symbol) == 0)
   {
      status.state = PFLS_EXECUTION_SYMBOL_INVALID;
      status.message = "BLOCKED: EMPTY MARKET SYMBOL";
      return;
   }

   if(!SymbolSelect(symbol, true))
   {
      status.state = PFLS_EXECUTION_SYMBOL_INVALID;
      status.message = "BLOCKED: SYMBOL SELECTION FAILED";
      return;
   }

   long symbol_trade_mode =
      SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);

   if(symbol_trade_mode == SYMBOL_TRADE_MODE_DISABLED)
   {
      status.state = PFLS_EXECUTION_SYMBOL_INVALID;
      status.message = "BLOCKED: SYMBOL TRADING DISABLED";
      return;
   }

   //===============================================================
   // SAFETY INSPECTION PASSED
   //===============================================================

   status.safety_checks_passed = true;

   //===============================================================
   // PERMANENT RESEARCH BUILD LOCK
   //===============================================================

   // Passing safety checks does NOT authorize trading.
   // This module has no order-placement functionality.
   // The final authorization function always returns false.

   status.order_execution_allowed = false;

   status.state = PFLS_EXECUTION_RESEARCH_ONLY;

   status.message =
      "INSPECTION PASSED - RESEARCH BUILD PERMANENTLY LOCKED";
}

//====================================================================
// EXECUTION STATE TEXT
//====================================================================

string PFLS_ExecutionStateText(
   PFLS_EXECUTION_STATE state
)
{
   switch(state)
   {
      case PFLS_EXECUTION_LOCKED:
         return "LOCKED";

      case PFLS_EXECUTION_DISABLED:
         return "EXECUTION DISABLED";

      case PFLS_EXECUTION_EMERGENCY_STOP:
         return "EMERGENCY STOP";

      case PFLS_EXECUTION_REAL_ACCOUNT_BLOCKED:
         return "REAL ACCOUNT BLOCKED";

      case PFLS_EXECUTION_TERMINAL_BLOCKED:
         return "TERMINAL PERMISSION BLOCKED";

      case PFLS_EXECUTION_ACCOUNT_BLOCKED:
         return "ACCOUNT PERMISSION BLOCKED";

      case PFLS_EXECUTION_SYMBOL_INVALID:
         return "INVALID SYMBOL";

      case PFLS_EXECUTION_RESEARCH_ONLY:
         return "RESEARCH ONLY";

      case PFLS_EXECUTION_CONNECTION_BLOCKED:
         return "TERMINAL CONNECTION BLOCKED";
   }

   return "UNKNOWN EXECUTION STATE";
}

//====================================================================
// FINAL EXECUTION AUTHORIZATION
//====================================================================

bool PFLS_IsOrderExecutionAllowed(
   const PFLS_ExecutionStatus &status
)
{
   // PERMANENTLY FALSE IN PFLS 2.00 RESEARCH BUILD.
   // No account, setting or permission can override this lock.

   return false;
}

//====================================================================
// MODULE VERSION
//====================================================================

string PFLS_GetExecutionModuleVersion()
{
   return PFLS_EXECUTION_MODULE_VERSION;
}

//+------------------------------------------------------------------+
#endif // PFLS_EXECUTION_MQH
