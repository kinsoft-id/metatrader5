#property copyright "ZigZag Segment"
#property version   "1.13"
#property indicator_chart_window
#property indicator_plots 0

input group "ZigZag"
input color InpLineColor = clrDimGray;
input int   InpLineWidth = 1;
input int   InpMaxPivots = 30;          // Max swing tersimpan

input group "Segment Box"
input color InpBullColor = C'144,238,144'; // Hijau: low → high
input color InpBearColor = C'255,182,193'; // Merah: high → low
input bool  InpShowActive = true;         // Tampilkan segmen ekstrem aktif

input group "Fibonacci"
input bool  InpShowSegmentFibo = false; // Fibo per segmen (off jika pakai EA Fibo)
input color InpFiboColor = clrSilver;
input int   InpFiboWidth = 1;
input bool  InpFiboShowLabels = false; // Show label level
input bool  InpFibo236   = true;   // Show 23.6
input bool  InpFibo382   = true;   // Show 38.2
input bool  InpFibo50    = true;   // Show 50.0
input bool  InpFibo618   = true;   // Show 61.8
input bool  InpFibo786   = true;   // Show 78.6
input bool  InpFibo886   = true;   // Show 88.6

enum ENUM_HL_TF
{
   HL_TF_H1 = 0, // H1
   HL_TF_H4 = 1, // H4
   HL_TF_D1 = 2  // Daily
};

enum ENUM_H1_LINE_END
{
   H1_END_RAY_RIGHT = 0, // Sampai ke kanan
   H1_END_H1_CLOSE  = 1  // Sampai close TF
};

input group "Previous High/Low"
input bool             InpShowH1HL    = true;          // Tampilkan previous high/low
input ENUM_HL_TF       InpHLTimeframe = HL_TF_H1;      // Timeframe
input int              InpH1MaxShow   = 3;             // Max show
input ENUM_H1_LINE_END InpH1LineEnd   = H1_END_H1_CLOSE; // Ujung garis
input color            InpH1BullColor = clrForestGreen;
input color            InpH1BearColor = clrCrimson;
input int              InpH1LineWidth = 1;
input ENUM_LINE_STYLE  InpH1LineStyle = STYLE_DASH;
input int              InpH1FontSize  = 8;

#define PREFIX "ZZSEG_"

ENUM_TIMEFRAMES HLTimeframe()
{
   int v = (int)InpHLTimeframe;
   if(v == 1 || v == (int)PERIOD_H4)
      return PERIOD_H4;
   if(v == 2 || v == (int)PERIOD_D1)
      return PERIOD_D1;
   return PERIOD_H1;
}

string HLTagFromTf(const ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_H4)
      return "H4";
   if(tf == PERIOD_D1)
      return "D1";
   return "H1";
}

struct PivotPoint
{
   datetime time;
   double   price;
   bool     isHigh;
};

PivotPoint g_pivots[];
int        g_count = 0;
PivotPoint g_active;
bool       g_hasActive = false;
bool       g_hasActiveLine = false;
datetime   g_lastBarTime = 0;
datetime   g_lastH1BarTime = 0;
int        g_h1Shown = 0;
ENUM_TIMEFRAMES g_hlTf = PERIOD_H1;

string HLObjName(const string kind, const int i)
{
   return PREFIX + "HL_" + HLTagFromTf(g_hlTf) + "_" + kind + "_" + IntegerToString(i);
}

void ClearLegacyHLObjects()
{
   for(int i = 0; i < 64; i++)
   {
      string idx = IntegerToString(i);
      ObjectDelete(0, PREFIX + "H1H_" + idx);
      ObjectDelete(0, PREFIX + "H1L_" + idx);
      ObjectDelete(0, PREFIX + "H1HT_" + idx);
      ObjectDelete(0, PREFIX + "H1LT_" + idx);
   }
}

void ClearAllHLObjects()
{
   ObjectsDeleteAll(0, PREFIX + "HL_");
   ClearLegacyHLObjects();
   g_h1Shown = 0;
}

int OnInit()
{
   g_hlTf = HLTimeframe();
   g_lastH1BarTime = 0;
   g_h1Shown = 0;
   ObjectsDeleteAll(0, PREFIX);
   IndicatorSetString(INDICATOR_SHORTNAME, "ZigZag Segment (" + HLTagFromTf(g_hlTf) + ")");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
   ArrayResize(g_pivots, 0);
   g_count = 0;
   g_hasActive = false;
   g_hasActiveLine = false;
   g_lastBarTime = 0;
   g_lastH1BarTime = 0;
   g_h1Shown = 0;
}

bool BodyBreakUp(const double closePrice, const double level)   { return closePrice > level; }
bool BodyBreakDown(const double closePrice, const double level) { return closePrice < level; }

