
//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| MAIN EXPERT ADVISOR                                              |
//| Version 2.00.3                                                   |
//|                                                                  |
//| Multi-Timeframe Price Flow and Research Engine                   |
//| Initial research target: Deriv Volatility 75 Index               |
//| Platform: MetaTrader 5                                           |
//|                                                                  |
//| IMPORTANT: RESEARCH ONLY                                         |
//| NO AUTOMATED ORDER EXECUTION                                     |
//+------------------------------------------------------------------+
#property copyright "PFLS Trader"
#property version   "2.00"
#property description "PFLS 2.00 - Multi-Timeframe Research EA"

//====================================================================
// MODULES
//====================================================================

#include "PFLS_EntryEngine.mqh"
#include "PFLS_RiskManager.mqh"
#include "PFLS_Execution.mqh"

//====================================================================
// INPUTS
//====================================================================

input group "PFLS MARKET SETTINGS"

input string InpMarketSymbol = "";
input int    InpLookbackBars = 300;
input int    InpPivotStrength = 2;
input int    InpScanIntervalSeconds = 30;

input group "PFLS ENTRY RESEARCH"

input double InpMinimumWickRatio = 1.5;
input bool   InpEnableEntryResearch = true;

input group "PFLS DASHBOARD"

input bool InpShowChartStatus = true;
input bool InpEnableResearchLog = true;

input group "PFLS EXECUTION SAFETY"

input bool InpEnableExecution = false;
input bool InpEmergencyStop = false;

//====================================================================
// TIMEFRAME CONFIGURATION
//====================================================================

#define PFLS_MAIN_TIMEFRAME_COUNT 8

ENUM_TIMEFRAMES PFLS_MainTimeframes[PFLS_MAIN_TIMEFRAME_COUNT] =
{
   PERIOD_W1,
   PERIOD_D1,
   PERIOD_H4,
   PERIOD_H1,
   PERIOD_M30,
   PERIOD_M15,
   PERIOD_M5,
   PERIOD_M1
};

string PFLS_TimeframeNames[PFLS_MAIN_TIMEFRAME_COUNT] =
{
   "W1", "D1", "H4", "H1",
   "M30", "M15", "M5", "M1"
};

//====================================================================
// GLOBAL STATE
//====================================================================

PFLS_PriceFlowState    PFLS_Flow;
PFLS_RiskConfig        PFLS_Risk;
PFLS_TradePlan         PFLS_CurrentTradePlan;
PFLS_EntryResult       PFLS_CurrentEntry;
PFLS_ExecutionStatus   PFLS_Execution;

datetime PFLS_LastScanTime = 0;
datetime PFLS_LastM5SignalTime = 0;

double PFLS_PreviousTickPrice = 0.0;
double PFLS_CurrentTickPrice  = 0.0;

bool PFLS_Initialised = false;
bool PFLS_DataAvailable = false;

string PFLS_StatusMessage = "INITIALISING";

//====================================================================
// MITIGATED ZONE MEMORY
//====================================================================

// Prevent a zone touched during this running session from being
// displayed again after a later timeframe rescan.
//
// The zone module separately maintains its own interaction history.
// This additional list protects the active dashboard snapshots.

#define PFLS_MAX_MITIGATED_ZONES 512

datetime PFLS_MitigatedOrigin[PFLS_MAX_MITIGATED_ZONES];
ENUM_TIMEFRAMES PFLS_MitigatedTimeframe[PFLS_MAX_MITIGATED_ZONES];
bool PFLS_MitigatedDemand[PFLS_MAX_MITIGATED_ZONES];

int PFLS_MitigatedCount = 0;

//====================================================================
// LOGGING
//====================================================================

void PFLS_Log(string message)
{
   if(!InpEnableResearchLog)
      return;

   Print("[PFLS 2.00] ", message);
}

//====================================================================
// SYMBOL
//====================================================================

string PFLS_GetMarketSymbol()
{
   if(StringLen(InpMarketSymbol) > 0)
      return InpMarketSymbol;

   return _Symbol;
}

//====================================================================
// TIMEFRAME INDEX
//====================================================================

