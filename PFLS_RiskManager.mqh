
#ifndef PFLS_RISK_MANAGER_MQH
#define PFLS_RISK_MANAGER_MQH

//+------------------------------------------------------------------+
//| PFLS TRADER 2.00                                                 |
//| RISK MANAGEMENT MODULE                                           |
//| Version 2.00.1                                                   |
//|                                                                  |
//| Responsibilities:                                                |
//| - Risk configuration                                             |
//| - Position volume calculation                                    |
//| - Stop-loss calculation                                          |
//| - Take-profit validation                                         |
//| - Risk/reward validation                                         |
//| - Daily trade limit                                              |
//| - Emergency execution lock                                       |
//|                                                                  |
//| Research module. No order placement.                             |
//+------------------------------------------------------------------+

#define PFLS_RISK_MODULE_VERSION "2.00.1"

//====================================================================
// DEFAULT RISK SETTINGS
//====================================================================

#define PFLS_DEFAULT_FIXED_LOT       0.01
#define PFLS_DEFAULT_MAX_RISK        3.0
#define PFLS_DEFAULT_MAX_DAILY_TRADES 2
#define PFLS_DEFAULT_MIN_RR          1.2
#define PFLS_DEFAULT_STOP_BUFFER     20
#define PFLS_DEFAULT_MAGIC_NUMBER    751103

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

   config.maximum_risk_percent =
      PFLS_DEFAULT_MAX_RISK;

   config.maximum_daily_trades =
      PFLS_DEFAULT_MAX_DAILY_TRADES;

   config.minimum_risk_reward =
      PFLS_DEFAULT_MIN_RR;

   config.stop_buffer_points =
      PFLS_DEFAULT_STOP_BUFFER;

   config.magic_number =
      PFLS_DEFAULT_MAGIC_NUMBER;

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
// CHECK CONFIGURATION
//====================================================================

bool PFLS_ValidateRiskConfig(
   const PFLS_RiskConfig &config)
{
   if(config.fixed_lot <= 0.0)
      return false;

   if(config.maximum_risk_percent <= 0.0 ||
      config.maximum_risk_percent > 3.0)
      return false;

   if(config.maximum_daily_trades < 1)
      return false;

   if(config.minimum_risk_reward < 1.2)
      return false;

   if(config.stop_buffer_points < 0)
      return false;

   return true;
}

//====================================================================
// CHECK EXECUTION PERMISSION
//====================================================================

bool PFLS_RiskExecutionAllowed(
   const PFLS_RiskConfig &config)
{
   if(!config.execution_enabled)
      return false;

   if(config.emergency_stop)
      return false;

   return true;
}

//====================================================================
// NORMALISE VOLUME
//====================================================================

double PFLS_NormaliseVolume(
   const string symbol,
   const double requested_volume)
{
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

   double steps =
      MathFloor((capped_volume - minimum_volume) /
                volume_step + 0.00000001);

   double normalised =
      minimum_volume + steps * volume_step;

   int volume_digits = 0;

   double step_check = volume_step;

   while(volume_digits < 8 &&
         MathAbs(step_check -
         MathRound(step_check)) > 0.00000001)
   {
      step_check *= 10.0;
      volume_digits++;
   }

   return NormalizeDouble(normalised, volume_digits);
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

   double point =
      SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(point <= 0.0)
      return false;

   double buffer =
      config.stop_buffer_points * point;

   if(entry.signal == PFLS_ENTRY_BUY_CANDIDATE)
   {
      stop_loss = entry.zone_lower - buffer;

      if(stop_loss >= entry.candidate_price)
         return false;

      return true;
   }

   if(entry.signal == PFLS_ENTRY_SELL_CANDIDATE)
   {
      stop_loss = entry.zone_upper + buffer;

      if(stop_loss <= entry.candidate_price)
         return false;

      return true;
   }

   return false;
}

//====================================================================
// VALIDATE TAKE PROFIT DIRECTION
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

   double calculated_profit = 0.0;

   if(!OrderCalcProfit(
      order_type,
      symbol,
      volume,
      entry_price,
      stop_loss,
      calculated_profit))
   {
      return false;
   }

   risk_money = MathAbs(calculated_profit);

   return (risk_money > 0.0);
}

//====================================================================
// CALCULATE POSITION VOLUME FROM RISK CAP
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
      maximum_volume <= 0.0 ||
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

   // Never force a minimum lot that exceeds the risk budget.
   if(minimum_risk > risk_budget)
      return 0.0;

   double low = minimum_volume;
   double high = maximum_volume;

   double best = 0.0;

   for(int i = 0; i < 60; i++)
   {
      double middle = (low + high) / 2.0;

      double candidate =
         PFLS_NormaliseVolume(symbol, middle);

      if(candidate <= 0.0)
         break;

      double candidate_risk = 0.0;

      if(!PFLS_EstimateMoneyRisk(
         symbol,
         order_type,
         candidate,
         entry_price,
         stop_loss,
         candidate_risk))
         return 0.0;

      if(candidate_risk <= risk_budget)
      {
         best = candidate;

         low = middle + volume_step / 2.0;
      }
      else
      {
         high = middle - volume_step / 2.0;
      }

      if(high < low)
         break;
   }

   return PFLS_NormaliseVolume(symbol, best);
}

//====================================================================
// COUNT TODAY'S EA TRADES
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

   datetime day_start =
      StructToTime(date_parts);

   if(!HistorySelect(day_start, now))
      return -1;

   int count = 0;

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

      ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(
            ticket, DEAL_ENTRY);

      if(entry == DEAL_ENTRY_IN ||
         entry == DEAL_ENTRY_INOUT)
      {
         count++;
      }
   }

   return count;
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
// BUILD A VALIDATED TRADE PLAN
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

   if(!PFLS_ValidateTargetDirection(
      entry.signal,
      entry.candidate_price,
      take_profit))
   {
      plan.rejection_reason = "INVALID TARGET DIRECTION";
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

   double risk_reward =
      PFLS_CalculateRiskReward(
         entry.signal,
         entry.candidate_price,
         stop_loss,
         take_profit);

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
      config.fixed_lot);

   if(volume <= 0.0)
   {
      plan.rejection_reason = "FIXED LOT NOT VALID FOR SYMBOL";
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

   plan.rejection_reason = "PLAN VALIDATED";

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