bool SamePivot(const PivotPoint &a, const PivotPoint &b)
{
   return (a.time == b.time && a.price == b.price && a.isHigh == b.isHigh);
}

void PushPivot(PivotPoint &pivots[], int &count, const int maxKeep,
               const datetime t, const double price, const bool isHigh)
{
   if(count < maxKeep)
   {
      ArrayResize(pivots, count + 1);
      pivots[count].time   = t;
      pivots[count].price  = price;
      pivots[count].isHigh = isHigh;
      count++;
      return;
   }

   for(int i = 0; i < maxKeep - 1; i++)
      pivots[i] = pivots[i + 1];

   pivots[maxKeep - 1].time   = t;
   pivots[maxKeep - 1].price  = price;
   pivots[maxKeep - 1].isHigh = isHigh;
}

void StartOppositeExtreme(const int pivotIdx,
                          const int upToIdx,
                          const bool nextIsHigh,
                          const double &high[],
                          const double &low[],
                          int &extreme,
                          bool &hasExtreme,
                          bool &lookingForHigh,
                          int &pendingA)
{
   lookingForHigh = nextIsHigh;
   hasExtreme = false;
   pendingA = -1;

   int start = pivotIdx + 1;
   if(start > upToIdx)
      return;

   extreme = start;
   for(int j = start + 1; j <= upToIdx; j++)
   {
      if(nextIsHigh)
      {
         if(high[j] > high[extreme])
            extreme = j;
      }
      else
      {
         if(low[j] < low[extreme])
            extreme = j;
      }
   }
   hasExtreme = true;
}

void BuildPivots(const int rates_total,
                 const datetime &time[],
                 const double &high[],
                 const double &low[],
                 const double &close[],
                 const int maxKeep,
                 PivotPoint &pivots[],
                 int &count,
                 PivotPoint &active,
                 bool &hasActive,
                 bool &hasActiveLine)
{
   count = 0;
   hasActive = false;
   hasActiveLine = false;
   ArrayResize(pivots, 0);
   if(rates_total < 4)
      return;

   const int lastClosed = rates_total - 2;

   bool lookingForHigh = true;
   int  extreme = 0;
   bool hasExtreme = false;
   int  pendingA = -1;

   for(int i = 0; i <= lastClosed; i++)
   {
      if(!hasExtreme)
      {
         extreme = i;
         hasExtreme = true;
         pendingA = -1;
         continue;
      }

      if(lookingForHigh)
      {
         if(high[i] > high[extreme])
         {
            extreme = i;
            pendingA = -1;
            continue;
         }

         if(i <= extreme)
            continue;

         if(pendingA < 0)
         {
            if(BodyBreakDown(close[i], low[extreme]))
               pendingA = i;
            continue;
         }

         if(i <= pendingA)
            continue;

         if(BodyBreakDown(close[i], close[pendingA]))
         {
            int pivotIdx = extreme;
            PushPivot(pivots, count, maxKeep, time[pivotIdx], high[pivotIdx], true);
            StartOppositeExtreme(pivotIdx, i, false, high, low, extreme, hasExtreme, lookingForHigh, pendingA);
         }
      }
      else
      {
         if(low[i] < low[extreme])
         {
            extreme = i;
            pendingA = -1;
            continue;
         }

         if(i <= extreme)
            continue;

         if(pendingA < 0)
         {
            if(BodyBreakUp(close[i], high[extreme]))
               pendingA = i;
            continue;
         }

         if(i <= pendingA)
            continue;

         if(BodyBreakUp(close[i], close[pendingA]))
         {
            int pivotIdx = extreme;
            PushPivot(pivots, count, maxKeep, time[pivotIdx], low[pivotIdx], false);
            StartOppositeExtreme(pivotIdx, i, true, high, low, extreme, hasExtreme, lookingForHigh, pendingA);
         }
      }
   }

   if(hasExtreme && count > 0)
   {
      active.time   = time[extreme];
      active.price  = lookingForHigh ? high[extreme] : low[extreme];
      active.isHigh = lookingForHigh;
      if(active.time > pivots[count - 1].time)
         hasActive = true;
   }

   if(!hasActive || count < 2)
      return;

   const PivotPoint nearest  = pivots[count - 1];
   const PivotPoint opposite = pivots[count - 2];

   if(nearest.time >= active.time)
      return;
   if(nearest.isHigh == opposite.isHigh)
      return;

   if(!nearest.isHigh)
   {
      if(active.isHigh && opposite.isHigh && BodyBreakUp(close[lastClosed], opposite.price))
         hasActiveLine = true;
   }
   else
   {
      if(!active.isHigh && !opposite.isHigh && BodyBreakDown(close[lastClosed], opposite.price))
         hasActiveLine = true;
   }
}

