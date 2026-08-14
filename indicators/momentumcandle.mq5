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
input double InpMinAtrMult    = 0.6;    // Minimal range = ATR x multiplier
input int    InpArrowOffset   = 20;     // Offset segitiga (points)

input group "Fibonacci"
input double InpFiboLevel1    = 74.5;   // Level Fibo 1
input double InpFiboLevel2    = 23.6;   // Level Fibo 2
input double InpFiboTarget    = 27.0;   // Target fibo negatif (-%) di luar candle
input color  InpFiboColor     = clrDodgerBlue;
input int    InpFiboWidth     = 3;
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
   ArraySetAsSeries(bullBuffer, true);
   ArraySetAsSeries(bearBuffer, true);

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

   if(range < atr * InpMinAtrMult)
      return false;

   double body = MathAbs(close - open);
   return ((body / range) * 100.0) >= InpBodyPercent;
}

//+------------------------------------------------------------------+
// Index series: 0=current, 1=last closed, candle sebelumnya = i+1, i+2, ...
bool BreaksPrevious(const int i, const int rates_total, const bool bullish,
                    const double &high[], const double &low[], const double &close[])
{
   if(InpBreakCandles < 1)
      return false;
   if(i + InpBreakCandles >= rates_total)
      return false;

   if(bullish)
   {
      double maxHigh = high[i + 1];
      for(int j = 2; j <= InpBreakCandles; j++)
         maxHigh = MathMax(maxHigh, high[i + j]);
      return (close[i] > maxHigh);
   }

   double minLow = low[i + 1];
   for(int j = 2; j <= InpBreakCandles; j++)
      minLow = MathMin(minLow, low[i + j]);
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
   ObjectSetString(0, name, OBJPROP_LEVELTEXT, 0, " ");

   ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 1, InpFiboLevel2 / 100.0);
   ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 1, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 1, InpFiboWidth);
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 1, InpFiboColor);
   ObjectSetString(0, name, OBJPROP_LEVELTEXT, 1, " ");

   ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 2, -InpFiboTarget / 100.0);
   ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 2, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 2, InpFiboWidth);
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 2, InpFiboColor);
   ObjectSetString(0, name, OBJPROP_LEVELTEXT, 2, " ");
}

//+------------------------------------------------------------------+
int DetectSignal(const int i, const int rates_total,
                 const double &open[], const double &high[],
                 const double &low[], const double &close[],
                 const double atr)
{
   if(!IsMomentumBody(open[i], high[i], low[i], close[i], atr))
      return 0;

   if(close[i] > open[i] && BreaksPrevious(i, rates_total, true, high, low, close))
   {
      if(InpShowSide == MOM_SHOW_BEARISH)
         return 0;
      return 1;
   }

   if(close[i] < open[i] && BreaksPrevious(i, rates_total, false, high, low, close))
   {
      if(InpShowSide == MOM_SHOW_BULLISH)
         return 0;
      return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
void ClearBar(const int i, const datetime &time[])
{
   bullBuffer[i] = EMPTY_VALUE;
   bearBuffer[i] = EMPTY_VALUE;
   ObjectDelete(0, PREFIX + "FB_" + (string)time[i]);
}

//+------------------------------------------------------------------+
void ApplySignal(const int i, const int signal, const double offset,
                 const datetime &time[],
                 const double &high[], const double &low[])
{
   ClearBar(i, time);
   if(signal == 0)
      return;

   string fiboName = PREFIX + "FB_" + (string)time[i];
   // series: bar lebih baru ada di index lebih kecil
   datetime t2 = (i > 0) ? time[i - 1] : time[i] + PeriodSeconds();

   if(signal > 0)
   {
      bullBuffer[i] = low[i] - offset;
      CreateFibo(fiboName, time[i], low[i], t2, high[i]);
   }
   else
   {
      bearBuffer[i] = high[i] + offset;
      CreateFibo(fiboName, time[i], high[i], t2, low[i]);
   }
}

//+------------------------------------------------------------------+
void PruneOlderSignals(const int rates_total, const int maxShow, const datetime &time[])
{
   int kept = 0;
   int maxI = rates_total - 1;
   for(int i = 1; i <= maxI; i++)
   {
      if(bullBuffer[i] == EMPTY_VALUE && bearBuffer[i] == EMPTY_VALUE)
         continue;

      kept++;
      if(kept > maxShow)
         ClearBar(i, time);
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

   // Samakan indexing: 0 = current bar (series)
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(bullBuffer, true);
   ArraySetAsSeries(bearBuffer, true);
   ArraySetAsSeries(atrBuf, true);

   if(CopyBuffer(atrHandle, 0, 0, rates_total, atrBuf) < rates_total)
      return(0);

   int maxShow = MathMax(1, InpMaxCandles);
   double offset = InpArrowOffset * _Point;
   int minShift = MathMax(InpBreakCandles, InpAtrPeriod);

   // Tick pada candle berjalan: tidak perlu kerja ulang
   if(prev_calculated > 0 && time[1] == g_lastClosedTime)
      return(rates_total);

   g_lastClosedTime = time[1];

   // Full load: scan dari terbaru (shift 1), stop setelah maxShow sinyal
   if(prev_calculated == 0)
   {
      ArrayInitialize(bullBuffer, EMPTY_VALUE);
      ArrayInitialize(bearBuffer, EMPTY_VALUE);
      ObjectsDeleteAll(0, PREFIX);

      int found = 0;
      for(int i = 1; i < rates_total - minShift && found < maxShow; i++)
      {
         // ATR bar sebelumnya = atrBuf[i+1]
         double atr = atrBuf[i + 1];
         int signal = DetectSignal(i, rates_total, open, high, low, close, atr);
         if(signal == 0)
            continue;

         ApplySignal(i, signal, offset, time, high, low);
         found++;
      }
      return(rates_total);
   }

   // Bar baru close: evaluasi last closed (index 1)
   double atr = atrBuf[2];
   int signal = DetectSignal(1, rates_total, open, high, low, close, atr);
   ApplySignal(1, signal, offset, time, high, low);

   if(signal != 0)
      PruneOlderSignals(rates_total, maxShow, time);

   return(rates_total);
}
