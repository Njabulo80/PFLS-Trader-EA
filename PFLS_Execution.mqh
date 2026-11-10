
#ifndef PFLS_EXECUTION_MQH
#define PFLS_EXECUTION_MQH

// =====================================================
// PFLS TRADER 2.00
// EXECUTION SAFETY MODULE
// Version 2.00.1
//
// PURPOSE:
// - Verify account and terminal permissions
// - Enforce demo-account restriction
// - Enforce emergency stop
// - Keep order execution disabled in this build
//
// IMPORTANT:
// This module does NOT send, modify or close orders.
// =====================================================

#define PFLS_EXECUTION_MODULE_VERSION "2.00.1"

// -----------------------------------------------------
// EXECUTION STATES
// -----------------------------------------------------

enum PFLS_EXECUTION_STATE
{
   PFLS_EXECUTION_LOCKED = 0,
   PFLS_EXECUTION_DISABLED,
   PFLS_EXECUTION_EMERGENCY_STOP,
   PFLS_EXECUTION_REAL_ACCOUNT_BLOCKED,
   PFLS_EXECUTION_TERMINAL_BLOCKED,
   PFLS_EXECUTION_ACCOUNT_BLOCKED,
   PFLS_EXECUTION_SYMBOL_INVALID,
   PFLS_EXECUTION_RESEARCH_ONLY
};

// -----------------------------------------------------
// EXECUTION STATUS
// -----------------------------------------------------

struct PFLS_ExecutionStatus
{
   PFLS_EXECUTION_STATE state;

   bool account_is_demo;
   bool terminal_permission;
   bool account_permission;
   bool expert_permission;

   bool execution_requested;
   bool emergency_stop;

   bool safety_checks_passed;
   bool order_execution_allowed;

   string symbol;
   string message;
};

// -----------------------------------------------------
// RESET EXECUTION STATUS
// -----------------------------------------------------

void PFLS_ResetExecutionStatus(
   PFLS_ExecutionStatus &status
)
{
   status.state = PFLS_EXECUTION_LOCKED;

   status.account_is_demo = false;
   status.terminal_permission = false;
   status.account_permission = false;
   status.expert_permission = false;

   status.execution_requested = false;
   status.emergency_stop = false;

   status.safety_checks_passed = false;
   status.order_execution_allowed = false;

   status.symbol = "";
   status.message = "EXECUTION LOCKED";
}

// -----------------------------------------------------
// ACCOUNT TYPE CHECK
// -----------------------------------------------------

bool PFLS_IsDemoAccount()
{
   ENUM_ACCOUNT_TRADE_MODE account_mode =
      (ENUM_ACCOUNT_TRADE_MODE)
      AccountInfoInteger(ACCOUNT_TRADE_MODE);

   return (account_mode == ACCOUNT_TRADE_MODE_DEMO);
}

// -----------------------------------------------------
// EXECUTION SAFETY INSPECTION
// -----------------------------------------------------

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

   // Check account type.
   status.account_is_demo = PFLS_IsDemoAccount();

   // Check terminal permission.
   status.terminal_permission =
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);

   // Check account permission.
   status.account_permission =
      (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);

   // Check Expert Advisor permission.
   status.expert_permission =
      (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);

   // --------------------------------------------------
   // SAFETY PRIORITY 1: EMERGENCY STOP
   // --------------------------------------------------

   if(emergency_stop)
   {
      status.state = PFLS_EXECUTION_EMERGENCY_STOP;
      status.message = "EMERGENCY STOP ACTIVE";
      return;
   }

   // --------------------------------------------------
   // SAFETY PRIORITY 2: EXECUTION DISABLED
   // --------------------------------------------------

   if(!enable_execution)
   {
      status.state = PFLS_EXECUTION_DISABLED;
      status.message = "EXECUTION DISABLED BY DEFAULT";
      return;
   }

   // --------------------------------------------------
   // SAFETY PRIORITY 3: DEMO ACCOUNT ONLY
   // --------------------------------------------------

   if(!status.account_is_demo)
   {
      status.state = PFLS_EXECUTION_REAL_ACCOUNT_BLOCKED;
      status.message = "BLOCKED: DEMO ACCOUNT REQUIRED";
      return;
   }

   // --------------------------------------------------
   // SAFETY PRIORITY 4: TERMINAL PERMISSION
   // --------------------------------------------------

   if(!status.terminal_permission)
   {
      status.state = PFLS_EXECUTION_TERMINAL_BLOCKED;
      status.message = "BLOCKED: TERMINAL TRADE PERMISSION";
      return;
   }

   // --------------------------------------------------
   // SAFETY PRIORITY 5: ACCOUNT PERMISSION
   // --------------------------------------------------

   if(!status.account_permission ||
      !status.expert_permission)
   {
      status.state = PFLS_EXECUTION_ACCOUNT_BLOCKED;
      status.message = "BLOCKED: ACCOUNT OR EA PERMISSION";
      return;
   }

   // --------------------------------------------------
   // SAFETY PRIORITY 6: SYMBOL VALIDATION
   // --------------------------------------------------

   if(StringLen(symbol) == 0 ||
      !SymbolSelect(symbol, true))
   {
      status.state = PFLS_EXECUTION_SYMBOL_INVALID;
      status.message = "BLOCKED: INVALID MARKET SYMBOL";
      return;
   }

   // --------------------------------------------------
   // SAFETY CHECKS PASSED
   // --------------------------------------------------

   status.safety_checks_passed = true;

   // --------------------------------------------------
   // PERMANENT RESEARCH BUILD LOCK
   // --------------------------------------------------

   // No order-sending functions are implemented here.
   // Passing these checks does not authorize trading.

   status.order_execution_allowed = false;

   status.state = PFLS_EXECUTION_RESEARCH_ONLY;

   status.message =
      "SAFETY CHECKS PASSED - RESEARCH BUILD LOCKED";
}

// -----------------------------------------------------
// EXECUTION STATE TEXT
// -----------------------------------------------------

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
   }

   return "UNKNOWN EXECUTION STATE";
}

// -----------------------------------------------------
// EXECUTION MODULE VERSION
// -----------------------------------------------------

string PFLS_GetExecutionModuleVersion()
{
   return PFLS_EXECUTION_MODULE_VERSION;
}

// -----------------------------------------------------
// FINAL EXECUTION AUTHORIZATION
// -----------------------------------------------------

bool PFLS_IsOrderExecutionAllowed(
   const PFLS_ExecutionStatus &status
)
{
   // Research build: always false.
   // No order can be placed through this module.

   return false;
}

#endif // PFLS_EXECUTION_MQH
