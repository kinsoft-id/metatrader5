//+------------------------------------------------------------------+
//|                                                  SND_EMA_EA.mq5  |
//|                                  Copyright 2026, User            |
//|  SND EMA — Zona S&D M1 RBR/DBD | Filter MA50/200 | Limit         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, User"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- Zona S&D (M1) — RBR & DBD only
input group "=== Zona S&D (M1) ==="
input double             InpBasingRatio    = 0.63;        // Rasio body/range untuk Base
input int                InpMaxBase        = 13;          // Max candle base berurutan
input int                InpMaxZones       = 5;           // Max zona aktif
input int                InpMaxTouch       = 0;           // Max retest zona (0=Fresh only)
input int                InpScanBars       = 500;         // Bar M1 di-scan
input bool               InpDrawZones      = true;        // Gambar zona di chart
input bool               InpShowMaLines    = true;        // Tampilkan MA50/200 di chart
input bool               InpShowDashboard  = true;        // Tampilkan panel info

//--- Filter Tren MA
input group "=== Filter Tren MA ==="
input int                InpMaFast         = 50;          // MA Fast (EMA)
input int                InpMaSlow         = 200;         // MA Slow (EMA)

//--- SL / Multi TP
input group "=== SL / Multi TP ==="
input double             InpSlBufferPct   = 30.0;        // Buffer SL di luar distal (% lebar zona)
input int                InpMaxEntries     = 5;           // Max layer entry per sinyal
input double             InpTpSlRatio1     = 1.0;         // Layer 1 TP/SL (0=off)
input double             InpTpSlRatio2     = 2.0;         // Layer 2 TP/SL (0=off)
input double             InpTpSlRatio3     = 3.0;         // Layer 3 TP/SL (0=off)
input double             InpTpSlRatio4     = 4.0;         // Layer 4 TP/SL (0=off)
input double             InpTpSlRatio5     = 5.0;         // Layer 5 TP/SL (0=off)

//--- Risk & Order
input group "=== Lot / Risk ==="
input double             InpRiskPercent    = 1.0;         // Risk % total batch (semua layer)
input bool               InpRiskUseEquity  = false;       // Risk dari equity (false=balance)
input double             InpMaxLotPerLayer = 0.0;         // Max lot per layer (0=tanpa batas)

input group "=== Order ==="
input int                InpMaxSpread      = 50;          // Max spread (pts, 0=off)
input int                InpEntrySpreadPts = 0;           // Buffer entry limit (pts, 0=spread live)
input ulong              InpMagic          = 88010;       // Magic Number
input string             InpComment        = "SND_EMA";   // Order comment
input bool               InpOneBatch       = true;        // Tunggu batch selesai sebelum order baru
input int                InpLimitExpiryBars = 60;         // Expired pending order (bar M1, 0=GTC)

//--- Struct zona
struct SDZone
{
   double   baseHigh;
   double   baseLow;
   double   distal;
   double   proximal;
   bool     isDemand;
   string   type;
   int      touchCount;
   datetime formedTime;
   int      barIndex;
};

//--- Globals
CTrade   trade;
string   PREF      = "";
string   ZONE_PREF = "";

int      g_maFastHandle = INVALID_HANDLE;
int      g_maSlowHandle = INVALID_HANDLE;
datetime g_lastBar      = 0;

SDZone   g_zones[];
int      g_zoneCount    = 0;
long     g_chartId      = 0;

const int DASH_BG_X   = 4;
const int DASH_BG_Y   = 10;
const int DASH_BG_W   = 420;
const int DASH_ROW_H  = 18;
const int DASH_ROWS   = 11;
const int DASH_BG_PAD = 8;

//+------------------------------------------------------------------+
//| Chart / visual helpers                                           |
//+------------------------------------------------------------------+
bool IsVisualMode()
{
   if(MQLInfoInteger(MQL_TESTER))
      return (bool)MQLInfoInteger(MQL_VISUAL_MODE);
   return true;
}