int PFLS_GetTimeframeIndex(ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < PFLS_MAIN_TIMEFRAME_COUNT; i++)
   {
      if(PFLS_MainTimeframes[i] == timeframe)
         return i;
   }

   return -1;
}

//====================================================================
// MITIGATED ZONE REGISTRATION
//====================================================================

bool PFLS_IsZonePreviouslyMitigated(
   const PFLS_ZoneRecord &zone
)
{
   for(int i = 0; i < PFLS_MitigatedCount; i++)
   {
      if(PFLS_MitigatedOrigin[i] == zone.origin_time &&
         PFLS_MitigatedTimeframe[i] == zone.timeframe &&
         PFLS_MitigatedDemand[i] == zone.is_demand)
      {
         return true;
      }
   }

   return false;
}

//--------------------------------------------------------------------

void PFLS_RegisterMitigatedZone(
   const PFLS_ZoneRecord &zone
)
{
   if(zone.origin_time <= 0)
      return;

   if(PFLS_IsZonePreviouslyMitigated(zone))
      return;

   if(PFLS_MitigatedCount >= PFLS_MAX_MITIGATED_ZONES)
      return;

   PFLS_MitigatedOrigin[PFLS_MitigatedCount] =
      zone.origin_time;

   PFLS_MitigatedTimeframe[PFLS_MitigatedCount] =
      zone.timeframe;

   PFLS_MitigatedDemand[PFLS_MitigatedCount] =
      zone.is_demand;

   PFLS_MitigatedCount++;

   PFLS_Log(
      "ZONE MITIGATED | " +
      EnumToString(zone.timeframe) +
      " | " +
      (zone.is_demand ? "DEMAND" : "SUPPLY")
   );
}

//--------------------------------------------------------------------

void PFLS_FilterMitigatedZone(
   PFLS_ZoneRecord &zone
)
{
   if(!zone.active)
      return;

   if(PFLS_IsZonePreviouslyMitigated(zone))
   {
      zone.active = false;
      zone.state = PFLS_ZONE_STATE_TOUCHED;
   }
}

//====================================================================
// APPLY ZONE FILTERS
//====================================================================

void PFLS_FilterAllMitigatedZones()
{
   for(int i = 0; i < PFLS_MAIN_TIMEFRAME_COUNT; i++)
   {
      PFLS_FilterMitigatedZone(
         PFLS_Flow.ladder[i].demand
      );

      PFLS_FilterMitigatedZone(
         PFLS_Flow.ladder[i].supply
      );
   }
}

//====================================================================
// LIVE ZONE INTERACTION
//====================================================================

void PFLS_UpdateLiveZoneInteractions(
   const double previous_price,
   const double current_price,
   const datetime event_time
)
{
   if(previous_price <= 0 || current_price <= 0)
      return;

   for(int i = 0; i < PFLS_MAIN_TIMEFRAME_COUNT; i++)
   {
      // DEMAND
      if(PFLS_Flow.ladder[i].demand.active)
      {
         PFLS_UpdateZoneInteractionPath(
            PFLS_Flow.ladder[i].demand,
            previous_price,
            current_price,
            event_time
         );

         if(PFLS_Flow.ladder[i].demand.first_touch_time > 0)
         {
            PFLS_RegisterMitigatedZone(
               PFLS_Flow.ladder[i].demand
            );
         }
      }

      // SUPPLY
      if(PFLS_Flow.ladder[i].supply.active)
      {
         PFLS_UpdateZoneInteractionPath(
            PFLS_Flow.ladder[i].supply,
            previous_price,
            current_price,
            event_time
         );

         if(PFLS_Flow.ladder[i].supply.first_touch_time > 0)
         {
            PFLS_RegisterMitigatedZone(
               PFLS_Flow.ladder[i].supply
            );
         }
      }
   }

   PFLS_FilterAllMitigatedZones();
}

//====================================================================
// OBJECTIVE INTERACTION
//====================================================================

void PFLS_UpdateLiveObjective(
   const double previous_price,
   const double current_price,
   const datetime event_time
)
{
   if(!PFLS_Flow.objective.valid)
      return;

   if(previous_price <= 0 || current_price <= 0)
      return;

   PFLS_UpdateObjectiveInteractionPath(
      PFLS_Flow.objective,
      previous_price,
      current_price,
      PFLS_Flow.d1_bias,
      event_time
   );
}

