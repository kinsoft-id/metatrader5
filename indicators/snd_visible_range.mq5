//+------------------------------------------------------------------+
//| snd_visible_range.mq5                                            |
//| Converted from Supply and Demand Visible Range [LuxAlgo]         |
//| CC BY-NC-SA 4.0  https://creativecommons.org/licenses/by-nc-sa/4.0/|
//+------------------------------------------------------------------+
#property copyright "Converted from Supply and Demand Visible Range [LuxAlgo] — CC BY-NC-SA 4.0"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots   0

input group "Settings"
input double          InpThreshold   = 10.0;            // Threshold %
input int             InpResolution  = 50;              // Resolution
input ENUM_TIMEFRAMES InpIntrabarTF  = PERIOD_CURRENT;  // Intrabar TF

input group "Supply"
input bool  InpShowSupply  = true;
input color InpSupplyCss   = C'33,87,243';
input bool  InpSupplyArea  = true;   // Area
input bool  InpSupplyAvg   = true;   // Average
input bool  InpSupplyWavg  = true;   // Weighted

input group "Equilibrium"
input bool  InpShowEqui    = true;
input color InpEquiCss     = clrGray;
input bool  InpEquiAvg     = true;   // Average
input bool  InpEquiWavg    = true;   // Weighted

input group "Demand"
input bool  InpShowDemand  = true;
input color InpDemandCss   = C'255,93,0';
input bool  InpDemandArea  = true;   // Area
input bool  InpDemandAvg   = true;   // Average
input bool  InpDemandWavg  = true;   // Weighted

#define PREFIX        "SNDVR_"
#define MAX_BARS_BACK 500
#define MAX_DIV       500
#define TRANS_AREA    80
#define TRANS_HIST    50

struct Bin
{
   double lvl;
   double prev;
   double sum;
   double prev_sum;
   double csum;
   double avg;
   bool   isreached;
};

int      g_div = 50;
int      g_supHistDrawn = 0;
int      g_demHistDrawn = 0;
int      g_leftShift = -1;
int      g_rightShift = -1;
double   g_rightHigh = 0.0;
double   g_rightLow  = 0.0;
long     g_rightVol  = 0;
datetime g_leftTime  = 0;
datetime g_rightTime = 0;

int ClampInt(const int v, const int lo, const int hi)
{
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
}

double ClampDouble(const double v, const double lo, const double hi)
{
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
}

color ApplyTransp(const color clr, const int transp)
{
   int t = ClampInt(transp, 0, 100);
   uchar alpha = (uchar)MathRound(2.55 * (100 - t));
   return (color)ColorToARGB(clr, alpha);
}

void StyleObject(const string name, const bool back)
{
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, back);
}

void HideObj(const string name)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

