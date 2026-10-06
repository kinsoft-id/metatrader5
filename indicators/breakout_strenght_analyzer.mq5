#property copyright "Breakout Strength Analyzer"
#property version   "1.00"
#property description "Scores breakout candles: body/ATR, upper wick, ATR expansion, consecutive bodies."
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   3

#property indicator_label1  "Open;High;Low;Close"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  clrLimeGreen,clrRed,clrDodgerBlue,clrDimGray
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Strong Bullish"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLimeGreen
#property indicator_width2  1

#property indicator_label3  "Strong Bearish"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  1

input group "Breakout Strength"
input int    InpAtrPeriod      = 14;   // ATR Period
input double InpBodyThreshold  = 1.0;  // Min Body / ATR Ratio
input double InpWickMaxRatio   = 1.5;  // Max Upper Wick / Body Ratio
input double InpAtrExpPct      = 5.0;  // ATR Expansion % vs Previous
input int    InpConsecRequired = 2;    // Consecutive Strong Candles Required
input bool   InpShowScore       = true; // Show Score on Candles
input bool   InpAlertScore      = true; // Alert when Score is 2 or 3

double openBuf[];
double highBuf[];
double lowBuf[];
double closeBuf[];
double colorBuf[];
double bullBuf[];
double bearBuf[];
double atrBuf[];

int      atrHandle = INVALID_HANDLE;
datetime g_lastAlertBar = 0;

//+------------------------------------------------------------------+
string Prefix()
{
   return "BSA_" + IntegerToString(ChartID()) + "_";
}

//+------------------------------------------------------------------+
int ConsecRequired()
{
   return (int)MathMax(1, MathMin(5, InpConsecRequired));
}

//+------------------------------------------------------------------+
#define PANEL_FONT 8

int g_colW[3] = {188, 92, 76};

//+------------------------------------------------------------------+
int TextWidthPx(const string text)
{
   int chars = MathMax(1, StringLen(text));
   uint w = 0, h = 0;
   if(!TextSetFont("Arial", -(PANEL_FONT * 10), FW_NORMAL) || !TextGetSize(text, w, h))
      return chars * (PANEL_FONT - 1);

   int width = (int)w;
   if(width > chars * PANEL_FONT * 3)
      width /= 10;
   return MathMax(width, 1);
}

//+------------------------------------------------------------------+
int ColWidth(const int col)
{
   return g_colW[col];
}

//+------------------------------------------------------------------+
// Jarak tepi kiri panel dari tepi kiri chart.
int PanelLeft()
{
   return 16;
}

//+------------------------------------------------------------------+
int PanelBottom()
{
   return 16;
}

//+------------------------------------------------------------------+
int RowHeight()
{
   return 22;
}

//+------------------------------------------------------------------+
int ColLeftEdge(const int col)
{
   int x = PanelLeft();
   for(int c = 0; c < col; c++)
      x += ColWidth(c) + 4;
   return x;
}

//+------------------------------------------------------------------+
int RowTop(const int row)
{
   return PanelBottom() + (6 - row) * RowHeight();
}

