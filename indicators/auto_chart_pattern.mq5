//+------------------------------------------------------------------+
//| auto_chart_pattern.mq5                                           |
//| Converted from Auto Chart Patterns [Trendoscope®] (Pine v6)      |
//| Geometric scan of zigzag pivots: channels, wedges, triangles.    |
//+------------------------------------------------------------------+
#property copyright "Converted from Auto Chart Patterns [Trendoscope®]"
#property version   "1.02"
#property indicator_chart_window
#property indicator_plots 0

enum ENUM_ACP_PIVOTS
{
   ACP_PIVOTS_5 = 5, // 5
   ACP_PIVOTS_6 = 6  // 6
};

enum ENUM_ACP_DIR
{
   ACP_DIR_UP     = 1,  // up
   ACP_DIR_DOWN   = -1, // down
   ACP_DIR_BOTH   = 0,  // both
   ACP_DIR_CUSTOM = 2   // custom
};

enum ENUM_ACP_DIR3
{
   ACP_DIR3_UP   = 1,  // up
   ACP_DIR3_DOWN = -1, // down
   ACP_DIR3_BOTH = 0   // both
};

enum ENUM_ACP_THEME
{
   ACP_THEME_DARK  = 0, // Dark
   ACP_THEME_LIGHT = 1  // Light
};

enum ENUM_ACP_LBL
{
   ACP_LBL_TINY   = 0, // tiny
   ACP_LBL_SMALL  = 1, // small
   ACP_LBL_NORMAL = 2, // normal
   ACP_LBL_LARGE  = 3, // large
   ACP_LBL_HUGE   = 4  // huge
};

input group "Zigzag"
input bool InpUseZigzag1 = true;
input int  InpZigzagLength1 = 8;
input int  InpDepth1 = 55;
input bool InpUseZigzag2 = false;
input int  InpZigzagLength2 = 13;
input int  InpDepth2 = 34;
input bool InpUseZigzag3 = false;
input int  InpZigzagLength3 = 21;
input int  InpDepth3 = 21;
input bool InpUseZigzag4 = false;
input int  InpZigzagLength4 = 34;
input int  InpDepth4 = 13;

input group "Scanning"
input ENUM_ACP_PIVOTS InpNumberOfPivots = ACP_PIVOTS_5;
input double          InpErrorThreshold = 20.0;   // Error Threshold
input double          InpFlatThreshold  = 20.0;   // Flat Threshold
input ENUM_ACP_DIR    InpLastPivotDirection = ACP_DIR_BOTH;
input bool            InpCheckBarRatio = true;
input double          InpBarRatioLimit = 0.382;
input bool            InpAvoidOverlap = false;
input bool            InpRepaint = false;

input group "Pattern Groups - Geometric Shapes"
input bool InpAllowChannels  = true;
input bool InpAllowWedges    = true;
input bool InpAllowTriangles = true;

input group "Pattern Groups - Direction"
input bool InpAllowRising         = true;
input bool InpAllowFalling        = true;
input bool InpAllowNonDirectional = true;

input group "Pattern Groups - Formation Dynamics"
input bool InpAllowExpanding  = true;
input bool InpAllowContracting = true;
input bool InpAllowParallel   = true;

input group "Price Channels"
input bool          InpAllowAscChannel = true;
input ENUM_ACP_DIR3 InpAscChannelLast  = ACP_DIR3_BOTH;
input bool          InpAllowDescChannel = true;
input ENUM_ACP_DIR3 InpDescChannelLast  = ACP_DIR3_BOTH;
input bool          InpAllowRangeChannel = true;
input ENUM_ACP_DIR3 InpRangeChannelLast  = ACP_DIR3_BOTH;

input group "Expanding Wedges"
input bool          InpAllowRisingWedgeExp = true;
input ENUM_ACP_DIR3 InpRisingWedgeExpLast  = ACP_DIR3_DOWN;
input bool          InpAllowFallingWedgeExp = true;
input ENUM_ACP_DIR3 InpFallingWedgeExpLast  = ACP_DIR3_UP;

input group "Contracting Wedges"
input bool          InpAllowRisingWedgeCon = true;
input ENUM_ACP_DIR3 InpRisingWedgeConLast  = ACP_DIR3_DOWN;
input bool          InpAllowFallingWedgeCon = true;
input ENUM_ACP_DIR3 InpFallingWedgeConLast  = ACP_DIR3_UP;

