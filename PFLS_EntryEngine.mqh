
#ifndef PFLS_ENTRY_ENGINE_MQH
#define PFLS_ENTRY_ENGINE_MQH

//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| ENTRY ENGINE                                                     |
//| Version 2.00.3                                                   |
//|                                                                  |
//| Research-only entry hypothesis.                                 |
//| No order placement.                                              |
//+------------------------------------------------------------------+

#include "PFLS_PriceFlow.mqh"

#define PFLS_ENTRY_MODULE_VERSION "2.00.3"

//====================================================================
// SIGNAL TYPES
//====================================================================

enum PFLS_ENTRY_SIGNAL
{
   PFLS_ENTRY_NONE = 0,
   PFLS_ENTRY_BUY_CANDIDATE,
   PFLS_ENTRY_SELL_CANDIDATE,
   PFLS_ENTRY_AMBIGUOUS
};

//====================================================================
// ENTRY RESULT
//====================================================================

struct PFLS_EntryResult
{
   bool              valid;
   PFLS_ENTRY_SIGNAL signal;

   ENUM_TIMEFRAMES   timeframe;

   double            candidate_price;
   double            rejection_high;
   double            rejection_low;

   double            zone_upper;
   double            zone_lower;

   double            structural_reference;

   datetime          rejection_time;
   datetime          confirmation_time;

   datetime          entry_zone_origin_time;

   ENUM_TIMEFRAMES   objective_timeframe;
   double            objective_upper;
   double            objective_lower;
   bool              objective_is_supply;

   string            explanation;
};

//====================================================================
// RESET ENTRY RESULT
//====================================================================

void PFLS_ResetEntryResult(PFLS_EntryResult &result)
{
   result.valid = false;
   result.signal = PFLS_ENTRY_NONE;

   result.timeframe = PERIOD_M5;

   result.candidate_price = 0.0;
   result.rejection_high = 0.0;
   result.rejection_low = 0.0;

   result.zone_upper = 0.0;
   result.zone_lower = 0.0;

   result.structural_reference = 0.0;

   result.rejection_time = 0;
   result.confirmation_time = 0;

   result.entry_zone_origin_time = 0;

   result.objective_timeframe = PERIOD_CURRENT;
   result.objective_upper = 0.0;
   result.objective_lower = 0.0;
   result.objective_is_supply = false;

   result.explanation = "NO CONFIRMED ENTRY CANDIDATE";
}

//====================================================================
// CANDLE BODY
//====================================================================

double PFLS_EntryCandleBody(const MqlRates &candle)
{
   return MathAbs(candle.close - candle.open);
}

//====================================================================
// LOWER WICK
//====================================================================

double PFLS_EntryLowerWick(const MqlRates &candle)
{
   double body_low = MathMin(candle.open, candle.close);

   return MathMax(0.0, body_low - candle.low);
}

//====================================================================
// UPPER WICK
//====================================================================

double PFLS_EntryUpperWick(const MqlRates &candle)
{
   double body_high = MathMax(candle.open, candle.close);

   return MathMax(0.0, candle.high - body_high);
}

//====================================================================
// CANDLE-ZONE INTERACTION
//====================================================================

bool PFLS_EntryCandleIntersectsZone(
   const MqlRates &candle,
   const double zone_upper,
   const double zone_lower)
{
   if(zone_upper <= zone_lower)
      return false;

   return (
      candle.high >= zone_lower &&
      candle.low <= zone_upper
   );
}

//====================================================================
// VERIFY SEPARATE M5 ENTRY ZONE
//====================================================================

bool PFLS_IsSeparateM5EntryZone(
   const PFLS_ZoneRecord &entry_zone,
   const PFLS_PriceFlowState &flow)
{
   if(!entry_zone.active)
      return false;

   if(entry_zone.timeframe != PERIOD_M5)
      return false;

   if(entry_zone.upper <= entry_zone.lower)
      return false;

   if(!PFLS_IsZoneFresh(entry_zone))
      return false;

   if(!flow.objective.valid)
      return false;

   if(flow.objective.upper <= flow.objective.lower)
      return false;

   // Entry and objective must be separate price areas.
   // Overlap and exact boundary contact are rejected.

   double overlap_upper = MathMin(
      entry_zone.upper,
      flow.objective.upper
   );

   double overlap_lower = MathMax(
      entry_zone.lower,
      flow.objective.lower
   );

   if(overlap_upper >= overlap_lower)
      return false;

   return true;
}

