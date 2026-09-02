#property copyright "Converted from Breaker Blocks with Signals [LuxAlgo] — CC BY-NC-SA 4.0"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots   0
#property indicator_buffers 8

//+------------------------------------------------------------------+
//| Buffers (iCustom shift 0 = bar terakhir)                         |
//| 0 +BB  1 signal UP  2 cancel UP  3 +BB mitigated                 |
//| 4 -BB  5 signal DN  6 cancel DN  7 -BB mitigated                 |
//+------------------------------------------------------------------+
double g_bufBBPlus[];
double g_bufSignUP[];
double g_bufCnclUP[];
double g_bufEndBl[];
double g_bufBBMinus[];
double g_bufSignDN[];
double g_bufCnclDN[];
double g_bufEndBr[];

input group "Market Structure"
input int    InpLength               = 5;       // Length (pivot kiri)
input int    InpLookback             = 2000;    // Max bars
input bool   InpShowZZ               = false;   // Tampilkan ZigZag

input group "Breaker Block"
input bool   InpOnlyBody             = false;   // Use only candle body
input bool   InpTwoCandles           = false;   // Use 2 candles instead of 1
input bool   InpTillFirstBreak       = true;    // Stop at first break of center line

input group "PD array"
input bool   InpOnlyWhenInPD         = false;   // Only when E is in Premium/Discount Array
input bool   InpShowPDarray          = false;   // Show Premium/Discount Zone
input bool   InpShowBreaks           = false;   // Highlight Swing Breaks
input bool   InpShowSPD              = true;    // Show Swings/PD Arrays
input color  InpPDtxtColor           = clrSilver; // Text Color
input color  InpPDSwingColor         = clrSilver; // Swing Line Color

input group "TP"
input bool   InpEnableTP             = false;   // Enable TP
input color  InpTPColor              = C'33,87,243';
input double InpR1a                  = 1.0;     // R:R 1
input double InpR2a                  = 2.0;
input double InpR1b                  = 1.0;     // R:R 2
input double InpR2b                  = 3.0;
input double InpR1c                  = 1.0;     // R:R 3
input double InpR2c                  = 4.0;

input group "Colours +BB / Last Swings"
input color  InpBBPlusA              = C'12,181,26';
input color  InpBBPlusB              = C'12,181,26';
input color  InpSwingBl              = C'255,82,82';

input group "Colours -BB / Last Swings"
input color  InpBBMinusA             = C'255,17,0';
input color  InpBBMinusB             = C'255,17,0';
input color  InpSwingBr              = C'0,137,123';

input group "Alerts"
input bool   InpAlerts               = false;   // Enable Alert()

#define PREFIX   "BBWS_"
#define ZZ_SIZE  50
#define LAB_MAX  256

#define BUF_BBPLUS  0
#define BUF_SIGNUP  1
#define BUF_CNCLUP  2
#define BUF_ENDBL   3
#define BUF_BBMINUS 4
#define BUF_SIGNDN  5
#define BUF_CNCLDN  6
#define BUF_ENDBR   7

#define LAB_UP      0
#define LAB_DN      1
#define LAB_CIRCLE  2
#define LAB_X       3
#define LAB_TEXT    4

struct ZZPoint
{
   int      dir;
   int      idx;
   datetime time;
   double   price;
};

struct SigLabel
{
   datetime t;
   double   price;
   string   text;
   color    clr;
   int      kind;
   int      fs;
};

struct BlockState
{
   int      dir;
   bool     broken;
   bool     mitigated;
   bool     scalp;
   bool     tp1_hit;
   bool     tp2_hit;
   bool     tp3_hit;
   bool     broken1;
   bool     broken2;
   bool     pdBroken1;
   bool     pdBroken2;
   bool     hasSwings;
   bool     hasPD1;
   bool     hasPD2;
   bool     hasPDzone;
   int      createdIdx;

   datetime boxA_left;
   datetime boxA_right;
   datetime boxB_left;
   datetime boxB_right;
   double   top;
   double   bottom;
   double   avg;

   datetime sw1_t1;
   datetime sw1_t2;
   datetime sw2_t1;
   datetime sw2_t2;
   double   sw1_y;
   double   sw2_y;

   datetime pd1_left;
   datetime pd1_right;
   datetime pd2_left;
   datetime pd2_right;
   double   pd1_top;
   double   pd1_bottom;
   double   pd2_top;
   double   pd2_bottom;

   datetime pda_left;
   datetime pda_right;
   double   pda_top;
   double   pda_mid;
   double   pda_bottom;
   bool     pdaDiscountOnBottom;

   datetime hl_time;
   double   hl_price;
   string   hl_text;

   double   tp1;
   double   tp2;
   double   tp3;
   bool     hasTP;
};

ZZPoint    g_zz[ZZ_SIZE];
int        g_zzCount;
int        g_mssDir;
BlockState g_bb;
SigLabel   g_labels[LAB_MAX];
int        g_labelCount;
int        g_drawnLabels;
int        g_drawnZZ;

datetime   g_alertTime[];

double BodyHigh(const int i, const double &open[], const double &close[])
{
   return MathMax(open[i], close[i]);
}

double BodyLow(const int i, const double &open[], const double &close[])
{
   return MathMin(open[i], close[i]);
}

int ClampLength()
{
   int v = InpLength;
   if(v < 1)  v = 1;
   if(v > 10) v = 10;
   return v;
}

int ClampLookback()
{
   int v = InpLookback;
   if(v < 200) v = 200;
   return v;
}

double Ratio(const double r1, const double r2)
{
   if(r1 == 0.0)
      return r2;
   return r2 / r1;
}

datetime TimeShift(const datetime &time[], const int idx, const int rates_total, const int barsAhead)
{
   const int t = idx + barsAhead;
   if(t >= 0 && t < rates_total)
      return time[t];
   int sec = PeriodSeconds();
   if(sec <= 0)
      sec = 60;
   if(idx >= 0 && idx < rates_total)
      return time[idx] + (datetime)(barsAhead * (long)sec);
   return 0;
}