input group "Expanding Triangles"
input bool          InpAllowAscTriExp = true;
input ENUM_ACP_DIR3 InpAscTriExpLast  = ACP_DIR3_UP;
input bool          InpAllowDescTriExp = true;
input ENUM_ACP_DIR3 InpDescTriExpLast  = ACP_DIR3_DOWN;
input bool          InpAllowDivergingTri = true;
input ENUM_ACP_DIR3 InpDivergingTriLast  = ACP_DIR3_BOTH;

input group "Contracting Triangles"
input bool          InpAllowAscTriCon = true;
input ENUM_ACP_DIR3 InpAscTriConLast  = ACP_DIR3_UP;
input bool          InpAllowDescTriCon = true;
input ENUM_ACP_DIR3 InpDescTriConLast  = ACP_DIR3_DOWN;
input bool          InpAllowConvergingTri = true;
input ENUM_ACP_DIR3 InpConvergingTriLast  = ACP_DIR3_BOTH;

input group "Display"
input ENUM_ACP_THEME InpTheme = ACP_THEME_DARK;
input int            InpPatternLineWidth = 2;
input bool           InpUseCustomColors = false;
input color          InpC1  = C'251,244,109';
input color          InpC2  = C'141,186,81';
input color          InpC3  = C'74,159,245';
input color          InpC4  = C'255,153,140';
input color          InpC5  = C'255,149,0';
input color          InpC6  = C'0,234,211';
input color          InpC7  = C'167,153,183';
input color          InpC8  = C'255,210,113';
input color          InpC9  = C'119,217,112';
input color          InpC10 = C'95,129,228';
input color          InpC11 = C'235,146,190';
input color          InpC12 = C'198,139,89';
input color          InpC13 = C'200,149,149';
input bool           InpShowPatternLabel = true;
input ENUM_ACP_LBL   InpPatternLabelSize = ACP_LBL_NORMAL;
input bool           InpShowPivotLabels = true;
input ENUM_ACP_LBL   InpPivotLabelSize = ACP_LBL_NORMAL;
input bool           InpShowZigzag = true;
input color          InpZigzagColor = clrBlue;
input bool           InpDeleteOldPatterns = true;
input int            InpMaxPatterns = 20;

#define PREFIX "ACP_"
#define MAX_BARS 5000
#define MAX_PIVOTS 256
#define MAX_LEVELS 12
#define PATTERN_NONE 0
#define PATTERN_ASC_CH 1
#define PATTERN_DESC_CH 2
#define PATTERN_RANGE_CH 3
#define PATTERN_RISE_WEDGE_EXP 4
#define PATTERN_FALL_WEDGE_EXP 5
#define PATTERN_DIV_TRI 6
#define PATTERN_ASC_TRI_EXP 7
#define PATTERN_DESC_TRI_EXP 8
#define PATTERN_RISE_WEDGE_CON 9
#define PATTERN_FALL_WEDGE_CON 10
#define PATTERN_CONV_TRI 11
#define PATTERN_DESC_TRI_CON 12
#define PATTERN_ASC_TRI_CON 13
#define SLOPE_FLAT 0
#define SLOPE_UP 1
#define SLOPE_DOWN -1
#define FORM_PARALLEL 0
#define FORM_EXPAND 1
#define FORM_CONTRACT -1

struct PivotPoint
{
   int      bar;
   datetime time;
   double   price;
   bool     isHigh;
};

struct PatternHit
{
   int      typeId;
   int      startBar;
   int      endBar;
   datetime startTime;
   datetime endTime;
   double   upperStart;
   double   upperEnd;
   double   lowerStart;
   double   lowerEnd;
   int      pivotCount;
   PivotPoint pivots[8];
};

PivotPoint g_work[];
PatternHit g_patterns[];
int        g_patternCount = 0;
datetime   g_lastAlertKey = 0;
int        g_lastAlertType = 0;
datetime   g_lastBarTime = 0;
long       g_chart = 0;
color      g_palette[13];
bool       g_allowed[14];
int        g_lastDir[14];

string PatternName(const int typeId)
{
   switch(typeId)
   {
      case PATTERN_ASC_CH:         return "Ascending Channel";
      case PATTERN_DESC_CH:        return "Descending Channel";
      case PATTERN_RANGE_CH:       return "Ranging Channel";
      case PATTERN_RISE_WEDGE_EXP: return "Rising Wedge (Expanding)";
      case PATTERN_FALL_WEDGE_EXP: return "Falling Wedge (Expanding)";
      case PATTERN_DIV_TRI:        return "Diverging Triangle";
      case PATTERN_ASC_TRI_EXP:    return "Ascending Triangle (Expanding)";
      case PATTERN_DESC_TRI_EXP:   return "Descending Triangle (Expanding)";
      case PATTERN_RISE_WEDGE_CON: return "Rising Wedge (Contracting)";
      case PATTERN_FALL_WEDGE_CON: return "Falling Wedge (Contracting)";
      case PATTERN_CONV_TRI:       return "Converging Triangle";
      case PATTERN_DESC_TRI_CON:   return "Descending Triangle (Contracting)";
      case PATTERN_ASC_TRI_CON:    return "Ascending Triangle (Contracting)";
   }
   return "";
}

