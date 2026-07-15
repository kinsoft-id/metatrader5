//+------------------------------------------------------------------+
//|                                      Pivot_Breakout_ADX_EA.mq5   |
//|                                  Copyright 2026, User            |
//|  Entry: body breakout pivot | SL: bawah/atas swing terdekat     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, User"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Pivot / struktur
input group "=== Pivot / Struktur ==="
input int                InpPivotPeriod      = 5;           // Periode pivot (kiri/kanan)
input int                InpMaxStructureLabels = 30;        // Max label HH/HL/LL/LH di chart
input bool               InpShowStructure    = true;        // Tampilkan label HH HL LL LH
input int                InpSlLookbackBars   = 50;          // Scan low/high terdekat (bar)
input int                InpSlBufferPoints   = 10;          // Buffer SL bawah low / atas high (pts)

//--- ADX filter sideways
input group "=== ADX Filter ==="
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
input double             InpRiskPercent      = 1.0;         // Risk % total batch (semua layer)
input bool               InpRiskUseEquity    = false;       // Risk dari equity (false=balance)
input double             InpMaxLotPerLayer   = 0.0;         // Max lot per layer (0=tanpa batas)

input group "=== Order ==="
input int                InpMaxSpread        = 50;          // Max spread (pts, 0=off)
input ulong              InpMagic            = 88004;       // Magic Number
input string             InpComment          = "PIVOT_BRK"; // Order comment prefix

input group "=== Lainnya ==="
input bool               InpOneBatch         = true;        // Tunggu semua layer tutup sebelum sinyal baru

//--- Globals
CTrade   trade;
string   PREF = "";
string   STRUCT_PREF = "";

int      g_adxHandle     = INVALID_HANDLE;
datetime g_lastBarTime   = 0;

double   g_lastSwingHigh = 0.0;
double   g_lastSwingLow  = 0.0;
double   g_refPivotHigh  = 0.0;
double   g_refPivotLow   = 0.0;
string   g_lastStructure = "-";

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

enum ENUM_SWING_TYPE
{
   SWING_NONE = 0,
   SWING_HIGH = 1,
   SWING_LOW  = 2
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

bool GetAdx(double shift, double &adx)
{
   return CopyBufferOne(g_adxHandle, (int)shift, adx, true);
}

ENUM_BOT_STATE GetBotState(double adx)
{
   if(adx < InpAdxIdleMax)    return BOT_IDLE_ADX;
   if(adx <= InpAdxEntryMin)  return BOT_WAIT_ADX;
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

bool IsPivotHigh(int shift, int period)
{
   if(shift + period >= iBars(_Symbol, _Period)) return false;
   if(shift - period < 0) return false;

   double pivot = iHigh(_Symbol, _Period, shift);
   for(int i = 1; i <= period; i++)
   {
      if(iHigh(_Symbol, _Period, shift - i) >= pivot) return false;
      if(iHigh(_Symbol, _Period, shift + i) >= pivot) return false;
   }
   return true;
}

bool IsPivotLow(int shift, int period)
{
   if(shift + period >= iBars(_Symbol, _Period)) return false;
   if(shift - period < 0) return false;

   double pivot = iLow(_Symbol, _Period, shift);
   for(int i = 1; i <= period; i++)
   {
      if(iLow(_Symbol, _Period, shift - i) <= pivot) return false;
      if(iLow(_Symbol, _Period, shift + i) <= pivot) return false;
   }
   return true;
}

color StructureColor(string label)
{
   if(label == "HH") return clrDodgerBlue;
   if(label == "HL") return clrMediumSeaGreen;
   if(label == "LL") return clrOrangeRed;
   if(label == "LH") return clrDarkOrange;
   return clrGray;
}

void DrawStructureLabel(string label, datetime barTime, double price, int seq)
{
   if(!InpShowStructure) return;

   string name = STRUCT_PREF + label + "_" + IntegerToString(seq) + "_" + IntegerToString((long)barTime);
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_TEXT, 0, barTime, price);
   ObjectSetString(0, name, OBJPROP_TEXT, "  " + label);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, StructureColor(label));
   bool isHighLabel = (label == "HH" || label == "LH" || label == "H");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isHighLabel ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void TrimStructureLabels()
{
   if(InpMaxStructureLabels <= 0) return;

   string names[];
   int count = 0;
   int total = ObjectsTotal(0, 0, OBJ_TEXT);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, OBJ_TEXT);
      if(StringFind(name, STRUCT_PREF) != 0) continue;
      ArrayResize(names, count + 1);
      names[count++] = name;
   }

   while(count > InpMaxStructureLabels)
   {
      ObjectDelete(0, names[0]);
      for(int j = 0; j < count - 1; j++)
         names[j] = names[j + 1];
      count--;
   }
}

