
#ifndef PFLS_ZONES_MQH
#define PFLS_ZONES_MQH

//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| ZONE DETECTION MODULE                                            |
//| Version 2.00.3                                                   |
//|                                                                  |
//| Research only. No trade execution.                               |
//|                                                                  |
//| Improvements:                                                    |
//| - Confirmed pivot detection                                      |
//| - Structural break validation                                    |
//| - Corrected origin selection                                     |
//| - First-entry mitigation detection                               |
//| - Historical zone record support                                 |
//| - Price-path interaction detection                               |
//| - Correct partial/full traversal lifecycle                      |
//+------------------------------------------------------------------+

#define PFLS_ZONE_MODULE_VERSION "2.00.3"

#ifndef PFLS_ZONE_HISTORY_CAPACITY
#define PFLS_ZONE_HISTORY_CAPACITY 512
#endif

//====================================================================
// ZONE LIFECYCLE
//====================================================================

enum PFLS_ZONE_STATE
{
   PFLS_ZONE_INVALID = 0,
   PFLS_ZONE_UNTESTED,
   PFLS_ZONE_TOUCHED,
   PFLS_ZONE_PARTIALLY_PENETRATED,
   PFLS_ZONE_FULLY_TRAVERSED
};

//====================================================================
// ACTIVE ZONE RECORD
// Keep compatible with File 4.
//====================================================================

struct PFLS_ZoneRecord
{
   bool              active;
   bool              is_demand;

   double            upper;
   double            lower;

   datetime          origin_time;
   datetime          detection_time;
   datetime          first_touch_time;

   ENUM_TIMEFRAMES   timeframe;

   PFLS_ZONE_STATE   state;
};

//====================================================================
// HISTORICAL ZONE RECORD
//====================================================================

struct PFLS_ZoneHistoryRecord
{
   bool              valid;
   bool              is_demand;

   double            upper;
   double            lower;

   datetime          origin_time;
   datetime          detection_time;
   datetime          first_touch_time;
   datetime          last_update_time;

   ENUM_TIMEFRAMES   timeframe;

   PFLS_ZONE_STATE   state;

   double            deepest_price;
};

//====================================================================
// HISTORY STORAGE
//====================================================================

PFLS_ZoneHistoryRecord
   PFLS_ZoneHistory[PFLS_ZONE_HISTORY_CAPACITY];

int PFLS_ZoneHistoryCount = 0;

//====================================================================
// RESET ACTIVE ZONE
//====================================================================

void PFLS_ResetZoneRecord(PFLS_ZoneRecord &zone)
{
   zone.active = false;
   zone.is_demand = false;

   zone.upper = 0.0;
   zone.lower = 0.0;

   zone.origin_time = 0;
   zone.detection_time = 0;
   zone.first_touch_time = 0;

   zone.timeframe = PERIOD_CURRENT;

   zone.state = PFLS_ZONE_INVALID;
}

//====================================================================
// RESET HISTORY RECORD
//====================================================================

void PFLS_ResetZoneHistoryRecord(
   PFLS_ZoneHistoryRecord &zone)
{
   zone.valid = false;
   zone.is_demand = false;

   zone.upper = 0.0;
   zone.lower = 0.0;

   zone.origin_time = 0;
   zone.detection_time = 0;
   zone.first_touch_time = 0;
   zone.last_update_time = 0;

   zone.timeframe = PERIOD_CURRENT;

   zone.state = PFLS_ZONE_INVALID;

   zone.deepest_price = 0.0;
}

//====================================================================
// INITIALISE HISTORY
//====================================================================

void PFLS_InitialiseZoneHistory()
{
   PFLS_ZoneHistoryCount = 0;

   for(int i = 0;
       i < PFLS_ZONE_HISTORY_CAPACITY;
       i++)
   {
      PFLS_ResetZoneHistoryRecord(
         PFLS_ZoneHistory[i]);
   }
}

//====================================================================
// CONFIRMED PIVOT HIGH
//====================================================================

bool PFLS_IsPivotHigh(
   const MqlRates &rates[],
   const int index,
   const int strength,
   const int total)
{
   if(strength < 1)
      return false;

   if(index - strength < 1)
      return false;

   if(index + strength >= total)
      return false;

   double pivot = rates[index].high;

   for(int i = 1; i <= strength; i++)
   {
      if(rates[index-i].high >= pivot)
         return false;

      if(rates[index+i].high > pivot)
         return false;
   }

   return true;
}

//====================================================================
// CONFIRMED PIVOT LOW
//====================================================================

bool PFLS_IsPivotLow(
   const MqlRates &rates[],
   const int index,
   const int strength,
   const int total)
{
   if(strength < 1)
      return false;

   if(index - strength < 1)
      return false;

   if(index + strength >= total)
      return false;

   double pivot = rates[index].low;

   for(int i = 1; i <= strength; i++)
   {
      if(rates[index-i].low <= pivot)
         return false;

      if(rates[index+i].low < pivot)
         return false;
   }

   return true;
}

