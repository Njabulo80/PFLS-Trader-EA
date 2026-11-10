
#ifndef PFLS_PRICE_FLOW_MQH
#define PFLS_PRICE_FLOW_MQH

//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| PRICE FLOW ENGINE                                                |
//| Version 2.00.2                                                   |
//|                                                                  |
//| W1: Higher-timeframe context                                     |
//| D1: Combined structure and zone directional evidence            |
//| H4-M1: Price-flow ladder                                         |
//|                                                                  |
//| Immediate objective may originate from any eligible timeframe.  |
//| Research only. No trade execution.                               |
//+------------------------------------------------------------------+

#include "PFLS_Zones.mqh"
#include "PFLS_MarketStructure.mqh"

#define PFLS_PRICE_FLOW_VERSION "2.00.2"

#ifndef PFLS_TIMEFRAME_COUNT
#define PFLS_TIMEFRAME_COUNT 8
#endif

//====================================================================
// TIMEFRAME INDEXES
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
// D1 BIAS EVIDENCE
//====================================================================

enum PFLS_BIAS_EVIDENCE
{
   PFLS_BIAS_EVIDENCE_NONE = 0,
   PFLS_BIAS_EVIDENCE_STRUCTURE_ONLY,
   PFLS_BIAS_EVIDENCE_STRUCTURE_ZONE_AGREEMENT,
   PFLS_BIAS_EVIDENCE_CONFLICT
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

   PFLS_BIAS_EVIDENCE d1_evidence;

   bool directional_objective_allowed;

   double current_price;
   double previous_price;

   PFLS_PriceFlowObjective objective;

   datetime last_analysis_time;
};

//====================================================================
// RESET OBJECTIVE
//====================================================================

void PFLS_ResetObjective(
   PFLS_PriceFlowObjective &objective)
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