void ScanPivotStructure()
{
   int period = InpPivotPeriod;
   if(period < 1) period = 1;

   int confirmShift = period + 1;
   if(confirmShift + period >= iBars(_Symbol, _Period)) return;

   if(IsPivotHigh(confirmShift, period))
   {
      double price = iHigh(_Symbol, _Period, confirmShift);
      datetime t   = iTime(_Symbol, _Period, confirmShift);
      string label   = "H";
      if(g_lastSwingHigh > 0.0)
         label = (price > g_lastSwingHigh) ? "HH" : "LH";
      g_lastSwingHigh = price;
      g_refPivotHigh  = price;
      g_lastStructure = label;
      DrawStructureLabel(label, t, price, (int)t);
   }

   if(IsPivotLow(confirmShift, period))
   {
      double price = iLow(_Symbol, _Period, confirmShift);
      datetime t   = iTime(_Symbol, _Period, confirmShift);
      string label   = "L";
      if(g_lastSwingLow > 0.0)
         label = (price > g_lastSwingLow) ? "HL" : "LL";
      g_lastSwingLow = price;
      g_refPivotLow  = price;
      g_lastStructure = label;
      DrawStructureLabel(label, t, price, (int)t);
   }

   TrimStructureLabels();
}

void BuildPivotHistory(int maxBars, bool drawLabels)
{
   int period = InpPivotPeriod;
   int bars   = iBars(_Symbol, _Period);
   int oldest = MathMax(period + 1, bars - maxBars);
   int seq    = 0;

   g_lastSwingHigh = 0.0;
   g_lastSwingLow  = 0.0;
   g_refPivotHigh  = 0.0;
   g_refPivotLow   = 0.0;
   g_lastStructure = "-";

   for(int shift = oldest; shift >= period + 1; shift--)
   {
      if(IsPivotHigh(shift, period))
      {
         double price = iHigh(_Symbol, _Period, shift);
         datetime t   = iTime(_Symbol, _Period, shift);
         string label   = "H";
         if(g_lastSwingHigh > 0.0)
            label = (price > g_lastSwingHigh) ? "HH" : "LH";
         g_lastSwingHigh = price;
         g_refPivotHigh  = price;
         g_lastStructure = label;
         seq++;
         if(drawLabels) DrawStructureLabel(label, t, price, seq);
      }

      if(IsPivotLow(shift, period))
      {
         double price = iLow(_Symbol, _Period, shift);
         datetime t   = iTime(_Symbol, _Period, shift);
         string label   = "L";
         if(g_lastSwingLow > 0.0)
            label = (price > g_lastSwingLow) ? "HL" : "LL";
         g_lastSwingLow = price;
         g_refPivotLow  = price;
         g_lastStructure = label;
         seq++;
         if(drawLabels) DrawStructureLabel(label, t, price, seq);
      }
   }
}

double BodyTop(int shift)
{
   return MathMax(iOpen(_Symbol, _Period, shift), iClose(_Symbol, _Period, shift));
}

double BodyBottom(int shift)
{
   return MathMin(iOpen(_Symbol, _Period, shift), iClose(_Symbol, _Period, shift));
}

bool IsBuyBreakout(int shift, double pivotHigh)
{
   if(pivotHigh <= 0.0) return false;
   double bodyTop    = BodyTop(shift);
   double prevBodyTop = BodyTop(shift + 1);
   return (bodyTop > pivotHigh && prevBodyTop <= pivotHigh);
}

bool IsSellBreakout(int shift, double pivotLow)
{
   if(pivotLow <= 0.0) return false;
   double bodyBot     = BodyBottom(shift);
   double prevBodyBot = BodyBottom(shift + 1);
   return (bodyBot < pivotLow && prevBodyBot >= pivotLow);
}

double FindNearestLowBelow(double refPrice, int fromShift, int lookback)
{
   double nearest     = 0.0;
   double smallestGap = DBL_MAX;
   int bars           = iBars(_Symbol, _Period);
   int lastShift      = MathMin(fromShift + lookback, bars - 1);

   for(int shift = fromShift; shift <= lastShift; shift++)
   {
      double candidate = iLow(_Symbol, _Period, shift);
      if(candidate >= refPrice) continue;

      double gap = refPrice - candidate;
      if(gap < smallestGap)
      {
         smallestGap = gap;
         nearest     = candidate;
      }
   }

   return nearest;
}