//====================================================================
// FIND DEMAND ORIGIN
// Most recent bearish candle between pivot and breakout.
// The breakout candle at index 1 is excluded.
//====================================================================

int PFLS_FindDemandOrigin(
   const MqlRates &rates[],
   const int pivot_index)
{
   if(pivot_index <= 2)
      return -1;

   for(int i = 2; i < pivot_index; i++)
   {
      if(rates[i].close < rates[i].open)
         return i;
   }

   return -1;
}

//====================================================================
// FIND SUPPLY ORIGIN
//====================================================================

int PFLS_FindSupplyOrigin(
   const MqlRates &rates[],
   const int pivot_index)
{
   if(pivot_index <= 2)
      return -1;

   for(int i = 2; i < pivot_index; i++)
   {
      if(rates[i].close > rates[i].open)
         return i;
   }

   return -1;
}

//====================================================================
// DEMAND BOUNDARIES
//====================================================================

void PFLS_CalculateDemandBoundaries(
   const MqlRates &rates[],
   const int origin_index,
   double &upper,
   double &lower)
{
   upper = MathMax(
      rates[origin_index].open,
      rates[origin_index].close);

   lower = rates[origin_index].low;
}

//====================================================================
// SUPPLY BOUNDARIES
//====================================================================

void PFLS_CalculateSupplyBoundaries(
   const MqlRates &rates[],
   const int origin_index,
   double &upper,
   double &lower)
{
   upper = rates[origin_index].high;

   lower = MathMin(
      rates[origin_index].open,
      rates[origin_index].close);
}

//====================================================================
// PRICE INTERSECTION
//====================================================================

bool PFLS_PricesIntersectZone(
   const double candle_high,
   const double candle_low,
   const double upper,
   const double lower)
{
   if(upper <= lower)
      return false;

   return (
      candle_high >= lower &&
      candle_low <= upper
   );
}

//====================================================================
// PRICE PATH INTERSECTION
// Detects a tick moving through a zone even if neither
// endpoint is inside the zone.
//====================================================================

bool PFLS_PricePathIntersectsZone(
   const double previous_price,
   const double current_price,
   const double upper,
   const double lower)
{
   if(upper <= lower ||
      previous_price <= 0.0 ||
      current_price <= 0.0)
   {
      return false;
   }

   double path_high = MathMax(
      previous_price,
      current_price);

   double path_low = MathMin(
      previous_price,
      current_price);

   return PFLS_PricesIntersectZone(
      path_high,
      path_low,
      upper,
      lower);
}

//====================================================================
// FIRST-ENTRY FRESHNESS VALIDATION
// Checks candles after origin, excluding index 1.
//====================================================================

bool PFLS_IsZoneFresh(
   const MqlRates &rates[],
   const int origin_index,
   const double upper,
   const double lower,
   datetime &first_touch)
{
   first_touch = 0;

   if(upper <= lower)
      return false;

   for(int i = origin_index - 1; i >= 2; i--)
   {
      if(PFLS_PricesIntersectZone(
         rates[i].high,
         rates[i].low,
         upper,
         lower))
      {
         first_touch = rates[i].time;
         return false;
      }
   }

   return true;
}

//====================================================================
// FIND HISTORY RECORD
//====================================================================

int PFLS_FindZoneHistoryRecord(
   const datetime origin_time,
   const ENUM_TIMEFRAMES timeframe,
   const bool demand)
{
   for(int i = 0; i < PFLS_ZoneHistoryCount; i++)
   {
      if(!PFLS_ZoneHistory[i].valid)
         continue;

      if(PFLS_ZoneHistory[i].origin_time == origin_time &&
         PFLS_ZoneHistory[i].timeframe == timeframe &&
         PFLS_ZoneHistory[i].is_demand == demand)
      {
         return i;
      }
   }

   return -1;
}

//====================================================================
// ADD HISTORY RECORD
//====================================================================