int LabelFont(const ENUM_ACP_LBL sz)
{
   if(sz == ACP_LBL_TINY)   return 7;
   if(sz == ACP_LBL_SMALL)  return 8;
   if(sz == ACP_LBL_LARGE)  return 11;
   if(sz == ACP_LBL_HUGE)   return 13;
   return 9;
}

color Darken(const color c)
{
   int r = (c & 0x0000FF);
   int g = (c & 0x00FF00) >> 8;
   int b = (c & 0xFF0000) >> 16;
   r = (int)MathMax(0, r * 0.55);
   g = (int)MathMax(0, g * 0.55);
   b = (int)MathMax(0, b * 0.55);
   return (color)(r | (g << 8) | (b << 16));
}

void InitPalette()
{
   color raw[13];
   raw[0]  = InpC1;  raw[1]  = InpC2;  raw[2]  = InpC3;  raw[3]  = InpC4;
   raw[4]  = InpC5;  raw[5]  = InpC6;  raw[6]  = InpC7;  raw[7]  = InpC8;
   raw[8]  = InpC9;  raw[9]  = InpC10; raw[10] = InpC11; raw[11] = InpC12;
   raw[12] = InpC13;
   for(int i = 0; i < 13; i++)
   {
      if(InpUseCustomColors)
         g_palette[i] = raw[i];
      else if(InpTheme == ACP_THEME_LIGHT)
         g_palette[i] = Darken(raw[i]);
      else
         g_palette[i] = raw[i];
   }
}

int ResolveLastDir(const ENUM_ACP_DIR3 customDir)
{
   if(InpLastPivotDirection == ACP_DIR_CUSTOM)
      return (int)customDir;
   if(InpLastPivotDirection == ACP_DIR_BOTH)
      return 0;
   return (int)InpLastPivotDirection;
}

void InitAllowed()
{
   for(int i = 0; i < 14; i++)
   {
      g_allowed[i] = false;
      g_lastDir[i] = 0;
   }

   g_allowed[PATTERN_ASC_CH] = InpAllowAscChannel && InpAllowRising && InpAllowParallel && InpAllowChannels;
   g_allowed[PATTERN_DESC_CH] = InpAllowDescChannel && InpAllowFalling && InpAllowParallel && InpAllowChannels;
   g_allowed[PATTERN_RANGE_CH] = InpAllowRangeChannel && InpAllowNonDirectional && InpAllowParallel && InpAllowChannels;
   g_allowed[PATTERN_RISE_WEDGE_EXP] = InpAllowRisingWedgeExp && InpAllowRising && InpAllowExpanding && InpAllowWedges;
   g_allowed[PATTERN_FALL_WEDGE_EXP] = InpAllowFallingWedgeExp && InpAllowFalling && InpAllowExpanding && InpAllowWedges;
   g_allowed[PATTERN_DIV_TRI] = InpAllowDivergingTri && InpAllowNonDirectional && InpAllowExpanding && InpAllowTriangles;
   g_allowed[PATTERN_ASC_TRI_EXP] = InpAllowAscTriExp && InpAllowRising && InpAllowExpanding && InpAllowTriangles;
   g_allowed[PATTERN_DESC_TRI_EXP] = InpAllowDescTriExp && InpAllowFalling && InpAllowExpanding && InpAllowTriangles;
   g_allowed[PATTERN_RISE_WEDGE_CON] = InpAllowRisingWedgeCon && InpAllowRising && InpAllowContracting && InpAllowWedges;
   g_allowed[PATTERN_FALL_WEDGE_CON] = InpAllowFallingWedgeCon && InpAllowFalling && InpAllowContracting && InpAllowWedges;
   g_allowed[PATTERN_CONV_TRI] = InpAllowConvergingTri && InpAllowNonDirectional && InpAllowContracting && InpAllowTriangles;
   g_allowed[PATTERN_DESC_TRI_CON] = InpAllowDescTriCon && InpAllowFalling && InpAllowContracting && InpAllowTriangles;
   g_allowed[PATTERN_ASC_TRI_CON] = InpAllowAscTriCon && InpAllowRising && InpAllowContracting && InpAllowTriangles;

   g_lastDir[PATTERN_ASC_CH] = ResolveLastDir(InpAscChannelLast);
   g_lastDir[PATTERN_DESC_CH] = ResolveLastDir(InpDescChannelLast);
   g_lastDir[PATTERN_RANGE_CH] = ResolveLastDir(InpRangeChannelLast);
   g_lastDir[PATTERN_RISE_WEDGE_EXP] = ResolveLastDir(InpRisingWedgeExpLast);
   g_lastDir[PATTERN_FALL_WEDGE_EXP] = ResolveLastDir(InpFallingWedgeExpLast);
   g_lastDir[PATTERN_DIV_TRI] = ResolveLastDir(InpDivergingTriLast);
   g_lastDir[PATTERN_ASC_TRI_EXP] = ResolveLastDir(InpAscTriExpLast);
   g_lastDir[PATTERN_DESC_TRI_EXP] = ResolveLastDir(InpDescTriExpLast);
   g_lastDir[PATTERN_RISE_WEDGE_CON] = ResolveLastDir(InpRisingWedgeConLast);
   g_lastDir[PATTERN_FALL_WEDGE_CON] = ResolveLastDir(InpFallingWedgeConLast);
   g_lastDir[PATTERN_CONV_TRI] = ResolveLastDir(InpConvergingTriLast);
   g_lastDir[PATTERN_DESC_TRI_CON] = ResolveLastDir(InpDescTriConLast);
   g_lastDir[PATTERN_ASC_TRI_CON] = ResolveLastDir(InpAscTriConLast);
}

