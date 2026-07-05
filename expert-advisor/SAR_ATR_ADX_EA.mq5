//+------------------------------------------------------------------+
//|                                            SAR_ATR_ADX_EA.mq5    |
//|                                  Copyright 2026, User            |
//|  Entry: SAR flip (tren balik) | SL/TP: ATR14 | Filter: ADX14    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, User"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>

//--- Indikator
input group "=== Indikator ==="
input double             InpSarStep          = 0.01;        // SAR Step
input double             InpSarMaximum       = 0.08;        // SAR Maximum
input int                InpAtrPeriod        = 14;          // ATR Period
input double             InpAtrSlMult        = 2.0;         // SL = ATR x multiplier
input int                InpAdxPeriod        = 14;          // ADX Period
input double             InpAdxEntryMin      = 25.0;        // ADX min untuk entry
input double             InpAdxIdleMax       = 20.0;        // ADX max idle (bot off)

//--- Multi Entry TP (SL sama, TP beda per layer)
input group "=== Multi Entry TP ==="
input int                InpMaxEntries       = 5;           // Max layer entry per sinyal
input double             InpTpSlRatio1       = 1.5;         // Layer 1 TP/SL (0=off)
input double             InpTpSlRatio2       = 2.0;         // Layer 2 TP/SL (0=off)
input double             InpTpSlRatio3       = 1.3;         // Layer 3 TP/SL (0=off)
input double             InpTpSlRatio4       = 3.0;         // Layer 4 TP/SL (0=off)
input double             InpTpSlRatio5       = 0.0;         // Layer 5 TP/SL (0=off)

//--- Risk & Order
input group "=== Risk & Order ==="
input double             InpLotPerLayer      = 0.02;        // Lot per layer
input int                InpMaxSpread        = 50;          // Max spread (pts, 0=off)
input ulong              InpMagic            = 88002;       // Magic Number
input string             InpComment          = "SAR_ATR_ADX"; // Order comment prefix

//--- Lainnya
input group "=== Lainnya ==="
input bool               InpOneBatch         = true;        // Tunggu semua layer tutup sebelum sinyal baru

//--- Globals
CTrade   trade;
string   PREF = "";

int      g_sarHandle = INVALID_HANDLE;
int      g_atrHandle = INVALID_HANDLE;
int      g_adxHandle = INVALID_HANDLE;

datetime g_lastBarTime = 0;

enum ENUM_BOT_STATE
{
   BOT_IDLE_ADX,
   BOT_WAIT_ADX,
   BOT_READY
};

const int MAX_LAYERS = 5;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int GetActiveLayerCount(double &ratios[])
{
   double src[MAX_LAYERS];
   src[0] = InpTpSlRatio1;
   src[1] = InpTpSlRatio2;
   src[2] = InpTpSlRatio3;
   src[3] = InpTpSlRatio4;
   src[4] = InpTpSlRatio5;

   ArrayResize(ratios, 0);
   int limit = MathMin(InpMaxEntries, MAX_LAYERS);
   if(limit < 1) limit = 1;

   for(int i = 0; i < limit; i++)
   {
      if(src[i] <= 0.0) continue;
      int n = ArraySize(ratios);
      ArrayResize(ratios, n + 1);
      ratios[n] = src[i];
   }
   return ArraySize(ratios);
}

string TpRatiosSummary()
{
   double ratios[];
   int n = GetActiveLayerCount(ratios);
   if(n <= 0) return "-";

   string s = "1:" + DoubleToString(ratios[0], 1);
   for(int i = 1; i < n; i++)
      s += ", 1:" + DoubleToString(ratios[i], 1);
   return s;
}
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
   return (value > 0.0);
}

bool GetIndicators(double &sar1, double &sar2, double &atr1, double &adx1,
                   double &close1, double &close2)
{
   if(!CopyOne(g_sarHandle, 0, 1, sar1)) return false;
   if(!CopyOne(g_sarHandle, 0, 2, sar2)) return false;
   if(!CopyOne(g_atrHandle, 0, 1, atr1)) return false;
   if(!CopyOne(g_adxHandle,  0, 1, adx1)) return false;

   close1 = iClose(_Symbol, _Period, 1);
   close2 = iClose(_Symbol, _Period, 2);
   if(close1 == 0.0 || close2 == 0.0) return false;
   return true;
}

