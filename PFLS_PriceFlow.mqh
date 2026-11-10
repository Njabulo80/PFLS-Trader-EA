
#ifndef PFLS_PRICE_FLOW_MQH
#define PFLS_PRICE_FLOW_MQH

//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| PRICE FLOW ENGINE                                                |
//| Version 2.00.1                                                   |
//|                                                                  |
//| W1: Higher-timeframe context                                     |
//| D1: Broad directional context                                    |
//| H4-M1: Price-flow ladder                                         |
//|                                                                  |
//| Immediate objective may originate from ANY timeframe.           |
//| Research module only. No trade execution.                       |
//+------------------------------------------------------------------+

#include "PFLS_Zones.mqh"
#include "PFLS_MarketStructure.mqh"

#define PFLS_PRICE_FLOW_VERSION "2.00.1"

//====================================================================
// CONFIGURATION
//====================================================================

#define PFLS_W1_INDEX 0
#define PFLS_D1_INDEX 1
#define PFLS_H4_INDEX 2
#define PFLS_H1_INDEX 3
#define PFLS_M30_INDEX 4
#define PFLS_M15_INDEX 5
#define PFLS_M5_INDEX 6
#define PFLS_M1_INDEX 7

//====================================================================
// OBJECTIVE STATUS
//====================================================================

enum PFLS_OBJECTIVE_STATUS
{
   PFLS_OBJECTIVE_NONE = 0,
   PFLS_OBJECTIVE_SELECTED,
   PFLS_OBJECTIVE_APPROACHING,
   PFLS_OBJECTIVE_INTERACTING,
   PFLS_OBJECTIVE_RESOLVED,
   PFLS_OBJECTIVE_INVALIDATED,
   PFLS_OBJECTIVE_OBSERVATION_ONLY
};

//====================================================================
// TIMEFRAME SNAPSHOT
//====================================================================

struct PFLS_TimeframeSnapshot
{
   ENUM_TIMEFRAMES timeframe;

   bool data_available;

   PFLS_ZoneRecord demand;
   PFLS_ZoneRecord supply;

   PFLS_MarketStructure structure;

   double current_price;

   datetime last_update;
};

//====================================================================
// PRICE FLOW OBJECTIVE
//====================================================================

struct PFLS_PriceFlowObjective
{
   bool valid;
   bool locked;
   bool interaction_started;

   bool is_supply;

   double upper;
   double lower;

   ENUM_TIMEFRAMES source_timeframe;

   PFLS_DIRECTION direction;

   PFLS_OBJECTIVE_STATUS status;

   datetime selection_time;
   datetime interaction_time;
   datetime resolution_time;
};

//====================================================================
// PRICE FLOW ENGINE STATE
//====================================================================

struct PFLS_PriceFlowState
{
   PFLS_TimeframeSnapshot ladder[PFLS_TIMEFRAME_COUNT];

   PFLS_DIRECTION w1_context;
   PFLS_DIRECTION d1_bias;

   PFLS_DIRECTION previous_d1_bias;

   bool directional_objective_allowed;

   double current_price;

   PFLS_PriceFlowObjective objective;

   datetime last_analysis_time;
};

//====================================================================
// RESET OBJECTIVE
//====================================================================

void PFLS_ResetObjective(PFLS_PriceFlowObjective &objective)
{
   objective.valid = false;
   objective.locked = false;
   objective.interaction_started = false;

   objective.is_supply = false;

   objective.upper = 0.0;
   objective.lower = 0.0;

   objective.source_timeframe = PERIOD_CURRENT;

   objective.direction = PFLS_DIRECTION_NEUTRAL;

   objective.status = PFLS_OBJECTIVE_NONE;

   objective.selection_time = 0;
   objective.interaction_time = 0;
   objective.resolution_time = 0;
}

//====================================================================
// INITIALISE PRICE FLOW STATE
//====================================================================

void PFLS_InitialisePriceFlow(PFLS_PriceFlowState &state)
{
   for(int i = 0; i < PFLS_TIMEFRAME_COUNT; i++)
   {
      state.ladder[i].timeframe =
         (ENUM_TIMEFRAMES)0;

      state.ladder[i].data_available = false;

      state.ladder[i].current_price = 0.0;
      state.ladder[i].last_update = 0;

      PFLS_ResetZoneRecord(state.ladder[i].demand);
      PFLS_ResetZoneRecord(state.ladder[i].supply);

      PFLS_ResetMarketStructure(state.ladder[i].structure);
   }

   state.w1_context = PFLS_DIRECTION_NEUTRAL;
   state.d1_bias = PFLS_DIRECTION_NEUTRAL;

   state.previous_d1_bias = PFLS_DIRECTION_NEUTRAL;

   state.directional_objective_allowed = false;

   state.current_price = 0.0;

   PFLS_ResetObjective(state.objective);

   state.last_analysis_time = 0;
}