void DeletePatternObjects()
{
   ObjectsDeleteAll(0, PREFIX);
}

int OnInit()
{
   if(InpZigzagLength1 < 1 || InpZigzagLength2 < 1 || InpZigzagLength3 < 1 || InpZigzagLength4 < 1)
   {
      Print("Zigzag length must be >= 1");
      return INIT_PARAMETERS_INCORRECT;
   }
   g_chart = ChartID();
   InitPalette();
   InitAllowed();
   ArrayResize(g_work, MAX_PIVOTS);
   ArrayResize(g_patterns, MathMax(InpMaxPatterns, 1) + 8);
   g_patternCount = 0;
   g_lastBarTime = 0;
   IndicatorSetString(INDICATOR_SHORTNAME, "ACP [Trendoscope®]");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeletePatternObjects();
}

bool IsPivotHighAt(const int i, const int length, const int lastBar, const double &high[])
{
   if(i < length || i + length > lastBar)
      return false;
   for(int k = 1; k <= length; k++)
   {
      if(high[i] < high[i - k] || high[i] <= high[i + k])
         return false;
   }
   return true;
}

bool IsPivotLowAt(const int i, const int length, const int lastBar, const double &low[])
{
   if(i < length || i + length > lastBar)
      return false;
   for(int k = 1; k <= length; k++)
   {
      if(low[i] > low[i - k] || low[i] >= low[i + k])
         return false;
   }
   return true;
}

void PushPivot(PivotPoint &pivots[], int &count, const PivotPoint &p)
{
   if(count > 0)
   {
      PivotPoint last = pivots[count - 1];
      if(last.isHigh == p.isHigh)
      {
         if(p.isHigh && p.price >= last.price)
            pivots[count - 1] = p;
         else if(!p.isHigh && p.price <= last.price)
            pivots[count - 1] = p;
         return;
      }
   }
   if(count >= ArraySize(pivots))
      return;
   pivots[count] = p;
   count++;
}

int BuildZigzag(const int length, const int depth, const int rates,
                const datetime &time[], const double &high[], const double &low[],
                const bool repaint, PivotPoint &out[])
{
   int count = 0;
   const int lastBar = repaint ? (rates - 1) : (rates - 2);
   const int from = MathMax(length, rates - MAX_BARS);
   const int to = lastBar - length;
   if(to <= from)
      return 0;

   for(int i = from; i <= to; i++)
   {
      PivotPoint p;
      p.bar = i;
      p.time = time[i];
      if(IsPivotHighAt(i, length, lastBar, high))
      {
         p.price = high[i];
         p.isHigh = true;
         PushPivot(out, count, p);
      }
      if(IsPivotLowAt(i, length, lastBar, low))
      {
         p.price = low[i];
         p.isHigh = false;
         PushPivot(out, count, p);
      }
   }

   const int cap = MathMax(8, depth);
   if(count > cap)
   {
      const int drop = count - cap;
      for(int i = 0; i < cap; i++)
         out[i] = out[i + drop];
      count = cap;
   }
   return count;
}