void EnsureRect(const string name, const datetime t1, const double p1,
                const datetime t2, const double p2, const color clr)
{
   if(t1 <= 0 || t2 <= 0)
   {
      HideObj(name);
      return;
   }
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      StyleObject(name, true);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void EnsureTrend(const string name, const datetime t1, const double p1,
                 const datetime t2, const double p2, const color clr,
                 const ENUM_LINE_STYLE style)
{
   if(t1 <= 0 || t2 <= 0)
   {
      HideObj(name);
      return;
   }
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      StyleObject(name, false);
   }
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void HideHistRange(const string base, const int fromIdx, int &drawn)
{
   for(int i = fromIdx; i < drawn; i++)
      ObjectDelete(0, base + IntegerToString(i));
   drawn = fromIdx;
}

void HideZones()
{
   HideObj(PREFIX + "SUP_AREA");
   HideObj(PREFIX + "SUP_AVG");
   HideObj(PREFIX + "SUP_WAVG");
   HideObj(PREFIX + "DEM_AREA");
   HideObj(PREFIX + "DEM_AVG");
   HideObj(PREFIX + "DEM_WAVG");
   HideObj(PREFIX + "EQUI");
   HideObj(PREFIX + "WEQUI");
   HideHistRange(PREFIX + "SUP_H_", 0, g_supHistDrawn);
   HideHistRange(PREFIX + "DEM_H_", 0, g_demHistDrawn);
}

void SetArea(const string boxName, const string avgName, const string wavgName,
             const datetime t1, const datetime t2,
             const double top, const double btm,
             const double avg, const double wavg,
             const color css,
             const bool showArea, const bool showAvg, const bool showWavg)
{
   if(showArea)
      EnsureRect(boxName, t1, top, t2, btm, ApplyTransp(css, TRANS_AREA));
   else
      HideObj(boxName);

   if(showAvg)
      EnsureTrend(avgName, t1, avg, t2, avg, css, STYLE_SOLID);
   else
      HideObj(avgName);

   if(showWavg)
      EnsureTrend(wavgName, t1, wavg, t2, wavg, css, STYLE_DASH);
   else
      HideObj(wavgName);
}

ENUM_TIMEFRAMES EffectiveLtf()
{
   if(InpIntrabarTF == PERIOD_CURRENT)
      return PERIOD_CURRENT;
   if(PeriodSeconds(InpIntrabarTF) >= PeriodSeconds(_Period))
      return PERIOD_CURRENT;
   return InpIntrabarTF;
}

bool GetVisibleShifts(int &leftShift, int &rightShift)
{
   const int total = Bars(_Symbol, PERIOD_CURRENT);
   if(total < 2)
      return false;

   const int first = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   const int vis   = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   if(first < 0 || vis < 1)
      return false;

   leftShift = first;
   if(leftShift >= total)
      leftShift = total - 1;

   rightShift = first - vis + 1;
   if(rightShift < 0)
      rightShift = 0;

   if(leftShift - rightShift + 1 > MAX_BARS_BACK)
      leftShift = rightShift + MAX_BARS_BACK - 1;

   return (leftShift >= rightShift);
}

void AccSample(Bin &supply, Bin &demand, const double h, const double l, const double vol)
{
   const double sAdd = (h > supply.lvl && h < supply.prev) ? vol : 0.0;
   supply.sum += sAdd;
   supply.avg += supply.lvl * sAdd;
   supply.csum += sAdd;
   supply.prev_sum = supply.sum;

   const double dAdd = (l < demand.lvl && l > demand.prev) ? vol : 0.0;
   demand.sum += dAdd;
   demand.avg += demand.lvl * dAdd;
   demand.csum += dAdd;
   demand.prev_sum = demand.sum;
}

bool MapLtfToHtf(const datetime &htfT[], const int nHtf,
                 const datetime &ltfT[], const int nLtf,
                 const int rightShift,
                 int &ltfFrom[], int &ltfTo[])
{
   ArrayResize(ltfFrom, nHtf);
   ArrayResize(ltfTo, nHtf);
   int k = 0;
   for(int i = 0; i < nHtf; i++)
   {
      const datetime t0 = htfT[i];
      datetime t1 = t0 + (datetime)PeriodSeconds(_Period);
      if(i + 1 < nHtf)
         t1 = htfT[i + 1];
      else if(rightShift == 0)
         t1 = (datetime)MathMax((long)t1, (long)TimeCurrent() + 1);

      while(k < nLtf && ltfT[k] < t0)
         k++;
      ltfFrom[i] = k;
      int k2 = k;
      while(k2 < nLtf && ltfT[k2] < t1)
         k2++;
      ltfTo[i] = k2;
   }
   return true;
}

void Recalc()
{
   int leftShift = 0;
   int rightShift = 0;
   if(!GetVisibleShifts(leftShift, rightShift))
   {
      HideZones();
      return;
   }

   datetime visT[];
   double   visH[], visL[];
   long     visVol[];
   ArraySetAsSeries(visT, false);
   ArraySetAsSeries(visH, false);
   ArraySetAsSeries(visL, false);
   ArraySetAsSeries(visVol, false);

   const int count = leftShift - rightShift + 1;
   const int nHtf  = CopyTime(_Symbol, PERIOD_CURRENT, rightShift, count, visT);
   if(nHtf < 2)
   {
      HideZones();
      return;
   }
   if(CopyHigh(_Symbol, PERIOD_CURRENT, rightShift, nHtf, visH) != nHtf ||
      CopyLow(_Symbol, PERIOD_CURRENT, rightShift, nHtf, visL) != nHtf ||
      CopyTickVolume(_Symbol, PERIOD_CURRENT, rightShift, nHtf, visVol) != nHtf)
   {
      HideZones();
      return;
   }

   // Copy*(start_pos, count) + array not-as-series: [0] = oldest (left)
   double maxP = visH[0];
   double minP = visL[0];
   double csum = (double)visVol[0];
   for(int i = 1; i < nHtf; i++)
   {
      if(visH[i] > maxP)
         maxP = visH[i];
      if(visL[i] < minP)
         minP = visL[i];
      csum += (double)visVol[i];
   }

   if(csum <= 0.0 || maxP <= minP)
   {
      HideZones();
      return;
   }

   const datetime tLeft  = visT[0];
   const datetime tRight = visT[nHtf - 1];
   const int      span   = nHtf - 1;
   const int      div    = g_div;
   const double   r      = (maxP - minP) / div;
   const double   per    = ClampDouble(InpThreshold, 0.0, 100.0);

   ENUM_TIMEFRAMES ltf = EffectiveLtf();
   bool useLtf = (ltf != PERIOD_CURRENT);

   double   ltfH[], ltfL[];
   long     ltfV[];
   datetime ltfT[];
   int      ltfFrom[], ltfTo[];
   int      nLtf = 0;

   if(useLtf)
   {
      datetime tStop = visT[nHtf - 1] + (datetime)PeriodSeconds(_Period);
      if(rightShift == 0)
         tStop = (datetime)MathMax((long)tStop, (long)TimeCurrent());

      ArraySetAsSeries(ltfT, false);
      ArraySetAsSeries(ltfH, false);
      ArraySetAsSeries(ltfL, false);
      ArraySetAsSeries(ltfV, false);

      nLtf = CopyTime(_Symbol, ltf, visT[0], tStop, ltfT);
      if(nLtf < 1 ||
         CopyHigh(_Symbol, ltf, visT[0], tStop, ltfH) != nLtf ||
         CopyLow(_Symbol, ltf, visT[0], tStop, ltfL) != nLtf ||
         CopyTickVolume(_Symbol, ltf, visT[0], tStop, ltfV) != nLtf)
      {
         useLtf = false;
      }
      else
         MapLtfToHtf(visT, nHtf, ltfT, nLtf, rightShift, ltfFrom, ltfTo);
   }

   Bin supply;
   supply.lvl = maxP;
   supply.prev = maxP;
   supply.sum = 0.0;
   supply.prev_sum = 0.0;
   supply.csum = 0.0;
   supply.avg = 0.0;
   supply.isreached = false;

   Bin demand;
   demand.lvl = minP;
   demand.prev = minP;
   demand.sum = 0.0;
   demand.prev_sum = 0.0;
   demand.csum = 0.0;
   demand.avg = 0.0;
   demand.isreached = false;

   double supplyWavg = 0.0;
   double demandWavg = 0.0;
   bool   hasSupplyWavg = false;
   bool   hasDemandWavg = false;
   bool   supplyDrawn = false;
   bool   demandDrawn = false;
   bool   equiDrawn = false;

   int supHist = 0;
   int demHist = 0;
   const color supHistClr = ApplyTransp(InpSupplyCss, TRANS_HIST);
   const color demHistClr = ApplyTransp(InpDemandCss, TRANS_HIST);

   for(int i = 0; i < div; i++)
   {
      supply.lvl -= r;
      demand.lvl += r;

      if(!supply.isreached && InpShowSupply && InpSupplyArea && csum > 0.0)
      {
         const int w = (int)(supply.sum / csum * span);
         if(w > 0)
         {
            int idx = w;
            if(idx >= nHtf)
               idx = nHtf - 1;
            EnsureRect(PREFIX + "SUP_H_" + IntegerToString(supHist),
                       tLeft, supply.prev, visT[idx], supply.lvl, supHistClr);
            supHist++;
         }
      }

      if(!demand.isreached && InpShowDemand && InpDemandArea && csum > 0.0)
      {
         const int w = (int)(demand.sum / csum * span);
         if(w > 0)
         {
            int idx = w;
            if(idx >= nHtf)
               idx = nHtf - 1;
            EnsureRect(PREFIX + "DEM_H_" + IntegerToString(demHist),
                       tLeft, demand.lvl, visT[idx], demand.prev, demHistClr);
            demHist++;
         }
      }

      for(int j = nHtf - 1; j >= 1; j--)
      {
         if(useLtf)
         {
            const int from = ltfFrom[j];
            const int to   = ltfTo[j];
            for(int k = from; k < to; k++)
               AccSample(supply, demand, ltfH[k], ltfL[k], (double)ltfV[k]);
         }
         else
            AccSample(supply, demand, visH[j], visL[j], (double)visVol[j]);

         if(csum > 0.0 && supply.sum / csum * 100.0 > per && !supply.isreached)
         {
            const double avg = 0.5 * (maxP + supply.lvl);
            if(supply.csum > 0.0)
            {
               supplyWavg = supply.avg / supply.csum;
               hasSupplyWavg = true;
            }
            if(InpShowSupply)
            {
               SetArea(PREFIX + "SUP_AREA", PREFIX + "SUP_AVG", PREFIX + "SUP_WAVG",
                       tLeft, tRight, maxP, supply.lvl, avg, supplyWavg,
                       InpSupplyCss, InpSupplyArea, InpSupplyAvg, InpSupplyWavg);
               supplyDrawn = true;
            }
            supply.isreached = true;
         }

         if(csum > 0.0 && demand.sum / csum * 100.0 > per && !demand.isreached && InpShowDemand)
         {
            const double avg = 0.5 * (minP + demand.lvl);
            if(demand.csum > 0.0)
            {
               demandWavg = demand.avg / demand.csum;
               hasDemandWavg = true;
            }
            SetArea(PREFIX + "DEM_AREA", PREFIX + "DEM_AVG", PREFIX + "DEM_WAVG",
                    tLeft, tRight, demand.lvl, minP, avg, demandWavg,
                    InpDemandCss, InpDemandArea, InpDemandAvg, InpDemandWavg);
            demandDrawn = true;
            demand.isreached = true;
         }

         if(supply.isreached && demand.isreached)
            break;
      }

      if(supply.isreached && demand.isreached && InpShowEqui)
      {
         if(InpEquiAvg)
            EnsureTrend(PREFIX + "EQUI", tLeft, 0.5 * (maxP + minP),
                        tRight, 0.5 * (maxP + minP), InpEquiCss, STYLE_SOLID);
         else
            HideObj(PREFIX + "EQUI");

         if(InpEquiWavg && hasSupplyWavg && hasDemandWavg)
         {
            const double wavg = 0.5 * (supplyWavg + demandWavg);
            EnsureTrend(PREFIX + "WEQUI", tLeft, wavg, tRight, wavg, InpEquiCss, STYLE_DASH);
         }
         else
            HideObj(PREFIX + "WEQUI");

         equiDrawn = true;
         break;
      }

      supply.prev = supply.lvl;
      demand.prev = demand.lvl;
   }

   if(!supplyDrawn)
   {
      HideObj(PREFIX + "SUP_AREA");
      HideObj(PREFIX + "SUP_AVG");
      HideObj(PREFIX + "SUP_WAVG");
   }
   else
   {
      if(!InpSupplyArea)
         HideObj(PREFIX + "SUP_AREA");
      if(!InpSupplyAvg)
         HideObj(PREFIX + "SUP_AVG");
      if(!InpSupplyWavg)
         HideObj(PREFIX + "SUP_WAVG");
   }

   if(!demandDrawn)
   {
      HideObj(PREFIX + "DEM_AREA");
      HideObj(PREFIX + "DEM_AVG");
      HideObj(PREFIX + "DEM_WAVG");
   }
   else
   {
      if(!InpDemandArea)
         HideObj(PREFIX + "DEM_AREA");
      if(!InpDemandAvg)
         HideObj(PREFIX + "DEM_AVG");
      if(!InpDemandWavg)
         HideObj(PREFIX + "DEM_WAVG");
   }

   if(!equiDrawn)
   {
      HideObj(PREFIX + "EQUI");
      HideObj(PREFIX + "WEQUI");
   }

   HideHistRange(PREFIX + "SUP_H_", supHist, g_supHistDrawn);
   HideHistRange(PREFIX + "DEM_H_", demHist, g_demHistDrawn);
   g_supHistDrawn = supHist;
   g_demHistDrawn = demHist;

   ChartRedraw(0);
}

bool VisibleStateUnchanged(const int leftShift, const int rightShift)
{
   if(leftShift != g_leftShift || rightShift != g_rightShift)
      return false;

   datetime tLeft[], tRight[];
   if(CopyTime(_Symbol, PERIOD_CURRENT, leftShift, 1, tLeft) != 1)
      return false;
   if(CopyTime(_Symbol, PERIOD_CURRENT, rightShift, 1, tRight) != 1)
      return false;
   if(tLeft[0] != g_leftTime || tRight[0] != g_rightTime)
      return false;

   double h[], l[];
   long   v[];
   if(CopyHigh(_Symbol, PERIOD_CURRENT, rightShift, 1, h) != 1)
      return false;
   if(CopyLow(_Symbol, PERIOD_CURRENT, rightShift, 1, l) != 1)
      return false;
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, rightShift, 1, v) != 1)
      return false;

   return (h[0] == g_rightHigh && l[0] == g_rightLow && v[0] == g_rightVol);
}