bool IsPivotHigh(const int pivot, const int left, const int right,
                 const double &high[], const int lastBar)
{
   if(pivot < left || pivot + right > lastBar)
      return false;
   const double v = high[pivot];
   for(int k = pivot - left; k <= pivot + right; k++)
   {
      if(k == pivot)
         continue;
      if(high[k] >= v)
         return false;
   }
   return true;
}

bool IsPivotLow(const int pivot, const int left, const int right,
                const double &low[], const int lastBar)
{
   if(pivot < left || pivot + right > lastBar)
      return false;
   const double v = low[pivot];
   for(int k = pivot - left; k <= pivot + right; k++)
   {
      if(k == pivot)
         continue;
      if(low[k] <= v)
         return false;
   }
   return true;
}

int ZZDir(const int idx)
{
   if(idx < 0 || idx >= g_zzCount)
      return 0;
   return g_zz[idx].dir;
}

double ZZPrice(const int idx)
{
   if(idx < 0 || idx >= g_zzCount)
      return 0.0;
   return g_zz[idx].price;
}

int ZZIdx(const int idx)
{
   if(idx < 0 || idx >= g_zzCount)
      return 0;
   return g_zz[idx].idx;
}

datetime ZZTime(const int idx)
{
   if(idx < 0 || idx >= g_zzCount)
      return 0;
   return g_zz[idx].time;
}

void ZZUnshift(const int dir, const int idx, const datetime t, const double price)
{
   const int n = MathMin(g_zzCount, ZZ_SIZE - 1);
   for(int i = n; i > 0; i--)
      g_zz[i] = g_zz[i - 1];
   g_zz[0].dir   = dir;
   g_zz[0].idx   = idx;
   g_zz[0].time  = t;
   g_zz[0].price = price;
   if(g_zzCount < ZZ_SIZE)
      g_zzCount++;
}

void ResetBlock()
{
   ZeroMemory(g_bb);
}

void ClearLabels()
{
   g_labelCount = 0;
}

void AddLabel(const datetime t, const double price, const string text,
              const color clr, const int kind, const int fs)
{
   if(g_labelCount >= LAB_MAX)
      return;
   g_labels[g_labelCount].t     = t;
   g_labels[g_labelCount].price = price;
   g_labels[g_labelCount].text  = text;
   g_labels[g_labelCount].clr   = clr;
   g_labels[g_labelCount].kind  = kind;
   g_labels[g_labelCount].fs    = fs;
   g_labelCount++;
}

void SetBuf(double &buf[], const int i, const double v)
{
   buf[i] = v;
}

void TryAlert(const int id, const datetime barTime, const int n, const int rates_total, const string msg)
{
   if(!InpAlerts)
      return;
   if(n < rates_total - 2)
      return;
   if(id < 0 || id >= ArraySize(g_alertTime))
      return;
   if(g_alertTime[id] == barTime)
      return;
   g_alertTime[id] = barTime;
   Alert(_Symbol, " ", EnumToString(_Period), " ", msg);
}

void StyleObject(const string name, const bool back)
{
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, back);
}

