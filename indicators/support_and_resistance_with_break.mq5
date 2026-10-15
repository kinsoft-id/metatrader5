//+------------------------------------------------------------------+
//| support_and_resistance_with_break.mq5                            |
//| Support and Resistance Levels with Breaks                        |
//| Konversi dari Pine Script v4 © LuxAlgo                           |
//| CC BY-NC-SA 4.0                                                  |
//| https://creativecommons.org/licenses/by-nc-sa/4.0/               |
//+------------------------------------------------------------------+
#property copyright "LuxAlgo — CC BY-NC-SA 4.0"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "1.00"
#property description "Support and Resistance Levels with Breaks [LuxAlgo]."
#property description "Garis pivot resistance/support, label B, Bull Wick, dan Bear Wick."
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "Resistance"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

#property indicator_label2  "Support"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  3

#property indicator_label3  "Bullish Break"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLimeGreen
#property indicator_width3  2

#property indicator_label4  "Bearish Break"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed
#property indicator_width4  2

input group "Support and Resistance"
input bool InpShowBreaks   = true;  // Show Breaks
input int  InpLeftBars     = 15;    // Left Bars
input int  InpRightBars    = 15;    // Right Bars
input int  InpVolumeThresh = 20;    // Volume Threshold
input int  InpLabelBars    = 0;     // Break Label Bars (0 = semua)

input group "Alerts"
input bool InpAlerts       = false; // Alert saat bar tutup

#define EMA_SHORT 5
#define EMA_LONG  10

const double ALPHA_SHORT = 2.0 / (EMA_SHORT + 1.0);
const double ALPHA_LONG  = 2.0 / (EMA_LONG + 1.0);
const color  CLR_SUPPORT = C'35,61,238';

double g_resBuf[];
double g_supBuf[];
double g_bullArr[];
double g_bearArr[];
double g_highUse[];
double g_lowUse[];
double g_osc[];

double   g_ema5At1     = EMPTY_VALUE;
double   g_ema10At1    = EMPTY_VALUE;
datetime g_lastBarTime = 0;
int      g_builtBars   = 0;
long     g_liveSig     = 0;

struct BarSignal
{
   bool resBreak;
   bool supBreak;
   bool bullWick;
   bool bearWick;
   bool resAlert;
   bool supAlert;
};

//+------------------------------------------------------------------+
string Prefix()
{
   return StringFormat("SNRBrk_%I64d_%d_%d_",
                       (long)ChartID(), InpLeftBars, InpRightBars);
}

//+------------------------------------------------------------------+
int LeftBars()
{
   return MathMax(0, InpLeftBars);
}

//+------------------------------------------------------------------+
int RightBars()
{
   return MathMax(0, InpRightBars);
}

//+------------------------------------------------------------------+
bool ResizeSeries(double &arr[], const int n)
{
   if(ArrayResize(arr, n) < n)
      return false;
   ArraySetAsSeries(arr, true);
   return true;
}

//+------------------------------------------------------------------+
bool HasValue(const double v)
{
   return (v != EMPTY_VALUE);
}