int NextLevel(const PivotPoint &in[], const int inCount, PivotPoint &out[])
{
   int count = 0;
   if(inCount < 5)
      return 0;

   double hPrev = EMPTY_VALUE, hCur = EMPTY_VALUE, hNext = EMPTY_VALUE;
   int    hiPrev = -1, hiCur = -1, hiNext = -1;
   double lPrev = EMPTY_VALUE, lCur = EMPTY_VALUE, lNext = EMPTY_VALUE;
   int    liPrev = -1, liCur = -1, liNext = -1;

   for(int i = 0; i < inCount; i++)
   {
      if(in[i].isHigh)
      {
         hPrev = hCur; hiPrev = hiCur;
         hCur  = hNext; hiCur  = hiNext;
         hNext = in[i].price; hiNext = i;
         if(hiPrev >= 0 && hiCur >= 0 && hiNext >= 0)
         {
            if(hCur >= hPrev && hCur >= hNext)
               PushPivot(out, count, in[hiCur]);
         }
      }
      else
      {
         lPrev = lCur; liPrev = liCur;
         lCur  = lNext; liCur  = liNext;
         lNext = in[i].price; liNext = i;
         if(liPrev >= 0 && liCur >= 0 && liNext >= 0)
         {
            if(lCur <= lPrev && lCur <= lNext)
               PushPivot(out, count, in[liCur]);
         }
      }
   }
   return count;
}

bool FitLine(const PivotPoint &pts[], const int n, double &intercept, double &slope)
{
   if(n < 2)
      return false;
   double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
   for(int i = 0; i < n; i++)
   {
      const double x = pts[i].bar;
      const double y = pts[i].price;
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumXX += x * x;
   }
   const double denom = n * sumXX - sumX * sumX;
   if(MathAbs(denom) < 1e-12)
      return false;
   slope = (n * sumXY - sumX * sumY) / denom;
   intercept = (sumY - slope * sumX) / n;
   return true;
}

int SlopeClass(const double startPrice, const double endPrice, const double range, const double flatRatio)
{
   if(range <= 0.0)
      return SLOPE_FLAT;
   const double ns = (endPrice - startPrice) / range;
   if(ns > flatRatio)
      return SLOPE_UP;
   if(ns < -flatRatio)
      return SLOPE_DOWN;
   return SLOPE_FLAT;
}

int ClassifyPattern(const int upSlope, const int dnSlope, const int formation)
{
   const bool upUp   = (upSlope == SLOPE_UP && dnSlope == SLOPE_UP);
   const bool dnDn   = (upSlope == SLOPE_DOWN && dnSlope == SLOPE_DOWN);
   const bool bothFlat = (upSlope == SLOPE_FLAT && dnSlope == SLOPE_FLAT);
   const bool rising = upUp || (upSlope == SLOPE_UP && dnSlope == SLOPE_FLAT) || (upSlope == SLOPE_FLAT && dnSlope == SLOPE_UP);
   const bool falling = dnDn || (upSlope == SLOPE_DOWN && dnSlope == SLOPE_FLAT) || (upSlope == SLOPE_FLAT && dnSlope == SLOPE_DOWN);
   const bool opposite = (upSlope == SLOPE_UP && dnSlope == SLOPE_DOWN) || (upSlope == SLOPE_DOWN && dnSlope == SLOPE_UP);

   if(formation == FORM_PARALLEL)
   {
      if(upUp)
         return PATTERN_ASC_CH;
      if(dnDn)
         return PATTERN_DESC_CH;
      if(bothFlat)
         return PATTERN_RANGE_CH;
      return PATTERN_NONE;
   }

   if(upUp)
      return (formation == FORM_EXPAND) ? PATTERN_RISE_WEDGE_EXP : PATTERN_RISE_WEDGE_CON;
   if(dnDn)
      return (formation == FORM_EXPAND) ? PATTERN_FALL_WEDGE_EXP : PATTERN_FALL_WEDGE_CON;

   if(opposite)
      return (formation == FORM_EXPAND) ? PATTERN_DIV_TRI : PATTERN_CONV_TRI;

   if(rising)
   {
      if(upSlope == SLOPE_UP && dnSlope == SLOPE_FLAT)
         return (formation == FORM_EXPAND) ? PATTERN_ASC_TRI_EXP : PATTERN_ASC_TRI_CON;
      if(upSlope == SLOPE_FLAT && dnSlope == SLOPE_UP)
         return (formation == FORM_EXPAND) ? PATTERN_ASC_TRI_EXP : PATTERN_ASC_TRI_CON;
   }
   if(falling)
   {
      if(upSlope == SLOPE_DOWN && dnSlope == SLOPE_FLAT)
         return (formation == FORM_EXPAND) ? PATTERN_DESC_TRI_EXP : PATTERN_DESC_TRI_CON;
      if(upSlope == SLOPE_FLAT && dnSlope == SLOPE_DOWN)
         return (formation == FORM_EXPAND) ? PATTERN_DESC_TRI_EXP : PATTERN_DESC_TRI_CON;
   }
   return PATTERN_NONE;
}

