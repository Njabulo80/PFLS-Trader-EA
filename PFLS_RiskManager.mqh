
#ifndef PFLS_RISK_MANAGER_MQH
#define PFLS_RISK_MANAGER_MQH

//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| RISK MANAGEMENT MODULE                                           |
//| Version 2.00.3                                                   |
//|                                                                  |
//| Risk calculations and validation only.                           |
//| No order placement.                                              |
//+------------------------------------------------------------------+

#include "PFLS_EntryEngine.mqh"

#define PFLS_RISK_MODULE_VERSION "2.00.3"

//====================================================================
// DEFAULT RISK SETTINGS
//====================================================================

#define PFLS_DEFAULT_FIXED_LOT          0.01
#define PFLS_DEFAULT_MAX_RISK           3.0
#define PFLS_DEFAULT_MAX_DAILY_TRADES   2
#define PFLS_DEFAULT_MIN_RR             1.2
#define PFLS_DEFAULT_STOP_BUFFER        20
#define PFLS_DEFAULT_MAGIC_NUMBER       751103

//====================================================================
// RISK CONFIGURATION
//====================================================================

struct PFLS_RiskConfig
{
   double fixed_lot;
   double maximum_risk_percent;

   int maximum_daily_trades;

   double minimum_risk_reward;

   int stop_buffer_points;

   ulong magic_number;

   bool execution_enabled;
   bool emergency_stop;
};

//====================================================================
// TRADE PLAN
//====================================================================

struct PFLS_TradePlan
{
   bool valid;

   ENUM_ORDER_TYPE order_type;

   double entry_price;
   double stop_loss;
   double take_profit;

   double stop_distance;
   double target_distance;

   double risk_reward;

   double volume;

   double estimated_risk_money;
   double estimated_risk_percent;

   string rejection_reason;
};

//====================================================================
// RESET CONFIGURATION
//====================================================================

void PFLS_ResetRiskConfig(PFLS_RiskConfig &config)
{
   config.fixed_lot = PFLS_DEFAULT_FIXED_LOT;
   config.maximum_risk_percent = PFLS_DEFAULT_MAX_RISK;
   config.maximum_daily_trades = PFLS_DEFAULT_MAX_DAILY_TRADES;
   config.minimum_risk_reward = PFLS_DEFAULT_MIN_RR;
   config.stop_buffer_points = PFLS_DEFAULT_STOP_BUFFER;
   config.magic_number = PFLS_DEFAULT_MAGIC_NUMBER;

   config.execution_enabled = false;
   config.emergency_stop = false;
}

//====================================================================
// RESET TRADE PLAN
//====================================================================

void PFLS_ResetTradePlan(PFLS_TradePlan &plan)
{
   plan.valid = false;

   plan.order_type = ORDER_TYPE_BUY;

   plan.entry_price = 0.0;
   plan.stop_loss = 0.0;
   plan.take_profit = 0.0;

   plan.stop_distance = 0.0;
   plan.target_distance = 0.0;

   plan.risk_reward = 0.0;
   plan.volume = 0.0;

   plan.estimated_risk_money = 0.0;
   plan.estimated_risk_percent = 0.0;

   plan.rejection_reason = "PLAN NOT VALIDATED";
}

//====================================================================
// VALIDATE CONFIGURATION
//====================================================================

bool PFLS_ValidateRiskConfig(
   const PFLS_RiskConfig &config)
{
   if(config.fixed_lot <= 0.0)
      return false;

   if(config.maximum_risk_percent <= 0.0 ||
      config.maximum_risk_percent > 3.0)
      return false;

   if(config.maximum_daily_trades < 1 ||
      config.maximum_daily_trades > 2)
      return false;

   if(config.minimum_risk_reward < 1.2)
      return false;

   if(config.stop_buffer_points < 0)
      return false;

   if(config.magic_number == 0)
      return false;

   return true;
}

//====================================================================
// EXECUTION PERMISSION
//====================================================================

