
//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| Research Build 1.00                                              |
//| Multi-Timeframe Price Flow and Zone Research Engine              |
//| Platform: MetaTrader 5                                           |
//| Initial target: Deriv Volatility 75 Index                        |
//|                                                                  |
//| IMPORTANT: RESEARCH ONLY. NO AUTOMATED TRADING.                  |
//+------------------------------------------------------------------+
#property copyright "PFLS Trader"
#property version   "1.00"
#property description "PFLS 2.00 - Multi-Timeframe Research EA"
#property strict

//====================================================================
// INPUTS
//====================================================================

input int    InpLookbackBars       = 300;
input int    InpPivotStrength      = 2;
input int    InpScanInterval       = 30;
input bool   InpShowChartStatus    = true;
input bool   InpEnableResearchLog  = true;

// Safety lock: this research build cannot execute trades.
input bool   InpEnableExecution    = false;

//====================================================================
// TIMEFRAME CONFIGURATION
//====================================================================

#define PFLS_TIMEFRAME_COUNT 8

ENUM_TIMEFRAMES PFLS_Timeframes[PFLS_TIMEFRAME_COUNT] =
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

//====================================================================
// ZONE DATA STRUCTURE
//====================================================================

struct PFLS_Zone
{
   bool     active;
   bool     demand;
   double   upper;
   double   lower;
   datetime origin_time;
   datetime detection_time;
   int      timeframe_index;
};

//====================================================================
// GLOBAL DATA
//====================================================================

PFLS_Zone DemandZones[PFLS_TIMEFRAME_COUNT];
PFLS_Zone SupplyZones[PFLS_TIMEFRAME_COUNT];

datetime LastScanTime = 0;

int TotalDemandZones = 0;
int TotalSupplyZones = 0;

string PFLS_Status = "INITIALISING";

//====================================================================
// RESET ZONE
//====================================================================

void ResetZone(PFLS_Zone &zone)
{
   zone.active = false;
   zone.demand = false;
   zone.upper = 0.0;
   zone.lower = 0.0;
   zone.origin_time = 0;
   zone.detection_time = 0;
   zone.timeframe_index = -1;
}

//====================================================================
// PIVOT HIGH
//====================================================================

