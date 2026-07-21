#property copyright "3 Pivot"
#property version   "1.93"
#property indicator_chart_window
#property indicator_plots 0

input group "Display"
input color InpHighColor = clrDodgerBlue;
input color InpLowColor  = clrOrangeRed;
input color InpLineColor = clrBlack;
input int   InpPointSize = 1;
input int   InpLineWidth = 1;

input group "Fibonacci (garis pivot ke-2, ke-3 & aktif)"
input color InpFiboColor = clrBlack;
input int   InpFiboWidth = 1;

#define PREFIX "3P_"
#define MAX_PIVOTS 4

struct PivotPoint
{
   datetime time;
   double   price;
   bool     isHigh;
};

PivotPoint g_last[MAX_PIVOTS];
int        g_lastCount = 0;
PivotPoint g_active;
bool       g_hasActive = false;
bool       g_hasActiveLine = false;
datetime   g_lastBarTime = 0;

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
   g_lastCount = 0;
   g_hasActive = false;
   g_hasActiveLine = false;
   g_lastBarTime = 0;
}

void PushPivot(PivotPoint &pivots[], int &count, const datetime t, const double price, const bool isHigh)
{
   if(count < MAX_PIVOTS)
   {
      pivots[count].time   = t;
      pivots[count].price  = price;
      pivots[count].isHigh = isHigh;
      count++;
      return;
   }

   for(int i = 0; i < MAX_PIVOTS - 1; i++)
      pivots[i] = pivots[i + 1];

   pivots[MAX_PIVOTS - 1].time   = t;
   pivots[MAX_PIVOTS - 1].price  = price;
   pivots[MAX_PIVOTS - 1].isHigh = isHigh;
}

bool SamePivot(const PivotPoint &a, const PivotPoint &b)
{
   return (a.time == b.time && a.price == b.price && a.isHigh == b.isHigh);
}

bool PivotsChanged(const PivotPoint &a[], const int aCount, const PivotPoint &b[], const int bCount)
{
   if(aCount != bCount)
      return true;

   for(int i = 0; i < aCount; i++)
   {
      if(!SamePivot(a[i], b[i]))
         return true;
   }
   return false;
}

void EnsurePoint(const string name, const PivotPoint &p)
{
   ENUM_ARROW_ANCHOR anchor = p.isHigh ? ANCHOR_BOTTOM : ANCHOR_TOP;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_ARROW, 0, p.time, p.price);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, InpPointSize);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }

   ObjectMove(0, name, 0, p.time, p.price);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, p.isHigh ? InpHighColor : InpLowColor);
}

void EnsurePoint(const int index, const PivotPoint &p)
{
   EnsurePoint(PREFIX + "PT_" + IntegerToString(index), p);
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
   }
   else
   {
      ObjectMove(0, name, 0, from.time, from.price);
      ObjectMove(0, name, 1, to.time, to.price);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, InpLineColor);
}

void EnsureLine(const int index, const PivotPoint &from, const PivotPoint &to)
{
   EnsureLine(PREFIX + "LN_" + IntegerToString(index), from, to);
}

void EnsureFiboOnLine(const string name, const PivotPoint &from, const PivotPoint &to)
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

void EnsureFiboOnLine(const int lineNo, const PivotPoint &from, const PivotPoint &to)
{
   EnsureFiboOnLine(PREFIX + "FIBO" + IntegerToString(lineNo), from, to);
}

void UpdateObjects(const PivotPoint &pivots[], const int count,
                   const PivotPoint &active, const bool hasActive,
                   const bool hasActiveLine)
{
   // Hapus objek lastClosed lama jika masih ada
   ObjectDelete(0, PREFIX + "PT_BREAK");
   ObjectDelete(0, PREFIX + "LN_BREAK");
   ObjectDelete(0, PREFIX + "FIBO_BREAK");

   for(int k = 0; k < count; k++)
   {
      EnsurePoint(k, pivots[k]);
      if(k > 0)
         EnsureLine(k - 1, pivots[k - 1], pivots[k]);
   }

   if(count >= 3)
      EnsureFiboOnLine(2, pivots[1], pivots[2]);
   else
      ObjectDelete(0, PREFIX + "FIBO2");

   if(count >= 4)
      EnsureFiboOnLine(3, pivots[2], pivots[3]);
   else
      ObjectDelete(0, PREFIX + "FIBO3");

   // Titik ekstrem aktif selalu ditampilkan
   if(hasActive)
      EnsurePoint(PREFIX + "PT_ACTIVE", active);
   else
      ObjectDelete(0, PREFIX + "PT_ACTIVE");

   // Garis/fibo ke ekstrem hanya setelah break swing lawan
   if(hasActive && hasActiveLine && count > 0)
   {
      EnsureLine(PREFIX + "LN_ACTIVE", pivots[count - 1], active);
      EnsureFiboOnLine(PREFIX + "FIBO_ACTIVE", pivots[count - 1], active);
   }
   else
   {
      ObjectDelete(0, PREFIX + "LN_ACTIVE");
      ObjectDelete(0, PREFIX + "FIBO_ACTIVE");
   }

   for(int k = count; k < MAX_PIVOTS; k++)
      ObjectDelete(0, PREFIX + "PT_" + IntegerToString(k));

   for(int k = MathMax(0, count - 1); k < MAX_PIVOTS - 1; k++)
      ObjectDelete(0, PREFIX + "LN_" + IntegerToString(k));
}

