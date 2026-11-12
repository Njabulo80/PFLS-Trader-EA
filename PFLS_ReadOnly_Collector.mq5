//+------------------------------------------------------------------+
//| PFLS READ-ONLY MT5 ACCOUNT COLLECTOR                             |
//| Version 1.00                                                     |
//| Reads demo account snapshots and recent deal history only.       |
//| NO OrderSend / OrderModify / OrderClose functions are present.   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "PFLS read-only MT5 demo account collector. No trading functions."

input group "PFLS SECURE BRIDGE"
input string InpBridgeURL = "https://pfls-communication-bridge-v2.dlamininjabulombhodziya.workers.dev/api/mt5/snapshot";
input string InpBridgeSecret = ""; // Set locally in MT5 EA inputs. Never share this value.
input int    InpSyncSeconds = 20;
input int    InpHistoryDays = 30;
input int    InpMaxHistoryDeals = 40;
input bool   InpDemoAccountsOnly = true;

string PFLS_JsonEscape(const string value)
{
   string out="";
   for(int i=0;i<StringLen(value);i++)
   {
      ushort ch=StringGetCharacter(value,i);
      if(ch==34) out+="\\\"";
      else if(ch==92) out+="\\\\";
      else if(ch==10) out+="\\n";
      else if(ch==13) out+="\\r";
      else if(ch==9) out+="\\t";
      else if(ch<32) out+=" ";
      else out+=ShortToString(ch);
   }
   return out;
}

string PFLS_JsonNumber(const double value,const int digits=2)
{
   if(!MathIsValidNumber(value)) return "0";
   return DoubleToString(value,digits);
}

string PFLS_AccountMode()
{
   ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(mode==ACCOUNT_TRADE_MODE_DEMO) return "DEMO";
   if(mode==ACCOUNT_TRADE_MODE_CONTEST) return "CONTEST";
   return "REAL";
}

string PFLS_BuildSnapshot()
{
   string symbol=_Symbol;
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   string server=AccountInfoString(ACCOUNT_SERVER);
   string company=AccountInfoString(ACCOUNT_COMPANY);
   long login=AccountInfoInteger(ACCOUNT_LOGIN);

   string json="{";
   json+="\"schema_version\":1,";
   json+="\"collector_version\":\"1.00\",";
   json+="\"account_type\":\""+PFLS_AccountMode()+"\",";
   json+="\"account_login\":"+IntegerToString(login)+",";
   json+="\"account_currency\":\""+PFLS_JsonEscape(currency)+"\",";
   json+="\"account_server\":\""+PFLS_JsonEscape(server)+"\",";
   json+="\"broker_company\":\""+PFLS_JsonEscape(company)+"\",";
   json+="\"balance\":"+PFLS_JsonNumber(AccountInfoDouble(ACCOUNT_BALANCE))+",";
   json+="\"equity\":"+PFLS_JsonNumber(AccountInfoDouble(ACCOUNT_EQUITY))+",";
   json+="\"margin\":"+PFLS_JsonNumber(AccountInfoDouble(ACCOUNT_MARGIN))+",";
   json+="\"free_margin\":"+PFLS_JsonNumber(AccountInfoDouble(ACCOUNT_MARGIN_FREE))+",";
   json+="\"margin_level\":"+PFLS_JsonNumber(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL))+",";
   json+="\"floating_profit\":"+PFLS_JsonNumber(AccountInfoDouble(ACCOUNT_PROFIT))+",";
   json+="\"terminal_connected\":"+(TerminalInfoInteger(TERMINAL_CONNECTED)?"true":"false")+",";
   json+="\"symbol\":\""+PFLS_JsonEscape(symbol)+"\",";
   json+="\"snapshot_time\":\""+TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS)+"\",";
   json+="\"open_positions\":[";

   int positions=PositionsTotal();
   for(int i=0;i<positions;i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(i>0) json+=",";
      string ps=PositionGetString(POSITION_SYMBOL);
      long type=PositionGetInteger(POSITION_TYPE);
      json+="{";
      json+="\"ticket\":"+IntegerToString((long)ticket)+",";
      json+="\"symbol\":\""+PFLS_JsonEscape(ps)+"\",";
      json+="\"side\":\""+(type==POSITION_TYPE_BUY?"BUY":"SELL")+"\",";
      json+="\"volume\":"+PFLS_JsonNumber(PositionGetDouble(POSITION_VOLUME),2)+",";
      json+="\"open_price\":"+PFLS_JsonNumber(PositionGetDouble(POSITION_PRICE_OPEN),8)+",";
      json+="\"current_price\":"+PFLS_JsonNumber(PositionGetDouble(POSITION_PRICE_CURRENT),8)+",";
      json+="\"stop_loss\":"+PFLS_JsonNumber(PositionGetDouble(POSITION_SL),8)+",";
      json+="\"take_profit\":"+PFLS_JsonNumber(PositionGetDouble(POSITION_TP),8)+",";
      json+="\"profit\":"+PFLS_JsonNumber(PositionGetDouble(POSITION_PROFIT))+",";
      json+="\"swap\":"+PFLS_JsonNumber(PositionGetDouble(POSITION_SWAP))+",";
      json+="\"open_time\":"+IntegerToString((long)PositionGetInteger(POSITION_TIME));
      json+="}";
   }
   json+="],\"recent_deals\":[";

   datetime to=TimeCurrent();
   datetime from=to-(datetime)(MathMax(1,InpHistoryDays)*86400);
   if(HistorySelect(from,to))
   {
      int total=HistoryDealsTotal();
      int emitted=0;
      int start=MathMax(0,total-MathMax(1,InpMaxHistoryDeals));
      for(int i=start;i<total;i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(deal==0) continue;
         long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
         long dtype=HistoryDealGetInteger(deal,DEAL_TYPE);
         if(emitted>0) json+=",";
         json+="{";
         json+="\"ticket\":"+IntegerToString((long)deal)+",";
         json+="\"order\":"+IntegerToString((long)HistoryDealGetInteger(deal,DEAL_ORDER))+",";
         json+="\"position_id\":"+IntegerToString((long)HistoryDealGetInteger(deal,DEAL_POSITION_ID))+",";
         json+="\"time\":"+IntegerToString((long)HistoryDealGetInteger(deal,DEAL_TIME))+",";
         json+="\"symbol\":\""+PFLS_JsonEscape(HistoryDealGetString(deal,DEAL_SYMBOL))+"\",";
         json+="\"deal_type\":\""+EnumToString((ENUM_DEAL_TYPE)dtype)+"\",";
         json+="\"entry_type\":\""+EnumToString((ENUM_DEAL_ENTRY)entry)+"\",";
         json+="\"volume\":"+PFLS_JsonNumber(HistoryDealGetDouble(deal,DEAL_VOLUME),2)+",";
         json+="\"price\":"+PFLS_JsonNumber(HistoryDealGetDouble(deal,DEAL_PRICE),8)+",";
         json+="\"profit\":"+PFLS_JsonNumber(HistoryDealGetDouble(deal,DEAL_PROFIT))+",";
         json+="\"commission\":"+PFLS_JsonNumber(HistoryDealGetDouble(deal,DEAL_COMMISSION))+",";
         json+="\"swap\":"+PFLS_JsonNumber(HistoryDealGetDouble(deal,DEAL_SWAP))+",";
         json+="\"fee\":"+PFLS_JsonNumber(HistoryDealGetDouble(deal,DEAL_FEE))+",";
         json+="\"comment\":\""+PFLS_JsonEscape(HistoryDealGetString(deal,DEAL_COMMENT))+"\"";
         json+="}";
         emitted++;
      }
   }
   json+="]}";
   return json;
}