void EnsureLine(const string name, const PivotPoint &from, const PivotPoint &to)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, from.time, from.price, to.time, to.price);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, InpLineWidth);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   }
   else
   {
      ObjectMove(0, name, 0, from.time, from.price);
      ObjectMove(0, name, 1, to.time, to.price);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpLineColor);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

void ApplyFiboLevel(const string name, const int idx, const double value, const string text)
{
   ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, idx, value);
   ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, idx, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, idx, InpFiboWidth);
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, idx, InpFiboColor);
   ObjectSetString(0, name, OBJPROP_LEVELTEXT, idx, InpFiboShowLabels ? text : " ");
}

int FiboVisibleCount()
{
   int n = 0;
   if(InpFibo236) n++;
   if(InpFibo382) n++;
   if(InpFibo50)  n++;
   if(InpFibo618) n++;
   if(InpFibo786) n++;
   if(InpFibo886) n++;
   return n;
}

void EnsureFibo(const string name, const PivotPoint &from, const PivotPoint &to)
{
   if(!InpShowSegmentFibo)
   {
      ObjectDelete(0, name);
      return;
   }

   int n = FiboVisibleCount();
   if(n <= 0)
   {
      ObjectDelete(0, name);
      return;
   }

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_FIBO, 0, from.time, from.price, to.time, to.price);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   }
   else
   {
      ObjectMove(0, name, 0, from.time, from.price);
      ObjectMove(0, name, 1, to.time, to.price);
   }

   ObjectSetInteger(0, name, OBJPROP_FILL, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrNONE);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 0);
   ObjectSetInteger(0, name, OBJPROP_LEVELS, n);

   int idx = 0;
   if(InpFibo236) ApplyFiboLevel(name, idx++, 0.236, "23.6");
   if(InpFibo382) ApplyFiboLevel(name, idx++, 0.382, "38.2");
   if(InpFibo50)  ApplyFiboLevel(name, idx++, 0.500, "50.0");
   if(InpFibo618) ApplyFiboLevel(name, idx++, 0.618, "61.8");
   if(InpFibo786) ApplyFiboLevel(name, idx++, 0.786, "78.6");
   if(InpFibo886) ApplyFiboLevel(name, idx++, 0.886, "88.6");
}

void EnsureBox(const string name, const PivotPoint &from, const PivotPoint &to)
{
   // Kotak tanpa fill: hanya bingkai hijau/merah (fill hitam menelan klik).
   double top = MathMax(from.price, to.price);
   double bot = MathMin(from.price, to.price);
   color  col = to.isHigh ? InpBullColor : InpBearColor;
   if(from.isHigh && !to.isHigh)
      col = InpBearColor;
   else if(!from.isHigh && to.isHigh)
      col = InpBullColor;

   datetime t1 = from.time;
   datetime t2 = to.time;
   if(t2 < t1)
   {
      datetime tmp = t1;
      t1 = t2;
      t2 = tmp;
   }

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bot);

   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, top);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, bot);
   ObjectSetInteger(0, name, OBJPROP_FILL, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, col);
}

void ClearSegmentObjects(const int keepCount)
{
   for(int i = keepCount; i < InpMaxPivots + 2; i++)
   {
      ObjectDelete(0, PREFIX + "LN_" + IntegerToString(i));
      ObjectDelete(0, PREFIX + "BX_" + IntegerToString(i));
      ObjectDelete(0, PREFIX + "FB_" + IntegerToString(i));
   }
}

void UpdateObjects(const PivotPoint &pivots[], const int count,
                   const PivotPoint &active, const bool hasActive, const bool hasActiveLine)
{
   int seg = 0;

   for(int k = 1; k < count; k++)
   {
      EnsureLine(PREFIX + "LN_" + IntegerToString(seg), pivots[k - 1], pivots[k]);
      EnsureBox(PREFIX + "BX_" + IntegerToString(seg), pivots[k - 1], pivots[k]);
      ObjectDelete(0, PREFIX + "FB_" + IntegerToString(seg));
      seg++;
   }

   // Segmen ekstrem aktif (setelah break swing lawan)
   if(InpShowActive && hasActive && hasActiveLine && count > 0)
   {
      EnsureLine(PREFIX + "LN_" + IntegerToString(seg), pivots[count - 1], active);
      EnsureBox(PREFIX + "BX_" + IntegerToString(seg), pivots[count - 1], active);
      ObjectDelete(0, PREFIX + "FB_" + IntegerToString(seg));
      seg++;
   }

   ClearSegmentObjects(seg);
}

bool StateChanged(const PivotPoint &pivots[], const int count,
                  const PivotPoint &active, const bool hasActive, const bool hasActiveLine)
{
   if(count != g_count || hasActive != g_hasActive || hasActiveLine != g_hasActiveLine)
      return true;

   for(int i = 0; i < count; i++)
   {
      if(!SamePivot(pivots[i], g_pivots[i]))
         return true;
   }

   if(hasActive && !SamePivot(active, g_active))
      return true;

   return false;
}