bool BarRatioOk(const PivotPoint &pts[], const int n)
{
   if(!InpCheckBarRatio || n < 3)
      return true;
   int minD = 100000000;
   int maxD = 0;
   for(int i = 1; i < n; i++)
   {
      const int d = MathAbs(pts[i].bar - pts[i - 1].bar);
      if(d <= 0)
         return false;
      if(d < minD)
         minD = d;
      if(d > maxD)
         maxD = d;
   }
   if(maxD <= 0)
      return false;
   return ((double)minD / (double)maxD) >= InpBarRatioLimit;
}

bool TryFindPattern(const PivotPoint &zz[], const int zzCount, PatternHit &hit)
{
   const int n = (int)InpNumberOfPivots;
   if(zzCount < n)
      return false;

   PivotPoint pts[8];
   const int startIdx = zzCount - n;
   for(int i = 0; i < n; i++)
      pts[i] = zz[startIdx + i];

   if(!BarRatioOk(pts, n))
      return false;

   PivotPoint up[6], dn[6];
   int upN = 0, dnN = 0;
   for(int i = 0; i < n; i++)
   {
      if(pts[i].isHigh)
      {
         up[upN] = pts[i];
         upN++;
      }
      else
      {
         dn[dnN] = pts[i];
         dnN++;
      }
   }
   if(upN < 2 || dnN < 2)
      return false;

   const int x1 = pts[0].bar;
   const int x2 = pts[n - 1].bar;
   if(x1 == x2)
      return false;

   double pMin = pts[0].price;
   double pMax = pts[0].price;
   for(int i = 1; i < n; i++)
   {
      pMin = MathMin(pMin, pts[i].price);
      pMax = MathMax(pMax, pts[i].price);
   }
   const double range = pMax - pMin;
   if(range <= 0.0)
      return false;

   double ua = 0, ub = 0, da = 0, db = 0;
   if(!FitLine(up, upN, ua, ub) || !FitLine(dn, dnN, da, db))
      return false;

   const double errorRatio = InpErrorThreshold / 100.0;
   for(int i = 0; i < upN; i++)
   {
      if(MathAbs(up[i].price - (ua + ub * up[i].bar)) / range > errorRatio)
         return false;
   }
   for(int i = 0; i < dnN; i++)
   {
      if(MathAbs(dn[i].price - (da + db * dn[i].bar)) / range > errorRatio)
         return false;
   }

   const double upperStart = ua + ub * x1;
   const double upperEnd   = ua + ub * x2;
   const double lowerStart = da + db * x1;
   const double lowerEnd   = da + db * x2;
   if(upperStart <= lowerStart || upperEnd <= lowerEnd)
      return false;

   const double flatRatio = InpFlatThreshold / 100.0;
   const int upSlope = SlopeClass(upperStart, upperEnd, range, flatRatio);
   const int dnSlope = SlopeClass(lowerStart, lowerEnd, range, flatRatio);

   const double w1 = upperStart - lowerStart;
   const double w2 = upperEnd - lowerEnd;
   int formation = FORM_PARALLEL;
   if(w1 > 0.0)
   {
      const double wr = w2 / w1;
      if(wr > 1.0 + errorRatio)
         formation = FORM_EXPAND;
      else if(wr < 1.0 - errorRatio)
         formation = FORM_CONTRACT;
   }

   const int typeId = ClassifyPattern(upSlope, dnSlope, formation);
   if(typeId == PATTERN_NONE || !g_allowed[typeId])
      return false;

   const int lastDir = pts[n - 1].isHigh ? 1 : -1;
   if(g_lastDir[typeId] != 0 && g_lastDir[typeId] != lastDir)
      return false;

   hit.typeId = typeId;
   hit.startBar = x1;
   hit.endBar = x2;
   hit.startTime = pts[0].time;
   hit.endTime = pts[n - 1].time;
   hit.upperStart = upperStart;
   hit.upperEnd = upperEnd;
   hit.lowerStart = lowerStart;
   hit.lowerEnd = lowerEnd;
   hit.pivotCount = n;
   for(int i = 0; i < n; i++)
      hit.pivots[i] = pts[i];
   return true;
}

