
#ifndef PFLS_ZONES_MQH
#define PFLS_ZONES_MQH

//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| ZONE DETECTION MODULE                                            |
//| Version 2.00.1                                                   |
//|                                                                  |
//| Responsibilities:                                                |
//| - Confirmed swing detection                                      |
//| - Structure-break validation                                    |
//| - Demand and supply origin identification                       |
//| - Fresh-zone validation                                         |
//| - First-entry mitigation detection                               |
//|                                                                  |
//| Research module. No trading commands.                            |
//+------------------------------------------------------------------+

#define PFLS_ZONE_MODULE_VERSION "2.00.1"

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
// ZONE RECORD
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
// RESET ZONE RECORD
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
// CONFIRMED PIVOT HIGH
//====================================================================

bool PFLS_IsPivotHigh(const MqlRates &rates[],
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

bool PFLS_IsPivotLow(const MqlRates &rates[],
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
// FIND DEMAND ORIGIN CANDLE
//====================================================================

int PFLS_FindDemandOrigin(const MqlRates &rates[],
                          const int pivot_index)
{
   // Search from the pivot towards the latest completed candle.
   // The last bearish candle is the primary demand origin.

   for(int i = pivot_index - 1; i >= 2; i--)
   {
      if(rates[i].close < rates[i].open)
         return i;
   }

   return -1;
}

//====================================================================
// FIND SUPPLY ORIGIN CANDLE
//====================================================================

int PFLS_FindSupplyOrigin(const MqlRates &rates[],
                          const int pivot_index)
{
   // The last bullish candle is the primary supply origin.

   for(int i = pivot_index - 1; i >= 2; i--)
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
   upper = MathMax(rates[origin_index].open,
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

   lower = MathMin(rates[origin_index].open,
                   rates[origin_index].close);
}

//====================================================================
// FIRST-ENTRY FRESHNESS VALIDATION
//====================================================================

bool PFLS_IsZoneFresh(const MqlRates &rates[],
                      const int origin_index,
                      const double upper,
                      const double lower,
                      datetime &first_touch)
{
   first_touch = 0;

   if(upper <= lower)
      return false;

   // Series arrays:
   // index 0 = currently forming candle
   // index 1 = most recently completed candle
   //
   // Every completed candle after the origin is checked.
   // Even a wick-only overlap counts as first interaction.

   for(int i = origin_index - 1; i >= 1; i--)
   {
      bool intersects =
         (rates[i].high >= lower &&
          rates[i].low <= upper);

      if(intersects)
      {
         first_touch = rates[i].time;
         return false;
      }
   }

   return true;
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

   int requested_maximum = lookback - pivot_strength - 2;

   if(maximum_index > requested_maximum)
      maximum_index = requested_maximum;

   if(maximum_index <= pivot_strength + 1)
      return false;

   // Search historical confirmed pivots.
   // The latest completed candle must close beyond the pivot.

   for(int i = pivot_strength + 2;
       i <= maximum_index;
       i++)
   {
      bool broken = false;

      if(demand)
      {
         if(PFLS_IsPivotHigh(rates,
                             i,
                             pivot_strength,
                             total))
         {
            if(rates[1].close > rates[i].high)
               broken = true;
         }
      }
      else
      {
         if(PFLS_IsPivotLow(rates,
                            i,
                            pivot_strength,
                            total))
         {
            if(rates[1].close < rates[i].low)
               broken = true;
         }
      }

      if(!broken)
         continue;

      int origin_index = -1;

      if(demand)
         origin_index = PFLS_FindDemandOrigin(rates, i);
      else
         origin_index = PFLS_FindSupplyOrigin(rates, i);

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

      result.origin_time = rates[origin_index].time;
      result.detection_time = TimeCurrent();
      result.first_touch_time = 0;

      result.timeframe = timeframe;
      result.state = PFLS_ZONE_UNTESTED;

      return true;
   }

   return false;
}

//====================================================================
// SCAN A TIMEFRAME FOR DEMAND AND SUPPLY
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

string PFLS_ZoneStateText(const PFLS_ZONE_STATE state)
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