//====================================================================
// BULLISH REJECTION TEST
//====================================================================

bool PFLS_IsBullishZoneRejection(
   const MqlRates &candle,
   const PFLS_ZoneRecord &zone,
   const double minimum_wick_ratio)
{
   if(!zone.active || !zone.is_demand)
      return false;

   if(!PFLS_IsZoneFresh(zone))
      return false;

   if(!PFLS_EntryCandleIntersectsZone(
      candle,
      zone.upper,
      zone.lower))
      return false;

   if(candle.close <= candle.open)
      return false;

   double body = PFLS_EntryCandleBody(candle);
   double lower_wick = PFLS_EntryLowerWick(candle);

   if(body <= 0.0)
      return false;

   if(lower_wick < body * minimum_wick_ratio)
      return false;

   double midpoint = (zone.upper + zone.lower) / 2.0;

   if(candle.close <= midpoint)
      return false;

   return true;
}

//====================================================================
// BEARISH REJECTION TEST
//====================================================================

bool PFLS_IsBearishZoneRejection(
   const MqlRates &candle,
   const PFLS_ZoneRecord &zone,
   const double minimum_wick_ratio)
{
   if(!zone.active || zone.is_demand)
      return false;

   if(!PFLS_IsZoneFresh(zone))
      return false;

   if(!PFLS_EntryCandleIntersectsZone(
      candle,
      zone.upper,
      zone.lower))
      return false;

   if(candle.close >= candle.open)
      return false;

   double body = PFLS_EntryCandleBody(candle);
   double upper_wick = PFLS_EntryUpperWick(candle);

   if(body <= 0.0)
      return false;

   if(upper_wick < body * minimum_wick_ratio)
      return false;

   double midpoint = (zone.upper + zone.lower) / 2.0;

   if(candle.close >= midpoint)
      return false;

   return true;
}

//====================================================================
// STRUCTURE DIRECTION FILTER
//====================================================================

bool PFLS_EntryStructureSupportsBuy(
   const PFLS_MarketStructure &structure)
{
   if(structure.direction == PFLS_DIRECTION_BULLISH)
      return true;

   if(structure.bullish_bos && !structure.bearish_bos)
      return true;

   return false;
}

//====================================================================
// STRUCTURE DIRECTION FILTER
//====================================================================

bool PFLS_EntryStructureSupportsSell(
   const PFLS_MarketStructure &structure)
{
   if(structure.direction == PFLS_DIRECTION_BEARISH)
      return true;

   if(structure.bearish_bos && !structure.bullish_bos)
      return true;

   return false;
}

//====================================================================
// BUY OBJECTIVE VALIDATION
// BUY MUST TARGET SUPPLY ABOVE CURRENT PRICE
//====================================================================

bool PFLS_EntryObjectiveSupportsBuy(
   const PFLS_PriceFlowState &flow)
{
   if(!flow.objective.valid)
      return false;

   if(flow.objective.status == PFLS_OBJECTIVE_INVALIDATED ||
      flow.objective.status == PFLS_OBJECTIVE_RESOLVED ||
      flow.objective.status == PFLS_OBJECTIVE_OBSERVATION_ONLY)
      return false;

   // Correct direction: BUY targets supply.
   if(!flow.objective.is_supply)
      return false;

   if(flow.d1_bias != PFLS_DIRECTION_BULLISH)
      return false;

   if(!flow.directional_objective_allowed)
      return false;

   if(flow.current_price <= 0.0)
      return false;

   // Supply objective must be above current price.
   if(flow.objective.lower <= flow.current_price)
      return false;

   return true;
}

//====================================================================
// SELL OBJECTIVE VALIDATION
// SELL MUST TARGET DEMAND BELOW CURRENT PRICE
//====================================================================