double FindNearestHighAbove(double refPrice, int fromShift, int lookback)
{
   double nearest     = 0.0;
   double smallestGap = DBL_MAX;
   int bars           = iBars(_Symbol, _Period);
   int lastShift      = MathMin(fromShift + lookback, bars - 1);

   for(int shift = fromShift; shift <= lastShift; shift++)
   {
      double candidate = iHigh(_Symbol, _Period, shift);
      if(candidate <= refPrice) continue;

      double gap = candidate - refPrice;
      if(gap < smallestGap)
      {
         smallestGap = gap;
         nearest     = candidate;
      }
   }

   return nearest;
}

double BuildStopLossPrice(ENUM_ORDER_TYPE orderType, double entryPrice, int signalShift)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double buffer = InpSlBufferPoints * _Point;
   double slRef  = 0.0;

   if(orderType == ORDER_TYPE_BUY)
   {
      slRef = FindNearestLowBelow(entryPrice, signalShift, InpSlLookbackBars);
      if(slRef <= 0.0) slRef = iLow(_Symbol, _Period, signalShift);
      return NormalizeDouble(slRef - buffer, digits);
   }

   slRef = FindNearestHighAbove(entryPrice, signalShift, InpSlLookbackBars);
   if(slRef <= 0.0) slRef = iHigh(_Symbol, _Period, signalShift);
   return NormalizeDouble(slRef + buffer, digits);
}

