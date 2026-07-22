#property copyright "ZigZag Segment"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

input group "ZigZag"
input color InpLineColor = clrBlack;
input int   InpLineWidth = 2;
input int   InpMaxPivots = 30;          // Max swing tersimpan

input group "Segment Box"
input color InpBullColor = C'144,238,144'; // Hijau: low → high
input color InpBearColor = C'255,182,193'; // Merah: high → low
input bool  InpShowActive = true;         // Tampilkan segmen ekstrem aktif

input group "Fibonacci"
input color InpFiboColor = clrBlack;
input int   InpFiboWidth = 1;

#define PREFIX "ZZSEG_"

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

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
   ArrayResize(g_pivots, 0);
   g_count = 0;
   g_hasActive = false;
   g_hasActiveLine = false;
   g_lastBarTime = 0;
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
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   else
   {
      ObjectMove(0, name, 0, from.time, from.price);
      ObjectMove(0, name, 1, to.time, to.price);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpLineColor);
}

void EnsureFibo(const string name, const PivotPoint &from, const PivotPoint &to)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_FIBO, 0, from.time, from.price, to.time, to.price);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, InpFiboWidth);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_LEVELS, 2);

      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 0, 0.382);
      ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 0, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 0, InpFiboWidth);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, 0, "38.2");

      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 1, 0.618);
      ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 1, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 1, InpFiboWidth);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, 1, "61.8");
   }
   else
   {
      ObjectMove(0, name, 0, from.time, from.price);
      ObjectMove(0, name, 1, to.time, to.price);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, InpFiboColor);
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 0, InpFiboColor);
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 1, InpFiboColor);
}

void EnsureBox(const string name, const PivotPoint &from, const PivotPoint &to)
{
   // Box: (timeFrom, highPrice) → (timeTo, lowPrice)
   double top = MathMax(from.price, to.price);
   double bot = MathMin(from.price, to.price);
   color  col = to.isHigh ? InpBullColor : InpBearColor; // naik=hijau, turun=merah
   // Jika from high → to low = bearish merah; from low → to high = bullish hijau
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
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bot);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, top);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, bot);
   }
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
      EnsureFibo(PREFIX + "FB_" + IntegerToString(seg), pivots[k - 1], pivots[k]);
      seg++;
   }

   // Segmen ekstrem aktif (setelah break swing lawan)
   if(InpShowActive && hasActive && hasActiveLine && count > 0)
   {
      EnsureLine(PREFIX + "LN_" + IntegerToString(seg), pivots[count - 1], active);
      EnsureBox(PREFIX + "BX_" + IntegerToString(seg), pivots[count - 1], active);
      EnsureFibo(PREFIX + "FB_" + IntegerToString(seg), pivots[count - 1], active);
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

   datetime curBar = time[rates_total - 1];
   bool needCalc = (prev_calculated == 0 || curBar != g_lastBarTime || rates_total != prev_calculated);
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
