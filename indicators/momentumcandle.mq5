#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "Bullish Momentum"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Bearish Momentum"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

enum ENUM_MOM_SHOW
{
   MOM_SHOW_BOTH = 0,      // Bullish & Bearish
   MOM_SHOW_BULLISH = 1,   // Bullish saja
   MOM_SHOW_BEARISH = 2    // Bearish saja
};

input group "Momentum Candle"
input ENUM_MOM_SHOW InpShowSide = MOM_SHOW_BOTH; // Tampilkan sisi
input double InpBodyPercent   = 70.0;   // Minimal body vs range (%)
input int    InpBreakCandles  = 2;      // Minimal break candle sebelumnya
input int    InpMaxCandles    = 10;     // Maksimal momentum candle ditampilkan
input int    InpAtrPeriod     = 14;     // Period ATR filter ukuran
input double InpMinAtrMult    = 1.0;    // Minimal range = ATR x multiplier
input int    InpArrowOffset   = 10;     // Offset segitiga (points)

input group "Fibonacci"
input double InpFiboLevel1    = 61.8;   // Level Fibo 1
input double InpFiboLevel2    = 38.2;   // Level Fibo 2
input double InpFiboTarget    = 27.0;   // Target fibo negatif (-%) di luar candle
input color  InpFiboColor     = clrDodgerBlue;
input int    InpFiboWidth     = 1;
input bool   InpFiboRayRight  = false;  // Ray ke kanan

#define PREFIX "MomCndl_"

double   bullBuffer[];
double   bearBuffer[];
double   atrBuf[];
int      atrHandle = INVALID_HANDLE;
datetime g_lastClosedTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, bullBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, bearBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 241);
   PlotIndexSetInteger(1, PLOT_ARROW, 242);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   atrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   if(atrHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("MomentumCandle(%.1f%%,%d)", InpBodyPercent, InpBreakCandles));

   g_lastClosedTime = 0;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
   ObjectsDeleteAll(0, PREFIX);
}

//+------------------------------------------------------------------+
bool IsMomentumBody(const double open, const double high, const double low, const double close, const double atr)
{
   double range = high - low;
   if(range <= 0.0 || atr <= 0.0)
      return false;

   // Filter candle kecil/persegi: range harus cukup besar vs ATR
   if(range < atr * InpMinAtrMult)
      return false;

   double body = MathAbs(close - open);
   return ((body / range) * 100.0) >= InpBodyPercent;
}

//+------------------------------------------------------------------+
bool BreaksPrevious(const int i, const bool bullish,
                    const double &high[], const double &low[], const double &close[])
{
   if(InpBreakCandles < 1 || i < InpBreakCandles)
      return false;

   if(bullish)
   {
      double maxHigh = high[i - 1];
      for(int j = 2; j <= InpBreakCandles; j++)
         maxHigh = MathMax(maxHigh, high[i - j]);
      return (close[i] > maxHigh);
   }

   double minLow = low[i - 1];
   for(int j = 2; j <= InpBreakCandles; j++)
      minLow = MathMin(minLow, low[i - j]);
   return (close[i] < minLow);
}

//+------------------------------------------------------------------+
void CreateFibo(const string name,
                const datetime t1, const double price1,
                const datetime t2, const double price2)
{
   if(ObjectFind(0, name) >= 0)
      return;

   ObjectCreate(0, name, OBJ_FIBO, 0, t1, price1, t2, price2);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, InpFiboRayRight);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrNONE);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 0);
   ObjectSetInteger(0, name, OBJPROP_LEVELS, 3);

   ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 0, InpFiboLevel1 / 100.0);
   ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 0, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 0, InpFiboWidth);
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 0, InpFiboColor);
   ObjectSetString(0, name, OBJPROP_LEVELTEXT, 0, DoubleToString(InpFiboLevel1, 1));

   ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 1, InpFiboLevel2 / 100.0);
   ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 1, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 1, InpFiboWidth);
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 1, InpFiboColor);
   ObjectSetString(0, name, OBJPROP_LEVELTEXT, 1, DoubleToString(InpFiboLevel2, 1));

   ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 2, -InpFiboTarget / 100.0);
   ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 2, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 2, InpFiboWidth);
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 2, InpFiboColor);
   ObjectSetString(0, name, OBJPROP_LEVELTEXT, 2, DoubleToString(-InpFiboTarget, 1));
}