void RememberVisibleState(const int leftShift, const int rightShift)
{
   g_leftShift = leftShift;
   g_rightShift = rightShift;

   datetime tLeft[], tRight[];
   if(CopyTime(_Symbol, PERIOD_CURRENT, leftShift, 1, tLeft) == 1)
      g_leftTime = tLeft[0];
   if(CopyTime(_Symbol, PERIOD_CURRENT, rightShift, 1, tRight) == 1)
      g_rightTime = tRight[0];

   double h[], l[];
   long   v[];
   if(CopyHigh(_Symbol, PERIOD_CURRENT, rightShift, 1, h) == 1)
      g_rightHigh = h[0];
   if(CopyLow(_Symbol, PERIOD_CURRENT, rightShift, 1, l) == 1)
      g_rightLow = l[0];
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, rightShift, 1, v) == 1)
      g_rightVol = v[0];
}

void RecalcIfNeeded(const bool force)
{
   int leftShift = 0;
   int rightShift = 0;
   if(!GetVisibleShifts(leftShift, rightShift))
   {
      HideZones();
      return;
   }

   if(!force && VisibleStateUnchanged(leftShift, rightShift))
      return;

   Recalc();
   RememberVisibleState(leftShift, rightShift);
}

int OnInit()
{
   g_div = ClampInt(InpResolution, 2, MAX_DIV);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("S&D Visible Range (%.1f,%d)", InpThreshold, g_div));
   g_leftShift = -1;
   return INIT_SUCCEEDED;
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
   RecalcIfNeeded(prev_calculated == 0);
   return rates_total;
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
      RecalcIfNeeded(true);
}
