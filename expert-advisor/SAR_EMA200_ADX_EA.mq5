//+------------------------------------------------------------------+
//|                                          SAR_EMA200_ADX_EA.mq5   |
//|                                  Copyright 2026, User            |
//|  Entry: Parabolic SAR flip + EMA200 trend + ADX14 strength       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, User"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Indikator
input group "=== Indikator ==="
input double             InpSarStep          = 0.01;        // SAR Step
input double             InpSarMaximum       = 0.08;        // SAR Maximum
input int                InpEmaPeriod        = 200;         // EMA Period
input int                InpAdxPeriod        = 14;          // ADX Period
input double             InpAdxEntryMin      = 25.0;        // ADX min untuk entry
input double             InpAdxIdleMax       = 20.0;        // ADX max idle (bot off)

//--- Risk & Order
input group "=== Risk & Order ==="
input double             InpLot              = 0.01;        // Lot
input int                InpSlPoints         = 0;           // SL tambahan (pts, 0=SAR saja)
input int                InpTpPoints         = 0;           // TP (pts, 0=exit SAR flip)
input int                InpMaxSpread        = 50;          // Max spread (pts, 0=off)
input ulong              InpMagic            = 88001;       // Magic Number
input string             InpComment          = "SAR_EMA_ADX"; // Order comment

//--- Lainnya
input group "=== Lainnya ==="
input bool               InpOnePosition      = true;        // Satu posisi sekaligus
input bool               InpCloseOnFlip      = true;        // Tutup posisi saat SAR flip lawan

//--- Globals
CTrade   trade;
string   PREF = "";

int      g_sarHandle  = INVALID_HANDLE;
int      g_emaHandle  = INVALID_HANDLE;
int      g_adxHandle  = INVALID_HANDLE;

datetime g_lastBarTime = 0;

enum ENUM_BOT_STATE
{
   BOT_IDLE_ADX,     // ADX < 20
   BOT_WAIT_ADX,     // 20 <= ADX <= 25
   BOT_READY         // ADX > 25
};

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0) stepLot = 0.01;

   lot = MathFloor(lot / stepLot + 0.0000001) * stepLot;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return lot;
}

bool IsNewBar()
{
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBarTime) return false;
   g_lastBarTime = barTime;
   return true;
}

bool IsSpreadOk()
{
   if(InpMaxSpread <= 0) return true;
   return (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpread);
}

bool CopyOne(int handle, int buffer, int shift, double &value)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, buffer, shift, 1, buf) != 1) return false;
   value = buf[0];
   return true;
}

bool GetIndicators(double &sar1, double &sar2, double &ema1, double &adx1,
                   double &close1, double &close2)
{
   if(!CopyOne(g_sarHandle, 0, 1, sar1)) return false;
   if(!CopyOne(g_sarHandle, 0, 2, sar2)) return false;
   if(!CopyOne(g_emaHandle, 0, 1, ema1)) return false;
   if(!CopyOne(g_adxHandle,  0, 1, adx1)) return false;

   close1 = iClose(_Symbol, _Period, 1);
   close2 = iClose(_Symbol, _Period, 2);
   if(close1 == 0.0 || close2 == 0.0) return false;
   return true;
}

ENUM_BOT_STATE GetBotState(double adx)
{
   if(adx < InpAdxIdleMax)  return BOT_IDLE_ADX;
   if(adx <= InpAdxEntryMin) return BOT_WAIT_ADX;
   return BOT_READY;
}

string BotStateText(ENUM_BOT_STATE state)
{
   switch(state)
   {
      case BOT_IDLE_ADX:  return "IDLE (ADX < " + DoubleToString(InpAdxIdleMax, 0) + ")";
      case BOT_WAIT_ADX:  return "WAIT (ADX " + DoubleToString(InpAdxIdleMax, 0) + "-" + DoubleToString(InpAdxEntryMin, 0) + ")";
      case BOT_READY:     return "READY (ADX > " + DoubleToString(InpAdxEntryMin, 0) + ")";
   }
   return "UNKNOWN";
}