//+------------------------------------------------------------------+
// Pivot high: high di center lebih tinggi dari left bar di kiri
// dan right bar di kanan. Index 0 = bar sekarang.
bool IsPivotHigh(const int center, const int left, const int right,
                 const double &high[], const int rates)
{
   if(center < right || center + left >= rates)
      return false;

   const double v = high[center];
   for(int k = 1; k <= left; k++)
   {
      if(high[center + k] >= v)
         return false;
   }
   for(int k = 1; k <= right; k++)
   {
      if(high[center - k] >= v)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool IsPivotLow(const int center, const int left, const int right,
                const double &low[], const int rates)
{
   if(center < right || center + left >= rates)
      return false;

   const double v = low[center];
   for(int k = 1; k <= left; k++)
   {
      if(low[center + k] <= v)
         return false;
   }
   for(int k = 1; k <= right; k++)
   {
      if(low[center - k] <= v)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
// highUsePivot = fixnan(pivothigh(left, right)[1])
// Nilai pivot baru masuk satu bar setelah konfirmasi, lalu ditahan.
void BuildHeldLevel(const int rates, const int left, const int right,
                    const double &price[], const bool isHigh, double &held[])
{
   double last = 0.0;
   bool   hasLast = false;
   double prevRaw = 0.0;
   bool   hasPrevRaw = false;

   for(int t = rates - 1; t >= 0; t--)
   {
      if(hasPrevRaw)
      {
         last = prevRaw;
         hasLast = true;
      }
      held[t] = hasLast ? last : EMPTY_VALUE;

      const int center = t + right;
      hasPrevRaw = false;
      if(center < rates)
      {
         const bool pivot = isHigh
                            ? IsPivotHigh(center, left, right, price, rates)
                            : IsPivotLow(center, left, right, price, rates);
         if(pivot)
         {
            prevRaw = price[center];
            hasPrevRaw = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
// osc = 100 * (ema(volume, 5) - ema(volume, 10)) / ema(volume, 10)
// EMA di-seed dengan SMA, sama seperti ema() Pine.
void BuildOsc(const int rates, const long &tickVolume[])
{
   double sum5 = 0.0;
   double sum10 = 0.0;
   int    n5 = 0;
   int    n10 = 0;
   double ema5 = 0.0;
   double ema10 = 0.0;
   bool   seed5 = false;
   bool   seed10 = false;

   g_ema5At1 = EMPTY_VALUE;
   g_ema10At1 = EMPTY_VALUE;

   for(int t = rates - 1; t >= 0; t--)
   {
      const double v = (double)tickVolume[t];

      if(!seed5)
      {
         sum5 += v;
         n5++;
         if(n5 == EMA_SHORT)
         {
            ema5 = sum5 / EMA_SHORT;
            seed5 = true;
         }
      }
      else
         ema5 = ALPHA_SHORT * v + (1.0 - ALPHA_SHORT) * ema5;

      if(!seed10)
      {
         sum10 += v;
         n10++;
         if(n10 == EMA_LONG)
         {
            ema10 = sum10 / EMA_LONG;
            seed10 = true;
         }
      }
      else
         ema10 = ALPHA_LONG * v + (1.0 - ALPHA_LONG) * ema10;

      if(seed5 && seed10 && ema10 != 0.0)
         g_osc[t] = 100.0 * (ema5 - ema10) / ema10;
      else
         g_osc[t] = EMPTY_VALUE;

      if(t == 1)
      {
         g_ema5At1 = seed5 ? ema5 : EMPTY_VALUE;
         g_ema10At1 = seed10 ? ema10 : EMPTY_VALUE;
      }
   }
}

//+------------------------------------------------------------------+
void UpdateOscAtZero(const long &tickVolume[])
{
   if(!HasValue(g_ema5At1) || !HasValue(g_ema10At1))
   {
      g_osc[0] = EMPTY_VALUE;
      return;
   }

   const double v = (double)tickVolume[0];
   const double ema5 = ALPHA_SHORT * v + (1.0 - ALPHA_SHORT) * g_ema5At1;
   const double ema10 = ALPHA_LONG * v + (1.0 - ALPHA_LONG) * g_ema10At1;
   g_osc[0] = (ema10 != 0.0) ? 100.0 * (ema5 - ema10) / ema10 : EMPTY_VALUE;
}

//+------------------------------------------------------------------+
bool CrossOver(const int t, const double &src[], const double &level[])
{
   if(!HasValue(level[t]) || !HasValue(level[t + 1]))
      return false;
   return (src[t] > level[t] && src[t + 1] <= level[t + 1]);
}

//+------------------------------------------------------------------+
bool CrossUnder(const int t, const double &src[], const double &level[])
{
   if(!HasValue(level[t]) || !HasValue(level[t + 1]))
      return false;
   return (src[t] < level[t] && src[t + 1] >= level[t + 1]);
}

//+------------------------------------------------------------------+
void EvalBar(const int t,
             const double &open[], const double &high[], const double &low[],
             const double &close[], BarSignal &sig)
{
   sig.resBreak = false;
   sig.supBreak = false;
   sig.bullWick = false;
   sig.bearWick = false;
   sig.resAlert = false;
   sig.supAlert = false;

   const bool up = CrossOver(t, close, g_highUse);
   const bool down = CrossUnder(t, close, g_lowUse);
   const bool bullWick = (open[t] - low[t]) > (close[t] - open[t]);
   const bool bearWick = (open[t] - close[t]) < (high[t] - open[t]);
   const bool volOk = HasValue(g_osc[t]) && g_osc[t] > (double)InpVolumeThresh;

   sig.bullWick = up && bullWick;
   sig.bearWick = down && bearWick;
   sig.resBreak = up && !bullWick && volOk;
   sig.supBreak = down && !bearWick && volOk;
   sig.resAlert = up && volOk;
   sig.supAlert = down && volOk;
}

//+------------------------------------------------------------------+
long SigKey(const BarSignal &sig)
{
   long key = 0;
   if(sig.supBreak)
      key |= 1;
   if(sig.resBreak)
      key |= 2;
   if(sig.bearWick)
      key |= 4;
   if(sig.bullWick)
      key |= 8;
   return key;
}

//+------------------------------------------------------------------+
double LabelGap(const double barHigh, const double barLow)
{
   const double range = barHigh - barLow;
   double gap = range * 0.55;
   const double floorGap = 18.0 * _Point;
   if(gap < floorGap)
      gap = floorGap;
   return gap;
}

//+------------------------------------------------------------------+
// Panah menempel di high/low candle, label teks berada di luarnya.
double ArrowGap(const double barHigh, const double barLow)
{
   const double range = barHigh - barLow;
   double gap = range * 0.12;
   const double floorGap = 4.0 * _Point;
   if(gap < floorGap)
      gap = floorGap;
   return gap;
}

//+------------------------------------------------------------------+
void EnsureText(const string name, const datetime t, const double price,
                const string text, const color clr, const bool above)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
         return;
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   }

   ObjectMove(0, name, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
}

//+------------------------------------------------------------------+
void PaintBar(const int t, const datetime &time[],
              const double &high[], const double &low[],
              const BarSignal &sig, const bool deleteMissing)
{
   const string base = Prefix() + IntegerToString((long)time[t]);
   const double gap = LabelGap(high[t], low[t]);
   const double arrowGap = ArrowGap(high[t], low[t]);
   const bool bearish = sig.supBreak || sig.bearWick;
   const bool bullish = sig.resBreak || sig.bullWick;

   if(bearish)
      g_bearArr[t] = high[t] + arrowGap;
   else if(deleteMissing)
      g_bearArr[t] = EMPTY_VALUE;

   if(bullish)
      g_bullArr[t] = low[t] - arrowGap;
   else if(deleteMissing)
      g_bullArr[t] = EMPTY_VALUE;

   if(sig.supBreak)
      EnsureText(base + "_SP", time[t], high[t] + gap, "B", clrRed, true);
   else if(deleteMissing)
      ObjectDelete(0, base + "_SP");

   if(sig.resBreak)
      EnsureText(base + "_RS", time[t], low[t] - gap, "B", clrLimeGreen, false);
   else if(deleteMissing)
      ObjectDelete(0, base + "_RS");

   if(sig.bearWick)
      EnsureText(base + "_BR", time[t], high[t] + gap, "Bear Wick", clrRed, true);
   else if(deleteMissing)
      ObjectDelete(0, base + "_BR");

   if(sig.bullWick)
      EnsureText(base + "_BW", time[t], low[t] - gap, "Bull Wick", clrLimeGreen, false);
   else if(deleteMissing)
      ObjectDelete(0, base + "_BW");
}

//+------------------------------------------------------------------+
int OldestLabelShift(const int rates)
{
   const int maxShift = rates - 2;
   if(maxShift < 0)
      return -1;
   if(InpLabelBars <= 0)
      return maxShift;
   return MathMin(maxShift, InpLabelBars - 1);
}

//+------------------------------------------------------------------+
void RebuildLabels(const int rates, const datetime &time[],
                   const double &open[], const double &high[],
                   const double &low[], const double &close[])
{
   ObjectsDeleteAll(0, Prefix());
   g_liveSig = 0;
   if(!InpShowBreaks)
      return;

   const int oldest = OldestLabelShift(rates);
   for(int t = oldest; t >= 0; t--)
   {
      BarSignal sig;
      EvalBar(t, open, high, low, close, sig);
      if(t == 0)
         g_liveSig = SigKey(sig);
      if(SigKey(sig) == 0)
         continue;
      PaintBar(t, time, high, low, sig, false);
   }
}

//+------------------------------------------------------------------+
void RefreshLiveLabel(const datetime &time[],
                      const double &open[], const double &high[],
                      const double &low[], const double &close[])
{
   BarSignal sig;
   EvalBar(0, open, high, low, close, sig);
   const long key = SigKey(sig);
   if(key == 0 && g_liveSig == 0)
      return;

   PaintBar(0, time, high, low, sig, true);
   g_liveSig = key;
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void EmitAlerts(const BarSignal &sig)
{
   if(!InpAlerts)
      return;

   string tf = EnumToString(_Period);
   StringReplace(tf, "PERIOD_", "");

   if(sig.supAlert)
      Alert(StringFormat("%s %s Support Broken", _Symbol, tf));
   if(sig.resAlert)
      Alert(StringFormat("%s %s Resistance Broken", _Symbol, tf));
}

//+------------------------------------------------------------------+
// Garis digambar dengan offset -(right + 1), sama seperti plot() Pine.
// Satu bar tempat pivot baru muncul dikosongkan supaya segmen terputus.
void PlotLevels(const int rates, const int shift)
{
   ArrayInitialize(g_resBuf, EMPTY_VALUE);
   ArrayInitialize(g_supBuf, EMPTY_VALUE);

   for(int t = 0; t < rates - 1; t++)
   {
      const int plot = t + shift;
      if(plot >= rates)
         break;

      if(HasValue(g_highUse[t]) && HasValue(g_highUse[t + 1]) && g_highUse[t] == g_highUse[t + 1])
         g_resBuf[plot] = g_highUse[t];

      if(HasValue(g_lowUse[t]) && HasValue(g_lowUse[t + 1]) && g_lowUse[t] == g_lowUse[t + 1])
         g_supBuf[plot] = g_lowUse[t];
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_resBuf, INDICATOR_DATA);
   SetIndexBuffer(1, g_supBuf, INDICATOR_DATA);
   SetIndexBuffer(2, g_bullArr, INDICATOR_DATA);
   SetIndexBuffer(3, g_bearArr, INDICATOR_DATA);
   ArraySetAsSeries(g_resBuf, true);
   ArraySetAsSeries(g_supBuf, true);
   ArraySetAsSeries(g_bullArr, true);
   ArraySetAsSeries(g_bearArr, true);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, clrRed);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, CLR_SUPPORT);
   PlotIndexSetInteger(2, PLOT_ARROW, 241);
   PlotIndexSetInteger(3, PLOT_ARROW, 242);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, 2);
   PlotIndexSetInteger(3, PLOT_LINE_WIDTH, 2);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("SNR Breaks(%d,%d,%d)",
                                   InpLeftBars, InpRightBars, InpVolumeThresh));

   g_lastBarTime = 0;
   g_builtBars = 0;
   g_liveSig = 0;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, Prefix());
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
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);
   ArraySetAsSeries(g_resBuf, true);
   ArraySetAsSeries(g_supBuf, true);
   ArraySetAsSeries(g_bullArr, true);
   ArraySetAsSeries(g_bearArr, true);

   const int left = LeftBars();
   const int right = RightBars();
   const int need = MathMax(left + right + 2, EMA_LONG + 2);
   if(rates_total < need)
      return(0);

   const bool newBar = (prev_calculated > 0 && g_lastBarTime > 0 && time[0] != g_lastBarTime);
   const bool rebuild = (prev_calculated == 0 || newBar || rates_total != g_builtBars);

   if(!rebuild)
   {
      if(InpShowBreaks)
      {
         ArraySetAsSeries(g_highUse, true);
         ArraySetAsSeries(g_lowUse, true);
         ArraySetAsSeries(g_osc, true);
         ArraySetAsSeries(g_bullArr, true);
         ArraySetAsSeries(g_bearArr, true);
         UpdateOscAtZero(tick_volume);
         RefreshLiveLabel(time, open, high, low, close);
      }
      return(rates_total);
   }

   if(!ResizeSeries(g_highUse, rates_total) ||
      !ResizeSeries(g_lowUse, rates_total) ||
      !ResizeSeries(g_osc, rates_total))
      return(0);

   BuildHeldLevel(rates_total, left, right, high, true, g_highUse);
   BuildHeldLevel(rates_total, left, right, low, false, g_lowUse);
   BuildOsc(rates_total, tick_volume);
   PlotLevels(rates_total, right + 1);
   ArrayInitialize(g_bullArr, EMPTY_VALUE);
   ArrayInitialize(g_bearArr, EMPTY_VALUE);
   RebuildLabels(rates_total, time, open, high, low, close);

   if(newBar)
   {
      BarSignal closed;
      EvalBar(1, open, high, low, close, closed);
      EmitAlerts(closed);
   }

   g_lastBarTime = time[0];
   g_builtBars = rates_total;
   ChartRedraw(0);
   return(rates_total);
}