ENUM_BOT_STATE GetBotState(double adx)
{
   if(adx < InpAdxIdleMax)   return BOT_IDLE_ADX;
   if(adx <= InpAdxEntryMin) return BOT_WAIT_ADX;
   return BOT_READY;
}

string BotStateText(ENUM_BOT_STATE state)
{
   switch(state)
   {
      case BOT_IDLE_ADX: return "IDLE (ADX < " + DoubleToString(InpAdxIdleMax, 0) + ")";
      case BOT_WAIT_ADX: return "WAIT (ADX " + DoubleToString(InpAdxIdleMax, 0) + "-" + DoubleToString(InpAdxEntryMin, 0) + ")";
      case BOT_READY:    return "READY (ADX > " + DoubleToString(InpAdxEntryMin, 0) + ")";
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

bool BuildSlTp(ENUM_ORDER_TYPE orderType, double entryPrice, double atr1,
               double tpSlRatio, double &sl, double &tp,
               double &slDist, double &tpDist)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   slDist = atr1 * InpAtrSlMult;
   tpDist = slDist * tpSlRatio;

   if(orderType == ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(entryPrice - slDist, digits);
      tp = NormalizeDouble(entryPrice + tpDist, digits);
   }
   else
   {
      sl = NormalizeDouble(entryPrice + slDist, digits);
      tp = NormalizeDouble(entryPrice - tpDist, digits);
   }

   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * point;

   if(minDist > 0.0)
   {
      if(orderType == ORDER_TYPE_BUY)
      {
         if(entryPrice - sl < minDist) sl = NormalizeDouble(entryPrice - minDist, digits);
         if(tp - entryPrice < minDist) tp = NormalizeDouble(entryPrice + minDist, digits);
      }
      else
      {
         if(sl - entryPrice < minDist) sl = NormalizeDouble(entryPrice + minDist, digits);
         if(entryPrice - tp < minDist) tp = NormalizeDouble(entryPrice - minDist, digits);
      }
      slDist = MathAbs(entryPrice - sl);
      tpDist = MathAbs(tp - entryPrice);
   }

   return (slDist > 0.0 && tpDist > 0.0);
}

bool OpenLayer(ENUM_ORDER_TYPE orderType, double atr1, int layerIndex,
               double tpSlRatio, double price)
{
   double lot = NormalizeLot(InpLotPerLayer);
   if(lot <= 0.0) return false;

   double sl = 0.0, tp = 0.0, slDist = 0.0, tpDist = 0.0;
   if(!BuildSlTp(orderType, price, atr1, tpSlRatio, sl, tp, slDist, tpDist))
   {
      Print("Layer ", layerIndex + 1, " SL/TP invalid");
      return false;
   }

   string comment = InpComment + "_L" + IntegerToString(layerIndex + 1);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);

   bool ok = false;
   if(orderType == ORDER_TYPE_BUY)
      ok = trade.Buy(lot, _Symbol, price, sl, tp, comment);
   else
      ok = trade.Sell(lot, _Symbol, price, sl, tp, comment);

   if(!ok)
      Print("Layer ", layerIndex + 1, " gagal: ", trade.ResultRetcodeDescription());
   else
      Print("Layer ", layerIndex + 1, " ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " @ ", DoubleToString(price, _Digits),
            " SL=", DoubleToString(sl, _Digits),
            " TP=", DoubleToString(tp, _Digits),
            " RR 1:", DoubleToString(tpSlRatio, 1));

   return ok;
}