bool PFLS_RiskExecutionAllowed(
   const PFLS_RiskConfig &config)
{
   // Research build: execution is permanently denied.
   return false;
}

//====================================================================
// PRICE NORMALISATION
//====================================================================

double PFLS_RiskNormalisePrice(
   const string symbol,
   const double price,
   const bool round_up)
{
   double tick_size =
      SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   int digits =
      (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   if(tick_size <= 0.0)
      tick_size = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tick_size <= 0.0 || price <= 0.0)
      return 0.0;

   double steps = price / tick_size;
   double rounded_steps;

   if(round_up)
      rounded_steps = MathCeil(steps - 0.00000001);
   else
      rounded_steps = MathFloor(steps + 0.00000001);

   return NormalizeDouble(
      rounded_steps * tick_size,
      digits
   );
}

//====================================================================
// VOLUME PRECISION
//====================================================================

int PFLS_RiskVolumeDigits(const double step)
{
   for(int digits = 0; digits <= 8; digits++)
   {
      double scaled = step * MathPow(10.0, digits);

      if(MathAbs(scaled - MathRound(scaled)) < 0.00000001)
         return digits;
   }

   return 8;
}

//====================================================================
// NORMALISE VOLUME
//====================================================================

double PFLS_NormaliseVolume(
   const string symbol,
   const double requested_volume)
{
   if(requested_volume <= 0.0)
      return 0.0;

   double minimum_volume =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   double maximum_volume =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   double volume_step =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(minimum_volume <= 0.0 ||
      maximum_volume <= 0.0 ||
      volume_step <= 0.0)
      return 0.0;

   if(requested_volume < minimum_volume)
      return 0.0;

   double capped_volume =
      MathMin(requested_volume, maximum_volume);

   double steps = MathFloor(
      (capped_volume - minimum_volume) / volume_step
      + 0.00000001
   );

   double normalised =
      minimum_volume + steps * volume_step;

   int digits = PFLS_RiskVolumeDigits(volume_step);

   normalised = NormalizeDouble(normalised, digits);

   if(normalised < minimum_volume ||
      normalised > maximum_volume)
      return 0.0;

   return normalised;
}

//====================================================================
// CALCULATE STOP LOSS
//====================================================================

bool PFLS_CalculateStopLoss(
   const string symbol,
   const PFLS_EntryResult &entry,
   const PFLS_RiskConfig &config,
   double &stop_loss)
{
   stop_loss = 0.0;

   if(!entry.valid)
      return false;

   if(entry.zone_upper <= entry.zone_lower)
      return false;

   double point =
      SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(point <= 0.0)
      return false;

   double buffer =
      config.stop_buffer_points * point;

   if(entry.signal == PFLS_ENTRY_BUY_CANDIDATE)
   {
      double raw_stop = entry.zone_lower - buffer;

      stop_loss = PFLS_RiskNormalisePrice(
         symbol,
         raw_stop,
         false
      );

      return (
         stop_loss > 0.0 &&
         stop_loss < entry.candidate_price
      );
   }

   if(entry.signal == PFLS_ENTRY_SELL_CANDIDATE)
   {
      double raw_stop = entry.zone_upper + buffer;

      stop_loss = PFLS_RiskNormalisePrice(
         symbol,
         raw_stop,
         true
      );

      return (
         stop_loss > entry.candidate_price
      );
   }

   return false;
}

//====================================================================
// VALIDATE TAKE-PROFIT DIRECTION
//====================================================================

bool PFLS_ValidateTargetDirection(
   const PFLS_ENTRY_SIGNAL signal,
   const double entry_price,
   const double take_profit)
{
   if(entry_price <= 0.0 ||
      take_profit <= 0.0)
      return false;

   if(signal == PFLS_ENTRY_BUY_CANDIDATE)
      return take_profit > entry_price;

   if(signal == PFLS_ENTRY_SELL_CANDIDATE)
      return take_profit < entry_price;

   return false;
}

//====================================================================
// VALIDATE TARGET AGAINST PRICE FLOW OBJECTIVE
// VERSION 2.00.3
//====================================================================

