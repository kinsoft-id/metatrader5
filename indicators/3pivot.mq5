#property copyright "3 Pivot"
#property version   "1.72"
#property indicator_chart_window
#property indicator_plots 0

input group "Display"
input color InpHighColor = clrDodgerBlue;
input color InpLowColor  = clrOrangeRed;
input color InpLineColor = clrSilver;
input int   InpPointSize = 5;
input int   InpLineWidth = 1;

input group "Fibonacci (garis pivot ke-2 & ke-3)"
input color InpFiboColor = clrGold;
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
datetime   g_lastBarTime = 0;

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
   g_lastCount = 0;
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

bool PivotsChanged(const PivotPoint &a[], const int aCount, const PivotPoint &b[], const int bCount)
{
   if(aCount != bCount)
      return true;

   for(int i = 0; i < aCount; i++)
   {
      if(a[i].time != b[i].time || a[i].price != b[i].price || a[i].isHigh != b[i].isHigh)
         return true;
   }
   return false;
}

void EnsurePoint(const int index, const PivotPoint &p)
{
   string name = PREFIX + "PT_" + IntegerToString(index);

   // High: titik di atas wick; Low: titik di bawah wick
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

void EnsureLine(const int index, const PivotPoint &from, const PivotPoint &to)
{
   string name = PREFIX + "LN_" + IntegerToString(index);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, from.time, from.price, to.time, to.price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpLineColor);
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
}

void EnsureFiboOnLine(const int lineNo, const PivotPoint &from, const PivotPoint &to)
{
   string name = PREFIX + "FIBO" + IntegerToString(lineNo);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_FIBO, 0, from.time, from.price, to.time, to.price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpFiboColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, InpFiboWidth);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_LEVELS, 2);

      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 0, 0.382);
      ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 0, InpFiboColor);
      ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 0, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 0, InpFiboWidth);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, 0, "38.2");

      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 1, 0.618);
      ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 1, InpFiboColor);
      ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 1, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 1, InpFiboWidth);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, 1, "61.8");
   }
   else
   {
      ObjectMove(0, name, 0, from.time, from.price);
      ObjectMove(0, name, 1, to.time, to.price);
   }
}

void UpdateObjects(const PivotPoint &pivots[], const int count)
{
   for(int k = 0; k < count; k++)
   {
      EnsurePoint(k, pivots[k]);
      if(k > 0)
         EnsureLine(k - 1, pivots[k - 1], pivots[k]);
   }

   // Fibo 38.2 & 61.8 di garis pivot ke-2 (titik[1] → titik[2])
   if(count >= 3)
      EnsureFiboOnLine(2, pivots[1], pivots[2]);
   else
      ObjectDelete(0, PREFIX + "FIBO2");

   // Fibo 38.2 & 61.8 di garis pivot ke-3 (titik[2] → titik[3])
   if(count >= 4)
      EnsureFiboOnLine(3, pivots[2], pivots[3]);
   else
      ObjectDelete(0, PREFIX + "FIBO3");

   for(int k = count; k < MAX_PIVOTS; k++)
      ObjectDelete(0, PREFIX + "PT_" + IntegerToString(k));

   for(int k = MathMax(0, count - 1); k < MAX_PIVOTS - 1; k++)
      ObjectDelete(0, PREFIX + "LN_" + IntegerToString(k));
}

// Body break = close menembus level (bukan sekadar wick)
bool BodyBreakUp(const double closePrice, const double level)
{
   return closePrice > level;
}

bool BodyBreakDown(const double closePrice, const double level)
{
   return closePrice < level;
}

// Setelah konfirmasi pivot, mulai lacak ekstrem lawan dari bar setelah titik pivot
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
// 2. Candle a = pertama body-break (close > high titik low)
// 3. Candle b = candle SETELAH a (boleh +1, +2, ...), pertama yang close > high a
// 4. Jika sudah ada a tapi b belum valid, lalu muncul candle lebih rendah
//    → hapus a, ganti extreme, ulang dari langkah 2
// Pivot HIGH: sebaliknya.
void BuildPivots(const int rates_total,
                 const datetime &time[],
                 const double &high[],
                 const double &low[],
                 const double &close[],
                 PivotPoint &pivots[],
                 int &count)
{
   count = 0;
   if(rates_total < 4)
      return;

   // Hanya bar yang sudah close (bar berjalan tidak dipakai konfirmasi)
   const int lastClosed = rates_total - 2;

   bool lookingForHigh = true;
   int  extreme = 0;
   bool hasExtreme = false;
   int  pendingA = -1; // candle a; -1 = belum ada / sudah dihapus

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
         // Lacak tertinggi; high baru sebelum b valid → hapus a, ulang langkah 2
         if(high[i] > high[extreme])
         {
            extreme = i;
            pendingA = -1;
            continue;
         }

         if(i <= extreme)
            continue;

         // Langkah 2: cari a (close < low extreme)
         if(pendingA < 0)
         {
            if(BodyBreakDown(close[i], low[extreme]))
               pendingA = i;
            continue;
         }

         // Sudah ada a: tunggu b di bar kapan saja setelah a (bukan wajib +1)
         if(i <= pendingA)
            continue;

         if(BodyBreakDown(close[i], low[pendingA]))
         {
            int pivotIdx = extreme;
            PushPivot(pivots, count, time[pivotIdx], high[pivotIdx], true);
            StartOppositeExtreme(pivotIdx, i, false, high, low, extreme, hasExtreme, lookingForHigh, pendingA);
         }
         // else: belum valid b → tetap simpan a, lanjut bar berikutnya
      }
      else
      {
         // Langkah 1: lacak candle terendah
         // Langkah 4: sudah ada a, b belum valid, low baru → hapus a, ganti extreme
         if(low[i] < low[extreme])
         {
            extreme = i;
            pendingA = -1;
            continue; // ulang dari langkah 2
         }

         if(i <= extreme)
            continue;

         // Langkah 2: Candle a = pertama close > high titik low
         if(pendingA < 0)
         {
            if(BodyBreakUp(close[i], high[extreme]))
               pendingA = i;
            continue;
         }

         // Langkah 3: b boleh muncul di +1, +2, ... setelah a
         if(i <= pendingA)
            continue;

         if(BodyBreakUp(close[i], high[pendingA]))
         {
            // Candle b valid → kunci pivot di candle terendah
            int pivotIdx = extreme;
            PushPivot(pivots, count, time[pivotIdx], low[pivotIdx], false);
            StartOppositeExtreme(pivotIdx, i, true, high, low, extreme, hasExtreme, lookingForHigh, pendingA);
         }
         // else: belum valid b → tetap simpan a; jika nanti low baru, langkah 4 menghapus a
      }
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
   BuildPivots(rates_total, time, high, low, close, pivots, count);

   if(!PivotsChanged(g_last, g_lastCount, pivots, count))
      return rates_total;

   for(int i = 0; i < count; i++)
      g_last[i] = pivots[i];
   g_lastCount = count;

   UpdateObjects(pivots, count);
   return rates_total;
}
