//+------------------------------------------------------------------+
//| SRchannel.mq5                                                    |
//| Support Resistance Channels                                      |
//| Converted from Pine Script v6 by LonesomeTheBlue (MPL 2.0)       |
//+------------------------------------------------------------------+
#property copyright "Converted from Support Resistance Channels [LonesomeTheBlue] — MPL 2.0"
#property link      "https://www.tradingview.com/script/si2UL9LT-Support-Resistance-Channels/"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

#property indicator_label1  "MA 1"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "MA 2"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Pivot High"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  1

#property indicator_label4  "Pivot Low"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  1

#property indicator_label5  "Resistance Broken"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLime
#property indicator_width5  1

#property indicator_label6  "Support Broken"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrRed
#property indicator_width6  1

enum ENUM_SR_SOURCE
{
   SR_SRC_HIGH_LOW   = 0, // High/Low
   SR_SRC_CLOSE_OPEN = 1  // Close/Open
};

enum ENUM_SR_MA_TYPE
{
   SR_MA_SMA = 0, // SMA
   SR_MA_EMA = 1  // EMA
};

input group "Settings"
input int            InpPivotPeriod  = 10;               // Pivot Period
input ENUM_SR_SOURCE InpSource       = SR_SRC_HIGH_LOW;  // Source
input int            InpChannelW     = 5;                // Maximum Channel Width %
input int            InpMinStrength  = 1;                // Minimum Strength
input int            InpMaxNumSR     = 6;                // Maximum Number of S/R
input int            InpLoopback     = 290;              // Loopback Period

input group "Colors"
input color          InpResColor     = clrRed;           // Resistance Color
input color          InpSupColor     = clrLime;          // Support Color
input color          InpInChColor    = clrGray;          // Color When Price in Channel
input int            InpFillTransp   = 75;               // Channel Fill Transparency (0-100)

input group "Extras"
input bool           InpShowPP       = false;            // Show Pivot Points
input bool           InpShowBroken   = false;            // Show Broken Support/Resistance
input bool           InpAlerts       = false;            // Enable Alert()

input group "MA 1"
input bool           InpMA1Enable    = false;            // MA 1
input int            InpMA1Len       = 50;               // Length
input ENUM_SR_MA_TYPE InpMA1Type     = SR_MA_SMA;        // Type

input group "MA 2"
input bool           InpMA2Enable    = false;            // MA 2
input int            InpMA2Len       = 200;              // Length
input ENUM_SR_MA_TYPE InpMA2Type     = SR_MA_SMA;        // Type

#define PREFIX       "SRC_"
#define RANGE_BARS   300
#define MAX_SR       10
#define PIVOT_STEP   64

double g_ma1Buf[];
double g_ma2Buf[];
double g_phBuf[];
double g_plBuf[];
double g_resBrkBuf[];
double g_supBrkBuf[];

int    g_ma1Handle = INVALID_HANDLE;
int    g_ma2Handle = INVALID_HANDLE;

double g_pivotVal[];
int    g_pivotLoc[];
int    g_pivotCount = 0;

double g_sr[MAX_SR * 2];
double g_stren[MAX_SR];

int    g_prd = 10;
int    g_channelW = 5;
int    g_minStrength = 1;
int    g_maxShow = 5;
int    g_loopback = 290;
int    g_fillTransp = 75;

datetime g_alertBar = 0;

//+------------------------------------------------------------------+
int ClampInt(const int v, const int lo, const int hi)
{
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
}

//+------------------------------------------------------------------+
color ApplyTransp(const color clr, const int transp)
{
   int t = ClampInt(transp, 0, 100);
   uchar alpha = (uchar)MathRound(2.55 * (100 - t));
   return (color)ColorToARGB(clr, alpha);
}

//+------------------------------------------------------------------+
ENUM_MA_METHOD MaMethod(const ENUM_SR_MA_TYPE t)
{
   return (t == SR_MA_EMA) ? MODE_EMA : MODE_SMA;
}