bool PFLS_ValidateObjectiveTarget(
   const PFLS_EntryResult &entry,
   const double take_profit)
{
   if(!entry.valid)
      return false;

   if(entry.candidate_price <= 0.0 ||
      take_profit <= 0.0)
      return false;

   if(entry.objective_upper <= entry.objective_lower)
      return false;

   if(entry.objective_timeframe == PERIOD_CURRENT)
      return false;

   // Take-profit must be inside the objective zone.
   if(take_profit < entry.objective_lower ||
      take_profit > entry.objective_upper)
      return false;

   // BUY must target supply entirely above entry.
   if(entry.signal == PFLS_ENTRY_BUY_CANDIDATE)
   {
      if(!entry.objective_is_supply)
         return false;

      if(entry.objective_lower <= entry.candidate_price)
         return false;

      if(take_profit <= entry.candidate_price)
         return false;

      return true;
   }

   // SELL must target demand entirely below entry.
   if(entry.signal == PFLS_ENTRY_SELL_CANDIDATE)
   {
      if(entry.objective_is_supply)
         return false;

      if(entry.objective_upper >= entry.candidate_price)
         return false;

      if(take_profit >= entry.candidate_price)
         return false;

      return true;
   }

   return false;
}

//====================================================================
// CALCULATE RISK REWARD
//====================================================================

double PFLS_CalculateRiskReward(
   const PFLS_ENTRY_SIGNAL signal,
   const double entry_price,
   const double stop_loss,
   const double take_profit)
{
   double risk = 0.0;
   double reward = 0.0;

   if(signal == PFLS_ENTRY_BUY_CANDIDATE)
   {
      risk = entry_price - stop_loss;
      reward = take_profit - entry_price;
   }
   else if(signal == PFLS_ENTRY_SELL_CANDIDATE)
   {
      risk = stop_loss - entry_price;
      reward = entry_price - take_profit;
   }
   else
   {
      return 0.0;
   }

   if(risk <= 0.0 || reward <= 0.0)
      return 0.0;

   return reward / risk;
}

//====================================================================
// ESTIMATE MONEY RISK
//====================================================================

bool PFLS_EstimateMoneyRisk(
   const string symbol,
   const ENUM_ORDER_TYPE order_type,
   const double volume,
   const double entry_price,
   const double stop_loss,
   double &risk_money)
{
   risk_money = 0.0;

   if(volume <= 0.0 ||
      entry_price <= 0.0 ||
      stop_loss <= 0.0)
      return false;

   double calculated_profit = 0.0;

   if(!OrderCalcProfit(
      order_type,
      symbol,
      volume,
      entry_price,
      stop_loss,
      calculated_profit))
      return false;

   risk_money = MathAbs(calculated_profit);

   return risk_money > 0.0;
}

//====================================================================
// CALCULATE RISK-BASED VOLUME
//====================================================================

double PFLS_CalculateRiskBasedVolume(
   const string symbol,
   const ENUM_ORDER_TYPE order_type,
   const double entry_price,
   const double stop_loss,
   const double maximum_risk_percent)
{
   if(maximum_risk_percent <= 0.0 ||
      maximum_risk_percent > 3.0)
      return 0.0;

   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity <= 0.0)
      return 0.0;

   double risk_budget =
      equity * maximum_risk_percent / 100.0;

   double minimum_volume =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   double maximum_volume =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   double volume_step =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(minimum_volume <= 0.0 ||
      maximum_volume < minimum_volume ||
      volume_step <= 0.0)
      return 0.0;

   double minimum_risk = 0.0;

   if(!PFLS_EstimateMoneyRisk(
      symbol,
      order_type,
      minimum_volume,
      entry_price,
      stop_loss,
      minimum_risk))
      return 0.0;

   if(minimum_risk > risk_budget)
      return 0.0;

   int maximum_steps = (int)MathFloor(
      (maximum_volume - minimum_volume) / volume_step
      + 0.00000001
   );

   int low = 0;
   int high = maximum_steps;
   int best_step = -1;

   for(int i = 0; i < 64 && low <= high; i++)
   {
      int middle = low + (high - low) / 2;

      double candidate_volume =
         minimum_volume + middle * volume_step;

      candidate_volume = NormalizeDouble(
         candidate_volume,
         PFLS_RiskVolumeDigits(volume_step)
      );

      double candidate_risk = 0.0;

      if(!PFLS_EstimateMoneyRisk(
         symbol,
         order_type,
         candidate_volume,
         entry_price,
         stop_loss,
         candidate_risk))
         return 0.0;

      if(candidate_risk <= risk_budget)
      {
         best_step = middle;
         low = middle + 1;
      }
      else
      {
         high = middle - 1;
      }
   }

   if(best_step < 0)
      return 0.0;

   double result =
      minimum_volume + best_step * volume_step;

   return NormalizeDouble(
      result,
      PFLS_RiskVolumeDigits(volume_step)
   );
}