//====================================================================
// PRICE FLOW SCAN
//====================================================================

bool PFLS_RunPriceFlowScan()
{
   string symbol = PFLS_GetMarketSymbol();

   if(!SymbolSelect(symbol, true))
   {
      PFLS_StatusMessage = "MARKET SYMBOL NOT AVAILABLE";
      PFLS_DataAvailable = false;
      return false;
   }

   bool result = PFLS_UpdatePriceFlow(
      symbol,
      InpLookbackBars,
      InpPivotStrength,
      PFLS_Flow
   );

   if(!result)
   {
      PFLS_StatusMessage = "WAITING FOR MULTI-TIMEFRAME DATA";
      PFLS_DataAvailable = false;
      return false;
   }

   // Remove zones already touched during this session.
   PFLS_FilterAllMitigatedZones();

   PFLS_LastScanTime = TimeCurrent();

   PFLS_DataAvailable = true;

   PFLS_StatusMessage = "MULTI-TIMEFRAME RESEARCH ACTIVE";

   PFLS_Log("PRICE FLOW SCAN COMPLETED");

   return true;
}

//====================================================================
// M5 ENTRY RESEARCH
//====================================================================

void PFLS_RunEntryResearch()
{
   if(!InpEnableEntryResearch)
   {
      PFLS_ResetEntryResult(PFLS_CurrentEntry);
      PFLS_ResetTradePlan(PFLS_CurrentTradePlan);
      return;
   }

   if(!PFLS_DataAvailable)
      return;

   // Entry hypotheses require directional permission.
   if(!PFLS_Flow.directional_objective_allowed)
   {
      PFLS_ResetEntryResult(PFLS_CurrentEntry);
      PFLS_ResetTradePlan(PFLS_CurrentTradePlan);

      return;
   }

   // An observation-only objective is not an entry target.
   if(!PFLS_Flow.objective.valid ||
      PFLS_Flow.objective.status == PFLS_OBJECTIVE_OBSERVATION_ONLY ||
      PFLS_Flow.objective.status == PFLS_OBJECTIVE_INVALIDATED ||
      PFLS_Flow.objective.status == PFLS_OBJECTIVE_RESOLVED)
   {
      PFLS_ResetEntryResult(PFLS_CurrentEntry);
      PFLS_ResetTradePlan(PFLS_CurrentTradePlan);

      return;
   }

   MqlRates m5_rates[];

   ArraySetAsSeries(m5_rates, true);

   int copied = CopyRates(
      PFLS_GetMarketSymbol(),
      PERIOD_M5,
      0,
      InpLookbackBars,
      m5_rates
   );

   if(copied < 20)
      return;

   PFLS_EntryResult candidate;

   ZeroMemory(candidate);

   bool evaluated = PFLS_EvaluateEntry(
      m5_rates,
      copied,
      PERIOD_M5,
      PFLS_Flow.ladder[6].demand,
      PFLS_Flow.ladder[6].supply,
      PFLS_Flow.ladder[6].structure,
      PFLS_Flow,
      InpMinimumWickRatio,
      candidate
   );

   if(!evaluated || !candidate.valid)
   {
      PFLS_ResetEntryResult(PFLS_CurrentEntry);
      PFLS_ResetTradePlan(PFLS_CurrentTradePlan);
      return;
   }

   // Avoid repeatedly recording the same completed M5 signal.
   if(candidate.confirmation_time <= PFLS_LastM5SignalTime)
      return;

   PFLS_LastM5SignalTime = candidate.confirmation_time;

   PFLS_CurrentEntry = candidate;

   PFLS_Log(
      "NEW M5 ENTRY HYPOTHESIS | " +
      candidate.explanation
   );

   // Determine the target from the selected objective.
   double objective_target = 0.0;

   if(candidate.signal == PFLS_ENTRY_BUY_CANDIDATE &&
      candidate.objective_is_supply)
   {
      objective_target = candidate.objective_lower;
   }
   else if(candidate.signal == PFLS_ENTRY_SELL_CANDIDATE &&
           !candidate.objective_is_supply)
   {
      objective_target = candidate.objective_upper;
   }

   if(objective_target <= 0)
   {
      PFLS_ResetTradePlan(PFLS_CurrentTradePlan);
      PFLS_Log("TRADE PLAN NOT BUILT: INVALID OBJECTIVE TARGET");
      return;
   }

   PFLS_ResetTradePlan(PFLS_CurrentTradePlan);

   bool plan_created = PFLS_BuildTradePlan(
      PFLS_GetMarketSymbol(),
      PFLS_CurrentEntry,
      PFLS_Risk,
      objective_target,
      PFLS_CurrentTradePlan
   );

   if(!plan_created || !PFLS_CurrentTradePlan.valid)
   {
      PFLS_Log(
         "TRADE PLAN REJECTED | " +
         PFLS_CurrentTradePlan.rejection_reason
      );

      return;
   }

   PFLS_Log(
      "RESEARCH TRADE PLAN CREATED | RR: " +
      DoubleToString(PFLS_CurrentTradePlan.risk_reward, 2)
   );
}