//====================================================================
// COPY OBJECTIVE
//====================================================================

void PFLS_CopyObjective(
   const PFLS_PriceFlowObjective &source,
   PFLS_PriceFlowObjective &destination)
{
   destination.valid = source.valid;
   destination.locked = source.locked;
   destination.interaction_started =
      source.interaction_started;

   destination.is_supply = source.is_supply;

   destination.upper = source.upper;
   destination.lower = source.lower;

   destination.source_timeframe =
      source.source_timeframe;

   destination.direction = source.direction;

   destination.status = source.status;

   destination.selection_time = source.selection_time;
   destination.interaction_time = source.interaction_time;
   destination.resolution_time = source.resolution_time;
}

//====================================================================
// SCAN ONE TIMEFRAME
//====================================================================

bool PFLS_UpdateTimeframeSnapshot(
   const string symbol,
   const ENUM_TIMEFRAMES timeframe,
   const int lookback,
   const int pivot_strength,
   PFLS_TimeframeSnapshot &snapshot)
{
   snapshot.timeframe = timeframe;
   snapshot.data_available = false;

   PFLS_ResetZoneRecord(snapshot.demand);
   PFLS_ResetZoneRecord(snapshot.supply);

   PFLS_ResetMarketStructure(snapshot.structure);

   MqlRates rates[];

   ArraySetAsSeries(rates, true);

   int copied = CopyRates(
      symbol,
      timeframe,
      0,
      lookback,
      rates);

   if(copied < 50)
      return false;

   snapshot.current_price =
      SymbolInfoDouble(symbol, SYMBOL_BID);

   if(snapshot.current_price <= 0.0)
      return false;

   bool zones_found = PFLS_ScanZones(
      symbol,
      timeframe,
      lookback,
      pivot_strength,
      snapshot.demand,
      snapshot.supply);

   bool structure_found = PFLS_AnalyseMarketStructure(
      rates,
      copied,
      pivot_strength,
      lookback - pivot_strength - 2,
      snapshot.structure);

   snapshot.data_available = true;
   snapshot.last_update = TimeCurrent();

   // A timeframe is available even if it has no qualifying zones.
   // Structure and zone availability are tracked separately.

   return true;
}

//====================================================================
// SELECT W1 CONTEXT
//====================================================================

PFLS_DIRECTION PFLS_GetW1Context(
   const PFLS_TimeframeSnapshot &w1)
{
   if(!w1.data_available)
      return PFLS_DIRECTION_NEUTRAL;

   return w1.structure.direction;
}

//====================================================================
// SELECT D1 BIAS
//====================================================================

PFLS_DIRECTION PFLS_GetD1Bias(
   const PFLS_TimeframeSnapshot &d1)
{
   if(!d1.data_available)
      return PFLS_DIRECTION_NEUTRAL;

   // Initial research implementation:
   // D1 confirmed structure provides the provisional broad bias.
   //
   // Zone reactions, structural acceptance and the complete
   // D1 transition rules will be integrated in a later revision.

   return d1.structure.direction;
}

//====================================================================
// CHECK WHETHER PRICE INTERSECTS A ZONE
//====================================================================

bool PFLS_PriceInsideZone(
   const double price,
   const double upper,
   const double lower)
{
   if(upper <= lower)
      return false;

   return (price >= lower && price <= upper);
}

//====================================================================
// CHECK OBJECTIVE INTERACTION
//====================================================================

void PFLS_UpdateObjectiveInteraction(
   PFLS_PriceFlowObjective &objective,
   const double price,
   const PFLS_DIRECTION current_d1_bias)
{
   if(!objective.valid || !objective.locked)
      return;

   // A confirmed opposite D1 directional bias overrides the lock.
   if(current_d1_bias != PFLS_DIRECTION_NEUTRAL &&
      current_d1_bias != PFLS_DIRECTION_CONFLICTED &&
      current_d1_bias != objective.direction)
   {
      objective.status = PFLS_OBJECTIVE_INVALIDATED;
      objective.valid = false;
      objective.locked = false;
      objective.resolution_time = TimeCurrent();

      return;
   }

   bool inside = PFLS_PriceInsideZone(
      price,
      objective.upper,
      objective.lower);

   if(inside)
   {
      if(!objective.interaction_started)
      {
         objective.interaction_started = true;
         objective.interaction_time = TimeCurrent();
      }

      objective.status = PFLS_OBJECTIVE_INTERACTING;

      return;
   }

   // Once interaction has started, price leaving the zone
   // resolves this objective for this research version.

   if(objective.interaction_started)
   {
      objective.status = PFLS_OBJECTIVE_RESOLVED;
      objective.valid = false;
      objective.locked = false;
      objective.resolution_time = TimeCurrent();
   }
   else
   {
      objective.status = PFLS_OBJECTIVE_APPROACHING;
   }
}