//+------------------------------------------------------------------+
// return: 1 bullish, -1 bearish, 0 none
int DetectSignal(const int i,
                 const double &open[], const double &high[],
                 const double &low[], const double &close[],
                 const double atr)
{
   if(!IsMomentumBody(open[i], high[i], low[i], close[i], atr))
      return 0;

   if(close[i] > open[i] && BreaksPrevious(i, true, high, low, close))
   {
      if(InpShowSide == MOM_SHOW_BEARISH)
         return 0;
      return 1;
   }

   if(close[i] < open[i] && BreaksPrevious(i, false, high, low, close))
   {
      if(InpShowSide == MOM_SHOW_BULLISH)
         return 0;
      return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
void ApplySignal(const int i, const int signal, const double offset,
                 const int rates_total,
                 const datetime &time[],
                 const double &high[], const double &low[])
{
   string fiboName = PREFIX + "FB_" + (string)time[i];
   datetime t2 = (i < rates_total - 1) ? time[i + 1] : time[i] + PeriodSeconds();

   if(signal > 0)
   {
      bullBuffer[i] = low[i] - offset;
      bearBuffer[i] = EMPTY_VALUE;
      CreateFibo(fiboName, time[i], low[i], t2, high[i]);
   }
   else if(signal < 0)
   {
      bullBuffer[i] = EMPTY_VALUE;
      bearBuffer[i] = high[i] + offset;
      CreateFibo(fiboName, time[i], high[i], t2, low[i]);
   }
   else
   {
      bullBuffer[i] = EMPTY_VALUE;
      bearBuffer[i] = EMPTY_VALUE;
   }
}

//+------------------------------------------------------------------+
void PruneOlderSignals(const int lastClosed, const int maxShow, const datetime &time[])
{
   int kept = 0;
   for(int i = lastClosed; i >= InpBreakCandles; i--)
   {
      if(bullBuffer[i] == EMPTY_VALUE && bearBuffer[i] == EMPTY_VALUE)
         continue;

      kept++;
      if(kept > maxShow)
      {
         bullBuffer[i] = EMPTY_VALUE;
         bearBuffer[i] = EMPTY_VALUE;
         ObjectDelete(0, PREFIX + "FB_" + (string)time[i]);
      }
   }
}

//+------------------------------------------------------------------+
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
   if(rates_total < InpBreakCandles + InpAtrPeriod + 2)
      return(0);

   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 0, rates_total, atrBuf) < rates_total)
      return(0);

   int lastClosed = rates_total - 2;
   int maxShow = MathMax(1, InpMaxCandles);
   double offset = InpArrowOffset * _Point;
   int minBar = MathMax(InpBreakCandles, InpAtrPeriod);

   // Tick pada candle berjalan: tidak perlu kerja ulang
   if(prev_calculated > 0 && time[lastClosed] == g_lastClosedTime)
      return(rates_total);

   g_lastClosedTime = time[lastClosed];

   // Full load: scan dari terbaru, stop setelah maxShow sinyal
   if(prev_calculated == 0)
   {
      ArrayInitialize(bullBuffer, EMPTY_VALUE);
      ArrayInitialize(bearBuffer, EMPTY_VALUE);
      ObjectsDeleteAll(0, PREFIX);

      int found = 0;
      for(int i = lastClosed; i >= minBar && found < maxShow; i--)
      {
         double atr = atrBuf[rates_total - 1 - i];
         int signal = DetectSignal(i, open, high, low, close, atr);
         if(signal == 0)
            continue;

         ApplySignal(i, signal, offset, rates_total, time, high, low);
         found++;
      }
      return(rates_total);
   }

   // Bar baru close: evaluasi bar yang baru saja close saja
   int start = MathMax(minBar, prev_calculated - 1);
   if(start > lastClosed)
      start = lastClosed;

   bool added = false;
   for(int i = start; i <= lastClosed; i++)
   {
      // bersihkan objek lama di bar ini (jika ada) sebelum evaluasi ulang
      ObjectDelete(0, PREFIX + "FB_" + (string)time[i]);

      double atr = atrBuf[rates_total - 1 - i];
      int signal = DetectSignal(i, open, high, low, close, atr);
      ApplySignal(i, signal, offset, rates_total, time, high, low);
      if(signal != 0)
         added = true;
   }

   if(added)
      PruneOlderSignals(lastClosed, maxShow, time);

   return(rates_total);
}