//+------------------------------------------------------------------+
void ResetPivots()
{
   g_pivotCount = 0;
   ArrayResize(g_pivotVal, PIVOT_STEP);
   ArrayResize(g_pivotLoc, PIVOT_STEP);
   ArrayInitialize(g_sr, 0);
   ArrayInitialize(g_stren, 0);
}

//+------------------------------------------------------------------+
void PivotUnshift(const double val, const int loc)
{
   if(g_pivotCount >= ArraySize(g_pivotVal))
   {
      int n = g_pivotCount + PIVOT_STEP;
      ArrayResize(g_pivotVal, n);
      ArrayResize(g_pivotLoc, n);
   }

   for(int i = g_pivotCount; i > 0; i--)
   {
      g_pivotVal[i] = g_pivotVal[i - 1];
      g_pivotLoc[i] = g_pivotLoc[i - 1];
   }

   g_pivotVal[0] = val;
   g_pivotLoc[0] = loc;
   g_pivotCount++;
}

//+------------------------------------------------------------------+
void PruneOldPivots(const int barIndex)
{
   for(int x = g_pivotCount - 1; x >= 0; x--)
   {
      if(barIndex - g_pivotLoc[x] > g_loopback)
      {
         g_pivotCount--;
         continue;
      }
      break;
   }
}

//+------------------------------------------------------------------+
double SrcHigh(const int i, const double &open[], const double &high[], const double &close[])
{
   if(InpSource == SR_SRC_HIGH_LOW)
      return high[i];
   return MathMax(close[i], open[i]);
}

//+------------------------------------------------------------------+
double SrcLow(const int i, const double &open[], const double &low[], const double &close[])
{
   if(InpSource == SR_SRC_HIGH_LOW)
      return low[i];
   return MathMin(close[i], open[i]);
}