int PFLS_AddZoneHistoryRecord(
   const PFLS_ZoneRecord &zone)
{
   int existing = PFLS_FindZoneHistoryRecord(
      zone.origin_time,
      zone.timeframe,
      zone.is_demand);

   if(existing >= 0)
      return existing;

   if(PFLS_ZoneHistoryCount >= PFLS_ZONE_HISTORY_CAPACITY)
      return -1;

   int index = PFLS_ZoneHistoryCount;

   PFLS_ResetZoneHistoryRecord(
      PFLS_ZoneHistory[index]);

   PFLS_ZoneHistory[index].valid = true;
   PFLS_ZoneHistory[index].is_demand = zone.is_demand;

   PFLS_ZoneHistory[index].upper = zone.upper;
   PFLS_ZoneHistory[index].lower = zone.lower;

   PFLS_ZoneHistory[index].origin_time = zone.origin_time;
   PFLS_ZoneHistory[index].detection_time = zone.detection_time;
   PFLS_ZoneHistory[index].first_touch_time =
      zone.first_touch_time;

   PFLS_ZoneHistory[index].timeframe = zone.timeframe;

   PFLS_ZoneHistory[index].state = zone.state;

   PFLS_ZoneHistory[index].deepest_price =
      zone.is_demand ? zone.upper : zone.lower;

   PFLS_ZoneHistoryCount++;

   return index;
}

//====================================================================
// UPDATE HISTORY RECORD FROM A PRICE PATH
//====================================================================

void PFLS_UpdateHistoricalZonePath(
   const int index,
   const double previous_price,
   const double current_price,
   const datetime event_time)
{
   if(index < 0 ||
      index >= PFLS_ZoneHistoryCount ||
      !PFLS_ZoneHistory[index].valid ||
      previous_price <= 0.0 ||
      current_price <= 0.0)
   {
      return;
   }

   double upper = PFLS_ZoneHistory[index].upper;
   double lower = PFLS_ZoneHistory[index].lower;

   bool demand = PFLS_ZoneHistory[index].is_demand;

   if(upper <= lower)
      return;

   bool intersects = PFLS_PricePathIntersectsZone(
      previous_price,
      current_price,
      upper,
      lower);

   // No first interaction has occurred yet.
   if(PFLS_ZoneHistory[index].first_touch_time == 0)
   {
      if(!intersects)
         return;

      PFLS_ZoneHistory[index].first_touch_time =
         event_time;

      PFLS_ZoneHistory[index].state =
         PFLS_ZONE_TOUCHED;
   }

   PFLS_ZoneHistory[index].last_update_time =
      event_time;

   // Track deepest penetration.
   if(demand)
   {
      if(current_price < PFLS_ZoneHistory[index].deepest_price)
      {
         PFLS_ZoneHistory[index].deepest_price =
            current_price;
      }

      // Demand is fully traversed when price reaches
      // or passes the lower boundary.
      if(current_price <= lower)
      {
         PFLS_ZoneHistory[index].state =
            PFLS_ZONE_FULLY_TRAVERSED;
      }
      else if(current_price < upper)
      {
         PFLS_ZoneHistory[index].state =
            PFLS_ZONE_PARTIALLY_PENETRATED;
      }
   }
   else
   {
      if(current_price > PFLS_ZoneHistory[index].deepest_price)
      {
         PFLS_ZoneHistory[index].deepest_price =
            current_price;
      }

      // Supply is fully traversed when price reaches
      // or passes the upper boundary.
      if(current_price >= upper)
      {
         PFLS_ZoneHistory[index].state =
            PFLS_ZONE_FULLY_TRAVERSED;
      }
      else if(current_price > lower)
      {
         PFLS_ZoneHistory[index].state =
            PFLS_ZONE_PARTIALLY_PENETRATED;
      }
   }
}

//====================================================================
// LEGACY HISTORY UPDATE
// Preserves the original function interface.
//====================================================================

void PFLS_UpdateHistoricalZone(
   const int index,
   const double current_price,
   const datetime event_time)
{
   PFLS_UpdateHistoricalZonePath(
      index,
      current_price,
      current_price,
      event_time);
}

//====================================================================
// UPDATE ACTIVE ZONE FROM PRICE PATH
// First entry hides the zone from active display.
// Historical record remains available.
//====================================================================

bool PFLS_UpdateZoneInteractionPath(
   PFLS_ZoneRecord &zone,
   const double previous_price,
   const double current_price,
   const datetime event_time)
{
   if(!zone.active ||
      previous_price <= 0.0 ||
      current_price <= 0.0)
   {
      return false;
   }

   bool entered = PFLS_PricePathIntersectsZone(
      previous_price,
      current_price,
      zone.upper,
      zone.lower);

   if(!entered)
      return false;

   // Ensure the historical record exists before
   // removing the zone from the active list.
   int history_index = PFLS_AddZoneHistoryRecord(zone);

   if(history_index >= 0)
   {
      PFLS_UpdateHistoricalZonePath(
         history_index,
         previous_price,
         current_price,
         event_time);

      zone.first_touch_time =
         PFLS_ZoneHistory[history_index].first_touch_time;

      zone.state =
         PFLS_ZoneHistory[history_index].state;
   }
   else
   {
      zone.first_touch_time = event_time;
      zone.state = PFLS_ZONE_TOUCHED;
   }

   zone.active = false;

   return true;
}

