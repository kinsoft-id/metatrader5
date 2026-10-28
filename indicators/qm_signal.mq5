//+------------------------------------------------------------------+
//| qm_signal.mq5                                                    |
//| Converted from QM Signal [TradingFinder] (Pine v5)               |
//| Original: © chartbox90, Mozilla Public License 2.0               |
//| Quasimodo / Head and Shoulders pivot pattern                     |
//+------------------------------------------------------------------+
#property copyright "Converted from QM Signal [TradingFinder] © chartbox90"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "Bullish QM"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

#property indicator_label2  "Bearish QM"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrCrimson
#property indicator_width2  2

input int InpPivotPeriod = 5;  // Pivot Period
input int InpATRPeriod   = 21; // ATR Period
input int InpMaxBars     = 5000; // Max bars back
input int InpMaxPatterns = 50; // Max drawn patterns

input group "Display"
input color InpBullColor   = C'38,150,41';
input color InpBullArrow   = C'4,215,252';
input color InpBearColor   = C'170,29,29';
input color InpBearArrow   = C'252,173,4';
input color InpEntryColor  = clrBlack;
input color InpSLColor     = C'170,29,29';
input color InpTPColor     = C'91,172,74';
input color InpLabelColor  = clrBlack;
input int   InpLegWidth    = 2;
input int   InpGuideWidth  = 1;

#define PREFIX "QM_"
#define EMPTY_VAL 0.0

struct SwingPoint
{
   string type;
   double value;
   int    index;
};

struct QMPattern
{
   bool     isBull;
   int      i1;
   int      i2;
   int      i3;
   int      i4;
   int      i5;
   double   v1;
   double   v2;
   double   v3;
   double   v4;
   double   v5;
   double   atr;
   datetime confirmTime;
};

double     g_bullBuf[];
double     g_bearBuf[];

SwingPoint g_swings[];
int        g_swingCount = 0;

QMPattern  g_patterns[];
int        g_patternCount = 0;

string     g_lastSignature = "";

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_bullBuf, INDICATOR_DATA);
   SetIndexBuffer(1, g_bearBuf, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VAL);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VAL);
   ArraySetAsSeries(g_bullBuf, true);
   ArraySetAsSeries(g_bearBuf, true);
   IndicatorSetString(INDICATOR_SHORTNAME, "QM Signal");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
   g_lastSignature = "";
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
   if(rates_total < InpPivotPeriod * 2 + InpATRPeriod + 10)
      return 0;

   const int copyCount = MathMin(rates_total, MathMax(InpMaxBars, InpPivotPeriod * 2 + 50));

   double   h[], l[], c[], atr[];
   datetime t[];
   if(CopyHigh(_Symbol, _Period, 0, copyCount, h) != copyCount)
      return prev_calculated;
   if(CopyLow(_Symbol, _Period, 0, copyCount, l) != copyCount)
      return prev_calculated;
   if(CopyClose(_Symbol, _Period, 0, copyCount, c) != copyCount)
      return prev_calculated;
   if(CopyTime(_Symbol, _Period, 0, copyCount, t) != copyCount)
      return prev_calculated;

   ArraySetAsSeries(h, false);
   ArraySetAsSeries(l, false);
   ArraySetAsSeries(c, false);
   ArraySetAsSeries(t, false);

   ComputeATR(h, l, c, copyCount, InpATRPeriod, atr);

   for(int i = 0; i < rates_total; i++)
   {
      g_bullBuf[i] = EMPTY_VAL;
      g_bearBuf[i] = EMPTY_VAL;
   }

   ScanHistory(h, l, c, t, atr, copyCount);

   return rates_total;
}

//+------------------------------------------------------------------+
void ComputeATR(const double &high[],
                const double &low[],
                const double &close[],
                const int bars,
                const int period,
                double &atr[])
{
   ArrayResize(atr, bars);
   ArraySetAsSeries(atr, false);

   double tr[];
   ArrayResize(tr, bars);
   tr[0] = high[0] - low[0];
   for(int i = 1; i < bars; i++)
   {
      const double range  = high[i] - low[i];
      const double upGap  = MathAbs(high[i] - close[i - 1]);
      const double dnGap  = MathAbs(low[i] - close[i - 1]);
      tr[i] = MathMax(range, MathMax(upGap, dnGap));
   }

   if(bars <= period)
   {
      ArrayInitialize(atr, 0.0);
      return;
   }

   double sum = 0.0;
   for(int i = 0; i < period; i++)
      sum += tr[i];
   atr[period - 1] = sum / period;

   for(int i = 0; i < period - 1; i++)
      atr[i] = atr[period - 1];

   for(int i = period; i < bars; i++)
      atr[i] = (atr[i - 1] * (period - 1) + tr[i]) / period;
}

