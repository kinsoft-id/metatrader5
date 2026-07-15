//+------------------------------------------------------------------+
//|                                            SAR3_ATR_ADX_EA.mq5    |
//|                                  Copyright 2026, User            |
//|  Entry: 3x SAR flip | SL/TP: ATR14 | Filter: EMA50/200 + ADX14    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, User"
#property version   "1.20"
#property strict

#include <Trade\Trade.mqh>

//--- Filter Tren EMA
input group "=== Filter Tren EMA ==="
input int                InpEmaFast          = 50;          // EMA Fast
input int                InpEmaSlow          = 200;         // EMA Slow

//--- SAR Entry (3 layer)
input group "=== SAR Entry (Slow / Mod / Fast) ==="
input double             InpSarSlowStep      = 0.01;        // SAR Slow Step
input double             InpSarSlowMax       = 0.2;         // SAR Slow Maximum
input double             InpSarModStep       = 0.02;        // SAR Moderate Step
input double             InpSarModMax        = 0.2;         // SAR Moderate Maximum
input double             InpSarFastStep      = 0.03;        // SAR Fast Step
input double             InpSarFastMax       = 0.2;         // SAR Fast Maximum

input group "=== ATR / ADX ==="
input int                InpAtrPeriod        = 14;          // ATR Period
input double             InpAtrSlMult        = 2.0;         // SL = ATR x multiplier
input int                InpAdxPeriod        = 14;          // ADX Period
input double             InpAdxEntryMin      = 25.0;        // ADX min untuk entry
input double             InpAdxIdleMax       = 20.0;        // ADX max idle (bot off)

//--- Multi Entry TP (SL sama, TP beda per layer)
input group "=== Multi Entry TP ==="
input int                InpMaxEntries       = 3;           // Max layer entry per sinyal
input double             InpTpSlRatio1       = 1.5;         // Layer 1 TP/SL (0=off)
input double             InpTpSlRatio2       = 2.0;         // Layer 2 TP/SL (0=off)
input double             InpTpSlRatio3       = 3.0;         // Layer 3 TP/SL (0=off)
input double             InpTpSlRatio4       = 4.0;         // Layer 4 TP/SL (0=off)
input double             InpTpSlRatio5       = 5.0;         // Layer 5 TP/SL (0=off)

enum ENUM_LOT_MODE
{
   LOT_FIXED        = 0,   // Lot tetap per layer
   LOT_RISK_PERCENT = 1    // Otomatis dari risk %
};

//--- Risk & Order
input group "=== Lot / Risk ==="
input ENUM_LOT_MODE      InpLotMode          = LOT_RISK_PERCENT; // Mode lot
input double             InpLotPerLayer      = 0.02;        // Lot tetap per layer
input double             InpRiskPercent      = 0.5;         // Risk % total batch (semua layer)
input bool               InpRiskUseEquity    = false;       // Risk dari equity (false=balance)
input double             InpMaxLotPerLayer   = 0.0;         // Max lot per layer (0=tanpa batas)

input group "=== Order ==="
input int                InpMaxSpread        = 50;          // Max spread (pts, 0=off)
input ulong              InpMagic            = 88002;       // Magic Number
input string             InpComment          = "SAR_ATR_ADX"; // Order comment prefix

//--- Lainnya
input group "=== Lainnya ==="
input bool               InpOneBatch         = true;        // Tunggu semua layer tutup sebelum sinyal baru

//--- Globals
CTrade   trade;
string   PREF = "";

int      g_sarSlowHandle = INVALID_HANDLE;
int      g_sarModHandle  = INVALID_HANDLE;
int      g_sarFastHandle = INVALID_HANDLE;
int      g_emaFastHandle = INVALID_HANDLE;
int      g_emaSlowHandle = INVALID_HANDLE;
int      g_atrHandle     = INVALID_HANDLE;
int      g_adxHandle     = INVALID_HANDLE;

datetime g_lastBarTime = 0;

const int DASH_BG_X    = 4;
const int DASH_BG_Y    = 10;
const int DASH_BG_W    = 420;
const int DASH_ROW_H   = 18;
const int DASH_ROWS    = 15;
const int DASH_BG_PAD  = 8;

