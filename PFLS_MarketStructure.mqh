
#ifndef PFLS_MARKET_STRUCTURE_MQH
#define PFLS_MARKET_STRUCTURE_MQH

//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| MARKET STRUCTURE MODULE                                          |
//| Version 2.00.2                                                   |
//|                                                                  |
//| Improvements:                                                    |
//| - Confirmed swing detection                                      |
//| - HH / HL / LH / LL classification                               |
//| - Newly occurring BOS detection                                 |
//| - Protected swing tracking                                       |
//| - Provisional directional bias                                   |
//| - Two-close structural invalidation                              |
//|                                                                  |
//| RESEARCH ONLY. NO TRADE EXECUTION.                               |
//| Assumes MqlRates arrays use series indexing.                     |
//+------------------------------------------------------------------+

#define PFLS_STRUCTURE_MODULE_VERSION "2.00.2"

//====================================================================
// ENUMERATIONS
//====================================================================

enum PFLS_DIRECTION
{
   PFLS_DIRECTION_CONFLICTED = -2,
   PFLS_DIRECTION_BEARISH    = -1,
   PFLS_DIRECTION_NEUTRAL    =  0,
   PFLS_DIRECTION_BULLISH    =  1
};

enum PFLS_STRUCTURE_EVENT
{
   PFLS_EVENT_NONE = 0,
   PFLS_EVENT_HIGHER_HIGH,
   PFLS_EVENT_HIGHER_LOW,
   PFLS_EVENT_LOWER_HIGH,
   PFLS_EVENT_LOWER_LOW,
   PFLS_EVENT_BULLISH_BOS,
   PFLS_EVENT_BEARISH_BOS
};

//====================================================================
// SWING RECORD
//====================================================================

struct PFLS_SwingPoint
{
   bool     valid;
   double   price;
   datetime time;
   int      bar_index;
};

//====================================================================
// MARKET STRUCTURE RECORD
//====================================================================

struct PFLS_MarketStructure
{
   PFLS_SwingPoint latest_high;
   PFLS_SwingPoint previous_high;

   PFLS_SwingPoint latest_low;
   PFLS_SwingPoint previous_low;

   bool higher_high;
   bool higher_low;

   bool lower_high;
   bool lower_low;

   bool bullish_bos;
   bool bearish_bos;

   double protected_high;
   double protected_low;

   PFLS_DIRECTION direction;

   PFLS_STRUCTURE_EVENT latest_event;

   datetime bos_time;
   double   bos_level;

   datetime analysis_time;
};

//====================================================================
// PROVISIONAL BIAS RECORD
//====================================================================

struct PFLS_ProvisionalBias
{
   PFLS_DIRECTION direction;

   bool active;
   bool invalidated;

   double protected_level;

   int acceptance_closes;

   datetime created_time;
   datetime invalidation_time;
};

//====================================================================
// RESET SWING
//====================================================================

void PFLS_ResetSwing(PFLS_SwingPoint &swing)
{
   swing.valid = false;
   swing.price = 0.0;
   swing.time = 0;
   swing.bar_index = -1;
}

//====================================================================
// RESET STRUCTURE
//====================================================================

void PFLS_ResetMarketStructure(
   PFLS_MarketStructure &structure)
{
   PFLS_ResetSwing(structure.latest_high);
   PFLS_ResetSwing(structure.previous_high);

   PFLS_ResetSwing(structure.latest_low);
   PFLS_ResetSwing(structure.previous_low);

   structure.higher_high = false;
   structure.higher_low = false;

   structure.lower_high = false;
   structure.lower_low = false;

   structure.bullish_bos = false;
   structure.bearish_bos = false;

   structure.protected_high = 0.0;
   structure.protected_low = 0.0;

   structure.direction = PFLS_DIRECTION_NEUTRAL;

   structure.latest_event = PFLS_EVENT_NONE;

   structure.bos_time = 0;
   structure.bos_level = 0.0;

   structure.analysis_time = 0;
}

//====================================================================
// RESET PROVISIONAL BIAS
//====================================================================