void RefreshChart()
{
   if(!IsVisualMode()) return;
   ChartRedraw(g_chartId);
}

bool AttachMaToChart(int handle, color clr)
{
   if(!InpShowMaLines || !IsVisualMode()) return false;
   if(handle == INVALID_HANDLE) return false;
   if(!ChartIndicatorAdd(g_chartId, 0, handle)) return false;
   string shortName = ChartIndicatorName(g_chartId, 0, ChartIndicatorsTotal(g_chartId, 0) - 1);
   if(shortName != "")
      ObjectSetInteger(g_chartId, shortName, OBJPROP_COLOR, clr);
   return true;
}

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

bool IsSpreadOk()
{
   if(InpMaxSpread <= 0) return true;
   return (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpread);
}

double GetEntrySpreadBuffer()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(InpEntrySpreadPts > 0)
      return InpEntrySpreadPts * point;
   return (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * point;
}

double CalcLimitEntry(const SDZone &zone)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double spreadBuf = GetEntrySpreadBuffer();
   if(zone.isDemand)
      return NormalizeDouble(zone.proximal + spreadBuf, digits);
   return NormalizeDouble(zone.proximal - spreadBuf, digits);
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

bool IsNewBar()
{
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBar) return false;
   g_lastBar = barTime;
   return true;
}

bool IsImpulsive(int idx)
{
   double body  = MathAbs(iClose(_Symbol, _Period, idx) - iOpen(_Symbol, _Period, idx));
   double range = MathAbs(iHigh(_Symbol, _Period, idx) - iLow(_Symbol, _Period, idx));
   if(range <= 0.0) return false;
   return (body > (range * InpBasingRatio));
}

bool IsBasing(int idx)
{
   double body  = MathAbs(iClose(_Symbol, _Period, idx) - iOpen(_Symbol, _Period, idx));
   double range = MathAbs(iHigh(_Symbol, _Period, idx) - iLow(_Symbol, _Period, idx));
   if(range <= 0.0) return true;
   return (body <= (range * InpBasingRatio));
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

int CountMyPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagic) continue;
      count++;
   }
   return count;
}

int CountMyBatch()
{
   return CountMyPositions() + CountMyPendingOrders();
}

bool GetMaValues(double &maFast1, double &maSlow1, double &maFast2, double &maSlow2)
{
   if(!CopyBufferOne(g_maFastHandle, 1, maFast1, false)) return false;
   if(!CopyBufferOne(g_maSlowHandle, 1, maSlow1, false)) return false;
   if(!CopyBufferOne(g_maFastHandle, 2, maFast2, false)) return false;
   if(!CopyBufferOne(g_maSlowHandle, 2, maSlow2, false)) return false;
   return (maFast1 != 0.0 && maSlow1 != 0.0);
}

bool IsUptrend(double maFast1, double maSlow1)
{
   return (maFast1 > maSlow1);
}

bool IsDowntrend(double maFast1, double maSlow1)
{
   return (maFast1 < maSlow1);
}

bool IsBullishCross(double maFast1, double maSlow1, double maFast2, double maSlow2)
{
   return (maFast1 > maSlow1 && maFast2 <= maSlow2);
}

bool IsBearishCross(double maFast1, double maSlow1, double maFast2, double maSlow2)
{
   return (maFast1 < maSlow1 && maFast2 >= maSlow2);
}

bool ZoneBetweenMa(const SDZone &zone, double maFast, double maSlow)
{
   double bandLo = MathMin(maFast, maSlow);
   double bandHi = MathMax(maFast, maSlow);
   return (zone.baseLow <= bandHi && zone.baseHigh >= bandLo);
}

bool HasPendingForZone(const SDZone &zone)
{
   string tag = zone.type + "_" + IntegerToString((int)zone.formedTime);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagic) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), tag) >= 0) return true;
   }
   return false;
}