//====================================================================
// EXECUTION SAFETY INSPECTION
//====================================================================

void PFLS_UpdateExecutionSafety()
{
   PFLS_CheckExecutionSafety(
      PFLS_GetMarketSymbol(),
      InpEnableExecution,
      InpEmergencyStop,
      PFLS_Execution
   );

   // Independent permanent execution lock.
   // This research build never sends orders.

   if(PFLS_IsOrderExecutionAllowed(PFLS_Execution))
   {
      PFLS_Log("UNEXPECTED EXECUTION AUTHORIZATION STATE");
   }
}

//====================================================================
// DASHBOARD HELPERS
//====================================================================

string PFLS_ZoneText(const PFLS_ZoneRecord &zone)
{
   if(!zone.active)
      return "NO ACTIVE FRESH ZONE";

   return
      DoubleToString(zone.lower, _Digits) +
      " - " +
      DoubleToString(zone.upper, _Digits);
}

//--------------------------------------------------------------------

string PFLS_ObjectiveText()
{
   if(!PFLS_Flow.objective.valid)
      return "NO VALID OBJECTIVE";

   string direction =
      PFLS_Flow.objective.is_supply ?
      "SUPPLY ABOVE" :
      "DEMAND BELOW";

   return
      direction +
      " | " +
      EnumToString(PFLS_Flow.objective.source_timeframe) +
      " | " +
      DoubleToString(PFLS_Flow.objective.lower, _Digits) +
      " - " +
      DoubleToString(PFLS_Flow.objective.upper, _Digits);
}

//--------------------------------------------------------------------

string PFLS_EntryText()
{
   if(!PFLS_CurrentEntry.valid)
      return "NO CONFIRMED ENTRY HYPOTHESIS";

   if(PFLS_CurrentEntry.signal == PFLS_ENTRY_BUY_CANDIDATE)
      return "BUY CANDIDATE";

   if(PFLS_CurrentEntry.signal == PFLS_ENTRY_SELL_CANDIDATE)
      return "SELL CANDIDATE";

   if(PFLS_CurrentEntry.signal == PFLS_ENTRY_AMBIGUOUS)
      return "AMBIGUOUS SIGNAL";

   return "NO ENTRY";
}

//====================================================================
// DASHBOARD
//====================================================================