//+------------------------------------------------------------------+
void PlaceRect(const string name, const int leftFromLeft, const int topFromBottom,
               const int width, const int height)
{
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, leftFromLeft);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, topFromBottom);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
void LayoutPanel()
{
   const int pad = 4;
   const int gaps = 4 * 2;
   const int tableW = ColWidth(0) + ColWidth(1) + ColWidth(2) + gaps;
   const int tableH = RowHeight() * 6;
   const string frame = Prefix() + "P_FRAME";

   PlaceRect(frame,
             PanelLeft() - pad,
             PanelBottom() + tableH + pad,
             tableW + pad * 2,
             tableH + pad * 2);

   for(int row = 0; row < 6; row++)
   {
      for(int col = 0; col < 3; col++)
      {
         string rect = Prefix() + "P_R" + IntegerToString(row) + "_" + IntegerToString(col);
         string text = Prefix() + "P_T" + IntegerToString(row) + "_" + IntegerToString(col);
         int left = ColLeftEdge(col);
         int top  = RowTop(row);

         PlaceRect(rect, left, top, ColWidth(col), RowHeight());
         ObjectSetInteger(0, text, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, text, OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(0, text, OBJPROP_XDISTANCE, left + 8);
         ObjectSetInteger(0, text, OBJPROP_YDISTANCE, top - RowHeight() / 2);
      }
   }
}

//+------------------------------------------------------------------+
void CreatePanel()
{
   const string frame = Prefix() + "P_FRAME";
   if(ObjectFind(0, frame) < 0)
      ObjectCreate(0, frame, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, frame, OBJPROP_BGCOLOR, C'16,16,16');
   ObjectSetInteger(0, frame, OBJPROP_COLOR, C'90,90,90');
   ObjectSetInteger(0, frame, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, frame, OBJPROP_ZORDER, 0);

   for(int row = 0; row < 6; row++)
   {
      for(int col = 0; col < 3; col++)
      {
         string rect = Prefix() + "P_R" + IntegerToString(row) + "_" + IntegerToString(col);
         string text = Prefix() + "P_T" + IntegerToString(row) + "_" + IntegerToString(col);

         if(ObjectFind(0, rect) < 0)
            ObjectCreate(0, rect, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         if(ObjectFind(0, text) < 0)
            ObjectCreate(0, text, OBJ_LABEL, 0, 0, 0);

         ObjectSetInteger(0, rect, OBJPROP_BGCOLOR, C'28,28,28');
         ObjectSetInteger(0, rect, OBJPROP_COLOR, C'28,28,28');
         ObjectSetInteger(0, rect, OBJPROP_ZORDER, 1);

         ObjectSetString(0, text, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, text, OBJPROP_FONTSIZE, PANEL_FONT);
         ObjectSetInteger(0, text, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, text, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, text, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, text, OBJPROP_BACK, false);
         ObjectSetInteger(0, text, OBJPROP_ZORDER, 2);
      }
   }

   LayoutPanel();
}

//+------------------------------------------------------------------+
void FitColumns(const string &cells[])
{
   for(int col = 0; col < 3; col++)
   {
      int widest = 36;
      for(int row = 0; row < 6; row++)
      {
         int w = TextWidthPx(cells[row * 3 + col]);
         if(w > widest)
            widest = w;
      }
      g_colW[col] = widest + 20;
   }
}

//+------------------------------------------------------------------+
void SetCell(const int row, const int col, const string value, const color textColor, const color bg)
{
   string rect = Prefix() + "P_R" + IntegerToString(row) + "_" + IntegerToString(col);
   string text = Prefix() + "P_T" + IntegerToString(row) + "_" + IntegerToString(col);
   ObjectSetString(0, text, OBJPROP_TEXT, value);
   ObjectSetInteger(0, text, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, rect, OBJPROP_BGCOLOR, bg);
}

//+------------------------------------------------------------------+
void UpdatePanel(const double bodyRatio, const bool ruleBody,
                 const double wickRatio, const bool ruleWick,
                 const double atrExp, const bool ruleAtr,
                 const int consec, const bool ruleConsec,
                 const int score)
{
   const color headerBg = C'70,70,70';
   const color cellBg   = C'20,20,20';
   const color passBg   = C'24,120,48';
   const color failBg   = C'150,42,42';
   const color weakBg   = C'90,90,90';
   const int need = ConsecRequired();

   string cells[18];
   color  textClr[18];
   color  bgClr[18];

   cells[0] = "RULE";   textClr[0] = clrWhite; bgClr[0] = headerBg;
   cells[1] = "VALUE";  textClr[1] = clrWhite; bgClr[1] = headerBg;
   cells[2] = "RESULT"; textClr[2] = clrWhite; bgClr[2] = headerBg;

   cells[3] = StringFormat("Body >= %sx ATR", DoubleToString(InpBodyThreshold, 1));
   cells[4] = DoubleToString(bodyRatio, 2) + "x";
   cells[5] = ruleBody ? "PASS" : "FAIL";
   textClr[3] = clrWhite;  bgClr[3] = cellBg;
   textClr[4] = clrYellow; bgClr[4] = cellBg;
   textClr[5] = clrWhite;  bgClr[5] = ruleBody ? passBg : failBg;

   cells[6] = StringFormat("Wick <= %sx Body", DoubleToString(InpWickMaxRatio, 1));
   cells[7] = DoubleToString(wickRatio, 2) + "x";
   cells[8] = ruleWick ? "PASS" : "FAIL";
   textClr[6] = clrWhite;  bgClr[6] = cellBg;
   textClr[7] = clrYellow; bgClr[7] = cellBg;
   textClr[8] = clrWhite;  bgClr[8] = ruleWick ? passBg : failBg;

   cells[9]  = StringFormat("ATR Exp >= %s%%", DoubleToString(InpAtrExpPct, 1));
   cells[10] = DoubleToString(atrExp, 2) + "%";
   cells[11] = ruleAtr ? "PASS" : "FAIL";
   textClr[9]  = clrWhite;  bgClr[9]  = cellBg;
   textClr[10] = clrYellow; bgClr[10] = cellBg;
   textClr[11] = clrWhite;  bgClr[11] = ruleAtr ? passBg : failBg;

   cells[12] = StringFormat("Consecutive >= %d", need);
   cells[13] = IntegerToString(consec) + " candles";
   cells[14] = ruleConsec ? "PASS" : "FAIL";
   textClr[12] = clrWhite;  bgClr[12] = cellBg;
   textClr[13] = clrYellow; bgClr[13] = cellBg;
   textClr[14] = clrWhite;  bgClr[14] = ruleConsec ? passBg : failBg;

   color scoreBg = (score >= 3) ? passBg : (score == 2 ? weakBg : failBg);
   cells[15] = "SCORE";
   cells[16] = IntegerToString(score) + " / 4";
   cells[17] = (score >= 3) ? "STRONG" : (score == 2 ? "WEAK" : "FAKE");
   textClr[15] = clrWhite;  bgClr[15] = headerBg;
   textClr[16] = clrYellow; bgClr[16] = headerBg;
   textClr[17] = clrWhite;  bgClr[17] = scoreBg;

   FitColumns(cells);
   for(int i = 0; i < 18; i++)
      SetCell(i / 3, i % 3, cells[i], textClr[i], bgClr[i]);
   LayoutPanel();
}

//+------------------------------------------------------------------+
void SyncLabel(const datetime barTime, const bool show, const double price,
               const string text, const color clr)
{
   const string name = Prefix() + "L_" + IntegerToString((long)barTime);
   if(!show)
   {
      ObjectDelete(0, name);
      return;
   }

   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, barTime, price))
         return;
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LOWER);
   }

   ObjectSetInteger(0, name, OBJPROP_TIME, 0, barTime);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpAtrPeriod < 1)
      return(INIT_PARAMETERS_INCORRECT);

   SetIndexBuffer(0, openBuf, INDICATOR_DATA);
   SetIndexBuffer(1, highBuf, INDICATOR_DATA);
   SetIndexBuffer(2, lowBuf, INDICATOR_DATA);
   SetIndexBuffer(3, closeBuf, INDICATOR_DATA);
   SetIndexBuffer(4, colorBuf, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(5, bullBuf, INDICATOR_DATA);
   SetIndexBuffer(6, bearBuf, INDICATOR_DATA);

   ArraySetAsSeries(openBuf, true);
   ArraySetAsSeries(highBuf, true);
   ArraySetAsSeries(lowBuf, true);
   ArraySetAsSeries(closeBuf, true);
   ArraySetAsSeries(colorBuf, true);
   ArraySetAsSeries(bullBuf, true);
   ArraySetAsSeries(bearBuf, true);

   PlotIndexSetInteger(1, PLOT_ARROW, 241);
   PlotIndexSetInteger(2, PLOT_ARROW, 242);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpAtrPeriod + 1);

   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   if(atrHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   IndicatorSetString(INDICATOR_SHORTNAME, "Breakout Strength");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   g_lastAlertBar = 0;
   CreatePanel();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
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
   if(rates_total < InpAtrPeriod + 2)
      return(0);

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(openBuf, true);
   ArraySetAsSeries(highBuf, true);
   ArraySetAsSeries(lowBuf, true);
   ArraySetAsSeries(closeBuf, true);
   ArraySetAsSeries(colorBuf, true);
   ArraySetAsSeries(bullBuf, true);
   ArraySetAsSeries(bearBuf, true);
   ArraySetAsSeries(atrBuf, true);

   int copied = CopyBuffer(atrHandle, 0, 0, rates_total, atrBuf);
   if(copied < 2)
      return(0);

   if(prev_calculated == 0)
      ObjectsDeleteAll(0, Prefix() + "L_");

   const int need = ConsecRequired();
   const bool refreshAll = (prev_calculated == 0);
   int consec = 0;

   double panelBody = 0.0;
   double panelWick = 0.0;
   double panelExp  = 0.0;
   int    panelConsec = 0;
   int    panelScore  = 0;
   bool   panelBodyPass = false;
   bool   panelWickPass = false;
   bool   panelAtrPass  = false;
   bool   panelConsecPass = false;
   int    closedScore = 0;
   bool   closedBullish = false;
   datetime closedTime = 0;

   for(int i = rates_total - 1; i >= 0; i--)
   {
      openBuf[i]  = open[i];
      highBuf[i]  = high[i];
      lowBuf[i]   = low[i];
      closeBuf[i] = close[i];
      colorBuf[i] = 3;
      bullBuf[i]  = EMPTY_VALUE;
      bearBuf[i]  = EMPTY_VALUE;

      if(i >= copied)
         continue;

      double atr = atrBuf[i];
      double atrPrev = (i + 1 < copied) ? atrBuf[i + 1] : 0.0;
      double body = MathAbs(close[i] - open[i]);
      double upperWick = high[i] - MathMax(close[i], open[i]);
      bool bullish = (close[i] > open[i]);

      double bodyRatio = (atr > 0.0) ? body / atr : 0.0;
      bool ruleBody = (atr > 0.0 && bodyRatio >= InpBodyThreshold);

      double wickRatio = upperWick / MathMax(body, 0.0001);
      bool ruleWick = (wickRatio <= InpWickMaxRatio);

      double atrExp = 0.0;
      bool ruleAtr = false;
      if(atrPrev > 0.0)
      {
         atrExp = (atr - atrPrev) / atrPrev * 100.0;
         ruleAtr = (atrExp >= InpAtrExpPct);
      }

      consec = ruleBody ? consec + 1 : 0;
      bool ruleConsec = (consec >= need);

      int score = (ruleBody ? 1 : 0) + (ruleWick ? 1 : 0) + (ruleAtr ? 1 : 0) + (ruleConsec ? 1 : 0);
      bool strong = (score >= 3);

      if(strong && bullish)
         colorBuf[i] = 0;
      else if(strong && !bullish)
         colorBuf[i] = 1;
      else if(ruleBody)
         colorBuf[i] = 2;

      double gap = (atr > 0.0) ? atr * 0.25 : 10.0 * _Point;
      if(strong && bullish)
         bullBuf[i] = low[i] - gap;
      else if(strong && !bullish)
         bearBuf[i] = high[i] + gap;

      if(refreshAll || i <= 1)
      {
         bool show = InpShowScore && ruleBody;
         color labelClr = strong ? clrGreen : clrDodgerBlue;
         double labelPrice = high[i] + ((atr > 0.0) ? atr * 0.3 : 10.0 * _Point);
         SyncLabel(time[i], show, labelPrice, IntegerToString(score), labelClr);
      }

      if(i == 0)
      {
         panelBody = bodyRatio;
         panelWick = wickRatio;
         panelExp = atrExp;
         panelConsec = consec;
         panelScore = score;
         panelBodyPass = ruleBody;
         panelWickPass = ruleWick;
         panelAtrPass = ruleAtr;
         panelConsecPass = ruleConsec;
      }

      if(i == 1)
      {
         closedScore = score;
         closedBullish = bullish;
         closedTime = time[i];
      }
   }

   if(prev_calculated == 0)
   {
      if(closedTime > 0)
         g_lastAlertBar = closedTime;
   }
   else if(InpAlertScore && closedTime > 0 && closedTime != g_lastAlertBar)
   {
      g_lastAlertBar = closedTime;
      if(closedScore == 2 || closedScore == 3)
      {
         string tf = EnumToString((ENUM_TIMEFRAMES)_Period);
         StringReplace(tf, "PERIOD_", "");
         Alert(StringFormat("Breakout Strength %s %s score %d %s",
                            _Symbol, tf, closedScore,
                            closedBullish ? "Bullish" : "Bearish"));
      }
   }

   UpdatePanel(panelBody, panelBodyPass,
               panelWick, panelWickPass,
               panelExp, panelAtrPass,
               panelConsec, panelConsecPass,
               panelScore);
   ChartRedraw(0);
   return(rates_total);
}