//====================================================================
// COUNT TODAY'S UNIQUE ENTRY POSITIONS
//====================================================================

int PFLS_CountDailyTrades(
   const string symbol,
   const ulong magic_number)
{
   datetime now = TimeCurrent();

   MqlDateTime date_parts;
   TimeToStruct(now, date_parts);

   date_parts.hour = 0;
   date_parts.min = 0;
   date_parts.sec = 0;

   datetime day_start = StructToTime(date_parts);

   if(!HistorySelect(day_start, now))
      return -1;

   ulong position_ids[2048];
   int unique_count = 0;

   int total = HistoryDealsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);

      if(ticket == 0)
         continue;

      if(HistoryDealGetString(
         ticket, DEAL_SYMBOL) != symbol)
         continue;

      if((ulong)HistoryDealGetInteger(
         ticket, DEAL_MAGIC) != magic_number)
         continue;

      ENUM_DEAL_ENTRY deal_entry =
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(
            ticket, DEAL_ENTRY);

      if(deal_entry != DEAL_ENTRY_IN &&
         deal_entry != DEAL_ENTRY_INOUT)
         continue;

      ulong position_id =
         (ulong)HistoryDealGetInteger(
            ticket, DEAL_POSITION_ID);

      if(position_id == 0)
         continue;

      bool already_counted = false;

      for(int j = 0; j < unique_count; j++)
      {
         if(position_ids[j] == position_id)
         {
            already_counted = true;
            break;
         }
      }

      if(already_counted)
         continue;

      if(unique_count >= 2048)
         return -1;

      position_ids[unique_count] = position_id;
      unique_count++;
   }

   return unique_count;
}

//====================================================================
// COUNT OPEN POSITIONS FOR SYMBOL
//====================================================================

int PFLS_CountOpenPositions(
   const string symbol,
   const ulong magic_number)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      if((ulong)PositionGetInteger(
         POSITION_MAGIC) != magic_number)
         continue;

      count++;
   }

   return count;
}

//====================================================================
// BUILD VALIDATED RESEARCH TRADE PLAN
//====================================================================