void PFLS_UpdateDashboard()
{
   if(!InpShowChartStatus)
      return;

   string symbol = PFLS_GetMarketSymbol();

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

   string dashboard = "";

   dashboard += "====================================\n";
   dashboard += "          PFLS TRADER 2.00\n";
   dashboard += "       MULTI-TIMEFRAME RESEARCH\n";
   dashboard += "====================================\n";

   dashboard += "SYMBOL: " + symbol + "\n";

   dashboard +=
      "PRICE: " +
      DoubleToString(bid, _Digits) +
      "\n";

   dashboard +=
      "DATA: " +
      (PFLS_DataAvailable ? "CONNECTED" : "WAITING") +
      "\n";

   dashboard +=
      "STATUS: " +
      PFLS_StatusMessage +
      "\n\n";

   dashboard += "---------- PRICE FLOW ----------\n";

   dashboard +=
      "W1 CONTEXT: " +
      PFLS_DirectionText(PFLS_Flow.w1_context) +
      "\n";

   dashboard +=
      "D1 BIAS: " +
      PFLS_DirectionText(PFLS_Flow.d1_bias) +
      "\n";

   dashboard +=
      "D1 EVIDENCE: " +
      PFLS_D1EvidenceText(PFLS_Flow.d1_evidence) +
      "\n";

   dashboard +=
      "DIRECTIONAL PERMISSION: " +
      (PFLS_Flow.directional_objective_allowed ?
       "YES" : "SUSPENDED") +
      "\n";

   dashboard +=
      "OBJECTIVE: " +
      PFLS_ObjectiveText() +
      "\n";

   dashboard +=
      "OBJECTIVE STATUS: " +
      PFLS_ObjectiveStatusText(PFLS_Flow.objective.status) +
      "\n\n";

   dashboard += "---------- ACTIVE ZONES ----------\n";

   dashboard +=
      "D1 DEMAND: " +
      PFLS_ZoneText(PFLS_Flow.ladder[1].demand) +
      "\n";

   dashboard +=
      "D1 SUPPLY: " +
      PFLS_ZoneText(PFLS_Flow.ladder[1].supply) +
      "\n";

   dashboard +=
      "H4 DEMAND: " +
      PFLS_ZoneText(PFLS_Flow.ladder[2].demand) +
      "\n";

   dashboard +=
      "H4 SUPPLY: " +
      PFLS_ZoneText(PFLS_Flow.ladder[2].supply) +
      "\n";

   dashboard +=
      "M5 DEMAND: " +
      PFLS_ZoneText(PFLS_Flow.ladder[6].demand) +
      "\n";

   dashboard +=
      "M5 SUPPLY: " +
      PFLS_ZoneText(PFLS_Flow.ladder[6].supply) +
      "\n\n";

   dashboard += "---------- ENTRY RESEARCH ----------\n";

   dashboard +=
      "M5 ENTRY: " +
      PFLS_EntryText() +
      "\n";

   dashboard +=
      "ENTRY DETAIL: " +
      (PFLS_CurrentEntry.valid ?
       PFLS_CurrentEntry.explanation :
       "WAITING FOR VALID SETUP") +
      "\n";

   dashboard +=
      "TRADE PLAN: " +
      (PFLS_CurrentTradePlan.valid ?
       "VALID RESEARCH PLAN" :
       "NOT VALIDATED") +
      "\n";

   if(PFLS_CurrentTradePlan.valid)
   {
      dashboard +=
         "ENTRY: " +
         DoubleToString(PFLS_CurrentTradePlan.entry_price, _Digits) +
         "\n";

      dashboard +=
         "STOP: " +
         DoubleToString(PFLS_CurrentTradePlan.stop_loss, _Digits) +
         "\n";

      dashboard +=
         "TARGET: " +
         DoubleToString(PFLS_CurrentTradePlan.take_profit, _Digits) +
         "\n";

      dashboard +=
         "RISK/REWARD: 1:" +
         DoubleToString(PFLS_CurrentTradePlan.risk_reward, 2) +
         "\n";
   }

   dashboard += "\n---------- EXECUTION SAFETY ----------\n";

   dashboard +=
      "EXECUTION STATE: " +
      PFLS_ExecutionStateText(PFLS_Execution.state) +
      "\n";

   dashboard +=
      "DEMO ACCOUNT: " +
      (PFLS_Execution.account_is_demo ? "YES" : "NO") +
      "\n";

   dashboard +=
      "SAFETY CHECKS: " +
      (PFLS_Execution.safety_checks_passed ? "PASSED" : "NOT PASSED") +
      "\n";

   dashboard += "ORDER EXECUTION: PERMANENTLY DISABLED\n";

   dashboard += "\n---------- DEVELOPMENT ----------\n";

   dashboard +=
      "ZONE MODULE: " +
      PFLS_GetZoneModuleVersion() +
      "\n";

   dashboard +=
      "STRUCTURE MODULE: " +
      PFLS_GetStructureModuleVersion() +
      "\n";

   dashboard +=
      "PRICE FLOW: " +
      PFLS_GetPriceFlowVersion() +
      "\n";

   dashboard +=
      "ENTRY ENGINE: " +
      PFLS_GetEntryModuleVersion() +
      "\n";

   dashboard +=
      "RISK MANAGER: " +
      PFLS_GetRiskModuleVersion() +
      "\n";

   dashboard +=
      "EXECUTION MODULE: " +
      PFLS_GetExecutionModuleVersion() +
      "\n";

   dashboard += "WIN-RATE GOAL: 70% - RESEARCH TARGET ONLY\n";
   dashboard += "NO VERIFIED WIN RATE YET\n";

   dashboard += "====================================";

   Comment(dashboard);
}