enum ENUM_BOT_STATE
{
   BOT_IDLE_ADX,
   BOT_WAIT_ADX,
   BOT_READY
};

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int GetActiveLayerCount(double &ratios[])
{
   double src[5];
   src[0] = InpTpSlRatio1;
   src[1] = InpTpSlRatio2;
   src[2] = InpTpSlRatio3;
   src[3] = InpTpSlRatio4;
   src[4] = InpTpSlRatio5;

   ArrayResize(ratios, 0);
   int limit = MathMin(InpMaxEntries, 5);
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

double GetRiskBaseAmount()
{
   if(InpRiskUseEquity)
      return AccountInfoDouble(ACCOUNT_EQUITY);
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

string LotModeLabel()
{
   if(InpLotMode == LOT_RISK_PERCENT)
      return "Risk " + DoubleToString(InpRiskPercent, 2) + "% / batch";
   return "Fixed " + DoubleToString(InpLotPerLayer, 2);
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

bool CopyBufferOne(int handle, int shift, double &value, bool requirePositive)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   value = buf[0];
   if(requirePositive && value <= 0.0) return false;
   return true;
}

bool GetIndicators(double &sarSlow1, double &sarSlow2,
                   double &sarMod1,  double &sarMod2,
                   double &sarFast1, double &sarFast2,
                   double &emaFast1, double &emaSlow1,
                   double &atr1, double &adx1,
                   double &close1, double &close2)
{
   if(!CopyBufferOne(g_sarSlowHandle, 1, sarSlow1, true)) return false;
   if(!CopyBufferOne(g_sarSlowHandle, 2, sarSlow2, true)) return false;
   if(!CopyBufferOne(g_sarModHandle,  1, sarMod1,  true)) return false;
   if(!CopyBufferOne(g_sarModHandle,  2, sarMod2,  true)) return false;
   if(!CopyBufferOne(g_sarFastHandle, 1, sarFast1, true)) return false;
   if(!CopyBufferOne(g_sarFastHandle, 2, sarFast2, true)) return false;
   if(!CopyBufferOne(g_emaFastHandle, 1, emaFast1, false)) return false;
   if(!CopyBufferOne(g_emaSlowHandle, 1, emaSlow1, false)) return false;
   if(!CopyBufferOne(g_atrHandle,     1, atr1,     true)) return false;
   if(!CopyBufferOne(g_adxHandle,     1, adx1,     true)) return false;

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

bool IsTripleSarBullish(double close1, double sarSlow1, double sarMod1, double sarFast1)
{
   return IsSarBullish(close1, sarSlow1) &&
          IsSarBullish(close1, sarMod1)  &&
          IsSarBullish(close1, sarFast1);
}

bool IsTripleSarBearish(double close1, double sarSlow1, double sarMod1, double sarFast1)
{
   return IsSarBearish(close1, sarSlow1) &&
          IsSarBearish(close1, sarMod1)  &&
          IsSarBearish(close1, sarFast1);
}

bool IsBuyEntrySignal(double close1, double close2,
                      double sarSlow1, double sarSlow2,
                      double sarMod1,  double sarMod2,
                      double sarFast1, double sarFast2)
{
   if(!IsTripleSarBullish(close1, sarSlow1, sarMod1, sarFast1)) return false;
   return IsBuyFlip(close1, close2, sarFast1, sarFast2) ||
          IsBuyFlip(close1, close2, sarMod1, sarMod2)  ||
          IsBuyFlip(close1, close2, sarSlow1, sarSlow2);
}

bool IsSellEntrySignal(double close1, double close2,
                       double sarSlow1, double sarSlow2,
                       double sarMod1,  double sarMod2,
                       double sarFast1, double sarFast2)
{
   if(!IsTripleSarBearish(close1, sarSlow1, sarMod1, sarFast1)) return false;
   return IsSellFlip(close1, close2, sarFast1, sarFast2) ||
          IsSellFlip(close1, close2, sarMod1, sarMod2)  ||
          IsSellFlip(close1, close2, sarSlow1, sarSlow2);
}

string SarSideLabel(double close1, double sar1)
{
   if(IsSarBullish(close1, sar1)) return "Bull";
   if(IsSarBearish(close1, sar1)) return "Bear";
   return "Flat";
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

double CalcLotPerLayer(ENUM_ORDER_TYPE orderType, double entryPrice,
                       double atr1, int layerCount)
{
   if(InpLotMode == LOT_FIXED || layerCount <= 0)
      return NormalizeLot(InpLotPerLayer);

   double sl = 0.0, tp = 0.0, slDist = 0.0, tpDist = 0.0;
   if(!BuildSlTp(orderType, entryPrice, atr1, 1.0, sl, tp, slDist, tpDist))
      return NormalizeLot(InpLotPerLayer);

   double base           = GetRiskBaseAmount();
   double totalRiskMoney = base * InpRiskPercent / 100.0;
   double riskPerLayer   = totalRiskMoney / (double)layerCount;

   double profit = 0.0;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entryPrice, sl, profit))
   {
      Print("OrderCalcProfit gagal, fallback lot tetap. Error: ", GetLastError());
      return NormalizeLot(InpLotPerLayer);
   }

   double lossPerLot = MathAbs(profit);
   if(lossPerLot <= 0.0)
      return NormalizeLot(InpLotPerLayer);

   double lot = NormalizeLot(riskPerLayer / lossPerLot);

   if(InpMaxLotPerLayer > 0.0 && lot > InpMaxLotPerLayer)
      lot = NormalizeLot(InpMaxLotPerLayer);

   return lot;
}

bool OpenLayer(ENUM_ORDER_TYPE orderType, double atr1, int layerIndex,
               double tpSlRatio, double price, double lot)
{
   lot = NormalizeLot(lot);
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
            " lot=", DoubleToString(lot, 2),
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

   double lotPerLayer = CalcLotPerLayer(orderType, price, atr1, layers);
   if(lotPerLayer <= 0.0)
   {
      Print("Lot per layer invalid");
      return 0;
   }

   int opened = 0;
   for(int i = 0; i < layers; i++)
   {
      if(OpenLayer(orderType, atr1, i, ratios[i], price, lotPerLayer))
         opened++;
   }

   Print("Multi entry: ", opened, "/", layers, " layer | lot/layer=", DoubleToString(lotPerLayer, 2),
         " (", LotModeLabel(), ") | SL=ATR x ", DoubleToString(InpAtrSlMult, 1));
   return opened;
}

void ProcessSignals()
{
   double sarSlow1, sarSlow2, sarMod1, sarMod2, sarFast1, sarFast2;
   double emaFast1, emaSlow1, atr1, adx1, close1, close2;
   if(!GetIndicators(sarSlow1, sarSlow2, sarMod1, sarMod2, sarFast1, sarFast2,
                     emaFast1, emaSlow1, atr1, adx1, close1, close2)) return;

   ENUM_BOT_STATE state = GetBotState(adx1);

   if(state != BOT_READY) return;
   if(!IsSpreadOk()) return;
   if(InpOneBatch && CountMyPositions() > 0) return;

   // Filter tren: EMA50 vs EMA200
   bool uptrend   = (emaFast1 > emaSlow1);
   bool downtrend = (emaFast1 < emaSlow1);

   if(uptrend && IsBuyEntrySignal(close1, close2, sarSlow1, sarSlow2, sarMod1, sarMod2, sarFast1, sarFast2) &&
      !HasPosition(POSITION_TYPE_BUY))
      OpenMultiTrades(ORDER_TYPE_BUY, atr1);
   else if(downtrend && IsSellEntrySignal(close1, close2, sarSlow1, sarSlow2, sarMod1, sarMod2, sarFast1, sarFast2) &&
           !HasPosition(POSITION_TYPE_SELL))
      OpenMultiTrades(ORDER_TYPE_SELL, atr1);
}

void UpdateDashboard(double atr1, double emaFast1, double emaSlow1, double adx1,
                     ENUM_BOT_STATE state, double close1,
                     double sarSlow1, double sarMod1, double sarFast1)
{
   double ratios[];
   int    layers  = GetActiveLayerCount(ratios);
   double slDist  = atr1 * InpAtrSlMult;
   bool   uptrend = (emaFast1 > emaSlow1);
   bool   downtrend = (emaFast1 < emaSlow1);
   string trend   = uptrend ? "UP (Buy only)" : downtrend ? "DOWN (Sell only)" : "FLAT";
   color  trendClr = uptrend ? clrDodgerBlue : downtrend ? clrOrangeRed : clrGray;
   string emaLive   = "EMA" + IntegerToString(InpEmaFast) + "=" + DoubleToString(emaFast1, _Digits) +
                      " | EMA" + IntegerToString(InpEmaSlow) + "=" + DoubleToString(emaSlow1, _Digits);

   double previewLot = InpLotPerLayer;
   if(InpLotMode == LOT_RISK_PERCENT && layers > 0)
   {
      double mid = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;
      previewLot = CalcLotPerLayer(ORDER_TYPE_BUY, mid, atr1, layers);
   }

   int x = 10, y = 20, lh = DASH_ROW_H;

   CreateDashboardBackground();

   CreateLabel(PREF + "Title", x, y, "SAR x3 + EMA + ATR + ADX EA", clrBlack, 10);
   y += lh;
   CreateLabel(PREF + "State", x, y, "Bot: " + BotStateText(state), BotStateColor(state), 9);
   y += lh;
   CreateLabel(PREF + "Adx", x, y, "ADX(" + IntegerToString(InpAdxPeriod) + "): " + DoubleToString(adx1, 2), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Ema", x, y, emaLive, clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Trend", x, y, "Filter tren: " + trend, trendClr, 9);
   y += lh;
   CreateLabel(PREF + "SarSlow", x, y,
              "SAR Slow (" + DoubleToString(InpSarSlowStep, 2) + "/" + DoubleToString(InpSarSlowMax, 1) + "): " +
              SarSideLabel(close1, sarSlow1),
              clrDarkSlateGray, 9);
   y += lh;
   CreateLabel(PREF + "SarMod", x, y,
              "SAR Mod (" + DoubleToString(InpSarModStep, 2) + "/" + DoubleToString(InpSarModMax, 1) + "): " +
              SarSideLabel(close1, sarMod1),
              clrDarkSlateGray, 9);
   y += lh;
   CreateLabel(PREF + "SarFast", x, y,
              "SAR Fast (" + DoubleToString(InpSarFastStep, 2) + "/" + DoubleToString(InpSarFastMax, 1) + "): " +
              SarSideLabel(close1, sarFast1),
              clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Atr", x, y, "ATR(" + IntegerToString(InpAtrPeriod) + "): " + DoubleToString(atr1, _Digits), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Sl", x, y,
              "SL: ATR(" + IntegerToString(InpAtrPeriod) + ") x " + DoubleToString(InpAtrSlMult, 1) +
              " = " + DoubleToString(slDist, _Digits),
              clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Tp", x, y, "TP RR: " + TpRatiosSummary(), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Layers", x, y,
              "Layer: " + IntegerToString(layers) + " x " + DoubleToString(previewLot, 2) + " lot (" + LotModeLabel() + ")",
              clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Pos", x, y, "Posisi: " + IntegerToString(CountMyPositions()), clrBlack, 9);

   // Hapus label lama dari versi sebelumnya
   string oldLabels[6] = {"Sar", "SarTrend", "SarTrendSet", "SarTrendVal", "SarEntrySet", "SarEntryVal"};
   for(int i = 0; i < 6; i++)
   {
      string oldName = PREF + oldLabels[i];
      if(ObjectFind(0, oldName) >= 0) ObjectDelete(0, oldName);
   }
}

void CreateDashboardBackground()
{
   string bgName = PREF + "Dash_BG";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }

   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, DASH_BG_X);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, DASH_BG_Y);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, DASH_BG_W);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, DASH_ROWS * DASH_ROW_H + DASH_BG_PAD * 2);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, clrLightGray);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, bgName, OBJPROP_ZORDER, 0);
}