//====================================================================
// LEGACY ACTIVE ZONE UPDATE
// Preserves the original function interface.
// Use the path version when previous price is available.
//====================================================================

bool PFLS_UpdateZoneInteraction(
   PFLS_ZoneRecord &zone,
   const double current_price,
   const datetime event_time)
{
   return PFLS_UpdateZoneInteractionPath(
      zone,
      current_price,
      current_price,
      event_time);
}

//====================================================================
// BUILD A FRESH ZONE
//====================================================================

bool PFLS_BuildFreshZone(
   const MqlRates &rates[],
   const int total,
   const ENUM_TIMEFRAMES timeframe,
   const int pivot_strength,
   const int lookback,
   const bool demand,
   PFLS_ZoneRecord &result)
{
   PFLS_ResetZoneRecord(result);

   if(total < 50)
      return false;

   if(pivot_strength < 1 || lookback < 20)
      return false;

   int maximum_index = total - pivot_strength - 1;

   int requested_maximum =
      lookback - pivot_strength - 2;

   if(maximum_index > requested_maximum)
      maximum_index = requested_maximum;

   if(maximum_index <= pivot_strength + 1)
      return false;

   // Search from the most recent eligible historical
   // pivot towards older pivots.
   for(int i = pivot_strength + 2;
       i <= maximum_index;
       i++)
   {
      bool broken = false;

      if(demand)
      {
         if(PFLS_IsPivotHigh(
            rates, i, pivot_strength, total))
         {
            broken = (rates[1].close > rates[i].high);
         }
      }
      else
      {
         if(PFLS_IsPivotLow(
            rates, i, pivot_strength, total))
         {
            broken = (rates[1].close < rates[i].low);
         }
      }

      if(!broken)
         continue;

      int origin_index = -1;

      if(demand)
      {
         origin_index = PFLS_FindDemandOrigin(
            rates, i);
      }
      else
      {
         origin_index = PFLS_FindSupplyOrigin(
            rates, i);
      }

      if(origin_index < 0)
         continue;

      double zone_upper = 0.0;
      double zone_lower = 0.0;

      if(demand)
      {
         PFLS_CalculateDemandBoundaries(
            rates,
            origin_index,
            zone_upper,
            zone_lower);
      }
      else
      {
         PFLS_CalculateSupplyBoundaries(
            rates,
            origin_index,
            zone_upper,
            zone_lower);
      }

      if(zone_upper <= zone_lower)
         continue;

      datetime first_touch = 0;

      if(!PFLS_IsZoneFresh(
         rates,
         origin_index,
         zone_upper,
         zone_lower,
         first_touch))
      {
         continue;
      }

      result.active = true;
      result.is_demand = demand;

      result.upper = zone_upper;
      result.lower = zone_lower;

      result.origin_time =
         rates[origin_index].time;

      result.detection_time = TimeCurrent();
      result.first_touch_time = 0;

      result.timeframe = timeframe;
      result.state = PFLS_ZONE_UNTESTED;

      PFLS_AddZoneHistoryRecord(result);

      return true;
   }

   return false;
}

//====================================================================
// SCAN A TIMEFRAME
//====================================================================

bool PFLS_ScanZones(
   const string symbol,
   const ENUM_TIMEFRAMES timeframe,
   const int lookback,
   const int pivot_strength,
   PFLS_ZoneRecord &demand_zone,
   PFLS_ZoneRecord &supply_zone)
{
   PFLS_ResetZoneRecord(demand_zone);
   PFLS_ResetZoneRecord(supply_zone);

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

   bool demand_found = PFLS_BuildFreshZone(
      rates,
      copied,
      timeframe,
      pivot_strength,
      lookback,
      true,
      demand_zone);

   bool supply_found = PFLS_BuildFreshZone(
      rates,
      copied,
      timeframe,
      pivot_strength,
      lookback,
      false,
      supply_zone);

   return (demand_found || supply_found);
}

//====================================================================
// ZONE STATE DESCRIPTION
//====================================================================

string PFLS_ZoneStateText(
   const PFLS_ZONE_STATE state)
{
   switch(state)
   {
      case PFLS_ZONE_INVALID:
         return "INVALID";

      case PFLS_ZONE_UNTESTED:
         return "UNTESTED";

      case PFLS_ZONE_TOUCHED:
         return "TOUCHED";

      case PFLS_ZONE_PARTIALLY_PENETRATED:
         return "PARTIALLY PENETRATED";

      case PFLS_ZONE_FULLY_TRAVERSED:
         return "FULLY TRAVERSED";
   }

   return "UNKNOWN";
}

//====================================================================
// MODULE VERSION
//====================================================================

string PFLS_GetZoneModuleVersion()
{
   return PFLS_ZONE_MODULE_VERSION;
}

//+------------------------------------------------------------------+
#endif // PFLS_ZONES_MQH