void EnsureRect(const string name, const datetime t1, const double p1,
                const datetime t2, const double p2, const color clr, const bool back)
{
   if(t1 <= 0 || t2 <= 0)
      return;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      StyleObject(name, back);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, back);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void EnsureTrend(const string name, const datetime t1, const double p1,
                 const datetime t2, const double p2, const color clr,
                 const ENUM_LINE_STYLE style, const int width)
{
   if(t1 <= 0 || t2 <= 0)
      return;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      StyleObject(name, true);
   }
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void EnsureText(const string name, const datetime t, const double price,
                const string text, const color clr, const int fs,
                const ENUM_ANCHOR_POINT anchor)
{
   if(t <= 0 || text == "")
      return;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      StyleObject(name, false);
   }
   ObjectMove(0, name, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void EnsureArrow(const string name, const datetime t, const double price,
                 const int code, const color clr, const int width,
                 const ENUM_ARROW_ANCHOR anchor)
{
   if(t <= 0)
      return;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
      StyleObject(name, false);
   }
   ObjectMove(0, name, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void HideObj(const string name)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

void UpdateZigZag(const int n, const int left, const datetime &time[],
                  const double &high[], const double &low[])
{
   const int pivot = n - 1;
   if(pivot < left)
      return;

   if(IsPivotHigh(pivot, left, 1, high, n))
   {
      const int dir = ZZDir(0);
      if(dir < 1)
         ZZUnshift(1, pivot, time[pivot], high[pivot]);
      else if(dir == 1 && high[pivot] > g_zz[0].price)
      {
         g_zz[0].idx   = pivot;
         g_zz[0].time  = time[pivot];
         g_zz[0].price = high[pivot];
      }
   }

   if(IsPivotLow(pivot, left, 1, low, n))
   {
      const int dir = ZZDir(0);
      if(dir > -1)
         ZZUnshift(-1, pivot, time[pivot], low[pivot]);
      else if(dir == -1 && low[pivot] < g_zz[0].price)
      {
         g_zz[0].idx   = pivot;
         g_zz[0].time  = time[pivot];
         g_zz[0].price = low[pivot];
      }
   }
}

void FillCandleRange(const int j, const bool onlyBody,
                     const double &open[], const double &high[],
                     const double &low[], const double &close[],
                     double &top, double &bottom)
{
   if(onlyBody)
   {
      top    = BodyHigh(j, open, close);
      bottom = BodyLow(j, open, close);
   }
   else
   {
      top    = high[j];
      bottom = low[j];
   }
}

bool CombineSecondCandle(const int j, const bool bull, const bool onlyBody,
                         const double &open[], const double &high[],
                         const double &low[], const double &close[],
                         int &idx, double &top, double &bottom)
{
   const int older = j - 1;
   if(older < 0)
      return false;
   const bool sameDir = bull ? (close[older] > open[older]) : (close[older] < open[older]);
   if(!sameDir)
      return false;

   double t2, b2;
   FillCandleRange(older, onlyBody, open, high, low, close, t2, b2);
   if(t2 > top || b2 < bottom)
      idx = older;
   top    = MathMax(top, t2);
   bottom = MathMin(bottom, b2);
   return true;
}

void CreateBullishBB(const int n, const int rates_total,
                     const datetime &time[], const double &open[],
                     const double &high[], const double &low[], const double &close[],
                     const int greenIdx, const double greenTop, const double greenBot,
                     const int Ax, const int Ex, const double AyMn, const double mid, const double yMax,
                     const int Cx, const double Cy, const double Ey)
{
   ClearLabels();
   g_bb.dir        = 1;
   g_bb.createdIdx = n;
   g_bb.broken     = false;
   g_bb.mitigated  = false;
   g_bb.scalp      = false;
   g_bb.tp1_hit    = false;
   g_bb.tp2_hit    = false;
   g_bb.tp3_hit    = false;
   g_bb.broken1    = false;
   g_bb.broken2    = false;
   g_bb.pdBroken1  = false;
   g_bb.pdBroken2  = false;
   g_bb.hasPD1     = false;
   g_bb.hasPD2     = false;
   g_bb.hasPDzone  = false;

   g_bb.top        = greenTop;
   g_bb.bottom     = greenBot;
   g_bb.avg        = (greenTop + greenBot) / 2.0;
   g_bb.boxA_left  = time[greenIdx];
   g_bb.boxA_right = time[n];
   g_bb.boxB_left  = time[n];
   g_bb.boxB_right = TimeShift(time, n, rates_total, 8);

   g_bb.hasSwings  = InpShowSPD;
   if(InpShowSPD)
   {
      g_bb.sw1_t1   = time[Cx];
      g_bb.sw1_t2   = time[n];
      g_bb.sw1_y    = Cy;
      g_bb.sw2_t1   = time[Ex];
      g_bb.sw2_t2   = time[n];
      g_bb.sw2_y    = Ey;
      g_bb.hl_time  = time[Ex];
      g_bb.hl_price = Ey;
      g_bb.hl_text  = "LL";
   }

   if(InpOnlyWhenInPD && InpShowPDarray)
   {
      g_bb.hasPDzone          = true;
      g_bb.pda_left           = time[Ax];
      g_bb.pda_right          = TimeShift(time, Ex, rates_total, 1);
      g_bb.pda_top            = yMax;
      g_bb.pda_mid            = mid;
      g_bb.pda_bottom         = AyMn;
      g_bb.pdaDiscountOnBottom = true;
   }

   if(InpShowSPD)
   {
      int cnt = 0;
      double hh1 = high[n];
      for(int c = 0; c < g_zzCount - 1; c++)
      {
         const int getX = g_zz[c].idx;
         const double getY = g_zz[c].price;
         if(getY > hh1 && g_zz[c].dir == 1 && getX >= 0 && getX < rates_total)
         {
            const double getY2 = (high[getX] - BodyLow(getX, open, close)) / 4.0;
            if(cnt == 0)
            {
               g_bb.hasPD1      = true;
               g_bb.pd1_left    = g_zz[c].time;
               g_bb.pd1_right   = time[n];
               g_bb.pd1_top     = getY;
               g_bb.pd1_bottom  = getY - getY2;
               cnt = 1;
               hh1 = getY;
            }
            else if(cnt == 1)
            {
               if(getY - getY2 > hh1)
               {
                  g_bb.hasPD2     = true;
                  g_bb.pd2_left   = g_zz[c].time;
                  g_bb.pd2_right  = time[n];
                  g_bb.pd2_top    = getY;
                  g_bb.pd2_bottom = getY - getY2;
                  cnt = 2;
               }
            }
         }
         if(cnt == 2)
            break;
      }
   }

   const double I = greenTop - greenBot;
   g_bb.tp1   = greenTop + (I * Ratio(InpR1a, InpR2a));
   g_bb.tp2   = greenTop + (I * Ratio(InpR1b, InpR2b));
   g_bb.tp3   = greenTop + (I * Ratio(InpR1c, InpR2c));
   g_bb.hasTP = InpEnableTP;

   AddLabel(time[n], low[n], "▲", InpBBPlusB, LAB_UP, 16);
}

void CreateBearishBB(const int n, const int rates_total,
                     const datetime &time[], const double &open[],
                     const double &high[], const double &low[], const double &close[],
                     const int redIdx, const double redTop, const double redBot,
                     const int Ax, const int Ex, const double AyMx, const double mid, const double yMin,
                     const int Cx, const double Cy, const double Ey)
{
   ClearLabels();
   g_bb.dir        = -1;
   g_bb.createdIdx = n;
   g_bb.broken     = false;
   g_bb.mitigated  = false;
   g_bb.scalp      = false;
   g_bb.tp1_hit    = false;
   g_bb.tp2_hit    = false;
   g_bb.tp3_hit    = false;
   g_bb.broken1    = false;
   g_bb.broken2    = false;
   g_bb.pdBroken1  = false;
   g_bb.pdBroken2  = false;
   g_bb.hasPD1     = false;
   g_bb.hasPD2     = false;
   g_bb.hasPDzone  = false;

   g_bb.top        = redTop;
   g_bb.bottom     = redBot;
   g_bb.avg        = (redTop + redBot) / 2.0;
   g_bb.boxA_left  = time[redIdx];
   g_bb.boxA_right = time[n];
   g_bb.boxB_left  = time[n];
   g_bb.boxB_right = TimeShift(time, n, rates_total, 8);

   g_bb.hasSwings  = InpShowSPD;
   if(InpShowSPD)
   {
      g_bb.sw1_t1   = time[Cx];
      g_bb.sw1_t2   = time[n];
      g_bb.sw1_y    = Cy;
      g_bb.sw2_t1   = time[Ex];
      g_bb.sw2_t2   = time[n];
      g_bb.sw2_y    = Ey;
      g_bb.hl_time  = time[Ex];
      g_bb.hl_price = Ey;
      g_bb.hl_text  = "HH";
   }

   if(InpOnlyWhenInPD && InpShowPDarray)
   {
      g_bb.hasPDzone          = true;
      g_bb.pda_left           = time[Ax];
      g_bb.pda_right          = TimeShift(time, Ex, rates_total, 1);
      g_bb.pda_top            = AyMx;
      g_bb.pda_mid            = mid;
      g_bb.pda_bottom         = yMin;
      g_bb.pdaDiscountOnBottom = false;
   }

   if(InpShowSPD)
   {
      int cnt = 0;
      double ll1 = low[n];
      for(int c = 0; c < g_zzCount - 1; c++)
      {
         const int getX = g_zz[c].idx;
         const double getY = g_zz[c].price;
         if(getY < ll1 && g_zz[c].dir == -1 && getX >= 0 && getX < rates_total)
         {
            const double getY2 = (BodyHigh(getX, open, close) - low[getX]) / 4.0;
            if(cnt == 0)
            {
               g_bb.hasPD1     = true;
               g_bb.pd1_left   = g_zz[c].time;
               g_bb.pd1_right  = time[n];
               g_bb.pd1_top    = getY + getY2;
               g_bb.pd1_bottom = getY;
               cnt = 1;
               ll1 = getY;
            }
            else if(cnt == 1)
            {
               if(getY + getY2 < ll1)
               {
                  g_bb.hasPD2     = true;
                  g_bb.pd2_left   = g_zz[c].time;
                  g_bb.pd2_right  = time[n];
                  g_bb.pd2_top    = getY + getY2;
                  g_bb.pd2_bottom = getY;
                  cnt = 2;
               }
            }
         }
         if(cnt == 2)
            break;
      }
   }

   const double I = redTop - redBot;
   g_bb.tp1   = redBot - (I * Ratio(InpR1a, InpR2a));
   g_bb.tp2   = redBot - (I * Ratio(InpR1b, InpR2b));
   g_bb.tp3   = redBot - (I * Ratio(InpR1c, InpR2c));
   g_bb.hasTP = InpEnableTP;

   AddLabel(time[n], high[n], "▼", InpBBMinusB, LAB_DN, 16);
}

void TryCreateMSS(const int n, const int rates_total, const bool allowBB,
                  const datetime &time[], const double &open[],
                  const double &high[], const double &low[], const double &close[])
{
   const int iH = (ZZDir(2) == 1) ? 2 : 1;
   const int iL = (ZZDir(2) == -1) ? 2 : 1;

   if(allowBB &&
      iH >= 0 && iH + 3 < g_zzCount &&
      close[n] > ZZPrice(iH) && ZZDir(iH) == 1 && g_mssDir < 1)
   {
      const int    Ex   = ZZIdx(iH - 1);
      const double Ey   = ZZPrice(iH - 1);
      const int    Dx   = ZZIdx(iH);
      const int    Cx   = ZZIdx(iH + 1);
      const double Cy   = ZZPrice(iH + 1);
      const int    Bx   = ZZIdx(iH + 2);
      const int    Ax   = ZZIdx(iH + 3);
      const double Ay   = ZZPrice(iH + 3);

      if(Dx >= 0 && Dx < n && Cx >= 0 && Cx <= n && Bx >= 0 && Bx < n && Ax >= 0 && Ax < n && Ex >= 0 && Ex <= n)
      {
         const double DyMx = BodyHigh(Dx, open, close);
         const double ByMx = BodyHigh(Bx, open, close);
         const double AyMn = BodyLow(Ax, open, close);
         const double yMax = MathMax(ByMx, DyMx);
         const double mid  = AyMn + ((yMax - AyMn) / 2.0);
         const bool   isOK = InpOnlyWhenInPD ? (Ay < Cy && Ay < Ey && Ey < mid) : true;

         if(Ey < Cy && Cx != Dx && isOK)
         {
            for(int j = Dx; j >= Cx; j--)
            {
               if(close[j] > open[j])
               {
                  int greenIdx = j;
                  double greenTop, greenBot;
                  FillCandleRange(j, InpOnlyBody, open, high, low, close, greenTop, greenBot);
                  if(InpTwoCandles)
                     CombineSecondCandle(j, true, InpOnlyBody, open, high, low, close, greenIdx, greenTop, greenBot);

                  CreateBullishBB(n, rates_total, time, open, high, low, close,
                                  greenIdx, greenTop, greenBot,
                                  Ax, Ex, AyMn, mid, yMax, Cx, Cy, Ey);
                  SetBuf(g_bufBBPlus, n, 1.0);
                  TryAlert(BUF_BBPLUS, time[n], n, rates_total, "+BB");
                  break;
               }
            }
         }
      }
      g_mssDir = 1;
   }
   else if(allowBB &&
      iL >= 0 && iL + 3 < g_zzCount &&
      close[n] < ZZPrice(iL) && ZZDir(iL) == -1 && g_mssDir > -1)
   {
      const int    Ex   = ZZIdx(iL - 1);
      const double Ey   = ZZPrice(iL - 1);
      const int    Dx   = ZZIdx(iL);
      const int    Cx   = ZZIdx(iL + 1);
      const double Cy   = ZZPrice(iL + 1);
      const int    Bx   = ZZIdx(iL + 2);
      const int    Ax   = ZZIdx(iL + 3);
      const double Ay   = ZZPrice(iL + 3);

      if(Dx >= 0 && Dx < n && Cx >= 0 && Cx <= n && Bx >= 0 && Bx < n && Ax >= 0 && Ax < n && Ex >= 0 && Ex <= n)
      {
         const double DyMn = BodyLow(Dx, open, close);
         const double ByMn = BodyLow(Bx, open, close);
         const double AyMx = BodyHigh(Ax, open, close);
         const double yMin = MathMin(ByMn, DyMn);
         const double mid  = AyMx - ((AyMx - yMin) / 2.0);
         const bool   isOK = InpOnlyWhenInPD ? (Ay > Cy && Ay > Ey && Ey > mid) : true;

         if(Ey > Cy && Cx != Dx && isOK)
         {
            for(int j = Dx; j >= Cx; j--)
            {
               if(close[j] < open[j])
               {
                  int redIdx = j;
                  double redTop, redBot;
                  FillCandleRange(j, InpOnlyBody, open, high, low, close, redTop, redBot);
                  if(InpTwoCandles)
                     CombineSecondCandle(j, false, InpOnlyBody, open, high, low, close, redIdx, redTop, redBot);

                  CreateBearishBB(n, rates_total, time, open, high, low, close,
                                  redIdx, redTop, redBot,
                                  Ax, Ex, AyMx, mid, yMin, Cx, Cy, Ey);
                  SetBuf(g_bufBBMinus, n, 1.0);
                  TryAlert(BUF_BBMINUS, time[n], n, rates_total, "-BB");
                  break;
               }
            }
         }
      }
      g_mssDir = -1;
   }
}

void UpdateActiveBB(const int n, const int rates_total,
                    const datetime &time[], const double &open[],
                    const double &high[], const double &low[], const double &close[])
{
   if(g_bb.dir == 0)
      return;

   const datetime tNow  = time[n];
   const datetime tExt  = TimeShift(time, n, rates_total, 8);
   const double   top   = g_bb.top;
   const double   btm   = g_bb.bottom;
   const double   avg   = g_bb.avg;
   const bool     afterCreate = (n > g_bb.createdIdx);

   if(g_bb.dir == 1)
   {
      if(!g_bb.mitigated)
      {
         if(close[n] < btm)
         {
            g_bb.mitigated  = true;
            g_bb.boxB_right = tNow;
            SetBuf(g_bufEndBl, n, 1.0);
            TryAlert(BUF_ENDBL, tNow, n, rates_total, "+BB Mitigated");
            AddLabel(tNow, low[n], "●", clrYellow, LAB_CIRCLE, 8);
         }
         else
            g_bb.boxB_right = tExt;

         if(afterCreate)
         {
            if(!g_bb.broken)
            {
               if(g_bb.scalp && g_bb.hasTP)
               {
                  if(!g_bb.tp1_hit && open[n] < g_bb.tp1 && high[n] > g_bb.tp1)
                  {
                     g_bb.tp1_hit = true;
                     AddLabel(tNow, g_bb.tp1, "●", C'255,0,221', LAB_CIRCLE, 8);
                     TryAlert(10, tNow, n, rates_total, "TP UP 1");
                  }
                  if(!g_bb.tp2_hit && open[n] < g_bb.tp2 && high[n] > g_bb.tp2)
                  {
                     g_bb.tp2_hit = true;
                     AddLabel(tNow, g_bb.tp2, "●", C'255,0,221', LAB_CIRCLE, 8);
                     TryAlert(11, tNow, n, rates_total, "TP UP 2");
                  }
                  if(!g_bb.tp3_hit && open[n] < g_bb.tp3 && high[n] > g_bb.tp3)
                  {
                     g_bb.tp3_hit = true;
                     AddLabel(tNow, g_bb.tp3, "●", C'255,0,221', LAB_CIRCLE, 8);
                     TryAlert(12, tNow, n, rates_total, "TP UP 3");
                  }
               }

               if(open[n] > avg && open[n] < top && close[n] > top)
               {
                  g_bb.tp1_hit = false;
                  g_bb.tp2_hit = false;
                  g_bb.tp3_hit = false;
                  g_bb.scalp   = true;
                  SetBuf(g_bufSignUP, n, 1.0);
                  TryAlert(BUF_SIGNUP, tNow, n, rates_total, "signal UP");
                  AddLabel(tNow, low[n], "▲", clrLime, LAB_UP, 12);
               }
               else if(close[n] < avg && close[n] > btm)
               {
                  g_bb.broken = true;
                  g_bb.scalp  = false;
                  SetBuf(g_bufCnclUP, n, 1.0);
                  TryAlert(BUF_CNCLUP, tNow, n, rates_total, "cancel UP");
                  AddLabel(tNow, low[n], "X", clrOrange, LAB_X, 10);
               }
            }
            else if(!InpTillFirstBreak && close[n] > top)
            {
               g_bb.broken = false;
               g_bb.scalp  = true;
               SetBuf(g_bufBBPlus, n, 1.0);
               TryAlert(BUF_BBPLUS, tNow, n, rates_total, "+BB (R)");
               AddLabel(tNow, low[n], "R", clrBlue, LAB_TEXT, 12);
            }
         }
      }

      if(g_bb.hasSwings && !g_bb.broken1)
      {
         g_bb.sw1_t2 = tNow;
         if(close[n] < g_bb.sw1_y)
         {
            g_bb.broken1 = true;
            if(InpShowBreaks)
               AddLabel(tNow, low[n], "●", C'192,0,0', LAB_CIRCLE, 8);
            TryAlert(20, tNow, n, rates_total, "LL 1 break");
         }
      }
      if(g_bb.hasSwings && !g_bb.broken2)
      {
         g_bb.sw2_t2 = tNow;
         if(close[n] < g_bb.sw2_y)
         {
            g_bb.broken2 = true;
            if(InpShowBreaks)
               AddLabel(tNow, low[n], "●", C'192,0,0', LAB_CIRCLE, 8);
            TryAlert(21, tNow, n, rates_total, "LL 2 break");
         }
      }
      if(g_bb.hasPD1 && !g_bb.pdBroken1)
      {
         g_bb.pd1_right = tNow;
         if(close[n] > g_bb.pd1_top && tNow > g_bb.pd1_left)
         {
            g_bb.pdBroken1 = true;
            if(InpShowBreaks)
               AddLabel(tNow, high[n], "●", C'192,0,0', LAB_CIRCLE, 8);
            TryAlert(22, tNow, n, rates_total, "Swing UP 1 break");
         }
      }
      if(g_bb.hasPD2 && !g_bb.pdBroken2)
      {
         g_bb.pd2_right = tNow;
         if(close[n] > g_bb.pd2_top && tNow > g_bb.pd2_left)
         {
            g_bb.pdBroken2 = true;
            if(InpShowBreaks)
               AddLabel(tNow, high[n], "●", C'192,0,0', LAB_CIRCLE, 8);
            TryAlert(23, tNow, n, rates_total, "Swing UP 2 break");
         }
      }
   }
   else if(g_bb.dir == -1)
   {
      if(!g_bb.mitigated)
      {
         if(close[n] > top)
         {
            g_bb.mitigated  = true;
            g_bb.boxB_right = tNow;
            SetBuf(g_bufEndBr, n, 1.0);
            TryAlert(BUF_ENDBR, tNow, n, rates_total, "-BB Mitigated");
            if(InpShowBreaks)
               AddLabel(tNow, high[n], "●", InpBBMinusB, LAB_CIRCLE, 8);
         }
         else
            g_bb.boxB_right = tExt;

         if(afterCreate)
         {
            if(!g_bb.broken)
            {
               if(g_bb.scalp && g_bb.hasTP)
               {
                  if(!g_bb.tp1_hit && open[n] > g_bb.tp1 && low[n] < g_bb.tp1)
                  {
                     g_bb.tp1_hit = true;
                     AddLabel(tNow, g_bb.tp1, "●", C'255,0,221', LAB_CIRCLE, 8);
                     TryAlert(13, tNow, n, rates_total, "TP DN 1");
                  }
                  if(!g_bb.tp2_hit && open[n] > g_bb.tp2 && low[n] < g_bb.tp2)
                  {
                     g_bb.tp2_hit = true;
                     AddLabel(tNow, g_bb.tp2, "●", C'255,0,221', LAB_CIRCLE, 8);
                     TryAlert(14, tNow, n, rates_total, "TP DN 2");
                  }
                  if(!g_bb.tp3_hit && open[n] > g_bb.tp3 && low[n] < g_bb.tp3)
                  {
                     g_bb.tp3_hit = true;
                     AddLabel(tNow, g_bb.tp3, "●", C'255,0,221', LAB_CIRCLE, 8);
                     TryAlert(15, tNow, n, rates_total, "TP DN 3");
                  }
               }

               if(open[n] < avg && open[n] > btm && close[n] < btm)
               {
                  g_bb.tp1_hit = false;
                  g_bb.tp2_hit = false;
                  g_bb.tp3_hit = false;
                  g_bb.scalp   = true;
                  SetBuf(g_bufSignDN, n, 1.0);
                  TryAlert(BUF_SIGNDN, tNow, n, rates_total, "signal DN");
                  AddLabel(tNow, high[n], "▼", clrOrange, LAB_DN, 12);
               }
               else if(close[n] > avg && close[n] < top)
               {
                  g_bb.broken = true;
                  g_bb.scalp  = false;
                  SetBuf(g_bufCnclDN, n, 1.0);
                  TryAlert(BUF_CNCLDN, tNow, n, rates_total, "cancel DN");
                  AddLabel(tNow, high[n], "X", clrRed, LAB_X, 10);
               }
            }
            else if(!InpTillFirstBreak && close[n] < btm)
            {
               g_bb.broken = false;
               g_bb.scalp  = true;
               SetBuf(g_bufBBMinus, n, 1.0);
               TryAlert(BUF_BBMINUS, tNow, n, rates_total, "-BB (R)");
               AddLabel(tNow, high[n], "R", clrBlue, LAB_TEXT, 12);
            }
         }
      }

      if(g_bb.hasSwings && !g_bb.broken1)
      {
         g_bb.sw1_t2 = tNow;
         if(close[n] > g_bb.sw1_y)
         {
            g_bb.broken1 = true;
            if(InpShowBreaks)
               AddLabel(tNow, high[n], "●", C'192,0,0', LAB_CIRCLE, 8);
            TryAlert(24, tNow, n, rates_total, "HH 1 break");
         }
      }
      if(g_bb.hasSwings && !g_bb.broken2)
      {
         g_bb.sw2_t2 = tNow;
         if(close[n] > g_bb.sw2_y)
         {
            g_bb.broken2 = true;
            if(InpShowBreaks)
               AddLabel(tNow, high[n], "●", C'192,0,0', LAB_CIRCLE, 8);
            TryAlert(25, tNow, n, rates_total, "HH 2 break");
         }
      }
      if(g_bb.hasPD1 && !g_bb.pdBroken1)
      {
         g_bb.pd1_right = tNow;
         if(close[n] < g_bb.pd1_bottom && tNow > g_bb.pd1_left)
         {
            g_bb.pdBroken1 = true;
            if(InpShowBreaks)
               AddLabel(tNow, low[n], "●", C'192,0,0', LAB_CIRCLE, 8);
            TryAlert(26, tNow, n, rates_total, "Swing DN 1 break");
         }
      }
      if(g_bb.hasPD2 && !g_bb.pdBroken2)
      {
         g_bb.pd2_right = tNow;
         if(close[n] < g_bb.pd2_bottom && tNow > g_bb.pd2_left)
         {
            g_bb.pdBroken2 = true;
            if(InpShowBreaks)
               AddLabel(tNow, low[n], "●", C'192,0,0', LAB_CIRCLE, 8);
            TryAlert(27, tNow, n, rates_total, "Swing DN 2 break");
         }
      }
   }
}

void DrawLabels()
{
   for(int i = 0; i < g_labelCount; i++)
   {
      const string name = PREFIX + "L_" + IntegerToString(i);
      const SigLabel lb = g_labels[i];
      int width = 2;
      if(lb.fs >= 16)
         width = 3;
      else if(lb.fs <= 8)
         width = 1;

      if(lb.kind == LAB_UP)
         EnsureArrow(name, lb.t, lb.price, 233, lb.clr, width, ANCHOR_TOP);
      else if(lb.kind == LAB_DN)
         EnsureArrow(name, lb.t, lb.price, 234, lb.clr, width, ANCHOR_BOTTOM);
      else if(lb.kind == LAB_CIRCLE)
         EnsureArrow(name, lb.t, lb.price, 159, lb.clr, width, ANCHOR_TOP);
      else if(lb.kind == LAB_X)
         EnsureArrow(name, lb.t, lb.price, 251, lb.clr, width, ANCHOR_TOP);
      else
         EnsureText(name, lb.t, lb.price, lb.text, lb.clr, lb.fs, ANCHOR_UPPER);
   }

   for(int i = g_labelCount; i < g_drawnLabels; i++)
      HideObj(PREFIX + "L_" + IntegerToString(i));
   g_drawnLabels = g_labelCount;
}

void DrawZigZag()
{
   int drawn = 0;
   if(InpShowZZ)
   {
      for(int i = 0; i < g_zzCount - 1; i++)
      {
         if(g_zz[i].time <= 0 || g_zz[i + 1].time <= 0)
            continue;
         const color col = (g_zz[i].dir == 1) ? InpBBPlusB : InpBBMinusB;
         EnsureTrend(PREFIX + "ZZ_" + IntegerToString(drawn),
                     g_zz[i + 1].time, g_zz[i + 1].price,
                     g_zz[i].time, g_zz[i].price,
                     col, STYLE_SOLID, 1);
         drawn++;
      }
   }
   for(int i = drawn; i < g_drawnZZ; i++)
      HideObj(PREFIX + "ZZ_" + IntegerToString(i));
   g_drawnZZ = drawn;
}

void DrawBlock(const datetime tNow)
{
   if(g_bb.dir == 0)
   {
      HideObj(PREFIX + "BOXA");
      HideObj(PREFIX + "BOXB");
      HideObj(PREFIX + "BOXT");
      HideObj(PREFIX + "MID");
      HideObj(PREFIX + "SW1");
      HideObj(PREFIX + "SW2");
      HideObj(PREFIX + "HL");
      HideObj(PREFIX + "PD1");
      HideObj(PREFIX + "PD1L");
      HideObj(PREFIX + "PD1T");
      HideObj(PREFIX + "PD2");
      HideObj(PREFIX + "PD2L");
      HideObj(PREFIX + "PD2T");
      HideObj(PREFIX + "PDA");
      HideObj(PREFIX + "PDB");
      HideObj(PREFIX + "PDAT");
      HideObj(PREFIX + "TP1");
      HideObj(PREFIX + "TP2");
      HideObj(PREFIX + "TP3");
      return;
   }

   const bool bull = (g_bb.dir == 1);
   const color fillA = bull ? InpBBPlusA : InpBBMinusA;
   const color fillB = bull ? InpBBPlusB : InpBBMinusB;

   EnsureRect(PREFIX + "BOXA", g_bb.boxA_left, g_bb.top, g_bb.boxA_right, g_bb.bottom, fillA, true);
   EnsureRect(PREFIX + "BOXB", g_bb.boxB_left, g_bb.top, g_bb.boxB_right, g_bb.bottom, fillB, true);
   EnsureText(PREFIX + "BOXT", g_bb.boxB_right, bull ? g_bb.bottom : g_bb.top,
              bull ? "+BB" : "-BB", fillB, 8,
              bull ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
   EnsureTrend(PREFIX + "MID", g_bb.boxB_left, g_bb.avg, g_bb.boxB_right, g_bb.avg,
               clrSilver, STYLE_DASH, 1);

   if(g_bb.hasSwings)
   {
      EnsureTrend(PREFIX + "SW1", g_bb.sw1_t1, g_bb.sw1_y, g_bb.sw1_t2, g_bb.sw1_y, InpPDSwingColor, STYLE_SOLID, 1);
      EnsureTrend(PREFIX + "SW2", g_bb.sw2_t1, g_bb.sw2_y, g_bb.sw2_t2, g_bb.sw2_y, InpPDSwingColor, STYLE_SOLID, 1);
      EnsureText(PREFIX + "HL", g_bb.hl_time, g_bb.hl_price, g_bb.hl_text, InpPDtxtColor, 8,
                 bull ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
   }
   else
   {
      HideObj(PREFIX + "SW1");
      HideObj(PREFIX + "SW2");
      HideObj(PREFIX + "HL");
   }

   if(g_bb.hasPD1)
   {
      EnsureRect(PREFIX + "PD1", g_bb.pd1_left, g_bb.pd1_top, g_bb.pd1_right, g_bb.pd1_bottom,
                 bull ? InpSwingBl : InpSwingBr, true);
      EnsureTrend(PREFIX + "PD1L", g_bb.pd1_left, bull ? g_bb.pd1_top : g_bb.pd1_bottom,
                  g_bb.pd1_right, bull ? g_bb.pd1_top : g_bb.pd1_bottom, InpPDSwingColor, STYLE_SOLID, 1);
      EnsureText(PREFIX + "PD1T", g_bb.pd1_left, bull ? g_bb.pd1_top : g_bb.pd1_bottom,
                 bull ? "Premium PD Array" : "Discount PD Array", InpPDtxtColor, 8,
                 bull ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
   }
   else
   {
      HideObj(PREFIX + "PD1");
      HideObj(PREFIX + "PD1L");
      HideObj(PREFIX + "PD1T");
   }

   if(g_bb.hasPD2)
   {
      EnsureRect(PREFIX + "PD2", g_bb.pd2_left, g_bb.pd2_top, g_bb.pd2_right, g_bb.pd2_bottom,
                 bull ? InpSwingBl : InpSwingBr, true);
      EnsureTrend(PREFIX + "PD2L", g_bb.pd2_left, bull ? g_bb.pd2_top : g_bb.pd2_bottom,
                  g_bb.pd2_right, bull ? g_bb.pd2_top : g_bb.pd2_bottom, InpPDSwingColor, STYLE_SOLID, 1);
      EnsureText(PREFIX + "PD2T", g_bb.pd2_left, bull ? g_bb.pd2_top : g_bb.pd2_bottom,
                 bull ? "Premium PD Array" : "Discount PD Array", InpPDtxtColor, 8,
                 bull ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
   }
   else
   {
      HideObj(PREFIX + "PD2");
      HideObj(PREFIX + "PD2L");
      HideObj(PREFIX + "PD2T");
   }

   if(g_bb.hasPDzone)
   {
      const color disc = C'132,248,171';
      const color prem = C'248,153,132';
      if(g_bb.pdaDiscountOnBottom)
      {
         EnsureRect(PREFIX + "PDA", g_bb.pda_left, g_bb.pda_mid, g_bb.pda_right, g_bb.pda_bottom, disc, true);
         EnsureRect(PREFIX + "PDB", g_bb.pda_left, g_bb.pda_top, g_bb.pda_right, g_bb.pda_mid, prem, true);
         EnsureText(PREFIX + "PDAT", g_bb.pda_right, g_bb.pda_mid, "Discount PD Array", disc, 8, ANCHOR_RIGHT);
      }
      else
      {
         EnsureRect(PREFIX + "PDA", g_bb.pda_left, g_bb.pda_top, g_bb.pda_right, g_bb.pda_mid, prem, true);
         EnsureRect(PREFIX + "PDB", g_bb.pda_left, g_bb.pda_mid, g_bb.pda_right, g_bb.pda_bottom, disc, true);
         EnsureText(PREFIX + "PDAT", g_bb.pda_right, g_bb.pda_mid, "Premium PD Array", prem, 8, ANCHOR_RIGHT);
      }
   }
   else
   {
      HideObj(PREFIX + "PDA");
      HideObj(PREFIX + "PDB");
      HideObj(PREFIX + "PDAT");
   }

   if(g_bb.hasTP && !g_bb.mitigated)
   {
      EnsureTrend(PREFIX + "TP1", g_bb.boxB_left, g_bb.tp1, tNow, g_bb.tp1, InpTPColor, STYLE_SOLID, 1);
      EnsureTrend(PREFIX + "TP2", g_bb.boxB_left, g_bb.tp2, tNow, g_bb.tp2, InpTPColor, STYLE_SOLID, 1);
      EnsureTrend(PREFIX + "TP3", g_bb.boxB_left, g_bb.tp3, tNow, g_bb.tp3, InpTPColor, STYLE_SOLID, 1);
   }
   else if(g_bb.hasTP)
   {
      EnsureTrend(PREFIX + "TP1", g_bb.boxB_left, g_bb.tp1, g_bb.boxB_right, g_bb.tp1, InpTPColor, STYLE_SOLID, 1);
      EnsureTrend(PREFIX + "TP2", g_bb.boxB_left, g_bb.tp2, g_bb.boxB_right, g_bb.tp2, InpTPColor, STYLE_SOLID, 1);
      EnsureTrend(PREFIX + "TP3", g_bb.boxB_left, g_bb.tp3, g_bb.boxB_right, g_bb.tp3, InpTPColor, STYLE_SOLID, 1);
   }
   else
   {
      HideObj(PREFIX + "TP1");
      HideObj(PREFIX + "TP2");
      HideObj(PREFIX + "TP3");
   }
}

void ResetState()
{
   g_zzCount    = 0;
   g_mssDir     = 0;
   g_labelCount = 0;
   ResetBlock();
   for(int i = 0; i < ZZ_SIZE; i++)
   {
      g_zz[i].dir   = 0;
      g_zz[i].idx   = 0;
      g_zz[i].time  = 0;
      g_zz[i].price = 0.0;
   }
}

int OnInit()
{
   SetIndexBuffer(0, g_bufBBPlus,  INDICATOR_DATA);
   SetIndexBuffer(1, g_bufSignUP,  INDICATOR_DATA);
   SetIndexBuffer(2, g_bufCnclUP,  INDICATOR_DATA);
   SetIndexBuffer(3, g_bufEndBl,   INDICATOR_DATA);
   SetIndexBuffer(4, g_bufBBMinus, INDICATOR_DATA);
   SetIndexBuffer(5, g_bufSignDN,  INDICATOR_DATA);
   SetIndexBuffer(6, g_bufCnclDN,  INDICATOR_DATA);
   SetIndexBuffer(7, g_bufEndBr,   INDICATOR_DATA);

   ArraySetAsSeries(g_bufBBPlus,  false);
   ArraySetAsSeries(g_bufSignUP,  false);
   ArraySetAsSeries(g_bufCnclUP,  false);
   ArraySetAsSeries(g_bufEndBl,   false);
   ArraySetAsSeries(g_bufBBMinus, false);
   ArraySetAsSeries(g_bufSignDN,  false);
   ArraySetAsSeries(g_bufCnclDN,  false);
   ArraySetAsSeries(g_bufEndBr,   false);

   ArrayResize(g_alertTime, 32);
   ArrayInitialize(g_alertTime, 0);

   IndicatorSetString(INDICATOR_SHORTNAME, "Breaker Blocks with Signals");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   g_drawnLabels = 0;
   g_drawnZZ     = 0;
   ResetState();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
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
   const int left = ClampLength();
   if(rates_total < left + 10)
      return 0;

   ArrayInitialize(g_bufBBPlus,  0.0);
   ArrayInitialize(g_bufSignUP,  0.0);
   ArrayInitialize(g_bufCnclUP,  0.0);
   ArrayInitialize(g_bufEndBl,   0.0);
   ArrayInitialize(g_bufBBMinus, 0.0);
   ArrayInitialize(g_bufSignDN,  0.0);
   ArrayInitialize(g_bufCnclDN,  0.0);
   ArrayInitialize(g_bufEndBr,   0.0);

   ResetState();

   const int lookback = ClampLookback();
   const int zzStart  = MathMax(left + 1, rates_total - lookback - 500);
   const int bbStart  = MathMax(zzStart, rates_total - lookback);

   for(int n = zzStart; n < rates_total; n++)
   {
      UpdateZigZag(n, left, time, high, low);
      TryCreateMSS(n, rates_total, (n >= bbStart), time, open, high, low, close);
      UpdateActiveBB(n, rates_total, time, open, high, low, close);
   }

   const datetime tNow = time[rates_total - 1];
   DrawBlock(tNow);
   DrawLabels();
   DrawZigZag();
   ChartRedraw(0);
   return rates_total;
}