//+------------------------------------------------------------------+
bool IsPivotHigh(const double &high[], const int bars, const int center, const int pp)
{
   if(center - pp < 0 || center + pp >= bars)
      return false;

   const double px = high[center];
   for(int k = center - pp; k <= center + pp; k++)
   {
      if(k == center)
         continue;
      if(high[k] >= px)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool IsPivotLow(const double &low[], const int bars, const int center, const int pp)
{
   if(center - pp < 0 || center + pp >= bars)
      return false;

   const double px = low[center];
   for(int k = center - pp; k <= center + pp; k++)
   {
      if(k == center)
         continue;
      if(low[k] <= px)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void ResetSwings()
{
   g_swingCount = 0;
   ArrayResize(g_swings, 64);
   g_patternCount = 0;
   ArrayResize(g_patterns, 16);
}

//+------------------------------------------------------------------+
void PushSwing(const string type, const double value, const int index)
{
   if(g_swingCount >= ArraySize(g_swings))
      ArrayResize(g_swings, g_swingCount + 64);

   g_swings[g_swingCount].type  = type;
   g_swings[g_swingCount].value = value;
   g_swings[g_swingCount].index = index;
   g_swingCount++;
}

//+------------------------------------------------------------------+
void RemoveLastSwing()
{
   if(g_swingCount > 0)
      g_swingCount--;
}

//+------------------------------------------------------------------+
string LastType()
{
   if(g_swingCount <= 0)
      return "";
   return g_swings[g_swingCount - 1].type;
}

//+------------------------------------------------------------------+
double LastValue()
{
   if(g_swingCount <= 0)
      return 0.0;
   return g_swings[g_swingCount - 1].value;
}

//+------------------------------------------------------------------+
string ClassifyHigh(const double highValue)
{
   if(g_swingCount > 2)
      return (g_swings[g_swingCount - 2].value < highValue) ? "HH" : "LH";
   return "H";
}

//+------------------------------------------------------------------+
string ClassifyLow(const double lowValue)
{
   if(g_swingCount > 2)
      return (g_swings[g_swingCount - 2].value < lowValue) ? "HL" : "LL";
   return "L";
}

//+------------------------------------------------------------------+
void PushHigh(const double highValue, const int highIndex)
{
   PushSwing(ClassifyHigh(highValue), highValue, highIndex);
}

//+------------------------------------------------------------------+
void PushLow(const double lowValue, const int lowIndex)
{
   PushSwing(ClassifyLow(lowValue), lowValue, lowIndex);
}

//+------------------------------------------------------------------+
void AddPattern(const bool isBull,
                const int i1, const int i2, const int i3, const int i4, const int i5,
                const double v1, const double v2, const double v3, const double v4, const double v5,
                const double atr,
                const datetime confirmTime)
{
   if(g_patternCount >= InpMaxPatterns)
   {
      for(int i = 1; i < g_patternCount; i++)
         g_patterns[i - 1] = g_patterns[i];
      g_patternCount--;
   }

   if(g_patternCount >= ArraySize(g_patterns))
      ArrayResize(g_patterns, g_patternCount + 16);

   QMPattern p;
   p.isBull = isBull;
   p.i1 = i1; p.i2 = i2; p.i3 = i3; p.i4 = i4; p.i5 = i5;
   p.v1 = v1; p.v2 = v2; p.v3 = v3; p.v4 = v4; p.v5 = v5;
   p.atr = atr;
   p.confirmTime = confirmTime;
   g_patterns[g_patternCount++] = p;
}

//+------------------------------------------------------------------+
void ScanHistory(const double &high[],
                 const double &low[],
                 const double &close[],
                 const datetime &time[],
                 const double &atr[],
                 const int bars)
{
   ResetSwings();

   const int pp = InpPivotPeriod;
   double highValue = 0.0;
   double lowValue  = 0.0;
   int    highIndex = 0;
   int    lowIndex  = 0;

   string th1 = "", th2 = "", th3 = "", th4 = "", th5 = "";
   int    ih1 = 0, ih2 = 0, ih3 = 0, ih4 = 0, ih5 = 0;
   double vh1 = 0.0, vh2 = 0.0, vh3 = 0.0, vh4 = 0.0, vh5 = 0.0;

   int    checkBe = 0;
   int    checkBu = 0;
   double bearStart = 0.0;
   double bullStart = 0.0;

   for(int bar = 0; bar < bars; bar++)
   {
      const int center = bar - pp;
      const bool highPivot = (center >= 0) && IsPivotHigh(high, bars, center, pp);
      const bool lowPivot  = (center >= 0) && IsPivotLow(low, bars, center, pp);

      if(highPivot)
      {
         highValue = high[center];
         highIndex = center;
      }
      if(lowPivot)
      {
         lowValue = low[center];
         lowIndex = center;
      }

      UpdateSwingArray(highPivot, lowPivot, highValue, lowValue, highIndex, lowIndex, close[bar]);

      if(g_swingCount > 5)
      {
         const int n = g_swingCount;
         th1 = g_swings[n - 1].type;  th2 = g_swings[n - 2].type;  th3 = g_swings[n - 3].type;
         th4 = g_swings[n - 4].type;  th5 = g_swings[n - 5].type;
         ih1 = g_swings[n - 1].index; ih2 = g_swings[n - 2].index; ih3 = g_swings[n - 3].index;
         ih4 = g_swings[n - 4].index; ih5 = g_swings[n - 5].index;
         vh1 = g_swings[n - 1].value; vh2 = g_swings[n - 2].value; vh3 = g_swings[n - 3].value;
         vh4 = g_swings[n - 4].value; vh5 = g_swings[n - 5].value;
      }

      if(th1 == "LL" && th2 == "HH" && th3 == "HL" && th4 == "HH" &&
         vh5 < vh1 && ih1 == (bar - pp) && checkBe == 0)
      {
         bearStart = vh2;
         checkBe = 1;
         AddPattern(false, ih1, ih2, ih3, ih4, ih5, vh1, vh2, vh3, vh4, vh5, atr[bar], time[bar]);

         const int bufPos = (int)iBarShift(_Symbol, _Period, time[bar]);
         if(bufPos >= 0)
            g_bearBuf[bufPos] = vh1;
      }

      if(bearStart != vh2)
         checkBe = 0;

      if(th1 == "HH" && th2 == "LL" && th3 == "LH" && th4 == "LL" &&
         vh5 > vh1 && ih1 == (bar - pp) && checkBu == 0)
      {
         bullStart = vh2;
         checkBu = 1;
         AddPattern(true, ih1, ih2, ih3, ih4, ih5, vh1, vh2, vh3, vh4, vh5, atr[bar], time[bar]);

         const int bufPos = (int)iBarShift(_Symbol, _Period, time[bar]);
         if(bufPos >= 0)
            g_bullBuf[bufPos] = vh1;
      }

      if(bullStart != vh2)
         checkBu = 0;
   }

   DrawPatterns(time, bars);
}

//+------------------------------------------------------------------+
void UpdateSwingArray(const bool highPivot,
                      const bool lowPivot,
                      const double highValue,
                      const double lowValue,
                      const int highIndex,
                      const int lowIndex,
                      const double closePrice)
{
   const double highPx = highValue;
   const double lowPx  = lowValue;

   if(highPivot && lowPivot)
   {
      if(g_swingCount == 0)
         return;

      const string last = LastType();
      if(last == "L" || last == "LL")
      {
         if(lowPx < LastValue())
         {
            RemoveLastSwing();
            PushLow(lowValue, lowIndex);
         }
         else
            PushHigh(highValue, highIndex);
      }
      else if(last == "H" || last == "HH")
      {
         if(highPx > LastValue())
         {
            RemoveLastSwing();
            PushHigh(highValue, highIndex);
         }
         else
            PushLow(lowValue, lowIndex);
      }
      else if(last == "LH")
      {
         if(highPx < LastValue())
            PushLow(lowValue, lowIndex);
         else if(highPx > LastValue())
         {
            if(closePrice < LastValue())
            {
               RemoveLastSwing();
               PushHigh(highValue, highIndex);
            }
            else if(closePrice > LastValue())
               PushLow(lowValue, lowIndex);
         }
      }
      else if(last == "HL")
      {
         if(lowPx > LastValue())
            PushHigh(highValue, highIndex);
         else if(lowPx < LastValue())
         {
            if(closePrice > LastValue())
            {
               RemoveLastSwing();
               PushLow(lowValue, lowIndex);
            }
            else if(closePrice < LastValue())
               PushHigh(highValue, highIndex);
         }
      }
      return;
   }

   if(highPivot)
   {
      if(g_swingCount == 0)
      {
         PushSwing("H", highValue, highIndex);
         return;
      }

      const string last = LastType();
      if(last == "L" || last == "HL" || last == "LL")
      {
         if(highPx > LastValue())
            PushHigh(highValue, highIndex);
         else if(highPx < LastValue())
         {
            RemoveLastSwing();
            PushLow(lowValue, lowIndex);
         }
      }
      else if(last == "H" || last == "HH" || last == "LH")
      {
         if(LastValue() < highValue)
         {
            RemoveLastSwing();
            PushHigh(highValue, highIndex);
         }
      }
      return;
   }

   if(lowPivot)
   {
      if(g_swingCount == 0)
      {
         PushSwing("L", lowValue, lowIndex);
         return;
      }

      const string last = LastType();
      if(last == "H" || last == "HH" || last == "LH")
      {
         if(lowPx < LastValue())
            PushLow(lowValue, lowIndex);
         else if(lowPx > LastValue())
         {
            RemoveLastSwing();
            PushHigh(highValue, highIndex);
         }
      }
      else if(last == "L" || last == "HL" || last == "LL")
      {
         if(LastValue() > lowValue)
         {
            RemoveLastSwing();
            PushLow(lowValue, lowIndex);
         }
      }
   }
}

//+------------------------------------------------------------------+
datetime BarTime(const datetime &time[], const int bars, const int index)
{
   if(index < 0)
      return time[0];
   if(index < bars)
      return time[index];

   int sec = (int)PeriodSeconds();
   if(sec <= 0)
      sec = 60;
   return time[bars - 1] + (datetime)(sec * (index - (bars - 1)));
}

//+------------------------------------------------------------------+
string PatternSignature()
{
   string sig = IntegerToString(g_patternCount);
   for(int i = 0; i < g_patternCount; i++)
   {
      sig += "|";
      sig += (g_patterns[i].isBull ? "B" : "S");
      sig += IntegerToString((long)g_patterns[i].confirmTime);
      sig += IntegerToString(g_patterns[i].i1);
   }
   return sig;
}

//+------------------------------------------------------------------+
void DrawPatterns(const datetime &time[], const int bars)
{
   const string sig = PatternSignature();
   if(sig == g_lastSignature)
      return;

   ObjectsDeleteAll(0, PREFIX);
   g_lastSignature = sig;

   for(int i = 0; i < g_patternCount; i++)
      DrawOnePattern(g_patterns[i], time, bars, i);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void DrawOnePattern(const QMPattern &p, const datetime &time[], const int bars, const int id)
{
   const int move = (int)MathRound((p.i2 - p.i4) / 2.0);
   const datetime t5 = BarTime(time, bars, p.i5);
   const datetime t4 = BarTime(time, bars, p.i4);
   const datetime t3 = BarTime(time, bars, p.i3);
   const datetime t2 = BarTime(time, bars, p.i2);
   const datetime t1 = BarTime(time, bars, p.i1);
   const datetime tArrow = BarTime(time, bars, p.i1 + move - 2);
   const datetime tEnd   = BarTime(time, bars, p.i1 + move);
   const datetime tLbl   = BarTime(time, bars, p.i1 + move + 1);

   const color legClr   = p.isBull ? InpBullColor : InpBearColor;
   const color arrowClr = p.isBull ? InpBullArrow : InpBearArrow;
   const string tag     = PREFIX + (p.isBull ? "BU" : "BE") + IntegerToString(id) + "_";

   CreateTrend(tag + "L1", t5, p.v5, t4, p.v4, legClr, InpLegWidth, STYLE_SOLID, false);
   CreateTrend(tag + "L2", t4, p.v4, t3, p.v3, legClr, InpLegWidth, STYLE_SOLID, false);
   CreateTrend(tag + "L3", t3, p.v3, t2, p.v2, legClr, InpLegWidth, STYLE_SOLID, false);
   CreateTrend(tag + "L4", t2, p.v2, t1, p.v1, legClr, InpLegWidth, STYLE_SOLID, false);
   CreateArrow(tag + "L5", t1, p.v1, tArrow, p.v4, arrowClr, InpLegWidth);

   const double sl = p.isBull ? (p.v2 - p.atr / 2.0) : (p.v2 + p.atr / 2.0);
   CreateTrend(tag + "EN", t4, p.v4, tEnd, p.v4, InpEntryColor, InpGuideWidth, STYLE_DOT, false);
   CreateTrend(tag + "SL", t2, sl, tEnd, sl, InpSLColor, InpGuideWidth, STYLE_DOT, false);
   CreateTrend(tag + "T1", t3, p.v3, tEnd, p.v3, InpTPColor, InpGuideWidth, STYLE_DOT, false);
   CreateTrend(tag + "T2", t1, p.v1, tEnd, p.v1, InpTPColor, InpGuideWidth, STYLE_DOT, false);

   CreateText(tag + "LE", tLbl, p.v4, "Entry");
   CreateText(tag + "LS", tLbl, sl, "SL");
   CreateText(tag + "LP1", tLbl, p.v3, "TP1");
   CreateText(tag + "LP2", tLbl, p.v1, "TP2");
}

//+------------------------------------------------------------------+
void CreateTrend(const string name,
                 const datetime t1, const double p1,
                 const datetime t2, const double p2,
                 const color clr, const int width,
                 const ENUM_LINE_STYLE style,
                 const bool ray)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);

   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, ray);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
void CreateArrow(const string name,
                 const datetime t1, const double p1,
                 const datetime t2, const double p2,
                 const color clr, const int width)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROWED_LINE, 0, t1, p1, t2, p2);

   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
void CreateText(const string name, const datetime t, const double price, const string text)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);

   ObjectMove(0, name, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpLabelColor);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}
//+------------------------------------------------------------------+