int OpenMultiTrades(ENUM_ORDER_TYPE orderType, double atr1)
{
   double ratios[];
   int layers = GetActiveLayerCount(ratios);
   if(layers <= 0) return 0;

   double price = (orderType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   int opened = 0;
   for(int i = 0; i < layers; i++)
   {
      if(OpenLayer(orderType, atr1, i, ratios[i], price))
         opened++;
   }

   Print("Multi entry: ", opened, "/", layers, " layer terbuka | SL=ATR x ",
         DoubleToString(InpAtrSlMult, 1));
   return opened;
}

void ProcessSignals()
{
   double sar1, sar2, atr1, adx1, close1, close2;
   if(!GetIndicators(sar1, sar2, atr1, adx1, close1, close2)) return;

   ENUM_BOT_STATE state = GetBotState(adx1);

   // ADX idle / wait — tidak entry, posisi terbuka dibiarkan (exit via SL/TP broker)
   if(state != BOT_READY) return;
   if(!IsSpreadOk()) return;
   if(InpOneBatch && CountMyPositions() > 0) return;

   // SAR flip = tren balik → buka semua layer (SL sama, TP beda)
   if(IsBuyFlip(close1, close2, sar1, sar2) && !HasPosition(POSITION_TYPE_BUY))
      OpenMultiTrades(ORDER_TYPE_BUY, atr1);
   else if(IsSellFlip(close1, close2, sar1, sar2) && !HasPosition(POSITION_TYPE_SELL))
      OpenMultiTrades(ORDER_TYPE_SELL, atr1);
}

void UpdateDashboard(double atr1, double adx1, ENUM_BOT_STATE state,
                     double close1, double sar1)
{
   double ratios[];
   int    layers  = GetActiveLayerCount(ratios);
   double slDist  = atr1 * InpAtrSlMult;
   string sarDir  = IsSarBullish(close1, sar1) ? "Bullish" : "Bearish";

   int x = 10, y = 20, lh = 18;

   CreateLabel(PREF + "Title", x, y, "SAR + ATR + ADX EA (Multi TP)", clrBlack, 10);
   y += lh;
   CreateLabel(PREF + "State", x, y, "Bot: " + BotStateText(state), BotStateColor(state), 9);
   y += lh;
   CreateLabel(PREF + "Adx", x, y, "ADX(" + IntegerToString(InpAdxPeriod) + "): " + DoubleToString(adx1, 2), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Atr", x, y, "ATR(" + IntegerToString(InpAtrPeriod) + "): " + DoubleToString(atr1, _Digits), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Sl", x, y, "SL dist: " + DoubleToString(slDist, _Digits) + " (semua layer)", clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Tp", x, y, "TP RR: " + TpRatiosSummary(), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Layers", x, y, "Layer aktif: " + IntegerToString(layers) + " x " + DoubleToString(InpLotPerLayer, 2) + " lot", clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Sar", x, y, "SAR: " + sarDir + " (entry only)", clrBlack, 9);
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
   PREF = "SARATR_" + IntegerToString(InpMagic) + "_";

   if(InpAdxIdleMax >= InpAdxEntryMin)
   {
      Print("Error: ADX idle max harus < ADX entry min");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpAtrSlMult <= 0.0 || InpLotPerLayer <= 0.0)
   {
      Print("Error: ATR SL mult dan lot per layer harus > 0");
      return INIT_PARAMETERS_INCORRECT;
   }

   double ratios[];
   if(GetActiveLayerCount(ratios) <= 0)
   {
      Print("Error: set minimal 1 InpTpSlRatio layer (> 0)");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_sarHandle = iSAR(_Symbol, _Period, InpSarStep, InpSarMaximum);
   g_atrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   g_adxHandle = iADX(_Symbol, _Period, InpAdxPeriod);

   if(g_sarHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE)
   {
      Print("Gagal buat handle indikator. Error: ", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   g_lastBarTime = iTime(_Symbol, _Period, 0);

   Print("SAR_ATR_ADX_EA v1.10 | SL=ATR(", InpAtrPeriod, ")x", InpAtrSlMult,
         " | Layers=", GetActiveLayerCount(ratios), " TP=", TpRatiosSummary(),
         " | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_sarHandle != INVALID_HANDLE) IndicatorRelease(g_sarHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   ObjectsDeleteAll(0, PREF);
}

void OnTick()
{
   double sar1, sar2, atr1, adx1, close1, close2;
   if(!GetIndicators(sar1, sar2, atr1, adx1, close1, close2)) return;

   ENUM_BOT_STATE state = GetBotState(adx1);
   UpdateDashboard(atr1, adx1, state, close1, sar1);

   if(!IsNewBar()) return;

   ProcessSignals();
}