bool PFLS_EntryObjectiveSupportsSell(
   const PFLS_PriceFlowState &flow)
{
   if(!flow.objective.valid)
      return false;

   if(flow.objective.status == PFLS_OBJECTIVE_INVALIDATED ||
      flow.objective.status == PFLS_OBJECTIVE_RESOLVED ||
      flow.objective.status == PFLS_OBJECTIVE_OBSERVATION_ONLY)
      return false;

   // Correct direction: SELL targets demand.
   if(flow.objective.is_supply)
      return false;

   if(flow.d1_bias != PFLS_DIRECTION_BEARISH)
      return false;

   if(!flow.directional_objective_allowed)
      return false;

   if(flow.current_price <= 0.0)
      return false;

   // Demand objective must be below current price.
   if(flow.objective.upper >= flow.current_price)
      return false;

   return true;
}

//====================================================================
// EVALUATE BUY CANDIDATE
//====================================================================

bool PFLS_EvaluateBuyCandidate(
   const MqlRates &rates[],
   const int total,
   const ENUM_TIMEFRAMES timeframe,
   const PFLS_ZoneRecord &demand_zone,
   const PFLS_MarketStructure &structure,
   const PFLS_PriceFlowState &flow,
   const double minimum_wick_ratio,
   PFLS_EntryResult &result)
{
   PFLS_ResetEntryResult(result);

   if(timeframe != PERIOD_M5)
      return false;

   if(total < 4 || minimum_wick_ratio <= 0.0)
      return false;

   if(!demand_zone.active || !demand_zone.is_demand)
      return false;

   if(!PFLS_IsSeparateM5EntryZone(demand_zone, flow))
      return false;

   if(!PFLS_EntryObjectiveSupportsBuy(flow))
      return false;

   if(!PFLS_EntryStructureSupportsBuy(structure))
      return false;

   // Series indexing:
   // rates[2] = completed rejection candle
   // rates[1] = completed confirmation candle
   // rates[0] = current forming candle

   const MqlRates rejection = rates[2];
   const MqlRates confirmation = rates[1];

   if(!PFLS_IsBullishZoneRejection(
      rejection,
      demand_zone,
      minimum_wick_ratio))
      return false;

   if(confirmation.time <= rejection.time)
      return false;

   if(confirmation.close <= rejection.high)
      return false;

   if(confirmation.close <= confirmation.open)
      return false;

   // Candidate must remain below the supply objective.
   if(flow.objective.lower <= confirmation.close)
      return false;

   result.valid = true;
   result.signal = PFLS_ENTRY_BUY_CANDIDATE;

   result.timeframe = PERIOD_M5;

   result.candidate_price = confirmation.close;

   result.rejection_high = rejection.high;
   result.rejection_low = rejection.low;

   result.zone_upper = demand_zone.upper;
   result.zone_lower = demand_zone.lower;

   result.structural_reference = structure.protected_low;

   result.rejection_time = rejection.time;
   result.confirmation_time = confirmation.time;

   result.entry_zone_origin_time = demand_zone.origin_time;

   result.objective_timeframe = flow.objective.source_timeframe;
   result.objective_upper = flow.objective.upper;
   result.objective_lower = flow.objective.lower;
   result.objective_is_supply = flow.objective.is_supply;

   result.explanation =
      "Bullish D1 bias + separate fresh M5 demand retracement "
      "+ bullish rejection + next completed candle breakout "
      "+ bullish M5 structure + supply objective above entry";

   return true;
}

//====================================================================
// EVALUATE SELL CANDIDATE
//====================================================================