//====================================================================
// INITIALISATION
//====================================================================

int OnInit()
{
   string symbol = PFLS_GetMarketSymbol();

   if(!SymbolSelect(symbol, true))
   {
      Print("PFLS INITIALISATION FAILED: SYMBOL NOT AVAILABLE");
      return INIT_FAILED;
   }

   if(InpLookbackBars < 50 ||
      InpPivotStrength < 1 ||
      InpScanIntervalSeconds < 1)
   {
      Print("PFLS INITIALISATION FAILED: INVALID INPUT SETTINGS");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Initialise zone history.
   PFLS_InitialiseZoneHistory();

   // Initialise price-flow state.
   PFLS_InitialisePriceFlow(PFLS_Flow);

   // Initialise risk configuration.
   PFLS_ResetRiskConfig(PFLS_Risk);

   // Execution remains disabled regardless of user inputs.
   PFLS_Risk.execution_enabled = false;
   PFLS_Risk.emergency_stop = InpEmergencyStop;

   PFLS_ValidateRiskConfig(PFLS_Risk);

   PFLS_ResetTradePlan(PFLS_CurrentTradePlan);

   PFLS_ResetExecutionStatus(PFLS_Execution);

   ZeroMemory(PFLS_CurrentEntry);

   PFLS_MitigatedCount = 0;

   PFLS_PreviousTickPrice = 0.0;
   PFLS_CurrentTickPrice = 0.0;

   PFLS_Initialised = true;

   // First research scan.
   PFLS_RunPriceFlowScan();

   // Execution inspection.
   PFLS_UpdateExecutionSafety();

   // Timer-based research updates.
   EventSetTimer(InpScanIntervalSeconds);

   PFLS_UpdateDashboard();

   PFLS_Log("PFLS TRADER 2.00 INITIALISED");
   PFLS_Log("RESEARCH MODE - ORDER EXECUTION DISABLED");

   return INIT_SUCCEEDED;
}

//====================================================================
// TIMER
//====================================================================

void OnTimer()
{
   if(!PFLS_Initialised)
      return;

   PFLS_RunPriceFlowScan();

   PFLS_RunEntryResearch();

   PFLS_UpdateExecutionSafety();

   PFLS_UpdateDashboard();
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   if(!PFLS_Initialised)
      return;

   string symbol = PFLS_GetMarketSymbol();

   MqlTick tick;

   if(!SymbolInfoTick(symbol, tick))
      return;

   PFLS_PreviousTickPrice = PFLS_CurrentTickPrice;

   PFLS_CurrentTickPrice = tick.bid;

   if(PFLS_PreviousTickPrice > 0 &&
      PFLS_CurrentTickPrice > 0)
   {
      datetime event_time = TimeCurrent();

      // Track zone first-touch events on incoming ticks.
      PFLS_UpdateLiveZoneInteractions(
         PFLS_PreviousTickPrice,
         PFLS_CurrentTickPrice,
         event_time
      );

      // Track objective interaction independently.
      PFLS_UpdateLiveObjective(
         PFLS_PreviousTickPrice,
         PFLS_CurrentTickPrice,
         event_time
      );
   }

   PFLS_UpdateDashboard();
}

//====================================================================
// DEINITIALISATION
//====================================================================

void OnDeinit(const int reason)
{
   EventKillTimer();

   Comment("");

   PFLS_Initialised = false;

   PFLS_Log(
      "PFLS TRADER STOPPED | REASON: " +
      IntegerToString(reason)
   );
}

//+------------------------------------------------------------------+