bool PFLS_BuildTradePlan(
   const string symbol,
   const PFLS_EntryResult &entry,
   const PFLS_RiskConfig &config,
   const double take_profit,
   PFLS_TradePlan &plan)
{
   PFLS_ResetTradePlan(plan);

   if(!PFLS_ValidateRiskConfig(config))
   {
      plan.rejection_reason = "INVALID RISK CONFIGURATION";
      return false;
   }

   if(!entry.valid)
   {
      plan.rejection_reason = "ENTRY CANDIDATE INVALID";
      return false;
   }

   if(entry.timeframe != PERIOD_M5)
   {
      plan.rejection_reason = "ENTRY MUST BE M5";
      return false;
   }

   if(entry.candidate_price <= 0.0)
   {
      plan.rejection_reason = "INVALID ENTRY PRICE";
      return false;
   }

   if(!PFLS_ValidateTargetDirection(
      entry.signal,
      entry.candidate_price,
      take_profit))
   {
      plan.rejection_reason = "INVALID TARGET DIRECTION";
      return false;
   }

   if(!PFLS_ValidateObjectiveTarget(entry, take_profit))
   {
      plan.rejection_reason =
         "OBJECTIVE TYPE, DIRECTION OR TARGET INVALID";
      return false;
   }

   // Enforce the daily research-plan limit.
   int daily_trades = PFLS_CountDailyTrades(
      symbol,
      config.magic_number
   );

   if(daily_trades < 0)
   {
      plan.rejection_reason = "DAILY HISTORY UNAVAILABLE";
      return false;
   }

   if(daily_trades >= config.maximum_daily_trades)
   {
      plan.rejection_reason = "DAILY TRADE LIMIT REACHED";
      return false;
   }

   // One open position per symbol and magic number.
   int open_positions = PFLS_CountOpenPositions(
      symbol,
      config.magic_number
   );

   if(open_positions < 0)
   {
      plan.rejection_reason = "POSITION CHECK FAILED";
      return false;
   }

   if(open_positions > 0)
   {
      plan.rejection_reason = "POSITION ALREADY OPEN";
      return false;
   }

   double stop_loss = 0.0;

   if(!PFLS_CalculateStopLoss(
      symbol,
      entry,
      config,
      stop_loss))
   {
      plan.rejection_reason = "STOP LOSS CALCULATION FAILED";
      return false;
   }

   double risk_reward = PFLS_CalculateRiskReward(
      entry.signal,
      entry.candidate_price,
      stop_loss,
      take_profit
   );

   if(risk_reward < config.minimum_risk_reward)
   {
      plan.rejection_reason = "RISK REWARD BELOW MINIMUM";
      return false;
   }

   ENUM_ORDER_TYPE order_type;

   if(entry.signal == PFLS_ENTRY_BUY_CANDIDATE)
      order_type = ORDER_TYPE_BUY;
   else if(entry.signal == PFLS_ENTRY_SELL_CANDIDATE)
      order_type = ORDER_TYPE_SELL;
   else
   {
      plan.rejection_reason = "UNSUPPORTED ENTRY SIGNAL";
      return false;
   }

   double volume = PFLS_NormaliseVolume(
      symbol,
      config.fixed_lot
   );

   if(volume <= 0.0)
   {
      plan.rejection_reason = "FIXED LOT INVALID FOR SYMBOL";
      return false;
   }

   double risk_money = 0.0;

   if(!PFLS_EstimateMoneyRisk(
      symbol,
      order_type,
      volume,
      entry.candidate_price,
      stop_loss,
      risk_money))
   {
      plan.rejection_reason = "MONEY RISK CALCULATION FAILED";
      return false;
   }

   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity <= 0.0)
   {
      plan.rejection_reason = "ACCOUNT EQUITY UNAVAILABLE";
      return false;
   }

   double risk_percent =
      (risk_money / equity) * 100.0;

   if(risk_percent > config.maximum_risk_percent)
   {
      plan.rejection_reason = "FIXED LOT EXCEEDS RISK CAP";
      return false;
   }

   plan.valid = true;
   plan.order_type = order_type;

   plan.entry_price = entry.candidate_price;
   plan.stop_loss = stop_loss;
   plan.take_profit = take_profit;

   plan.stop_distance =
      MathAbs(entry.candidate_price - stop_loss);

   plan.target_distance =
      MathAbs(take_profit - entry.candidate_price);

   plan.risk_reward = risk_reward;
   plan.volume = volume;

   plan.estimated_risk_money = risk_money;
   plan.estimated_risk_percent = risk_percent;

   plan.rejection_reason = "RESEARCH PLAN VALIDATED";

   return true;
}

//====================================================================
// MODULE VERSION
//====================================================================

string PFLS_GetRiskModuleVersion()
{
   return PFLS_RISK_MODULE_VERSION;
}

//+------------------------------------------------------------------+
#endif // PFLS_RISK_MANAGER_MQH