void PFLS_InitialisePriceFlow(
   PFLS_PriceFlowState &state)
{
   for(int i = 0; i < PFLS_TIMEFRAME_COUNT; i++)
   {
      state.ladder[i].timeframe = (ENUM_TIMEFRAMES)0;

      state.ladder[i].data_available = false;

      state.ladder[i].current_price = 0.0;
      state.ladder[i].last_update = 0;

      PFLS_ResetZoneRecord(state.ladder[i].demand);
      PFLS_ResetZoneRecord(state.ladder[i].supply);

      PFLS_ResetMarketStructure(
         state.ladder[i].structure);
   }

   state.w1_context = PFLS_DIRECTION_NEUTRAL;
   state.d1_bias = PFLS_DIRECTION_NEUTRAL;
   state.previous_d1_bias = PFLS_DIRECTION_NEUTRAL;

   state.d1_evidence = PFLS_BIAS_EVIDENCE_NONE;

   state.directional_objective_allowed = false;

   state.current_price = 0.0;
   state.previous_price = 0.0;

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
// GET TIMEFRAME FROM INDEX
//====================================================================

ENUM_TIMEFRAMES PFLS_TimeframeFromIndex(
   const int index)
{
   switch(index)
   {
      case PFLS_W1_INDEX:  return PERIOD_W1;
      case PFLS_D1_INDEX:  return PERIOD_D1;
      case PFLS_H4_INDEX:  return PERIOD_H4;
      case PFLS_H1_INDEX:  return PERIOD_H1;
      case PFLS_M30_INDEX: return PERIOD_M30;
      case PFLS_M15_INDEX: return PERIOD_M15;
      case PFLS_M5_INDEX:  return PERIOD_M5;
      case PFLS_M1_INDEX:  return PERIOD_M1;
   }

   return PERIOD_CURRENT;
}

//====================================================================
// CLEAR FAILED SNAPSHOT
//====================================================================

void PFLS_ClearTimeframeSnapshot(
   PFLS_TimeframeSnapshot &snapshot,
   const ENUM_TIMEFRAMES timeframe)
{
   snapshot.timeframe = timeframe;

   snapshot.data_available = false;

   snapshot.current_price = 0.0;
   snapshot.last_update = 0;

   PFLS_ResetZoneRecord(snapshot.demand);
   PFLS_ResetZoneRecord(snapshot.supply);

   PFLS_ResetMarketStructure(snapshot.structure);
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
   PFLS_ClearTimeframeSnapshot(
      snapshot,
      timeframe);

   if(lookback < 50 || pivot_strength < 1)
      return false;

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

   double bid = SymbolInfoDouble(
      symbol,
      SYMBOL_BID);

   if(bid <= 0.0)
      return false;

   snapshot.current_price = bid;

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

   // A timeframe is available even if no fresh zones
   // or confirmed structure are found.
   snapshot.data_available = true;

   snapshot.last_update = TimeCurrent();

   return true;
}

//====================================================================
// SELECT W1 CONTEXT
// W1 is contextual evidence, not the immediate objective
// direction controller.
//====================================================================

PFLS_DIRECTION PFLS_GetW1Context(
   const PFLS_TimeframeSnapshot &w1)
{
   if(!w1.data_available)
      return PFLS_DIRECTION_NEUTRAL;

   return w1.structure.direction;
}

//====================================================================
// CHECK WHETHER PRICE IS INSIDE A ZONE
//====================================================================

bool PFLS_PriceInsideZone(
   const double price,
   const double upper,
   const double lower)
{
   if(upper <= lower || price <= 0.0)
      return false;

   return (
      price >= lower &&
      price <= upper
   );
}

//====================================================================
// D1 ZONE DIRECTIONAL EVIDENCE
//
// Fresh demand below price supports bullish context.
// Fresh supply above price supports bearish context.
//
// The nearest eligible D1 zone supplies the zone vote.
// If there is no eligible D1 zone, zone evidence is absent.
//====================================================================

PFLS_DIRECTION PFLS_GetD1ZoneEvidence(
   const PFLS_TimeframeSnapshot &d1,
   const double price)
{
   if(!d1.data_available || price <= 0.0)
      return PFLS_DIRECTION_NEUTRAL;

   bool demand_valid =
      d1.demand.active &&
      d1.demand.is_demand &&
      d1.demand.upper < price;

   bool supply_valid =
      d1.supply.active &&
      !d1.supply.is_demand &&
      d1.supply.lower > price;

   if(!demand_valid && !supply_valid)
      return PFLS_DIRECTION_NEUTRAL;

   if(demand_valid && !supply_valid)
      return PFLS_DIRECTION_BULLISH;

   if(supply_valid && !demand_valid)
      return PFLS_DIRECTION_BEARISH;

   double demand_distance =
      price - d1.demand.upper;

   double supply_distance =
      d1.supply.lower - price;

   if(demand_distance < supply_distance)
      return PFLS_DIRECTION_BULLISH;

   if(supply_distance < demand_distance)
      return PFLS_DIRECTION_BEARISH;

   return PFLS_DIRECTION_CONFLICTED;
}

//====================================================================
// SELECT D1 BIAS
//
// Conservative combined model:
// 1. Confirmed D1 structure provides the structure vote.
// 2. Nearest fresh D1 zone provides the zone vote.
// 3. Agreement permits directional objectives.
// 4. Disagreement suspends new directional objectives.
//
// This is a research-stage proxy. Candle reaction and
// structural acceptance still require further validation.
//====================================================================

PFLS_DIRECTION PFLS_GetD1Bias(
   const PFLS_TimeframeSnapshot &d1,
   const double price,
   PFLS_BIAS_EVIDENCE &evidence)
{
   evidence = PFLS_BIAS_EVIDENCE_NONE;

   if(!d1.data_available)
      return PFLS_DIRECTION_NEUTRAL;

   PFLS_DIRECTION structure_vote =
      d1.structure.direction;

   PFLS_DIRECTION zone_vote =
      PFLS_GetD1ZoneEvidence(d1, price);

   bool structure_directional =
      (structure_vote == PFLS_DIRECTION_BULLISH ||
       structure_vote == PFLS_DIRECTION_BEARISH);

   bool zone_directional =
      (zone_vote == PFLS_DIRECTION_BULLISH ||
       zone_vote == PFLS_DIRECTION_BEARISH);

   if(!structure_directional && !zone_directional)
   {
      if(structure_vote == PFLS_DIRECTION_CONFLICTED ||
         zone_vote == PFLS_DIRECTION_CONFLICTED)
      {
         evidence = PFLS_BIAS_EVIDENCE_CONFLICT;
         return PFLS_DIRECTION_CONFLICTED;
      }

      return PFLS_DIRECTION_NEUTRAL;
   }

   // Both evidence sources must agree before a
   // combined directional bias is authorised.
   if(structure_directional && zone_directional)
   {
      if(structure_vote == zone_vote)
      {
         evidence =
            PFLS_BIAS_EVIDENCE_STRUCTURE_ZONE_AGREEMENT;

         return structure_vote;
      }

      evidence = PFLS_BIAS_EVIDENCE_CONFLICT;

      return PFLS_DIRECTION_CONFLICTED;
   }

   // Structure without zone confirmation is recorded
   // but is not sufficient for a new directional target.
   evidence = PFLS_BIAS_EVIDENCE_STRUCTURE_ONLY;

   return PFLS_DIRECTION_NEUTRAL;
}

//====================================================================
// CHECK OBJECTIVE INVALIDATION
//====================================================================

bool PFLS_ObjectiveBiasInvalidated(
   const PFLS_PriceFlowObjective &objective,
   const PFLS_DIRECTION current_d1_bias)
{
   if(!objective.valid)
      return false;

   if(current_d1_bias == PFLS_DIRECTION_NEUTRAL ||
      current_d1_bias == PFLS_DIRECTION_CONFLICTED)
   {
      return false;
   }

   return (current_d1_bias != objective.direction);
}

//====================================================================
// UPDATE OBJECTIVE INTERACTION USING PRICE PATH
//====================================================================

void PFLS_UpdateObjectiveInteractionPath(
   PFLS_PriceFlowObjective &objective,
   const double previous_price,
   const double current_price,
   const PFLS_DIRECTION current_d1_bias,
   const datetime event_time)
{
   if(!objective.valid || !objective.locked)
      return;

   // Confirmed opposite D1 bias overrides the lock.
   if(PFLS_ObjectiveBiasInvalidated(
      objective,
      current_d1_bias))
   {
      objective.status = PFLS_OBJECTIVE_INVALIDATED;

      objective.valid = false;
      objective.locked = false;

      objective.resolution_time = event_time;

      return;
   }

   bool path_intersects =
      PFLS_PricePathIntersectsZone(
         previous_price,
         current_price,
         objective.upper,
         objective.lower);

   bool currently_inside =
      PFLS_PriceInsideZone(
         current_price,
         objective.upper,
         objective.lower);

   if(!objective.interaction_started &&
      (path_intersects || currently_inside))
   {
      objective.interaction_started = true;

      objective.interaction_time = event_time;

      objective.status = PFLS_OBJECTIVE_INTERACTING;

      return;
   }

   if(!objective.interaction_started)
   {
      objective.status = PFLS_OBJECTIVE_APPROACHING;

      return;
   }

   if(currently_inside)
   {
      objective.status = PFLS_OBJECTIVE_INTERACTING;

      return;
   }

   // After first interaction, leaving the zone on either
   // side completes the zone interaction observation.
   //
   // This does NOT prove a successful reversal or rejection.
   // The market-structure engine must evaluate the response.

   if(current_price > objective.upper ||
      current_price < objective.lower)
   {
      objective.status = PFLS_OBJECTIVE_RESOLVED;

      objective.valid = false;
      objective.locked = false;

      objective.resolution_time = event_time;
   }
}

//====================================================================
// LEGACY OBJECTIVE INTERACTION INTERFACE
//====================================================================

void PFLS_UpdateObjectiveInteraction(
   PFLS_PriceFlowObjective &objective,
   const double price,
   const PFLS_DIRECTION current_d1_bias)
{
   PFLS_UpdateObjectiveInteractionPath(
      objective,
      price,
      price,
      current_d1_bias,
      TimeCurrent());
}

//====================================================================
// TIMEFRAME PRIORITY
//
// Distance remains the primary selection factor.
// When distances are equal, higher timeframe receives
// priority as the tie-breaker.
// W1 is excluded from immediate objective selection.
//====================================================================

int PFLS_GetObjectiveTimeframePriority(
   const int timeframe_index)
{
   switch(timeframe_index)
   {
      case PFLS_D1_INDEX:  return 1;
      case PFLS_H4_INDEX:  return 2;
      case PFLS_H1_INDEX:  return 3;
      case PFLS_M30_INDEX: return 4;
      case PFLS_M15_INDEX: return 5;
      case PFLS_M5_INDEX:  return 6;
      case PFLS_M1_INDEX:  return 7;
   }

   return 99;
}

//====================================================================
// SELECT NEAREST OBJECTIVE FROM ALL ELIGIBLE TIMEFRAMES
//====================================================================

bool PFLS_SelectNearestObjective(
   PFLS_PriceFlowState &state)
{
   if(!state.directional_objective_allowed ||
      state.current_price <= 0.0)
   {
      return false;
   }

   double best_distance = DBL_MAX;

   int best_timeframe = -1;
   int best_priority = 99;

   bool best_is_supply = false;

   double best_upper = 0.0;
   double best_lower = 0.0;

   for(int i = PFLS_D1_INDEX;
       i < PFLS_TIMEFRAME_COUNT;
       i++)
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

         int priority =
            PFLS_GetObjectiveTimeframePriority(i);

         bool nearer = distance < best_distance;

         bool equal_distance_better_priority =
            (MathAbs(distance - best_distance) <=
             _Point * 0.5 &&
             priority < best_priority);

         if(nearer || equal_distance_better_priority)
         {
            best_distance = distance;
            best_timeframe = i;
            best_priority = priority;

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

         int priority =
            PFLS_GetObjectiveTimeframePriority(i);

         bool nearer = distance < best_distance;

         bool equal_distance_better_priority =
            (MathAbs(distance - best_distance) <=
             _Point * 0.5 &&
             priority < best_priority);

         if(nearer || equal_distance_better_priority)
         {
            best_distance = distance;
            best_timeframe = i;
            best_priority = priority;

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

   PFLS_UpdateObjectiveInteractionPath(
      state.objective,
      state.previous_price,
      state.current_price,
      state.d1_bias,
      TimeCurrent());

   if(!state.objective.valid)
      return;

   bool inside = PFLS_PriceInsideZone(
      state.current_price,
      state.objective.upper,
      state.objective.lower);

   bool path_intersects =
      PFLS_PricePathIntersectsZone(
         state.previous_price,
         state.current_price,
         state.objective.upper,
         state.objective.lower);

   if(inside || path_intersects ||
      state.objective.interaction_started)
   {
      state.objective.locked = true;
   }

   if(!state.objective.interaction_started &&
      !inside &&
      !path_intersects)
   {
      state.objective.status =
         PFLS_OBJECTIVE_APPROACHING;
   }
}

//====================================================================
// PRESERVE OBJECTIVE AS OBSERVATION REFERENCE
//====================================================================

void PFLS_SetObjectiveObservationOnly(
   PFLS_PriceFlowObjective &objective)
{
   if(!objective.valid)
      return;

   objective.status =
      PFLS_OBJECTIVE_OBSERVATION_ONLY;

   // Preserve its price boundaries, source timeframe,
   // direction and interaction history.
   // It is no longer treated as a newly authorised target.
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

   double bid = SymbolInfoDouble(
      symbol,
      SYMBOL_BID);

   if(bid <= 0.0)
      return false;

   state.previous_price = state.current_price;
   state.current_price = bid;

   // Preserve the previous objective before refreshing data.
   PFLS_PriceFlowObjective previous_objective;

   PFLS_CopyObjective(
      state.objective,
      previous_objective);

   PFLS_DIRECTION previous_bias =
      state.d1_bias;

   // Scan all eight timeframes.
   for(int i = 0; i < PFLS_TIMEFRAME_COUNT; i++)
   {
      ENUM_TIMEFRAMES timeframe =
         PFLS_TimeframeFromIndex(i);

      PFLS_UpdateTimeframeSnapshot(
         symbol,
         timeframe,
         lookback,
         pivot_strength,
         state.ladder[i]);
   }

   // Refresh W1 context.
   state.w1_context =
      PFLS_GetW1Context(
         state.ladder[PFLS_W1_INDEX]);

   // Refresh combined D1 directional evidence.
   state.d1_bias =
      PFLS_GetD1Bias(
         state.ladder[PFLS_D1_INDEX],
         state.current_price,
         state.d1_evidence);

   state.previous_d1_bias = previous_bias;

   state.directional_objective_allowed =
      (state.d1_bias == PFLS_DIRECTION_BULLISH ||
       state.d1_bias == PFLS_DIRECTION_BEARISH);

   //===============================================================
   // EXISTING OBJECTIVE MANAGEMENT
   //===============================================================

   if(previous_objective.valid)
   {
      PFLS_CopyObjective(
         previous_objective,
         state.objective);

      // Opposite confirmed directional bias invalidates
      // the previous objective.
      if(PFLS_ObjectiveBiasInvalidated(
         state.objective,
         state.d1_bias))
      {
         state.objective.status =
            PFLS_OBJECTIVE_INVALIDATED;

         state.objective.valid = false;
         state.objective.locked = false;

         state.objective.resolution_time =
            TimeCurrent();
      }
      else if(!state.directional_objective_allowed)
      {
         // Neutral/conflicted D1:
         // retain the previous objective as an observation.
         PFLS_SetObjectiveObservationOnly(
            state.objective);
      }
      else
      {
         // If the bias has returned in the same direction,
         // resume management of the preserved reference.
         if(state.objective.direction == state.d1_bias)
         {
            if(state.objective.status ==
               PFLS_OBJECTIVE_OBSERVATION_ONLY)
            {
               state.objective.status =
                  state.objective.interaction_started
                  ? PFLS_OBJECTIVE_INTERACTING
                  : PFLS_OBJECTIVE_APPROACHING;
            }

            if(state.objective.locked)
            {
               PFLS_ManageObjectiveLock(state);
            }
         }
         else
         {
            state.objective.valid = false;
            state.objective.locked = false;

            state.objective.status =
               PFLS_OBJECTIVE_INVALIDATED;

            state.objective.resolution_time =
               TimeCurrent();
         }
      }
   }

   //===============================================================
   // SELECT A NEW OBJECTIVE ONLY WHEN NONE IS PRESERVED
   //===============================================================

   if(!state.objective.valid &&
      state.directional_objective_allowed)
   {
      PFLS_SelectNearestObjective(state);

      if(state.objective.valid)
      {
         PFLS_ManageObjectiveLock(state);
      }
   }

   //===============================================================
   // NEUTRAL OR CONFLICTED D1
   //===============================================================

   if(!state.directional_objective_allowed &&
      !state.objective.valid)
   {
      state.objective.status =
         PFLS_OBJECTIVE_OBSERVATION_ONLY;
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
// D1 EVIDENCE DESCRIPTION
//====================================================================

string PFLS_D1EvidenceText(
   const PFLS_BIAS_EVIDENCE evidence)
{
   switch(evidence)
   {
      case PFLS_BIAS_EVIDENCE_NONE:
         return "NO D1 EVIDENCE";

      case PFLS_BIAS_EVIDENCE_STRUCTURE_ONLY:
         return "STRUCTURE ONLY";

      case PFLS_BIAS_EVIDENCE_STRUCTURE_ZONE_AGREEMENT:
         return "STRUCTURE + ZONE AGREEMENT";

      case PFLS_BIAS_EVIDENCE_CONFLICT:
         return "D1 EVIDENCE CONFLICT";
   }

   return "UNKNOWN";
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