bool IsPivotHigh(MqlRates &rates[], int index, int strength,
                 int total)
{
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
// PIVOT LOW
//====================================================================

bool IsPivotLow(MqlRates &rates[], int index, int strength,
                int total)
{
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
// CHECK WHETHER A CANDLE ENTERED A ZONE
//====================================================================

bool CandleIntersectsZone(MqlRates &candle[],
                          double upper,
                          double lower)
{
   if(candle[0].high >= lower &&
      candle[0].low <= upper)
   {
      return true;
   }

   return false;
}

//====================================================================
// BUILD A PROVISIONAL ZONE
//====================================================================

bool BuildZone(MqlRates &rates[],
               int total,
               int timeframe_index,
               bool demand,
               PFLS_Zone &result)
{
   ResetZone(result);

   int strength = InpPivotStrength;

   if(total < strength * 2 + 20)
      return false;

   int maximum_index = total - strength - 1;

   if(maximum_index > InpLookbackBars - strength - 2)
      maximum_index = InpLookbackBars - strength - 2;

   // Search for the nearest confirmed pivot broken by
   // the most recently completed candle.

   for(int i = strength + 2; i <= maximum_index; i++)
   {
      bool structure_break = false;

      if(demand)
      {
         if(IsPivotHigh(rates, i, strength, total) &&
            rates[1].close > rates[i].high)
         {
            structure_break = true;
         }
      }
      else
      {
         if(IsPivotLow(rates, i, strength, total) &&
            rates[1].close < rates[i].low)
         {
            structure_break = true;
         }
      }

      if(!structure_break)
         continue;

      // Find the last opposing candle before the break.
      int origin_index = -1;

      for(int j = i - 1; j >= 2; j--)
      {
         if(demand && rates[j].close < rates[j].open)
         {
            origin_index = j;
            break;
         }

         if(!demand && rates[j].close > rates[j].open)
         {
            origin_index = j;
            break;
         }
      }

      if(origin_index < 0)
         continue;

      double zone_upper = 0.0;
      double zone_lower = 0.0;

      if(demand)
      {
         // Demand: highest body boundary to lowest wick.
         zone_upper = MathMax(rates[origin_index].open,
                              rates[origin_index].close);

         zone_lower = rates[origin_index].low;
      }
      else
      {
         // Supply: highest wick to lowest body boundary.
         zone_upper = rates[origin_index].high;

         zone_lower = MathMin(rates[origin_index].open,
                              rates[origin_index].close);
      }

      if(zone_upper <= zone_lower)
         continue;

      // First subsequent price entry means the zone
      // is no longer fresh and must not be active.
      bool touched = false;

      for(int k = origin_index - 1; k >= 1; k--)
      {
         if(rates[k].high >= zone_lower &&
            rates[k].low <= zone_upper)
         {
            touched = true;
            break;
         }
      }

      if(touched)
         continue;

      result.active = true;
      result.demand = demand;
      result.upper = zone_upper;
      result.lower = zone_lower;
      result.origin_time = rates[origin_index].time;
      result.detection_time = TimeCurrent();
      result.timeframe_index = timeframe_index;

      return true;
   }

   return false;
}

//====================================================================
// SCAN ONE TIMEFRAME
//====================================================================

void ScanTimeframe(int index)
{
   MqlRates rates[];

   ArraySetAsSeries(rates, true);

   int copied = CopyRates(_Symbol,
                          PFLS_Timeframes[index],
                          0,
                          InpLookbackBars,
                          rates);

   if(copied < 50)
   {
      ResetZone(DemandZones[index]);
      ResetZone(SupplyZones[index]);

      if(InpEnableResearchLog)
      {
         Print("PFLS | Insufficient history | ",
               EnumToString(PFLS_Timeframes[index]),
               " | Bars: ", copied);
      }

      return;
   }

   BuildZone(rates, copied, index, true, DemandZones[index]);

   BuildZone(rates, copied, index, false, SupplyZones[index]);
}

//====================================================================
// SCAN ALL TIMEFRAMES
//====================================================================

void ScanAllTimeframes()
{
   TotalDemandZones = 0;
   TotalSupplyZones = 0;

   for(int i = 0; i < PFLS_TIMEFRAME_COUNT; i++)
   {
      ScanTimeframe(i);

      if(DemandZones[i].active)
         TotalDemandZones++;

      if(SupplyZones[i].active)
         TotalSupplyZones++;
   }

   LastScanTime = TimeCurrent();

   PFLS_Status = "RESEARCH SCAN COMPLETE";

   if(InpEnableResearchLog)
   {
      Print("================================================");
      Print("PFLS TRADER 2.00 | RESEARCH SCAN");
      Print("Symbol: ", _Symbol);
      Print("Demand zones: ", TotalDemandZones);
      Print("Supply zones: ", TotalSupplyZones);
      Print("Timeframes scanned: ", PFLS_TIMEFRAME_COUNT);
      Print("Execution: DISABLED");
      Print("================================================");

      for(int i = 0; i < PFLS_TIMEFRAME_COUNT; i++)
      {
         string tf = EnumToString(PFLS_Timeframes[i]);

         if(DemandZones[i].active)
         {
            Print("FRESH DEMAND | ", tf,
                  " | Lower: ", DoubleToString(DemandZones[i].lower, _Digits),
                  " | Upper: ", DoubleToString(DemandZones[i].upper, _Digits));
         }

         if(SupplyZones[i].active)
         {
            Print("FRESH SUPPLY | ", tf,
                  " | Lower: ", DoubleToString(SupplyZones[i].lower, _Digits),
                  " | Upper: ", DoubleToString(SupplyZones[i].upper, _Digits));
         }
      }
   }
}

//====================================================================
// PRICE FLOW OBSERVATION
//====================================================================

string GetPriceLocation()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(bid <= 0.0)
      return "PRICE UNAVAILABLE";

   bool inside_demand = false;
   bool inside_supply = false;

   for(int i = 0; i < PFLS_TIMEFRAME_COUNT; i++)
   {
      if(DemandZones[i].active &&
         bid >= DemandZones[i].lower &&
         bid <= DemandZones[i].upper)
      {
         inside_demand = true;
      }

      if(SupplyZones[i].active &&
         bid >= SupplyZones[i].lower &&
         bid <= SupplyZones[i].upper)
      {
         inside_supply = true;
      }
   }

   if(inside_demand && inside_supply)
      return "OVERLAPPING ZONE AREAS";

   if(inside_demand)
      return "INSIDE FRESH DEMAND AREA";

   if(inside_supply)
      return "INSIDE FRESH SUPPLY AREA";

   return "BETWEEN ACTIVE ZONES";
}

//====================================================================
// DASHBOARD
//====================================================================

void UpdateDashboard()
{
   if(!InpShowChartStatus)
      return;

   string display =
      "PFLS TRADER 2.00\n"
      "RESEARCH BUILD 1.00\n"
      "--------------------------\n";

   display += "Symbol: " + _Symbol + "\n";
   display += "Status: " + PFLS_Status + "\n";

   display += "Timeframes: W1 D1 H4 H1\n";
   display += "             M30 M15 M5 M1\n";

   display += "Fresh demand: " +
              IntegerToString(TotalDemandZones) + "\n";

   display += "Fresh supply: " +
              IntegerToString(TotalSupplyZones) + "\n";

   display += "Price location: " + GetPriceLocation() + "\n";

   display += "Last scan: " +
              TimeToString(LastScanTime,
                           TIME_DATE | TIME_MINUTES | TIME_SECONDS) + "\n";

   display += "--------------------------\n";
   display += "EXECUTION: LOCKED OFF\n";
   display += "ENTRY ENGINE: NOT ENABLED\n";
   display += "RESEARCH MODE ONLY";

   Comment(display);
}

//====================================================================
// INITIALISATION
//====================================================================

int OnInit()
{
   for(int i = 0; i < PFLS_TIMEFRAME_COUNT; i++)
   {
      ResetZone(DemandZones[i]);
      ResetZone(SupplyZones[i]);
   }

   if(InpLookbackBars < 50 ||
      InpPivotStrength < 1 ||
      InpScanInterval < 1)
   {
      Print("PFLS ERROR: Invalid input settings.");
      return INIT_PARAMETERS_INCORRECT;
   }

   // This build deliberately refuses execution mode.
   if(InpEnableExecution)
   {
      Print("PFLS SAFETY LOCK: Execution is not available ",
            "in Research Build 1.00.");
   }

   EventSetTimer(InpScanInterval);

   Print("PFLS TRADER 2.00 INITIALISED");
   Print("Research mode active.");
   Print("Symbol: ", _Symbol);
   Print("Automated trading is not implemented.");

   ScanAllTimeframes();
   UpdateDashboard();

   return INIT_SUCCEEDED;
}

//====================================================================
// TIMER
//====================================================================

void OnTimer()
{
   ScanAllTimeframes();
   UpdateDashboard();
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   // No trading commands are present in this research build.
   // Tick data is used only to refresh the displayed observation.

   UpdateDashboard();
}

//====================================================================
// SHUTDOWN
//====================================================================

void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");

   Print("PFLS TRADER 2.00 STOPPED.");
}
//+------------------------------------------------------------------+