bool PatternExists(const PatternHit &hit)
{
   for(int i = 0; i < g_patternCount; i++)
   {
      if(g_patterns[i].typeId == hit.typeId &&
         g_patterns[i].startTime == hit.startTime &&
         g_patterns[i].endTime == hit.endTime)
         return true;
   }
   return false;
}

void AddPattern(const PatternHit &hit)
{
   if(PatternExists(hit))
      return;
   if(InpAvoidOverlap && g_patternCount > 0)
   {
      datetime lastEnd = g_patterns[0].endTime;
      for(int i = 1; i < g_patternCount; i++)
      {
         if(g_patterns[i].endTime > lastEnd)
            lastEnd = g_patterns[i].endTime;
      }
      if(hit.startTime < lastEnd)
         return;
   }

   if(g_patternCount >= ArraySize(g_patterns))
      ArrayResize(g_patterns, g_patternCount + 8);
   g_patterns[g_patternCount] = hit;
   g_patternCount++;

   if(InpDeleteOldPatterns && g_patternCount > InpMaxPatterns)
   {
      const int drop = g_patternCount - InpMaxPatterns;
      for(int i = 0; i < InpMaxPatterns; i++)
         g_patterns[i] = g_patterns[i + drop];
      g_patternCount = InpMaxPatterns;
   }
}

void ScanPrefixLevels(const PivotPoint &zz[], const int zzCount)
{
   const int need = (int)InpNumberOfPivots;
   if(zzCount < need)
      return;

   PivotPoint cur[];
   ArrayResize(cur, zzCount);
   ArrayCopy(cur, zz, 0, 0, zzCount);
   int n = zzCount;

   for(int lvl = 0; lvl < MAX_LEVELS; lvl++)
   {
      PatternHit hit;
      if(TryFindPattern(cur, n, hit))
         AddPattern(hit);

      PivotPoint nxt[];
      ArrayResize(nxt, MAX_PIVOTS);
      const int nn = NextLevel(cur, n, nxt);
      if(nn < need || nn >= n)
         break;
      ArrayResize(cur, nn);
      ArrayCopy(cur, nxt, 0, 0, nn);
      n = nn;
   }
}

void ScanZigzagInstance(const int length, const int depth, const int rates,
                        const datetime &time[], const double &high[], const double &low[])
{
   PivotPoint level0[];
   ArrayResize(level0, MAX_PIVOTS);
   const int n0 = BuildZigzag(length, depth, rates, time, high, low, InpRepaint, level0);
   const int need = (int)InpNumberOfPivots;
   if(n0 < need)
      return;

   for(int end = need; end <= n0; end++)
      ScanPrefixLevels(level0, end);
}

void SetObjCommon(const string name, const bool back, const int zorder)
{
   ObjectSetInteger(0, name, OBJPROP_BACK, back);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, zorder);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void EnsureTrend(const string name, const datetime t1, const double p1,
                 const datetime t2, const double p2, const color clr,
                 const int width, const ENUM_LINE_STYLE style)
{
   if(t1 <= 0 || t2 <= 0)
      return;

   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
      {
         Print("ACP create trend failed ", name, " err=", GetLastError(),
               " t1=", TimeToString(t1), " t2=", TimeToString(t2),
               " p1=", DoubleToString(p1, _Digits), " p2=", DoubleToString(p2, _Digits));
         return;
      }
   }
   else
   {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   SetObjCommon(name, false, 20);
}

void EnsureText(const string name, const datetime t, const double price,
                const string text, const color clr, const int fontSize,
                const ENUM_ANCHOR_POINT anchor)
{
   if(t <= 0)
      return;

   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
         return;
   }
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   SetObjCommon(name, false, 21);
}