bool BuildSlTpFromCandle(ENUM_ORDER_TYPE orderType, double entryPrice,
                         double slPrice, double tpSlRatio,
                         double &sl, double &tp,
                         double &slDist, double &tpDist)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   sl = NormalizeDouble(slPrice, digits);
   slDist = MathAbs(entryPrice - sl);
   if(slDist <= 0.0) return false;

   tpDist = slDist * tpSlRatio;
   if(orderType == ORDER_TYPE_BUY)
      tp = NormalizeDouble(entryPrice + tpDist, digits);
   else
      tp = NormalizeDouble(entryPrice - tpDist, digits);

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
                       double slPrice, int layerCount)
{
   if(InpLotMode == LOT_FIXED || layerCount <= 0)
      return NormalizeLot(InpLotPerLayer);

   double sl = 0.0, tp = 0.0, slDist = 0.0, tpDist = 0.0;
   if(!BuildSlTpFromCandle(orderType, entryPrice, slPrice, 1.0, sl, tp, slDist, tpDist))
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

bool OpenLayer(ENUM_ORDER_TYPE orderType, double slPrice, int layerIndex,
               double tpSlRatio, double price, double lot)
{
   lot = NormalizeLot(lot);
   if(lot <= 0.0) return false;

   double sl = 0.0, tp = 0.0, slDist = 0.0, tpDist = 0.0;
   if(!BuildSlTpFromCandle(orderType, price, slPrice, tpSlRatio, sl, tp, slDist, tpDist))
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

int OpenMultiTrades(ENUM_ORDER_TYPE orderType, double slPrice)
{
   double ratios[];
   int layers = GetActiveLayerCount(ratios);
   if(layers <= 0) return 0;

   double price = (orderType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double lotPerLayer = CalcLotPerLayer(orderType, price, slPrice, layers);
   if(lotPerLayer <= 0.0)
   {
      Print("Lot per layer invalid");
      return 0;
   }

   int opened = 0;
   for(int i = 0; i < layers; i++)
   {
      if(OpenLayer(orderType, slPrice, i, ratios[i], price, lotPerLayer))
         opened++;
   }

   Print("Multi entry: ", opened, "/", layers, " layer | lot/layer=", DoubleToString(lotPerLayer, 2),
         " (", LotModeLabel(), ") | SL=",
         (orderType == ORDER_TYPE_BUY ? "bawah low terdekat" : "atas high terdekat"));
   return opened;
}

void ProcessSignals(double adx1)
{
   ENUM_BOT_STATE state = GetBotState(adx1);
   if(state != BOT_READY) return;
   if(!IsSpreadOk()) return;
   if(InpOneBatch && CountMyPositions() > 0) return;

   const int shift = 1;
   double pivotHigh = g_refPivotHigh;
   double pivotLow  = g_refPivotLow;
   double entryBuy  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double entrySell = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(IsBuyBreakout(shift, pivotHigh) && !HasPosition(POSITION_TYPE_BUY))
   {
      double slPrice = BuildStopLossPrice(ORDER_TYPE_BUY, entryBuy, shift);
      OpenMultiTrades(ORDER_TYPE_BUY, slPrice);
   }
   else if(IsSellBreakout(shift, pivotLow) && !HasPosition(POSITION_TYPE_SELL))
   {
      double slPrice = BuildStopLossPrice(ORDER_TYPE_SELL, entrySell, shift);
      OpenMultiTrades(ORDER_TYPE_SELL, slPrice);
   }
}

void UpdateDashboard(double adx1, ENUM_BOT_STATE state)
{
   double ratios[];
   int    layers = GetActiveLayerCount(ratios);

   double previewLot = InpLotPerLayer;
   if(InpLotMode == LOT_RISK_PERCENT && layers > 0)
   {
      double mid = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;
      double dummySl = mid - 100 * _Point;
      previewLot = CalcLotPerLayer(ORDER_TYPE_BUY, mid, dummySl, layers);
   }

   int x = 10, y = 20, lh = DASH_ROW_H;

   CreateDashboardBackground();

   CreateLabel(PREF + "Title", x, y, "Pivot Breakout + ADX EA", clrBlack, 10);
   y += lh;
   CreateLabel(PREF + "State", x, y, "Bot: " + BotStateText(state), BotStateColor(state), 9);
   y += lh;
   CreateLabel(PREF + "Adx", x, y, "ADX(" + IntegerToString(InpAdxPeriod) + "): " + DoubleToString(adx1, 2), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Pivot", x, y,
              "Pivot period: " + IntegerToString(InpPivotPeriod) +
              " | Struktur: " + g_lastStructure,
              clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "RefHigh", x, y,
              "Ref Pivot High: " + (g_refPivotHigh > 0 ? DoubleToString(g_refPivotHigh, _Digits) : "-"),
              clrDodgerBlue, 9);
   y += lh;
   CreateLabel(PREF + "RefLow", x, y,
              "Ref Pivot Low: " + (g_refPivotLow > 0 ? DoubleToString(g_refPivotLow, _Digits) : "-"),
              clrOrangeRed, 9);
   y += lh;
   CreateLabel(PREF + "Entry", x, y,
              "Buy: break High, SL=low terdekat-" + IntegerToString(InpSlBufferPoints) + "pt",
              clrDarkSlateGray, 8);
   y += lh;
   CreateLabel(PREF + "Entry2", x, y,
              "Sell: break Low, SL=high terdekat+" + IntegerToString(InpSlBufferPoints) + "pt",
              clrDarkSlateGray, 8);
   y += lh;
   CreateLabel(PREF + "Tp", x, y, "TP RR: " + TpRatiosSummary(), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Layers", x, y,
              "Layer: " + IntegerToString(layers) + " x " + DoubleToString(previewLot, 2) +
              " lot (" + LotModeLabel() + ")",
              clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Pos", x, y, "Posisi: " + IntegerToString(CountMyPositions()), clrBlack, 9);
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
   PREF        = "PVBRK_" + IntegerToString(InpMagic) + "_";
   STRUCT_PREF = "PVBRK_ST_" + IntegerToString(InpMagic) + "_";

   if(InpAdxIdleMax >= InpAdxEntryMin)
   {
      Print("Error: ADX idle max harus < ADX entry min");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpPivotPeriod < 1)
   {
      Print("Error: pivot period harus >= 1");
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

   g_adxHandle = iADX(_Symbol, _Period, InpAdxPeriod);
   if(g_adxHandle == INVALID_HANDLE)
   {
      Print("Gagal buat handle ADX. Error: ", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   g_lastBarTime = iTime(_Symbol, _Period, 0);

   BuildPivotHistory(500, InpShowStructure);

   Print("Pivot_Breakout_ADX_EA v1.00 | Pivot=", InpPivotPeriod,
         " | ADX ", InpAdxPeriod, " idle<", InpAdxIdleMax, " entry>", InpAdxEntryMin,
         " | Lot=", LotModeLabel(),
         " | Layers=", GetActiveLayerCount(ratios), " TP=", TpRatiosSummary(),
         " | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   ObjectsDeleteAll(0, PREF);
   ObjectsDeleteAll(0, STRUCT_PREF);
}

void OnTick()
{
   double adx1 = 0.0;
   if(!GetAdx(1, adx1)) return;

   ENUM_BOT_STATE state = GetBotState(adx1);
   UpdateDashboard(adx1, state);

   if(!IsNewBar()) return;

   ScanPivotStructure();
   ProcessSignals(adx1);
}