//====================================================================
// SELECT NEAREST OBJECTIVE FROM ALL TIMEFRAMES
//====================================================================

bool PFLS_SelectNearestObjective(
   PFLS_PriceFlowState &state)
{
   if(!state.directional_objective_allowed)
      return false;

   double best_distance = DBL_MAX;

   int best_timeframe = -1;

   bool best_is_supply = false;

   double best_upper = 0.0;
   double best_lower = 0.0;

   // Bullish flow seeks a valid supply objective above price.
   // Bearish flow seeks a valid demand objective below price.
   //
   // All eight timeframes compete equally in this initial
   // nearest-objective selection.

   for(int i = 0; i < PFLS_TIMEFRAME_COUNT; i++)
   {
      if(!state.ladder[i].data_available)
         continue;

      if(state.d1_bias == PFLS_DIRECTION_BULLISH)
      {
         if(!state.ladder[i].supply.active)
            continue;

         double distance =
            state.ladder[i].supply.lower -
            state.current_price;

         if(distance <= 0.0)
            continue;

         if(distance < best_distance)
         {
            best_distance = distance;
            best_timeframe = i;

            best_is_supply = true;

            best_upper = state.ladder[i].supply.upper;
            best_lower = state.ladder[i].supply.lower;
         }
      }
      else if(state.d1_bias == PFLS_DIRECTION_BEARISH)
      {
         if(!state.ladder[i].demand.active)
            continue;

         double distance =
            state.current_price -
            state.ladder[i].demand.upper;

         if(distance <= 0.0)
            continue;

         if(distance < best_distance)
         {
            best_distance = distance;
            best_timeframe = i;

            best_is_supply = false;

            best_upper = state.ladder[i].demand.upper;
            best_lower = state.ladder[i].demand.lower;
         }
      }
   }

   if(best_timeframe < 0)
      return false;

   PFLS_ResetObjective(state.objective);

   state.objective.valid = true;
   state.objective.locked = false;
   state.objective.interaction_started = false;

   state.objective.is_supply = best_is_supply;

   state.objective.upper = best_upper;
   state.objective.lower = best_lower;

   state.objective.source_timeframe =
      state.ladder[best_timeframe].timeframe;

   state.objective.direction = state.d1_bias;

   state.objective.status = PFLS_OBJECTIVE_SELECTED;

   state.objective.selection_time = TimeCurrent();

   return true;
}

//====================================================================
// UPDATE OBJECTIVE LOCK
//====================================================================

void PFLS_ManageObjectiveLock(
   PFLS_PriceFlowState &state)
{
   if(!state.objective.valid)
      return;

   // Update interaction and check structural invalidation.
   PFLS_UpdateObjectiveInteraction(
      state.objective,
      state.current_price,
      state.d1_bias);

   // Entering the objective locks it against ordinary
   // reassignment until the interaction is resolved.
   if(state.objective.valid &&
      PFLS_PriceInsideZone(
         state.current_price,
         state.objective.upper,
         state.objective.lower))
   {
      state.objective.locked = true;
   }
}

//====================================================================
// UPDATE COMPLETE PRICE FLOW ENGINE
//====================================================================