void EnsureNameBox(const string name, const datetime t, const double price,
                   const string text, const color bg)
{
   if(t <= 0)
      return;
   const int padBars = MathMax(8, (int)PeriodSeconds() > 0 ? 8 : 8);
   datetime t2 = t + PeriodSeconds() * padBars;
   const double h = MathMax(price * 0.0008, _Point * 80);

   string box = name + "B";
   if(ObjectFind(0, box) < 0)
      ObjectCreate(0, box, OBJ_RECTANGLE, 0, t, price + h, t2, price - h);
   else
   {
      ObjectMove(0, box, 0, t, price + h);
      ObjectMove(0, box, 1, t2, price - h);
   }
   ObjectSetInteger(0, box, OBJPROP_COLOR, bg);
   ObjectSetInteger(0, box, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, box, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, box, OBJPROP_FILL, true);
   SetObjCommon(box, false, 22);

   EnsureText(name + "T", t, price, text, clrBlack, LabelFont(InpPatternLabelSize), ANCHOR_LEFT);
}

void DrawStatus()
{
   const string name = PREFIX + "STATUS";
   string text = "ACP: no pattern";
   color clr = clrSilver;
   if(g_patternCount > 0)
   {
      const PatternHit last = g_patterns[g_patternCount - 1];
      text = "ACP: " + PatternName(last.typeId) + " x" + IntegerToString(g_patternCount) +
             "  " + TimeToString(last.startTime, TIME_DATE|TIME_MINUTES) +
             " -> " + TimeToString(last.endTime, TIME_DATE|TIME_MINUTES);
      clr = g_palette[(last.typeId - 1) % 13];
   }

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 18);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   SetObjCommon(name, false, 30);
}

void DrawPattern(const PatternHit &hit, const int idx)
{
   const color clr = g_palette[(hit.typeId - 1) % 13];
   const string id = PREFIX + IntegerToString(idx) + "_";

   EnsureTrend(id + "U", hit.startTime, hit.upperStart, hit.endTime, hit.upperEnd, clr, InpPatternLineWidth, STYLE_SOLID);
   EnsureTrend(id + "L", hit.startTime, hit.lowerStart, hit.endTime, hit.lowerEnd, clr, InpPatternLineWidth, STYLE_SOLID);

   if(InpShowZigzag)
   {
      for(int i = 1; i < hit.pivotCount; i++)
      {
         EnsureTrend(id + "Z" + IntegerToString(i),
                     hit.pivots[i - 1].time, hit.pivots[i - 1].price,
                     hit.pivots[i].time, hit.pivots[i].price,
                     InpZigzagColor, 1, STYLE_DOT);
      }
   }

   if(InpShowPivotLabels)
   {
      for(int i = 0; i < hit.pivotCount; i++)
      {
         EnsureText(id + "P" + IntegerToString(i), hit.pivots[i].time, hit.pivots[i].price,
                    IntegerToString(i + 1), clr, LabelFont(InpPivotLabelSize),
                    hit.pivots[i].isHigh ? ANCHOR_LOWER : ANCHOR_UPPER);
      }
   }

   if(InpShowPatternLabel)
   {
      const double mid = (hit.upperEnd + hit.lowerEnd) * 0.5;
      EnsureNameBox(id + "N", hit.endTime, mid, PatternName(hit.typeId), clr);
   }
}

void RedrawAll()
{
   DeletePatternObjects();
   for(int i = 0; i < g_patternCount; i++)
      DrawPattern(g_patterns[i], i);
   DrawStatus();
}

void ScanAll(const int rates, const datetime &time[], const double &high[], const double &low[], const bool allowAlert)
{
   g_patternCount = 0;
   if(InpUseZigzag1)
      ScanZigzagInstance(InpZigzagLength1, InpDepth1, rates, time, high, low);
   if(InpUseZigzag2)
      ScanZigzagInstance(InpZigzagLength2, InpDepth2, rates, time, high, low);
   if(InpUseZigzag3)
      ScanZigzagInstance(InpZigzagLength3, InpDepth3, rates, time, high, low);
   if(InpUseZigzag4)
      ScanZigzagInstance(InpZigzagLength4, InpDepth4, rates, time, high, low);
   RedrawAll();

   if(allowAlert && g_patternCount > 0)
   {
      const PatternHit last = g_patterns[g_patternCount - 1];
      if(last.startTime != g_lastAlertKey || last.typeId != g_lastAlertType)
      {
         g_lastAlertKey = last.startTime;
         g_lastAlertType = last.typeId;
         Alert("New Pattern Alert: ", PatternName(last.typeId));
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
   if(rates_total < 50)
      return 0;

   const datetime curBar = time[rates_total - 1];
   const bool newBar = (prev_calculated == 0 || curBar != g_lastBarTime);
   if(!newBar && !InpRepaint)
      return rates_total;
   g_lastBarTime = curBar;

   ScanAll(rates_total, time, high, low, prev_calculated != 0);
   ChartRedraw(0);
   return rates_total;
}
