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

input group "Momentum Candle"
input double InpBodyPercent   = 70.0;   // Minimal body vs range (%)
input int    InpBreakCandles  = 2;      // Minimal break candle sebelumnya
input int    InpArrowOffset   = 10;     // Offset segitiga (points)

input group "Fibonacci"
input double InpFiboLevel1    = 61.8;   // Level Fibo 1
input double InpFiboLevel2    = 38.2;   // Level Fibo 2
input color  InpFiboColor     = clrGold;
input int    InpFiboWidth     = 1;
input bool   InpFiboRayRight  = true;   // Ray ke kanan

#define PREFIX "MomCndl_"

double bullBuffer[];
double bearBuffer[];

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, bullBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, bearBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 241); // segitiga atas (dari bawah candle)
   PlotIndexSetInteger(1, PLOT_ARROW, 242); // segitiga bawah (dari atas candle)
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("MomentumCandle(%.1f%%,%d)", InpBodyPercent, InpBreakCandles));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
}

//+------------------------------------------------------------------+
bool IsMomentumBody(const double open, const double high, const double low, const double close)
{
   double range = high - low;
   if(range <= 0.0)
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
void EnsureFibo(const string name,
                const datetime t1, const double price1,
                const datetime t2, const double price2)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_FIBO, 0, t1, price1, t2, price2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, InpFiboWidth);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_LEVELS, 2);

      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 0, InpFiboLevel1 / 100.0);
      ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 0, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 0, InpFiboWidth);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, 0, DoubleToString(InpFiboLevel1, 1));

      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 1, InpFiboLevel2 / 100.0);
      ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 1, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 1, InpFiboWidth);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, 1, DoubleToString(InpFiboLevel2, 1));
   }
   else
   {
      ObjectMove(0, name, 0, t1, price1);
      ObjectMove(0, name, 1, t2, price2);
   }

   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, InpFiboRayRight);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpFiboColor);
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 0, InpFiboColor);
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 1, InpFiboColor);
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
   if(rates_total < InpBreakCandles + 2)
      return(0);

   int start = (prev_calculated > 1) ? prev_calculated - 1 : InpBreakCandles;

   // Jangan evaluasi candle yang masih berjalan (baca saat close)
   int lastClosed = rates_total - 2;

   if(prev_calculated == 0)
   {
      ArrayInitialize(bullBuffer, EMPTY_VALUE);
      ArrayInitialize(bearBuffer, EMPTY_VALUE);
      ObjectsDeleteAll(0, PREFIX);
      start = InpBreakCandles;
   }

   double offset = InpArrowOffset * _Point;

   for(int i = start; i <= lastClosed; i++)
   {
      bullBuffer[i] = EMPTY_VALUE;
      bearBuffer[i] = EMPTY_VALUE;

      string fiboName = PREFIX + "FB_" + (string)time[i];

      if(!IsMomentumBody(open[i], high[i], low[i], close[i]))
      {
         ObjectDelete(0, fiboName);
         continue;
      }

      bool bullish = (close[i] > open[i]);
      bool bearish = (close[i] < open[i]);

      if(bullish && BreaksPrevious(i, true, high, low, close))
      {
         bullBuffer[i] = low[i] - offset;
         // Bullish: impulse low -> high, level fibo = retracement dari high
         datetime t2 = (i < rates_total - 1) ? time[i + 1] : time[i] + PeriodSeconds();
         EnsureFibo(fiboName, time[i], high[i], t2, low[i]);
      }
      else if(bearish && BreaksPrevious(i, false, high, low, close))
      {
         bearBuffer[i] = high[i] + offset;
         // Bearish: impulse high -> low
         datetime t2 = (i < rates_total - 1) ? time[i + 1] : time[i] + PeriodSeconds();
         EnsureFibo(fiboName, time[i], low[i], t2, high[i]);
      }
      else
      {
         ObjectDelete(0, fiboName);
      }
   }

   ChartRedraw(0);
   return(rates_total);
}