void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
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
   if(InpAtrSlMult <= 0.0 || InpEmaFast <= 0 || InpEmaSlow <= 0 ||
      InpSarSlowStep <= 0.0 || InpSarSlowMax <= 0.0 ||
      InpSarModStep <= 0.0  || InpSarModMax <= 0.0 ||
      InpSarFastStep <= 0.0 || InpSarFastMax <= 0.0)
   {
      Print("Error: parameter EMA dan SAR harus > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpEmaFast >= InpEmaSlow)
   {
      Print("Error: EMA fast harus < EMA slow");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLotMode == LOT_FIXED && InpLotPerLayer <= 0.0)
   {
      Print("Error: lot tetap harus > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLotMode == LOT_RISK_PERCENT && InpRiskPercent <= 0.0)
   {
      Print("Error: risk % harus > 0");
      return INIT_PARAMETERS_INCORRECT;
   }

   double ratios[];
   if(GetActiveLayerCount(ratios) <= 0)
   {
      Print("Error: set minimal 1 InpTpSlRatio layer (> 0)");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_sarSlowHandle = iSAR(_Symbol, _Period, InpSarSlowStep, InpSarSlowMax);
   g_sarModHandle  = iSAR(_Symbol, _Period, InpSarModStep,  InpSarModMax);
   g_sarFastHandle = iSAR(_Symbol, _Period, InpSarFastStep, InpSarFastMax);
   g_emaFastHandle = iMA(_Symbol, _Period, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowHandle = iMA(_Symbol, _Period, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_atrHandle     = iATR(_Symbol, _Period, InpAtrPeriod);
   g_adxHandle     = iADX(_Symbol, _Period, InpAdxPeriod);

   if(g_sarSlowHandle == INVALID_HANDLE || g_sarModHandle == INVALID_HANDLE ||
      g_sarFastHandle == INVALID_HANDLE || g_emaFastHandle == INVALID_HANDLE ||
      g_emaSlowHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE ||
      g_adxHandle == INVALID_HANDLE)
   {
      Print("Gagal buat handle indikator. Error: ", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   g_lastBarTime = iTime(_Symbol, _Period, 0);

   Print("SAR_ATR_ADX_EA v1.20 | EMA", InpEmaFast, "/", InpEmaSlow,
         " | SAR Slow ", InpSarSlowStep, "/", InpSarSlowMax,
         " Mod ", InpSarModStep, "/", InpSarModMax,
         " Fast ", InpSarFastStep, "/", InpSarFastMax,
         " | Lot=", LotModeLabel(),
         " | SL=ATR(", InpAtrPeriod, ")x", InpAtrSlMult,
         " | Layers=", GetActiveLayerCount(ratios), " TP=", TpRatiosSummary(),
         " | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_sarSlowHandle != INVALID_HANDLE) IndicatorRelease(g_sarSlowHandle);
   if(g_sarModHandle  != INVALID_HANDLE) IndicatorRelease(g_sarModHandle);
   if(g_sarFastHandle != INVALID_HANDLE) IndicatorRelease(g_sarFastHandle);
   if(g_emaFastHandle != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
   if(g_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
   if(g_atrHandle     != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle     != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   ObjectsDeleteAll(0, PREF);
}

void OnTick()
{
   double sarSlow1, sarSlow2, sarMod1, sarMod2, sarFast1, sarFast2;
   double emaFast1, emaSlow1, atr1, adx1, close1, close2;
   if(!GetIndicators(sarSlow1, sarSlow2, sarMod1, sarMod2, sarFast1, sarFast2,
                     emaFast1, emaSlow1, atr1, adx1, close1, close2)) return;

   ENUM_BOT_STATE state = GetBotState(adx1);
   UpdateDashboard(atr1, emaFast1, emaSlow1, adx1, state, close1, sarSlow1, sarMod1, sarFast1);

   if(!IsNewBar()) return;

   ProcessSignals();
}