//+------------------------------------------------------------------+
bool IsPivot(const int confirmBar, const int prd, const bool isHigh,
             const double &open[], const double &high[], const double &low[], const double &close[])
{
   int pb = confirmBar - prd;
   if(pb < prd)
      return false;

   double v = isHigh ? SrcHigh(pb, open, high, close)
                     : SrcLow(pb, open, low, close);

   for(int k = pb - prd; k <= pb + prd; k++)
   {
      if(k == pb)
         continue;
      double s = isHigh ? SrcHigh(k, open, high, close)
                        : SrcLow(k, open, low, close);
      if(isHigh)
      {
         if(s >= v)
            return false;
      }
      else
      {
         if(s <= v)
            return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
double HighestRange(const double &high[], const int i, const int n)
{
   int from = i - n + 1;
   if(from < 0)
      from = 0;
   double m = high[from];
   for(int k = from + 1; k <= i; k++)
   {
      if(high[k] > m)
         m = high[k];
   }
   return m;
}

//+------------------------------------------------------------------+
double LowestRange(const double &low[], const int i, const int n)
{
   int from = i - n + 1;
   if(from < 0)
      from = 0;
   double m = low[from];
   for(int k = from + 1; k <= i; k++)
   {
      if(low[k] < m)
         m = low[k];
   }
   return m;
}

//+------------------------------------------------------------------+
void GetSRVals(const int ind, const double cwidth, double &outHi, double &outLo, int &numpp)
{
   double lo = g_pivotVal[ind];
   double hi = lo;
   numpp = 0;

   for(int y = 0; y < g_pivotCount; y++)
   {
      double cpp = g_pivotVal[y];
      double wdth = (cpp <= hi) ? (hi - cpp) : (cpp - lo);
      if(wdth <= cwidth)
      {
         if(cpp <= hi)
            lo = MathMin(lo, cpp);
         else
            hi = MathMax(hi, cpp);
         numpp += 20;
      }
   }

   outHi = hi;
   outLo = lo;
}

//+------------------------------------------------------------------+
void RecalcChannels(const int i, const double &high[], const double &low[], const double cwidth)
{
   int n = g_pivotCount;
   if(n <= 0)
   {
      ArrayInitialize(g_sr, 0);
      ArrayInitialize(g_stren, 0);
      return;
   }

   double supres[];
   ArrayResize(supres, n * 3);

   for(int x = 0; x < n; x++)
   {
      double hi, lo;
      int strength;
      GetSRVals(x, cwidth, hi, lo, strength);
      supres[x * 3]     = (double)strength;
      supres[x * 3 + 1] = hi;
      supres[x * 3 + 2] = lo;
   }

   int maxY = MathMin(g_loopback, i);
   for(int x = 0; x < n; x++)
   {
      double h = supres[x * 3 + 1];
      double l = supres[x * 3 + 2];
      int s = 0;
      for(int y = 0; y <= maxY; y++)
      {
         double hy = high[i - y];
         double ly = low[i - y];
         if((hy <= h && hy >= l) || (ly <= h && ly >= l))
            s++;
      }
      supres[x * 3] += s;
   }

   ArrayInitialize(g_sr, 0);
   ArrayInitialize(g_stren, 0);

   int src = 0;
   double minStr = (double)g_minStrength * 20.0;
   for(int x = 0; x < n; x++)
   {
      double stv = -1.0;
      int stl = -1;
      for(int y = 0; y < n; y++)
      {
         if(supres[y * 3] > stv && supres[y * 3] >= minStr)
         {
            stv = supres[y * 3];
            stl = y;
         }
      }

      if(stl >= 0)
      {
         double hh = supres[stl * 3 + 1];
         double ll = supres[stl * 3 + 2];
         g_sr[src * 2]     = hh;
         g_sr[src * 2 + 1] = ll;
         g_stren[src]      = supres[stl * 3];

         for(int y = 0; y < n; y++)
         {
            if((supres[y * 3 + 1] <= hh && supres[y * 3 + 1] >= ll) ||
               (supres[y * 3 + 2] <= hh && supres[y * 3 + 2] >= ll))
               supres[y * 3] = -1.0;
         }

         src++;
         if(src >= MAX_SR)
            break;
      }
   }

   for(int x = 0; x < MAX_SR - 1; x++)
   {
      for(int y = x + 1; y < MAX_SR; y++)
      {
         if(g_stren[y] > g_stren[x])
         {
            double ts = g_stren[y];
            g_stren[y] = g_stren[x];
            g_stren[x] = ts;

            double th = g_sr[y * 2];
            g_sr[y * 2] = g_sr[x * 2];
            g_sr[x * 2] = th;

            double tl = g_sr[y * 2 + 1];
            g_sr[y * 2 + 1] = g_sr[x * 2 + 1];
            g_sr[x * 2 + 1] = tl;
         }
      }
   }
}

//+------------------------------------------------------------------+
color ChannelColor(const int pairIndex, const double price)
{
   int hiIdx = pairIndex * 2;
   int loIdx = hiIdx + 1;
   if(hiIdx >= MAX_SR * 2)
      return clrNONE;
   if(g_sr[hiIdx] == 0.0 && g_sr[loIdx] == 0.0)
      return clrNONE;

   if(g_sr[hiIdx] > price && g_sr[loIdx] > price)
      return ApplyTransp(InpResColor, g_fillTransp);
   if(g_sr[hiIdx] < price && g_sr[loIdx] < price)
      return ApplyTransp(InpSupColor, g_fillTransp);
   return ApplyTransp(InpInChColor, g_fillTransp);
}

//+------------------------------------------------------------------+
void StyleHidden(const string name, const bool back)
{
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, back);
}

//+------------------------------------------------------------------+
void EnsureChannelBox(const int idx, const datetime t1, const datetime t2,
                      const double top, const double bot, const color clr)
{
   string name = PREFIX + "CH_" + IntegerToString(idx);
   if(clr == clrNONE || (top == 0.0 && bot == 0.0))
   {
      if(ObjectFind(0, name) >= 0)
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      return;
   }

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bot);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      StyleHidden(name, true);
   }

   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, top);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, bot);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void DrawChannels(const datetime tLeft, const datetime tRight, const double price)
{
   for(int x = 0; x <= g_maxShow; x++)
   {
      color clr = ChannelColor(x, price);
      EnsureChannelBox(x, tLeft, tRight, g_sr[x * 2], g_sr[x * 2 + 1], clr);
   }

   for(int x = g_maxShow + 1; x < MAX_SR; x++)
   {
      string name = PREFIX + "CH_" + IntegerToString(x);
      if(ObjectFind(0, name) >= 0)
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   }
}