bool BuildSlTpFromZone(ENUM_ORDER_TYPE orderType, double entryPrice,
                       const SDZone &zone, double tpSlRatio,
                       double &sl, double &tp,
                       double &slDist, double &tpDist)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double zoneWidth = zone.baseHigh - zone.baseLow;
   if(zoneWidth <= 0.0) return false;
   double buffer = zoneWidth * InpSlBufferPct / 100.0;

   if(orderType == ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(zone.distal - buffer, digits);
      slDist = entryPrice - sl;
   }
   else
   {
      sl = NormalizeDouble(zone.distal + buffer, digits);
      slDist = sl - entryPrice;
   }

   if(slDist <= 0.0) return false;

   tpDist = slDist * tpSlRatio;
   if(orderType == ORDER_TYPE_BUY)
      tp = NormalizeDouble(entryPrice + tpDist, digits);
   else
      tp = NormalizeDouble(entryPrice - tpDist, digits);

   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist  = stopsLevel * point;
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
                       const SDZone &zone, int layerCount)
{
   if(layerCount <= 0) return 0.0;

   double sl = 0.0, tp = 0.0, slDist = 0.0, tpDist = 0.0;
   if(!BuildSlTpFromZone(orderType, entryPrice, zone, 1.0, sl, tp, slDist, tpDist))
      return 0.0;

   double base           = GetRiskBaseAmount();
   double totalRiskMoney = base * InpRiskPercent / 100.0;
   double riskPerLayer   = totalRiskMoney / (double)layerCount;

   double profit = 0.0;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entryPrice, sl, profit))
   {
      Print("OrderCalcProfit gagal. Error: ", GetLastError());
      return 0.0;
   }

   double lossPerLot = MathAbs(profit);
   if(lossPerLot <= 0.0) return 0.0;

   double lot = NormalizeLot(riskPerLayer / lossPerLot);
   if(InpMaxLotPerLayer > 0.0 && lot > InpMaxLotPerLayer)
      lot = NormalizeLot(InpMaxLotPerLayer);
   return lot;
}

datetime LimitExpiryTime()
{
   if(InpLimitExpiryBars <= 0) return 0;
   return iTime(_Symbol, _Period, 0) + (datetime)(InpLimitExpiryBars * PeriodSeconds(_Period));
}

bool OpenLimitLayer(ENUM_ORDER_TYPE orderType, const SDZone &zone,
                    int layerIndex, double tpSlRatio, double entryPrice, double lot)
{
   lot = NormalizeLot(lot);
   if(lot <= 0.0) return false;

   double sl = 0.0, tp = 0.0, slDist = 0.0, tpDist = 0.0;
   if(!BuildSlTpFromZone(orderType, entryPrice, zone, tpSlRatio, sl, tp, slDist, tpDist))
   {
      Print("Layer ", layerIndex + 1, " SL/TP invalid");
      return false;
   }

   string tag = zone.type + "_" + IntegerToString((int)zone.formedTime);
   string comment = InpComment + "_" + tag + "_L" + IntegerToString(layerIndex + 1);
   datetime expiry = LimitExpiryTime();
   ENUM_ORDER_TYPE_TIME timeType = (expiry > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);

   bool ok = false;
   if(orderType == ORDER_TYPE_BUY)
      ok = trade.BuyLimit(lot, entryPrice, _Symbol, sl, tp, timeType, expiry, comment);
   else
      ok = trade.SellLimit(lot, entryPrice, _Symbol, sl, tp, timeType, expiry, comment);

   if(!ok)
      Print("Limit L", layerIndex + 1, " gagal: ", trade.ResultRetcodeDescription());
   else
      Print("Limit L", layerIndex + 1, " ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " ", zone.type, " lot=", DoubleToString(lot, 2),
            " @ ", DoubleToString(entryPrice, _Digits),
            " SL=", DoubleToString(sl, _Digits),
            " TP=", DoubleToString(tp, _Digits),
            " RR 1:", DoubleToString(tpSlRatio, 1));

   return ok;
}