void EnsureHRay(const string name, const datetime t, const double price, const color col)
{
   datetime t2 = t + PeriodSeconds(g_hlTf);
   bool rayRight = (InpH1LineEnd == H1_END_RAY_RIGHT);
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t, price, t2, price);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   else
   {
      ObjectMove(0, name, 0, t, price);
      ObjectMove(0, name, 1, t2, price);
   }
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpH1LineWidth);
   ObjectSetInteger(0, name, OBJPROP_STYLE, InpH1LineStyle);
}

void EnsureHText(const string name, const datetime t, const double price,
                 const string text, const color col, const ENUM_ANCHOR_POINT anchor)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpH1FontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   }
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetString(0, name, OBJPROP_TEXT, " " + text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
}

void ClearH1Objects(const int keepCount)
{
   int lim = MathMax(g_h1Shown, keepCount);
   for(int i = keepCount; i < lim; i++)
   {
      ObjectDelete(0, HLObjName("H", i));
      ObjectDelete(0, HLObjName("L", i));
      ObjectDelete(0, HLObjName("HT", i));
      ObjectDelete(0, HLObjName("LT", i));
   }
   g_h1Shown = keepCount;
}

bool UpdateH1Levels()
{
   if(!InpShowH1HL)
   {
      ClearAllHLObjects();
      return true;
   }

   int maxShow = MathMax(0, InpH1MaxShow);
   if(maxShow <= 0)
   {
      ClearAllHLObjects();
      return true;
   }

   ENUM_TIMEFRAMES tf = g_hlTf;
   if(!SeriesInfoInteger(_Symbol, tf, SERIES_SYNCHRONIZED))
   {
      datetime wait[];
      CopyTime(_Symbol, tf, 0, 1, wait);
      return false;
   }

   MqlRates htf[];
   ArraySetAsSeries(htf, true);
   int copied = CopyRates(_Symbol, tf, 1, maxShow, htf);
   if(copied <= 0)
      return false;

   datetime expect = iTime(_Symbol, tf, 1);
   if(expect == 0 || htf[0].time != expect)
      return false;

   if(tf != PERIOD_H1)
   {
      datetime tH1 = iTime(_Symbol, PERIOD_H1, 1);
      if(tH1 != 0 && htf[0].time == tH1)
         return false;
   }

   ClearLegacyHLObjects();

   int shown = 0;
   for(int i = 0; i < copied; i++)
   {
      bool isBull = (htf[i].close >= htf[i].open);
      color col = isBull ? InpH1BullColor : InpH1BearColor;
      datetime t = htf[i].time;

      string highLabel = isBull ? "Bullish" : "Strong High";
      string lowLabel  = isBull ? "Strong Low" : "Bearish";

      EnsureHRay(HLObjName("H", i), t, htf[i].high, col);
      EnsureHRay(HLObjName("L", i), t, htf[i].low, col);
      EnsureHText(HLObjName("HT", i), t, htf[i].high, highLabel, col, ANCHOR_LEFT_LOWER);
      EnsureHText(HLObjName("LT", i), t, htf[i].low, lowLabel, col, ANCHOR_LEFT_UPPER);
      shown++;
   }

   ClearH1Objects(shown);
   return true;
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 4)
      return 0;

   if(prev_calculated == 0)
      ObjectsDeleteAll(0, PREFIX + "FB_");

   datetime curBar = time[rates_total - 1];
   datetime htfBar = iTime(_Symbol, g_hlTf, 0);
   bool needCalc = (prev_calculated == 0 || curBar != g_lastBarTime || rates_total != prev_calculated);
   bool needH1 = (prev_calculated == 0 || htfBar == 0 || htfBar != g_lastH1BarTime);

   if(!needCalc && !needH1)
      return rates_total;

   if(needH1)
   {
      if(UpdateH1Levels() && htfBar != 0)
         g_lastH1BarTime = htfBar;
   }

   if(!needCalc)
      return rates_total;

   g_lastBarTime = curBar;

   int maxKeep = MathMax(4, InpMaxPivots);
   PivotPoint pivots[];
   int count = 0;
   PivotPoint active;
   bool hasActive = false;
   bool hasActiveLine = false;

   BuildPivots(rates_total, time, high, low, close, maxKeep,
               pivots, count, active, hasActive, hasActiveLine);

   if(!StateChanged(pivots, count, active, hasActive, hasActiveLine))
      return rates_total;

   ArrayResize(g_pivots, count);
   for(int i = 0; i < count; i++)
      g_pivots[i] = pivots[i];
   g_count = count;
   g_active = active;
   g_hasActive = hasActive;
   g_hasActiveLine = hasActiveLine;

   UpdateObjects(pivots, count, active, hasActive, hasActiveLine);
   return rates_total;
}