bool PFLS_SendSnapshot()
{
   if(StringLen(InpBridgeSecret)<24)
   {
      Print("PFLS BRIDGE: configure a strong bridge secret in EA inputs.");
      return false;
   }
   if(InpDemoAccountsOnly && PFLS_AccountMode()!="DEMO")
   {
      Print("PFLS SAFETY: collector is configured for DEMO accounts only. No snapshot sent.");
      return false;
   }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      Print("PFLS BRIDGE: MT5 terminal is not connected.");
      return false;
   }

   string body=PFLS_BuildSnapshot();
   char data[],result[];
   string response_headers;
   int size=StringToCharArray(body,data,0,WHOLE_ARRAY,CP_UTF8);
   if(size<=1) return false;
   ArrayResize(data,size-1); // omit terminating null byte

   string headers="Content-Type: application/json\r\nAuthorization: Bearer "+InpBridgeSecret+"\r\n";
   ResetLastError();
   int code=WebRequest("POST",InpBridgeURL,headers,12000,data,result,response_headers);
   if(code==-1)
   {
      Print("PFLS BRIDGE WebRequest failed. MT5 error ",GetLastError(),
            ". Add https://pfls-communication-bridge-v2.dlamininjabulombhodziya.workers.dev to Tools > Options > Expert Advisors > Allow WebRequest.");
      return false;
   }
   string response=CharArrayToString(result,0,-1,CP_UTF8);
   if(code<200 || code>=300)
   {
      Print("PFLS BRIDGE HTTP ",code,": ",response);
      return false;
   }
   Print("PFLS BRIDGE: read-only demo snapshot delivered. HTTP ",code);
   return true;
}

int OnInit()
{
   if(InpSyncSeconds<10 || InpHistoryDays<1 || InpMaxHistoryDeals<1 || InpMaxHistoryDeals>100)
      return INIT_PARAMETERS_INCORRECT;
   if(StringLen(InpBridgeSecret)<24)
   {
      Print("PFLS BRIDGE: set InpBridgeSecret locally before enabling collector.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpDemoAccountsOnly && PFLS_AccountMode()!="DEMO")
   {
      Print("PFLS SAFETY: DEMO account required. Collector will not start on a real account.");
      return INIT_FAILED;
   }
   EventSetTimer(InpSyncSeconds);
   PFLS_SendSnapshot();
   Print("PFLS READ-ONLY COLLECTOR 1.00 INITIALISED. ORDER EXECUTION IS NOT IMPLEMENTED.");
   return INIT_SUCCEEDED;
}

void OnTimer()
{
   PFLS_SendSnapshot();
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("PFLS read-only collector stopped.");
}