//+------------------------------------------------------------------+
bool NotInChannel(const double price)
{
   for(int x = 0; x <= g_maxShow; x++)
   {
      double hi = g_sr[x * 2];
      double lo = g_sr[x * 2 + 1];
      if(hi == 0.0 && lo == 0.0)
         continue;
      if(price <= hi && price >= lo)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void CheckBroken(const int i, const double &close[], bool &resBroken, bool &supBroken)
{
   resBroken = false;
   supBroken = false;
   if(i <= 0)
      return;
   if(!NotInChannel(close[i]))
      return;

   for(int x = 0; x <= g_maxShow; x++)
   {
      double hi = g_sr[x * 2];
      double lo = g_sr[x * 2 + 1];
      if(hi == 0.0 && lo == 0.0)
         continue;
      if(close[i - 1] <= hi && close[i] > hi)
         resBroken = true;
      if(close[i - 1] >= lo && close[i] < lo)
         supBroken = true;
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_prd          = ClampInt(InpPivotPeriod, 4, 30);
   g_channelW     = ClampInt(InpChannelW, 1, 8);
   g_minStrength  = MathMax(InpMinStrength, 1);
   g_maxShow      = ClampInt(InpMaxNumSR, 1, MAX_SR) - 1;
   g_loopback     = ClampInt(InpLoopback, 100, 400);
   g_fillTransp   = ClampInt(InpFillTransp, 0, 100);

   SetIndexBuffer(0, g_ma1Buf, INDICATOR_DATA);
   SetIndexBuffer(1, g_ma2Buf, INDICATOR_DATA);
   SetIndexBuffer(2, g_phBuf, INDICATOR_DATA);
   SetIndexBuffer(3, g_plBuf, INDICATOR_DATA);
   SetIndexBuffer(4, g_resBrkBuf, INDICATOR_DATA);
   SetIndexBuffer(5, g_supBrkBuf, INDICATOR_DATA);

   ArraySetAsSeries(g_ma1Buf, false);
   ArraySetAsSeries(g_ma2Buf, false);
   ArraySetAsSeries(g_phBuf, false);
   ArraySetAsSeries(g_plBuf, false);
   ArraySetAsSeries(g_resBrkBuf, false);
   ArraySetAsSeries(g_supBrkBuf, false);

   PlotIndexSetInteger(2, PLOT_ARROW, 159);
   PlotIndexSetInteger(3, PLOT_ARROW, 159);
   PlotIndexSetInteger(4, PLOT_ARROW, 233);
   PlotIndexSetInteger(5, PLOT_ARROW, 234);

   for(int p = 0; p < 6; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpMA1Enable ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, InpMA2Enable ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, InpShowPP ? DRAW_ARROW : DRAW_NONE);
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, InpShowPP ? DRAW_ARROW : DRAW_NONE);
   PlotIndexSetInteger(4, PLOT_DRAW_TYPE, InpShowBroken ? DRAW_ARROW : DRAW_NONE);
   PlotIndexSetInteger(5, PLOT_DRAW_TYPE, InpShowBroken ? DRAW_ARROW : DRAW_NONE);

   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("SRchannel(%d,%d)", g_prd, InpMaxNumSR));

   g_ma1Handle = iMA(_Symbol, PERIOD_CURRENT, MathMax(InpMA1Len, 1), 0, MaMethod(InpMA1Type), PRICE_CLOSE);
   g_ma2Handle = iMA(_Symbol, PERIOD_CURRENT, MathMax(InpMA2Len, 1), 0, MaMethod(InpMA2Type), PRICE_CLOSE);
   if(g_ma1Handle == INVALID_HANDLE || g_ma2Handle == INVALID_HANDLE)
      return INIT_FAILED;

   ResetPivots();
   g_alertBar = 0;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_ma1Handle != INVALID_HANDLE)
      IndicatorRelease(g_ma1Handle);
   if(g_ma2Handle != INVALID_HANDLE)
      IndicatorRelease(g_ma2Handle);
   ObjectsDeleteAll(0, PREFIX);
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
   if(rates_total < g_prd * 2 + 2)
      return 0;

   if(InpMA1Enable)
   {
      if(CopyBuffer(g_ma1Handle, 0, 0, rates_total, g_ma1Buf) < rates_total)
         return prev_calculated;
   }
   if(InpMA2Enable)
   {
      if(CopyBuffer(g_ma2Handle, 0, 0, rates_total, g_ma2Buf) < rates_total)
         return prev_calculated;
   }

   int start;
   if(prev_calculated <= 0)
   {
      ResetPivots();
      ArrayInitialize(g_phBuf, EMPTY_VALUE);
      ArrayInitialize(g_plBuf, EMPTY_VALUE);
      ArrayInitialize(g_resBrkBuf, EMPTY_VALUE);
      ArrayInitialize(g_supBrkBuf, EMPTY_VALUE);
      if(!InpMA1Enable)
         ArrayInitialize(g_ma1Buf, EMPTY_VALUE);
      if(!InpMA2Enable)
         ArrayInitialize(g_ma2Buf, EMPTY_VALUE);
      start = g_prd * 2;
   }
   else
      start = prev_calculated - 1;

   if(start < g_prd * 2)
      start = g_prd * 2;

   for(int i = start; i < rates_total; i++)
   {
      if(!InpMA1Enable)
         g_ma1Buf[i] = EMPTY_VALUE;
      if(!InpMA2Enable)
         g_ma2Buf[i] = EMPTY_VALUE;

      g_resBrkBuf[i] = EMPTY_VALUE;
      g_supBrkBuf[i] = EMPTY_VALUE;

      bool isForming = (i == rates_total - 1);

      if(!isForming)
      {
         int pivotBar = i - g_prd;
         bool ph = IsPivot(i, g_prd, true, open, high, low, close);
         bool pl = IsPivot(i, g_prd, false, open, high, low, close);

         if(ph || pl)
         {
            double pval = ph ? SrcHigh(pivotBar, open, high, close)
                             : SrcLow(pivotBar, open, low, close);
            PivotUnshift(pval, i);
            PruneOldPivots(i);

            double cwidth = (HighestRange(high, i, RANGE_BARS) - LowestRange(low, i, RANGE_BARS))
                            * g_channelW / 100.0;
            RecalcChannels(i, high, low, cwidth);

            if(InpShowPP)
            {
               if(ph)
                  g_phBuf[pivotBar] = SrcHigh(pivotBar, open, high, close);
               if(pl)
                  g_plBuf[pivotBar] = SrcLow(pivotBar, open, low, close);
            }
         }
      }

      bool resBroken = false;
      bool supBroken = false;
      CheckBroken(i, close, resBroken, supBroken);

      if(InpShowBroken)
      {
         if(resBroken)
            g_resBrkBuf[i] = low[i];
         if(supBroken)
            g_supBrkBuf[i] = high[i];
      }

      if(InpAlerts && isForming && (resBroken || supBroken) && time[i] != g_alertBar)
      {
         g_alertBar = time[i];
         if(resBroken)
            Alert(_Symbol, " ", EnumToString(_Period), " Resistance Broken");
         if(supBroken)
            Alert(_Symbol, " ", EnumToString(_Period), " Support Broken");
      }
   }

   int last = rates_total - 1;
   datetime tRight = time[last] + (datetime)PeriodSeconds(_Period) * 50;
   DrawChannels(time[0], tRight, close[last]);
   return rates_total;
}
//+------------------------------------------------------------------+