color BotStateColor(ENUM_BOT_STATE state)
{
   switch(state)
   {
      case BOT_IDLE_ADX: return clrTomato;
      case BOT_WAIT_ADX: return clrOrange;
      case BOT_READY:    return clrLimeGreen;
   }
   return clrGray;
}

int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      count++;
   }
   return count;
}

bool HasPosition(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE) == type) return true;
   }
   return false;
}

bool IsSarBullish(double closePrice, double sarValue)
{
   return (closePrice > sarValue);
}

bool IsSarBearish(double closePrice, double sarValue)
{
   return (closePrice < sarValue);
}

bool IsBuyFlip(double close1, double close2, double sar1, double sar2)
{
   return IsSarBullish(close1, sar1) && IsSarBearish(close2, sar2);
}

bool IsSellFlip(double close1, double close2, double sar1, double sar2)
{
   return IsSarBearish(close1, sar1) && IsSarBullish(close2, sar2);
}

double BuildSlPrice(ENUM_ORDER_TYPE orderType, double sar1)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(orderType == ORDER_TYPE_BUY)
   {
      double sl = sar1;
      if(InpSlPoints > 0) sl -= InpSlPoints * point;
      return NormalizeDouble(sl, digits);
   }

   double sl = sar1;
   if(InpSlPoints > 0) sl += InpSlPoints * point;
   return NormalizeDouble(sl, digits);
}

double BuildTpPrice(ENUM_ORDER_TYPE orderType, double entryPrice)
{
   if(InpTpPoints <= 0) return 0.0;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(orderType == ORDER_TYPE_BUY)
      return NormalizeDouble(entryPrice + InpTpPoints * point, digits);

   return NormalizeDouble(entryPrice - InpTpPoints * point, digits);
}

bool OpenTrade(ENUM_ORDER_TYPE orderType, double sar1)
{
   double lot = NormalizeLot(InpLot);
   if(lot <= 0.0) return false;

   double price = (orderType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl = BuildSlPrice(orderType, sar1);
   double tp = BuildTpPrice(orderType, price);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);

   bool ok = false;
   if(orderType == ORDER_TYPE_BUY)
      ok = trade.Buy(lot, _Symbol, price, sl, tp, InpComment);
   else
      ok = trade.Sell(lot, _Symbol, price, sl, tp, InpComment);

   if(!ok)
      Print("Order gagal: ", trade.ResultRetcodeDescription());
   else
      Print("Order ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " @ ", DoubleToString(price, _Digits),
            " SL=", DoubleToString(sl, _Digits),
            " TP=", (tp > 0 ? DoubleToString(tp, _Digits) : "SAR flip"));

   return ok;
}

void ClosePositionsByType(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE) != type) continue;

      if(!trade.PositionClose(ticket))
         Print("Close gagal ticket ", ticket, ": ", trade.ResultRetcodeDescription());
   }
}

void TrailSlWithSar(double sar1)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;

      double curSl = PositionGetDouble(POSITION_SL);
      long   ptype = PositionGetInteger(POSITION_TYPE);

      if(ptype == POSITION_TYPE_BUY)
      {
         double newSl = sar1;
         if(InpSlPoints > 0) newSl -= InpSlPoints * point;
         newSl = NormalizeDouble(newSl, digits);
         if(newSl > curSl || curSl == 0.0)
            trade.PositionModify(ticket, newSl, PositionGetDouble(POSITION_TP));
      }
      else if(ptype == POSITION_TYPE_SELL)
      {
         double newSl = sar1;
         if(InpSlPoints > 0) newSl += InpSlPoints * point;
         newSl = NormalizeDouble(newSl, digits);
         if(newSl < curSl || curSl == 0.0)
            trade.PositionModify(ticket, newSl, PositionGetDouble(POSITION_TP));
      }
   }
}