bool PFLS_EvaluateSellCandidate(
   const MqlRates &rates[],
   const int total,
   const ENUM_TIMEFRAMES timeframe,
   const PFLS_ZoneRecord &supply_zone,
   const PFLS_MarketStructure &structure,
   const PFLS_PriceFlowState &flow,
   const double minimum_wick_ratio,
   PFLS_EntryResult &result)
{
   PFLS_ResetEntryResult(result);

   if(timeframe != PERIOD_M5)
      return false;

   if(total < 4 || minimum_wick_ratio <= 0.0)
      return false;

   if(!supply_zone.active || supply_zone.is_demand)
      return false;

   if(!PFLS_IsSeparateM5EntryZone(supply_zone, flow))
      return false;

   if(!PFLS_EntryObjectiveSupportsSell(flow))
      return false;

   if(!PFLS_EntryStructureSupportsSell(structure))
      return false;

   const MqlRates rejection = rates[2];
   const MqlRates confirmation = rates[1];

   if(!PFLS_IsBearishZoneRejection(
      rejection,
      supply_zone,
      minimum_wick_ratio))
      return false;

   if(confirmation.time <= rejection.time)
      return false;

   if(confirmation.close >= rejection.low)
      return false;

   if(confirmation.close >= confirmation.open)
      return false;

   // Candidate must remain above the demand objective.
   if(flow.objective.upper >= confirmation.close)
      return false;

   result.valid = true;
   result.signal = PFLS_ENTRY_SELL_CANDIDATE;

   result.timeframe = PERIOD_M5;

   result.candidate_price = confirmation.close;

   result.rejection_high = rejection.high;
   result.rejection_low = rejection.low;

   result.zone_upper = supply_zone.upper;
   result.zone_lower = supply_zone.lower;

   result.structural_reference = structure.protected_high;

   result.rejection_time = rejection.time;
   result.confirmation_time = confirmation.time;

   result.entry_zone_origin_time = supply_zone.origin_time;

   result.objective_timeframe = flow.objective.source_timeframe;
   result.objective_upper = flow.objective.upper;
   result.objective_lower = flow.objective.lower;
   result.objective_is_supply = flow.objective.is_supply;

   result.explanation =
      "Bearish D1 bias + separate fresh M5 supply retracement "
      "+ bearish rejection + next completed candle breakout "
      "+ bearish M5 structure + demand objective below entry";

   return true;
}

//====================================================================
// EVALUATE BOTH DIRECTIONS
//====================================================================

bool PFLS_EvaluateEntry(
   const MqlRates &rates[],
   const int total,
   const ENUM_TIMEFRAMES timeframe,
   const PFLS_ZoneRecord &demand_zone,
   const PFLS_ZoneRecord &supply_zone,
   const PFLS_MarketStructure &structure,
   const PFLS_PriceFlowState &flow,
   const double minimum_wick_ratio,
   PFLS_EntryResult &result)
{
   PFLS_ResetEntryResult(result);

   if(timeframe != PERIOD_M5)
      return false;

   if(total < 4 || minimum_wick_ratio <= 0.0)
      return false;

   PFLS_EntryResult buy_result;
   PFLS_EntryResult sell_result;

   PFLS_ResetEntryResult(buy_result);
   PFLS_ResetEntryResult(sell_result);

   bool buy_found = PFLS_EvaluateBuyCandidate(
      rates,
      total,
      timeframe,
      demand_zone,
      structure,
      flow,
      minimum_wick_ratio,
      buy_result);

   bool sell_found = PFLS_EvaluateSellCandidate(
      rates,
      total,
      timeframe,
      supply_zone,
      structure,
      flow,
      minimum_wick_ratio,
      sell_result);

   if(buy_found && sell_found)
   {
      result.signal = PFLS_ENTRY_AMBIGUOUS;
      result.explanation =
         "Conflicting buy and sell candidates. No candidate selected.";

      return false;
   }

   if(buy_found)
   {
      result = buy_result;
      return true;
   }

   if(sell_found)
   {
      result = sell_result;
      return true;
   }

   return false;
}

//====================================================================
// SIGNAL DESCRIPTION
//====================================================================

string PFLS_EntrySignalText(
   const PFLS_ENTRY_SIGNAL signal)
{
   switch(signal)
   {
      case PFLS_ENTRY_NONE:
         return "NONE";

      case PFLS_ENTRY_BUY_CANDIDATE:
         return "BUY CANDIDATE";

      case PFLS_ENTRY_SELL_CANDIDATE:
         return "SELL CANDIDATE";

      case PFLS_ENTRY_AMBIGUOUS:
         return "AMBIGUOUS";
   }

   return "UNKNOWN";
}

//====================================================================
// MODULE VERSION
//====================================================================

string PFLS_GetEntryModuleVersion()
{
   return PFLS_ENTRY_MODULE_VERSION;
}

//+------------------------------------------------------------------+
#endif // PFLS_ENTRY_ENGINE_MQH