int PlaceMultiLimits(ENUM_ORDER_TYPE orderType, const SDZone &zone, double entryPrice)
{
   double ratios[];
   int layers = GetActiveLayerCount(ratios);
   if(layers <= 0) return 0;

   double lotPerLayer = CalcLotPerLayer(orderType, entryPrice, zone, layers);
   if(lotPerLayer <= 0.0)
   {
      Print("Lot per layer invalid");
      return 0;
   }

   int placed = 0;
   for(int i = 0; i < layers; i++)
   {
      if(OpenLimitLayer(orderType, zone, i, ratios[i], entryPrice, lotPerLayer))
         placed++;
   }

   Print("Multi limit ", zone.type, ": ", placed, "/", layers,
         " layer | lot/layer=", DoubleToString(lotPerLayer, 2),
         " | risk batch=", DoubleToString(InpRiskPercent, 2), "%");
   return placed;
}

//+------------------------------------------------------------------+
//| Scan zona S&D di M1                                              |
//+------------------------------------------------------------------+
void ClearZoneObjects()
{
   if(!InpDrawZones) return;
   ObjectsDeleteAll(g_chartId, ZONE_PREF);
}

void DrawZone(const SDZone &z, int idx)
{
   if(!InpDrawZones || !IsVisualMode()) return;

   datetime endTime = iTime(_Symbol, _Period, 0) + (datetime)(PeriodSeconds(_Period) * 200);
   string name = ZONE_PREF + z.type + "_" + IntegerToString(idx);

   if(ObjectFind(g_chartId, name) < 0)
   {
      if(!ObjectCreate(g_chartId, name, OBJ_RECTANGLE, 0, z.formedTime, z.baseLow, endTime, z.baseHigh))
      {
         Print("DrawZone gagal: ", name, " err=", GetLastError());
         return;
      }
   }
   else
   {
      ObjectMove(g_chartId, name, 0, z.formedTime, z.baseLow);
      ObjectMove(g_chartId, name, 1, endTime, z.baseHigh);
   }

   color clr = z.isDemand ? clrSkyBlue : clrLightSalmon;
   ObjectSetInteger(g_chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(g_chartId, name, OBJPROP_FILL, true);
   ObjectSetInteger(g_chartId, name, OBJPROP_BACK, false);
   ObjectSetInteger(g_chartId, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chartId, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(g_chartId, name, OBJPROP_ZORDER, 0);

   string lbl = ZONE_PREF + "LBL_" + IntegerToString(idx);
   double lblPrice = z.isDemand ? z.baseLow : z.baseHigh;
   string touchTxt = (z.touchCount == 0) ? "Fresh" : "Tested " + IntegerToString(z.touchCount) + "x";
   if(ObjectFind(g_chartId, lbl) < 0)
   {
      if(!ObjectCreate(g_chartId, lbl, OBJ_TEXT, 0, endTime, lblPrice))
         return;
   }
   else
   {
      ObjectMove(g_chartId, lbl, 0, endTime, lblPrice);
   }
   ObjectSetString(g_chartId, lbl, OBJPROP_TEXT, "  " + z.type + " " + touchTxt);
   ObjectSetString(g_chartId, lbl, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(g_chartId, lbl, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(g_chartId, lbl, OBJPROP_COLOR, z.isDemand ? clrBlue : clrRed);
   ObjectSetInteger(g_chartId, lbl, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chartId, lbl, OBJPROP_HIDDEN, false);
}

void ScanSDZones()
{
   ArrayResize(g_zones, 0);
   g_zoneCount = 0;
   ClearZoneObjects();

   int limit = InpScanBars;
   if(limit < 50) limit = 50;

   for(int i = 1; i < limit && g_zoneCount < InpMaxZones; i++)
   {
      if(!IsImpulsive(i)) continue;

      int baseCount = 0;
      double baseHigh = 0.0;
      double baseLow  = 999999999.0;

      for(int j = i + 1; j < i + 1 + InpMaxBase; j++)
      {
         if(IsBasing(j))
         {
            baseCount++;
            baseHigh = (baseHigh == 0.0) ? iHigh(_Symbol, _Period, j)
                                           : MathMax(baseHigh, iHigh(_Symbol, _Period, j));
            baseLow = MathMin(baseLow, iLow(_Symbol, _Period, j));
         }
         else break;
      }

      if(baseCount < 1) continue;

      int legInIdx = i + 1 + baseCount;
      if(!IsImpulsive(legInIdx)) continue;

      bool legInUp  = (iClose(_Symbol, _Period, legInIdx) > iOpen(_Symbol, _Period, legInIdx));
      bool legOutUp = (iClose(_Symbol, _Period, i) > iOpen(_Symbol, _Period, i));

      string type = "";
      if(legInUp && legOutUp)        type = "RBR";
      else if(!legInUp && !legOutUp) type = "DBD";
      else continue;

      int touchCount = 0;
      bool isBroken = false;

      for(int k = i - 1; k >= 0; k--)
      {
         double candleHigh = iHigh(_Symbol, _Period, k);
         double candleLow  = iLow(_Symbol, _Period, k);

         if(legOutUp)
         {
            if(candleLow < baseLow) { isBroken = true; break; }
            if(candleLow <= baseHigh) touchCount++;
         }
         else
         {
            if(candleHigh > baseHigh) { isBroken = true; break; }
            if(candleHigh >= baseLow) touchCount++;
         }
      }

      if(isBroken) continue;
      if(touchCount > InpMaxTouch) continue;

      SDZone z;
      z.baseHigh    = baseHigh;
      z.baseLow     = baseLow;
      z.isDemand    = legOutUp;
      z.type        = type;
      z.touchCount  = touchCount;
      z.formedTime  = iTime(_Symbol, _Period, i);
      z.barIndex    = i;
      z.distal      = legOutUp ? baseLow : baseHigh;
      z.proximal    = legOutUp ? baseHigh : baseLow;

      int n = g_zoneCount;
      ArrayResize(g_zones, n + 1);
      g_zones[n] = z;
      g_zoneCount = n + 1;

      DrawZone(z, n);
   }

   RefreshChart();
}

//+------------------------------------------------------------------+
//| Entry logic — Buy/Sell Limit                                     |
//+------------------------------------------------------------------+
void ProcessLimits()
{
   if(!IsSpreadOk()) return;
   if(InpOneBatch && CountMyBatch() > 0) return;
   if(g_zoneCount <= 0) return;

   double maFast1, maSlow1, maFast2, maSlow2;
   if(!GetMaValues(maFast1, maSlow1, maFast2, maSlow2)) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int z = 0; z < g_zoneCount; z++)
   {
      SDZone zone = g_zones[z];
      if(HasPendingForZone(zone)) continue;
      if(!ZoneBetweenMa(zone, maFast1, maSlow1)) continue;

      if(zone.isDemand)
      {
         if(!IsUptrend(maFast1, maSlow1)) continue;

         double entry = CalcLimitEntry(zone);
         if(entry >= ask) continue;

         if(PlaceMultiLimits(ORDER_TYPE_BUY, zone, entry) > 0) return;
      }
      else
      {
         if(!IsDowntrend(maFast1, maSlow1)) continue;

         double entry = CalcLimitEntry(zone);
         if(entry <= bid) continue;

         if(PlaceMultiLimits(ORDER_TYPE_SELL, zone, entry) > 0) return;
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void CreateDashboardBackground()
{
   if(!InpShowDashboard || !IsVisualMode()) return;

   string bgName = PREF + "Dash_BG";
   if(ObjectFind(g_chartId, bgName) < 0)
   {
      ObjectCreate(g_chartId, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(g_chartId, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(g_chartId, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(g_chartId, bgName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(g_chartId, bgName, OBJPROP_BACK, false);
      ObjectSetInteger(g_chartId, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }

   ObjectSetInteger(g_chartId, bgName, OBJPROP_XDISTANCE, DASH_BG_X);
   ObjectSetInteger(g_chartId, bgName, OBJPROP_YDISTANCE, DASH_BG_Y);
   ObjectSetInteger(g_chartId, bgName, OBJPROP_XSIZE, DASH_BG_W);
   ObjectSetInteger(g_chartId, bgName, OBJPROP_YSIZE, DASH_ROWS * DASH_ROW_H + DASH_BG_PAD * 2);
   ObjectSetInteger(g_chartId, bgName, OBJPROP_BGCOLOR, clrLightGray);
   ObjectSetInteger(g_chartId, bgName, OBJPROP_COLOR, clrGray);
   ObjectSetInteger(g_chartId, bgName, OBJPROP_ZORDER, 100);
}

void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(!InpShowDashboard || !IsVisualMode()) return;

   if(ObjectFind(g_chartId, name) < 0)
   {
      ObjectCreate(g_chartId, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(g_chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(g_chartId, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(g_chartId, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(g_chartId, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(g_chartId, name, OBJPROP_HIDDEN, false);
   }
   ObjectSetInteger(g_chartId, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(g_chartId, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(g_chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(g_chartId, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(g_chartId, name, OBJPROP_ZORDER, 101);
   ObjectSetString(g_chartId, name, OBJPROP_TEXT, text);
}

string ZoneSummary()
{
   if(g_zoneCount <= 0) return "Tidak ada zona aktif";

   int demand = 0, supply = 0;
   for(int i = 0; i < g_zoneCount; i++)
   {
      if(g_zones[i].isDemand) demand++;
      else supply++;
   }
   return IntegerToString(g_zoneCount) + " zona (D:" + IntegerToString(demand) +
          " S:" + IntegerToString(supply) + ")";
}

string TrendLabel(double maFast1, double maSlow1, double maFast2, double maSlow2)
{
   if(IsBullishCross(maFast1, maSlow1, maFast2, maSlow2)) return "BULL CROSS";
   if(IsBearishCross(maFast1, maSlow1, maFast2, maSlow2)) return "BEAR CROSS";
   if(IsUptrend(maFast1, maSlow1))   return "UP (MA50>MA200)";
   if(IsDowntrend(maFast1, maSlow1)) return "DOWN (MA50<MA200)";
   return "FLAT";
}

color TrendColor(double maFast1, double maSlow1)
{
   if(IsUptrend(maFast1, maSlow1))   return clrDodgerBlue;
   if(IsDowntrend(maFast1, maSlow1)) return clrOrangeRed;
   return clrGray;
}

void UpdateDashboard(double maFast1, double maSlow1, double maFast2, double maSlow2)
{
   if(!InpShowDashboard || !IsVisualMode()) return;

   int x = 10, y = 20, lh = DASH_ROW_H;
   CreateDashboardBackground();

   double ratios[];
   int layers = GetActiveLayerCount(ratios);
   double previewLot = 0.0;
   if(g_zoneCount > 0 && layers > 0)
   {
      double entry = CalcLimitEntry(g_zones[0]);
      previewLot = CalcLotPerLayer(g_zones[0].isDemand ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                   entry, g_zones[0], layers);
   }

   CreateLabel(PREF + "Title", x, y, "SND EMA", clrBlack, 10);
   y += lh;
   CreateLabel(PREF + "Zones", x, y, "Zona M1: " + ZoneSummary(), clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Ma", x, y,
              "MA" + IntegerToString(InpMaFast) + "=" + DoubleToString(maFast1, _Digits) +
              " | MA" + IntegerToString(InpMaSlow) + "=" + DoubleToString(maSlow1, _Digits),
              clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Trend", x, y, "Trend: " + TrendLabel(maFast1, maSlow1, maFast2, maSlow2),
              TrendColor(maFast1, maSlow1), 9);
   y += lh;
   CreateLabel(PREF + "Risk", x, y,
              "Lot auto: " + DoubleToString(InpRiskPercent, 2) + "% / batch",
              clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "SlTp", x, y,
              "SL: distal + " + DoubleToString(InpSlBufferPct, 0) + "% lebar zona | TP: " + TpRatiosSummary(),
              clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Layers", x, y,
              "Layer: " + IntegerToString(layers) + " x " + DoubleToString(previewLot, 2) + " lot",
              clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Batch", x, y,
              "Pos: " + IntegerToString(CountMyPositions()) +
              " | Pending: " + IntegerToString(CountMyPendingOrders()),
              clrBlack, 9);
   y += lh;
   CreateLabel(PREF + "Rule", x, y,
              "Entry: proximal +/- spread buf | Buy RBR / Sell DBD",
              clrDarkSlateGray, 8);

   RefreshChart();
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   g_chartId = ChartID();
   PREF      = "SNDEMA_" + IntegerToString(InpMagic) + "_";
   ZONE_PREF = "SNDEMA_Z_" + IntegerToString(InpMagic) + "_";

   if(_Period != PERIOD_M1)
      Print("Peringatan: EA dirancang untuk chart M1.");

   if(InpRiskPercent <= 0.0 || InpMaFast <= 0 || InpMaSlow <= 0 || InpSlBufferPct < 0.0)
   {
      Print("Error: parameter risk atau MA harus > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMaFast >= InpMaSlow)
   {
      Print("Error: MA fast harus < MA slow");
      return INIT_PARAMETERS_INCORRECT;
   }

   double ratios[];
   if(GetActiveLayerCount(ratios) <= 0)
   {
      Print("Error: set minimal 1 InpTpSlRatio layer (> 0)");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_maFastHandle = iMA(_Symbol, _Period, InpMaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_maSlowHandle = iMA(_Symbol, _Period, InpMaSlow, 0, MODE_EMA, PRICE_CLOSE);
   if(g_maFastHandle == INVALID_HANDLE || g_maSlowHandle == INVALID_HANDLE)
   {
      Print("Gagal buat handle MA. Error: ", GetLastError());
      return INIT_FAILED;
   }

   AttachMaToChart(g_maFastHandle, clrDodgerBlue);
   AttachMaToChart(g_maSlowHandle, clrOrangeRed);

   trade.SetExpertMagicNumber(InpMagic);
   g_lastBar = iTime(_Symbol, _Period, 0);

   ScanSDZones();
   RefreshChart();

   Print("SND EMA v2.00 | M1 RBR/DBD | MA", InpMaFast, "/", InpMaSlow,
         " | Limit entry | Risk=", InpRiskPercent, "% | Layers=",
         GetActiveLayerCount(ratios), " TP=", TpRatiosSummary(),
         " | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_maFastHandle != INVALID_HANDLE) IndicatorRelease(g_maFastHandle);
   if(g_maSlowHandle != INVALID_HANDLE) IndicatorRelease(g_maSlowHandle);
   ObjectsDeleteAll(g_chartId, PREF);
   ObjectsDeleteAll(g_chartId, ZONE_PREF);
}

void OnTick()
{
   bool newBar = IsNewBar();

   if(newBar)
      ScanSDZones();

   double maFast1, maSlow1, maFast2, maSlow2;
   bool maOk = GetMaValues(maFast1, maSlow1, maFast2, maSlow2);

   if(maOk)
   {
      UpdateDashboard(maFast1, maSlow1, maFast2, maSlow2);
      if(newBar)
         ProcessLimits();
   }
   else if(InpShowDashboard && IsVisualMode())
   {
      CreateLabel(PREF + "Title", 10, 20, "SND EMA — tunggu MA siap...", clrGray, 10);
      RefreshChart();
   }
}