bool BodyBreakUp(const double closePrice, const double level)
{
   return closePrice > level;
}

bool BodyBreakDown(const double closePrice, const double level)
{
   return closePrice < level;
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

// Pivot LOW:
// 1. Lacak candle terendah (extreme)
// 2. a = pertama close > high titik low
// 3. b = setelah a (+1,+2,...), wajib close > close a
// 4. Jika a ada, b belum valid, muncul low baru → hapus a, ganti extreme, ulang langkah 2
// 5. Garis ke titik ekstrem aktif:
//    - cari swing terdekat ke ekstrem aktif
//    - terdekat = LOW  → garis setelah break swing HIGH → ke high ekstrem
//    - terdekat = HIGH → garis setelah break swing LOW  → ke low ekstrem
void BuildPivots(const int rates_total,
                 const datetime &time[],
                 const double &high[],
                 const double &low[],
                 const double &close[],
                 PivotPoint &pivots[],
                 int &count,
                 PivotPoint &active,
                 bool &hasActive,
                 bool &hasActiveLine)
{
   count = 0;
   hasActive = false;
   hasActiveLine = false;
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
            PushPivot(pivots, count, time[pivotIdx], high[pivotIdx], true);
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
            PushPivot(pivots, count, time[pivotIdx], low[pivotIdx], false);
            StartOppositeExtreme(pivotIdx, i, true, high, low, extreme, hasExtreme, lookingForHigh, pendingA);
         }
      }
   }

   // Titik ekstrem aktif
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

   // Swing terdekat ke titik ekstrem aktif = pivot terkonfirmasi terakhir
   const PivotPoint nearest  = pivots[count - 1];
   const PivotPoint opposite = pivots[count - 2];

   if(nearest.time >= active.time)
      return;
   if(nearest.isHigh == opposite.isHigh)
      return;

   // Break dicek dari close lastClosed terhadap swing lawan
   if(!nearest.isHigh)
   {
      // Swing terdekat = LOW → garis ke high ekstrem setelah break swing HIGH
      if(active.isHigh && opposite.isHigh && BodyBreakUp(close[lastClosed], opposite.price))
         hasActiveLine = true;
   }
   else
   {
      // Swing terdekat = HIGH → garis ke low ekstrem setelah break swing LOW
      if(!active.isHigh && !opposite.isHigh && BodyBreakDown(close[lastClosed], opposite.price))
         hasActiveLine = true;
   }
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
   if(rates_total < 3)
      return 0;

   datetime curBar = time[rates_total - 1];
   bool needCalc = (prev_calculated == 0 || curBar != g_lastBarTime || rates_total != prev_calculated);

   if(!needCalc)
      return rates_total;

   g_lastBarTime = curBar;

   PivotPoint pivots[MAX_PIVOTS];
   int count = 0;
   PivotPoint active;
   bool hasActive = false;
   bool hasActiveLine = false;
   BuildPivots(rates_total, time, high, low, close, pivots, count,
               active, hasActive, hasActiveLine);

   bool changed = PivotsChanged(g_last, g_lastCount, pivots, count);
   if(!changed)
   {
      if(hasActive != g_hasActive || hasActiveLine != g_hasActiveLine)
         changed = true;
      else if(hasActive && !SamePivot(active, g_active))
         changed = true;
   }

   if(!changed)
      return rates_total;

   for(int i = 0; i < count; i++)
      g_last[i] = pivots[i];
   g_lastCount = count;
   g_active = active;
   g_hasActive = hasActive;
   g_hasActiveLine = hasActiveLine;

   UpdateObjects(pivots, count, active, hasActive, hasActiveLine);
   return rates_total;
}