void ProcessSignals()
{
   double sar1, sar2, ema1, adx1, close1, close2;
   if(!GetIndicators(sar1, sar2, ema1, adx1, close1, close2)) return;

   ENUM_BOT_STATE state = GetBotState(adx1);

   // Trailing SL mengikuti SAR (posisi terbuka)
   if(CountMyPositions() > 0)
      TrailSlWithSar(sar1);

   // Exit saat SAR flip lawan arah
   if(InpCloseOnFlip)
   {
      if(IsSellFlip(close1, close2, sar1, sar2) && HasPosition(POSITION_TYPE_BUY))
         ClosePositionsByType(POSITION_TYPE_BUY);

      if(IsBuyFlip(close1, close2, sar1, sar2) && HasPosition(POSITION_TYPE_SELL))
         ClosePositionsByType(POSITION_TYPE_SELL);
   }

   // Bot idle / wait — tidak entry
   if(state != BOT_READY) return;
   if(!IsSpreadOk()) return;
   if(InpOnePosition && CountMyPositions() > 0) return;

   bool uptrend   = (close1 > ema1);
   bool downtrend = (close1 < ema1);

   // Buy: harga di atas EMA200 + SAR flip bullish
   if(uptrend && IsBuyFlip(close1, close2, sar1, sar2))
   {
      if(!HasPosition(POSITION_TYPE_BUY))
         OpenTrade(ORDER_TYPE_BUY, sar1);
      return;
   }

   // Sell: harga di bawah EMA200 + SAR flip bearish
   if(downtrend && IsSellFlip(close1, close2, sar1, sar2))
   {
      if(!HasPosition(POSITION_TYPE_SELL))
         OpenTrade(ORDER_TYPE_SELL, sar1);
   }
}

void UpdateDashboard(double ema1, double adx1, ENUM_BOT_STATE state,
                     double close1, double sar1)
{
   string trend = (close1 > ema1) ? "UP (Buy only)" : (close1 < ema1) ? "DOWN (Sell only)" : "FLAT";
   color  trendClr = (close1 > ema1) ? clrDodgerBlue : (close1 < ema1) ? clrOrangeRed : clrGray;
   string sarDir = IsSarBullish(close1, sar1) ? "Bullish" : "Bearish";

   int x = 10, y = 20, lh = 18;

   CreateLabel(PREF + "Title", x, y, "SAR + EMA200 + ADX EA", clrBlack, 10);
   y += lh;
   CreateLabel(PREF + "State", x, y, "Bot: " + BotStateText(state), BotStateColor(state), 9);
   y += lh;
   CreateLabel(PREF + "Adx", x, y, "ADX(" + IntegerToString(InpAdxPeriod) + "): " + DoubleToString(adx1, 2), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Ema", x, y, "EMA(" + IntegerToString(InpEmaPeriod) + "): " + DoubleToString(ema1, _Digits), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Trend", x, y, "Trend: " + trend, trendClr, 9);
   y += lh;
   CreateLabel(PREF + "Sar", x, y, "SAR: " + sarDir + " @ " + DoubleToString(sar1, _Digits), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Pos", x, y, "Posisi: " + IntegerToString(CountMyPositions()), clrBlack, 9);
}

void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   PREF = "SARADX_" + IntegerToString(InpMagic) + "_";

   if(InpAdxIdleMax >= InpAdxEntryMin)
   {
      Print("Error: ADX idle max harus < ADX entry min");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_sarHandle = iSAR(_Symbol, _Period, InpSarStep, InpSarMaximum);
   g_emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_adxHandle = iADX(_Symbol, _Period, InpAdxPeriod);

   if(g_sarHandle == INVALID_HANDLE || g_emaHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE)
   {
      Print("Gagal buat handle indikator. Error: ", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);

   g_lastBarTime = iTime(_Symbol, _Period, 0);

   Print("SAR_EMA200_ADX_EA initialized | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_sarHandle  != INVALID_HANDLE) IndicatorRelease(g_sarHandle);
   if(g_emaHandle  != INVALID_HANDLE) IndicatorRelease(g_emaHandle);
   if(g_adxHandle  != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   ObjectsDeleteAll(0, PREF);
}

void OnTick()
{
   double sar1, sar2, ema1, adx1, close1, close2;
   if(!GetIndicators(sar1, sar2, ema1, adx1, close1, close2)) return;

   ENUM_BOT_STATE state = GetBotState(adx1);
   UpdateDashboard(ema1, adx1, state, close1, sar1);

   if(!IsNewBar()) return;

   ProcessSignals();
}