void PFLS_ResetProvisionalBias(
   PFLS_ProvisionalBias &bias)
{
   bias.direction = PFLS_DIRECTION_NEUTRAL;

   bias.active = false;
   bias.invalidated = false;

   bias.protected_level = 0.0;

   bias.acceptance_closes = 0;

   bias.created_time = 0;
   bias.invalidation_time = 0;
}

//====================================================================
// CONFIRMED PIVOT HIGH
//====================================================================

bool PFLS_MS_IsPivotHigh(
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
      // More recent candles.
      if(rates[index-i].high >= pivot)
         return false;

      // Older candles.
      if(rates[index+i].high > pivot)
         return false;
   }

   return true;
}

//====================================================================
// CONFIRMED PIVOT LOW
//====================================================================

bool PFLS_MS_IsPivotLow(
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
// FIND TWO MOST RECENT CONFIRMED SWING HIGHS
//====================================================================

int PFLS_FindSwingHighs(
   const MqlRates &rates[],
   const int total,
   const int strength,
   const int lookback,
   PFLS_SwingPoint &latest,
   PFLS_SwingPoint &previous)
{
   PFLS_ResetSwing(latest);
   PFLS_ResetSwing(previous);

   if(total < 3 || strength < 1 || lookback < 1)
      return 0;

   int maximum_index = total - strength - 1;

   if(maximum_index > lookback)
      maximum_index = lookback;

   int found = 0;

   for(int i = strength + 1;
       i <= maximum_index;
       i++)
   {
      if(!PFLS_MS_IsPivotHigh(
         rates, i, strength, total))
      {
         continue;
      }

      if(found == 0)
      {
         latest.valid = true;
         latest.price = rates[i].high;
         latest.time = rates[i].time;
         latest.bar_index = i;

         found = 1;
      }
      else
      {
         previous.valid = true;
         previous.price = rates[i].high;
         previous.time = rates[i].time;
         previous.bar_index = i;

         found = 2;
         break;
      }
   }

   return found;
}

//====================================================================
// FIND TWO MOST RECENT CONFIRMED SWING LOWS
//====================================================================

int PFLS_FindSwingLows(
   const MqlRates &rates[],
   const int total,
   const int strength,
   const int lookback,
   PFLS_SwingPoint &latest,
   PFLS_SwingPoint &previous)
{
   PFLS_ResetSwing(latest);
   PFLS_ResetSwing(previous);

   if(total < 3 || strength < 1 || lookback < 1)
      return 0;

   int maximum_index = total - strength - 1;

   if(maximum_index > lookback)
      maximum_index = lookback;

   int found = 0;

   for(int i = strength + 1;
       i <= maximum_index;
       i++)
   {
      if(!PFLS_MS_IsPivotLow(
         rates, i, strength, total))
      {
         continue;
      }

      if(found == 0)
      {
         latest.valid = true;
         latest.price = rates[i].low;
         latest.time = rates[i].time;
         latest.bar_index = i;

         found = 1;
      }
      else
      {
         previous.valid = true;
         previous.price = rates[i].low;
         previous.time = rates[i].time;
         previous.bar_index = i;

         found = 2;
         break;
      }
   }

   return found;
}

//====================================================================
// CLASSIFY STRUCTURE
//====================================================================

void PFLS_ClassifyStructure(
   PFLS_MarketStructure &structure)
{
   structure.higher_high = false;
   structure.higher_low = false;

   structure.lower_high = false;
   structure.lower_low = false;

   structure.latest_event = PFLS_EVENT_NONE;

   if(structure.latest_high.valid &&
      structure.previous_high.valid)
   {
      structure.higher_high =
         structure.latest_high.price >
         structure.previous_high.price;

      structure.lower_high =
         structure.latest_high.price <
         structure.previous_high.price;
   }

   if(structure.latest_low.valid &&
      structure.previous_low.valid)
   {
      structure.higher_low =
         structure.latest_low.price >
         structure.previous_low.price;

      structure.lower_low =
         structure.latest_low.price <
         structure.previous_low.price;
   }

   // Determine the most recent classified swing event.
   if(structure.latest_high.valid &&
      structure.latest_low.valid)
   {
      if(structure.latest_high.time >
         structure.latest_low.time)
      {
         if(structure.higher_high)
            structure.latest_event =
               PFLS_EVENT_HIGHER_HIGH;

         else if(structure.lower_high)
            structure.latest_event =
               PFLS_EVENT_LOWER_HIGH;
      }
      else
      {
         if(structure.higher_low)
            structure.latest_event =
               PFLS_EVENT_HIGHER_LOW;

         else if(structure.lower_low)
            structure.latest_event =
               PFLS_EVENT_LOWER_LOW;
      }
   }

   // Establish the current structural classification.
   if(structure.higher_high &&
      structure.higher_low)
   {
      structure.direction = PFLS_DIRECTION_BULLISH;
   }
   else if(structure.lower_high &&
           structure.lower_low)
   {
      structure.direction = PFLS_DIRECTION_BEARISH;
   }
   else if((structure.higher_high &&
            structure.lower_low) ||
           (structure.lower_high &&
            structure.higher_low))
   {
      structure.direction = PFLS_DIRECTION_CONFLICTED;
   }
   else
   {
      structure.direction = PFLS_DIRECTION_NEUTRAL;
   }

   // Initial protected-level references.
   if(structure.latest_high.valid)
      structure.protected_high =
         structure.latest_high.price;

   if(structure.latest_low.valid)
      structure.protected_low =
         structure.latest_low.price;
}

//====================================================================
// DETECT A NEW STRUCTURE BREAK
//====================================================================

void PFLS_DetectStructureBreak(
   const MqlRates &rates[],
   const int total,
   PFLS_MarketStructure &structure)
{
   structure.bullish_bos = false;
   structure.bearish_bos = false;

   structure.bos_time = 0;
   structure.bos_level = 0.0;

   if(total < 3)
      return;

   // A bullish BOS requires a newly completed close
   // crossing above the latest confirmed swing high.
   if(structure.latest_high.valid)
   {
      bool crossed_up =
         (rates[2].close <= structure.latest_high.price &&
          rates[1].close > structure.latest_high.price);

      if(crossed_up)
      {
         structure.bullish_bos = true;

         structure.bos_time = rates[1].time;
         structure.bos_level =
            structure.latest_high.price;

         structure.latest_event =
            PFLS_EVENT_BULLISH_BOS;

         // The latest confirmed low becomes the
         // provisional protected low for this break.
         if(structure.latest_low.valid)
         {
            structure.protected_low =
               structure.latest_low.price;
         }
      }
   }

   // A bearish BOS requires a newly completed close
   // crossing below the latest confirmed swing low.
   if(structure.latest_low.valid)
   {
      bool crossed_down =
         (rates[2].close >= structure.latest_low.price &&
          rates[1].close < structure.latest_low.price);

      if(crossed_down)
      {
         structure.bearish_bos = true;

         structure.bos_time = rates[1].time;
         structure.bos_level =
            structure.latest_low.price;

         structure.latest_event =
            PFLS_EVENT_BEARISH_BOS;

         if(structure.latest_high.valid)
         {
            structure.protected_high =
               structure.latest_high.price;
         }
      }
   }

   if(structure.bullish_bos &&
      !structure.bearish_bos)
   {
      structure.direction = PFLS_DIRECTION_BULLISH;
   }
   else if(structure.bearish_bos &&
           !structure.bullish_bos)
   {
      structure.direction = PFLS_DIRECTION_BEARISH;
   }
   else if(structure.bullish_bos &&
           structure.bearish_bos)
   {
      structure.direction = PFLS_DIRECTION_CONFLICTED;
   }
}

//====================================================================
// COMPLETE STRUCTURE ANALYSIS
//====================================================================

bool PFLS_AnalyseMarketStructure(
   const MqlRates &rates[],
   const int total,
   const int pivot_strength,
   const int lookback,
   PFLS_MarketStructure &structure)
{
   PFLS_ResetMarketStructure(structure);

   if(total < 50)
      return false;

   if(pivot_strength < 1 || lookback < 20)
      return false;

   int high_count = PFLS_FindSwingHighs(
      rates,
      total,
      pivot_strength,
      lookback,
      structure.latest_high,
      structure.previous_high);

   int low_count = PFLS_FindSwingLows(
      rates,
      total,
      pivot_strength,
      lookback,
      structure.latest_low,
      structure.previous_low);

   if(high_count < 2 || low_count < 2)
      return false;

   PFLS_ClassifyStructure(structure);

   PFLS_DetectStructureBreak(
      rates,
      total,
      structure);

   structure.analysis_time = TimeCurrent();

   return true;
}

//====================================================================
// CREATE PROVISIONAL BIAS
//====================================================================

bool PFLS_CreateProvisionalBias(
   const PFLS_MarketStructure &structure,
   PFLS_ProvisionalBias &bias)
{
   PFLS_ResetProvisionalBias(bias);

   if(structure.bullish_bos &&
      !structure.bearish_bos)
   {
      bias.direction = PFLS_DIRECTION_BULLISH;

      bias.protected_level =
         structure.protected_low;
   }
   else if(structure.bearish_bos &&
           !structure.bullish_bos)
   {
      bias.direction = PFLS_DIRECTION_BEARISH;

      bias.protected_level =
         structure.protected_high;
   }
   else
   {
      return false;
   }

   if(bias.protected_level <= 0.0)
      return false;

   bias.active = true;
   bias.invalidated = false;

   bias.acceptance_closes = 0;

   bias.created_time = structure.bos_time;

   if(bias.created_time == 0)
      bias.created_time = TimeCurrent();

   return true;
}

//====================================================================
// MONITOR PROVISIONAL BIAS INVALIDATION
//====================================================================

bool PFLS_CheckProvisionalInvalidation(
   const MqlRates &rates[],
   const int total,
   PFLS_ProvisionalBias &bias)
{
   if(!bias.active ||
      bias.invalidated ||
      total < 3)
   {
      return false;
   }

   if(bias.protected_level <= 0.0)
      return false;

   bool close_beyond = false;

   if(bias.direction == PFLS_DIRECTION_BULLISH)
   {
      close_beyond =
         (rates[1].close < bias.protected_level &&
          rates[2].close < bias.protected_level);
   }
   else if(bias.direction == PFLS_DIRECTION_BEARISH)
   {
      close_beyond =
         (rates[1].close > bias.protected_level &&
          rates[2].close > bias.protected_level);
   }
   else
   {
      return false;
   }

   if(close_beyond)
   {
      bias.acceptance_closes = 2;

      bias.invalidated = true;
      bias.active = false;

      bias.invalidation_time = rates[1].time;

      return true;
   }

   bias.acceptance_closes = 0;

   return false;
}

//====================================================================
// DIRECTION TEXT
//====================================================================

string PFLS_DirectionText(
   const PFLS_DIRECTION direction)
{
   switch(direction)
   {
      case PFLS_DIRECTION_BULLISH:
         return "BULLISH";

      case PFLS_DIRECTION_BEARISH:
         return "BEARISH";

      case PFLS_DIRECTION_NEUTRAL:
         return "NEUTRAL";

      case PFLS_DIRECTION_CONFLICTED:
         return "CONFLICTED";
   }

   return "UNKNOWN";
}

//====================================================================
// STRUCTURE EVENT TEXT
//====================================================================

string PFLS_StructureEventText(
   const PFLS_STRUCTURE_EVENT event)
{
   switch(event)
   {
      case PFLS_EVENT_NONE:
         return "NONE";

      case PFLS_EVENT_HIGHER_HIGH:
         return "HIGHER HIGH";

      case PFLS_EVENT_HIGHER_LOW:
         return "HIGHER LOW";

      case PFLS_EVENT_LOWER_HIGH:
         return "LOWER HIGH";

      case PFLS_EVENT_LOWER_LOW:
         return "LOWER LOW";

      case PFLS_EVENT_BULLISH_BOS:
         return "BULLISH BOS";

      case PFLS_EVENT_BEARISH_BOS:
         return "BEARISH BOS";
   }

   return "UNKNOWN";
}

//====================================================================
// MODULE VERSION
//====================================================================

string PFLS_GetStructureModuleVersion()
{
   return PFLS_STRUCTURE_MODULE_VERSION;
}

//+------------------------------------------------------------------+
#endif // PFLS_MARKET_STRUCTURE_MQH