bool PFLS_UpdatePriceFlow(
   const string symbol,
   const int lookback,
   const int pivot_strength,
   PFLS_PriceFlowState &state)
{
   if(lookback < 50 || pivot_strength < 1)
      return false;

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

   if(bid <= 0.0)
      return false;

   state.current_price = bid;

   // Preserve the prior objective and bias before refreshing
   // the timeframe data.
   PFLS_PriceFlowObjective previous_objective;

   PFLS_CopyObjective(
      state.objective,
      previous_objective);

   PFLS_DIRECTION previous_bias = state.d1_bias;

   // Scan all eight timeframes.
   for(int i = 0; i < PFLS_TIMEFRAME_COUNT; i++)
   {
      ENUM_TIMEFRAMES timeframe =
         (ENUM_TIMEFRAMES)0;

      switch(i)
      {
         case PFLS_W1_INDEX: timeframe = PERIOD_W1; break;
         case PFLS_D1_INDEX: timeframe = PERIOD_D1; break;
         case PFLS_H4_INDEX: timeframe = PERIOD_H4; break;
         case PFLS_H1_INDEX: timeframe = PERIOD_H1; break;
         case PFLS_M30_INDEX: timeframe = PERIOD_M30; break;
         case PFLS_M15_INDEX: timeframe = PERIOD_M15; break;
         case PFLS_M5_INDEX: timeframe = PERIOD_M5; break;
         case PFLS_M1_INDEX: timeframe = PERIOD_M1; break;
      }

      PFLS_UpdateTimeframeSnapshot(
         symbol,
         timeframe,
         lookback,
         pivot_strength,
         state.ladder[i]);
   }

   // Refresh higher-timeframe context and bias.
   state.w1_context =
      PFLS_GetW1Context(state.ladder[PFLS_W1_INDEX]);

   state.d1_bias =
      PFLS_GetD1Bias(state.ladder[PFLS_D1_INDEX]);

   state.previous_d1_bias = previous_bias;

   state.directional_objective_allowed =
      (state.d1_bias == PFLS_DIRECTION_BULLISH ||
       state.d1_bias == PFLS_DIRECTION_BEARISH);

   // Restore an existing locked objective.
   if(previous_objective.valid &&
      previous_objective.locked)
   {
      PFLS_CopyObjective(
         previous_objective,
         state.objective);

      PFLS_ManageObjectiveLock(state);
   }
   else
   {
      PFLS_ResetObjective(state.objective);

      if(state.directional_objective_allowed)
      {
         PFLS_SelectNearestObjective(state);

         PFLS_ManageObjectiveLock(state);
      }
      else
      {
         // Neutral/conflicted D1:
         // no new directional objective is selected.
         // Existing reference is not promoted to a new target.
         state.objective.status =
            PFLS_OBJECTIVE_OBSERVATION_ONLY;
      }
   }

   state.last_analysis_time = TimeCurrent();

   return true;
}

//====================================================================
// PRICE LOCATION DESCRIPTION
//====================================================================

string PFLS_GetPriceFlowLocation(
   const PFLS_PriceFlowState &state)
{
   if(state.current_price <= 0.0)
      return "PRICE UNAVAILABLE";

   bool inside_demand = false;
   bool inside_supply = false;

   for(int i = 0; i < PFLS_TIMEFRAME_COUNT; i++)
   {
      if(!state.ladder[i].data_available)
         continue;

      if(state.ladder[i].demand.active &&
         PFLS_PriceInsideZone(
            state.current_price,
            state.ladder[i].demand.upper,
            state.ladder[i].demand.lower))
      {
         inside_demand = true;
      }

      if(state.ladder[i].supply.active &&
         PFLS_PriceInsideZone(
            state.current_price,
            state.ladder[i].supply.upper,
            state.ladder[i].supply.lower))
      {
         inside_supply = true;
      }
   }

   if(inside_demand && inside_supply)
      return "OVERLAPPING ACTIVE ZONES";

   if(inside_demand)
      return "INSIDE FRESH DEMAND";

   if(inside_supply)
      return "INSIDE FRESH SUPPLY";

   return "BETWEEN ACTIVE ZONES";
}

//====================================================================
// OBJECTIVE STATUS TEXT
//====================================================================

string PFLS_ObjectiveStatusText(
   const PFLS_OBJECTIVE_STATUS status)
{
   switch(status)
   {
      case PFLS_OBJECTIVE_NONE:
         return "NONE";

      case PFLS_OBJECTIVE_SELECTED:
         return "SELECTED";

      case PFLS_OBJECTIVE_APPROACHING:
         return "APPROACHING";

      case PFLS_OBJECTIVE_INTERACTING:
         return "INTERACTING";

      case PFLS_OBJECTIVE_RESOLVED:
         return "RESOLVED";

      case PFLS_OBJECTIVE_INVALIDATED:
         return "INVALIDATED";

      case PFLS_OBJECTIVE_OBSERVATION_ONLY:
         return "OBSERVATION ONLY";
   }

   return "UNKNOWN";
}

//====================================================================
// OBJECTIVE DESCRIPTION
//====================================================================

string PFLS_GetObjectiveDescription(
   const PFLS_PriceFlowState &state,
   const int digits)
{
   if(!state.objective.valid)
   {
      if(state.objective.status ==
         PFLS_OBJECTIVE_OBSERVATION_ONLY)
      {
         return "DIRECTIONAL OBJECTIVE SUSPENDED";
      }

      return "NO ACTIVE OBJECTIVE";
   }

   string type =
      state.objective.is_supply ? "SUPPLY" : "DEMAND";

   return type + " | " +
          EnumToString(state.objective.source_timeframe) +
          " | " +
          DoubleToString(state.objective.lower, digits) +
          " - " +
          DoubleToString(state.objective.upper, digits);
}

//====================================================================
// MODULE VERSION
//====================================================================

string PFLS_GetPriceFlowVersion()
{
   return PFLS_PRICE_FLOW_VERSION;
}

//+------------------------------------------------------------------+
#endif // PFLS_PRICE_FLOW_MQH
