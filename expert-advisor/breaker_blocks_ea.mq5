#property copyright "Copyright 2026, User"
#property version   "1.30"
#property strict

#include <Trade\Trade.mqh>

#define CMT_L1      "BBWS_L1"
#define CMT_L2      "BBWS_L2"
#define ZZ_SIZE     50
#define MAX_ZZ_DRAW 80

enum ENUM_LOT_MODE
{
   LOT_FIXED        = 0, // Lot tetap per layer
   LOT_RISK_PERCENT = 1  // Auto dari risk % total
};

input group "=== Market Structure ==="
input int    InpLength            = 5;     // Length pivot
input int    InpLookback          = 2000;  // Max bars scan
input bool   InpShowZZ            = true;  // Tampilkan ZigZag
input bool   InpOnlyBody          = false; // Use only candle body
input bool   InpTwoCandles        = false; // Use 2 candles
input bool   InpOnlyWhenInPD      = false; // Filter PD array

input group "=== Entry ==="
input bool   InpAllowBuy          = true;
input bool   InpAllowSell         = true;

input group "=== SL (buffer wick M5) ==="
input int    InpSlAtrPeriod       = 14;
input double InpSlAtrMult         = 0.35;
input int    InpSlWickBars        = 20;
input double InpSlWickMult        = 1.5;
input int    InpSlExtraPoints     = 80;
input bool   InpSlAddSpread       = true;

input group "=== Lot / Risk ==="
input ENUM_LOT_MODE InpLotMode        = LOT_RISK_PERCENT;
input double        InpLotPerLayer    = 0.02;
input double        InpRiskPercent    = 1.0;
input bool          InpRiskUseEquity  = false;
input double        InpMaxLotPerLayer = 0.0;

input group "=== Order ==="
input ulong  InpMagic            = 260902;
input int    InpMaxSpread        = 80;
input int    InpDeviation        = 30;
input bool   InpOneSetup         = true;

input group "=== Lainnya ==="
input bool   InpShowDashboard    = true;

CTrade   trade;
string   PREF;
string   g_setupKey;
datetime g_lastBarTime = 0;
int      g_atrHandle   = INVALID_HANDLE;
int      g_zzDrawn     = 0;

const int DASH_X   = 8;
const int DASH_Y   = 18;
const int DASH_ROW = 17;

struct BBSetup
{
   int      dir;
   int      createdIdx;
   datetime signalTime;
   double   bbTop;
   double   bbBot;
   double   bbMid;
   double   sw1;
   double   sw2;
   double   pd1;
   double   pd2;
   double   tp1;
   double   tp2;
   double   sl;
   bool     valid;
   bool     broken;
   bool     mitigated;
   bool     hasSignal;
};

struct ZZPoint
{
   int      dir;
   int      idx;
   datetime time;
   double   price;
};

ZZPoint g_zz[ZZ_SIZE];
int     g_zzCount = 0;
int     g_mssDir  = 0;
BBSetup g_core;

double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0)
      stepLot = 0.01;
   lot = MathFloor(lot / stepLot + 1e-12) * stepLot;
   if(InpMaxLotPerLayer > 0.0 && lot > InpMaxLotPerLayer)
      lot = MathFloor(InpMaxLotPerLayer / stepLot + 1e-12) * stepLot;
   if(lot < minLot)
      lot = minLot;
   if(lot > maxLot)
      lot = maxLot;
   return lot;
}

double GetRiskBase()
{
   return InpRiskUseEquity ? AccountInfoDouble(ACCOUNT_EQUITY)
                           : AccountInfoDouble(ACCOUNT_BALANCE);
}

double PointSize()
{
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (pt > 0.0 ? pt : 0.00001);
}

double MinStopDistance()
{
   long lv = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                     SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   if(lv < 1)
      lv = 1;
   return (double)lv * PointSize();
}

bool IsSpreadOk()
{
   if(InpMaxSpread <= 0)
      return true;
   return (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpread);
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == g_lastBarTime)
      return false;
   g_lastBarTime = t;
   return true;
}

double AvgM5Wick(const bool upper, const int bars)
{
   int n = MathMax(bars, 5);
   double sum = 0.0;
   int cnt = 0;
   for(int i = 1; i <= n; i++)
   {
      double o = iOpen(_Symbol, PERIOD_M5, i);
      double h = iHigh(_Symbol, PERIOD_M5, i);
      double l = iLow(_Symbol, PERIOD_M5, i);
      double c = iClose(_Symbol, PERIOD_M5, i);
      if(h <= 0.0 || l <= 0.0)
         continue;
      double w = upper ? (h - MathMax(o, c)) : (MathMin(o, c) - l);
      if(w > 0.0)
      {
         sum += w;
         cnt++;
      }
   }
   return (cnt > 0 ? sum / (double)cnt : 0.0);
}

double SlBufferPrice(const bool bearish)
{
   double atr = 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 1, 1, buf) == 1)
      atr = buf[0];

   double wick = AvgM5Wick(bearish, InpSlWickBars);
   double slb  = 0.0;
   if(atr > 0.0)
      slb = MathMax(slb, atr * InpSlAtrMult);
   if(wick > 0.0)
      slb = MathMax(slb, wick * InpSlWickMult);
   slb += (double)MathMax(InpSlExtraPoints, 0) * PointSize();
   if(InpSlAddSpread)
      slb += (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * PointSize();
   return MathMax(slb, MinStopDistance());
}

void FinalizeSetup(BBSetup &s)
{
   if(!s.valid)
      return;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(s.dir == 1)
   {
      s.sl  = NormalizeDouble(s.sw2 - SlBufferPrice(false), dg);
      s.tp1 = NormalizeDouble(MathMin(s.pd1, s.pd2), dg);
      s.tp2 = NormalizeDouble(MathMax(s.pd1, s.pd2), dg);
   }
   else
   {
      s.sl  = NormalizeDouble(s.sw2 + SlBufferPrice(true), dg);
      s.tp1 = NormalizeDouble(MathMax(s.pd1, s.pd2), dg);
      s.tp2 = NormalizeDouble(MathMin(s.pd1, s.pd2), dg);
   }
   s.bbTop = NormalizeDouble(s.bbTop, dg);
   s.bbBot = NormalizeDouble(s.bbBot, dg);
   s.bbMid = NormalizeDouble(s.bbMid, dg);
   s.sw1   = NormalizeDouble(s.sw1, dg);
   s.sw2   = NormalizeDouble(s.sw2, dg);
   s.pd1   = NormalizeDouble(s.pd1, dg);
   s.pd2   = NormalizeDouble(s.pd2, dg);
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

bool IsPivotHigh(const int pivot, const int left, const MqlRates &r[], const int lastBar)
{
   if(pivot < left || pivot + 1 > lastBar)
      return false;
   const double v = r[pivot].high;
   for(int k = pivot - left; k <= pivot + 1; k++)
   {
      if(k == pivot)
         continue;
      if(r[k].high >= v)
         return false;
   }
   return true;
}

bool IsPivotLow(const int pivot, const int left, const MqlRates &r[], const int lastBar)
{
   if(pivot < left || pivot + 1 > lastBar)
      return false;
   const double v = r[pivot].low;
   for(int k = pivot - left; k <= pivot + 1; k++)
   {
      if(k == pivot)
         continue;
      if(r[k].low <= v)
         return false;
   }
   return true;
}

double BodyHigh(const MqlRates &r[], const int i) { return MathMax(r[i].open, r[i].close); }
double BodyLow(const MqlRates &r[], const int i)  { return MathMin(r[i].open, r[i].close); }

void FillRange(const MqlRates &r[], const int j, double &top, double &bot)
{
   if(InpOnlyBody)
   {
      top = BodyHigh(r, j);
      bot = BodyLow(r, j);
   }
   else
   {
      top = r[j].high;
      bot = r[j].low;
   }
}

void CombineSecond(const MqlRates &r[], const int j, const bool bull, int &idx, double &top, double &bot)
{
   const int older = j - 1;
   if(older < 0)
      return;
   const bool same = bull ? (r[older].close > r[older].open) : (r[older].close < r[older].open);
   if(!same)
      return;
   double t2, b2;
   FillRange(r, older, t2, b2);
   if(t2 > top || b2 < bot)
      idx = older;
   top = MathMax(top, t2);
   bot = MathMin(bot, b2);
}

void FillPD(const int dir, const int n, const MqlRates &r[], double &pd1, double &pd2)
{
   pd1 = 0.0;
   pd2 = 0.0;
   int cnt = 0;
   if(dir == 1)
   {
      double hh1 = r[n].high;
      for(int c = 0; c < g_zzCount - 1; c++)
      {
         const int getX = g_zz[c].idx;
         const double getY = g_zz[c].price;
         if(g_zz[c].dir != 1 || getY <= hh1 || getX < 0 || getX >= n)
            continue;
         const double getY2 = (r[getX].high - BodyLow(r, getX)) / 4.0;
         if(cnt == 0)
         {
            pd1 = getY;
            cnt = 1;
            hh1 = getY;
         }
         else if(getY - getY2 > hh1)
         {
            pd2 = getY;
            break;
         }
      }
   }
   else
   {
      double ll1 = r[n].low;
      for(int c = 0; c < g_zzCount - 1; c++)
      {
         const int getX = g_zz[c].idx;
         const double getY = g_zz[c].price;
         if(g_zz[c].dir != -1 || getY >= ll1 || getX < 0 || getX >= n)
            continue;
         const double getY2 = (BodyHigh(r, getX) - r[getX].low) / 4.0;
         if(cnt == 0)
         {
            pd1 = getY;
            cnt = 1;
            ll1 = getY;
         }
         else if(getY + getY2 < ll1)
         {
            pd2 = getY;
            break;
         }
      }
   }
}

void SetCoreBB(const int dir, const int n, const MqlRates &r[],
               const double top, const double bot,
               const double sw1, const double sw2)
{
   ZeroMemory(g_core);
   g_core.dir        = dir;
   g_core.createdIdx = n;
   g_core.bbTop      = top;
   g_core.bbBot      = bot;
   g_core.bbMid      = (top + bot) / 2.0;
   g_core.sw1        = sw1;
   g_core.sw2        = sw2;
   FillPD(dir, n, r, g_core.pd1, g_core.pd2);
   g_core.valid = (top > bot && sw1 > 0.0 && sw2 > 0.0 && g_core.pd1 > 0.0 && g_core.pd2 > 0.0);
   FinalizeSetup(g_core);
}

void UpdateBB(const int n, const MqlRates &r[])
{
   if(g_core.dir == 0 || g_core.mitigated)
      return;

   const double top = g_core.bbTop;
   const double btm = g_core.bbBot;
   const double avg = g_core.bbMid;
   const bool after = (n > g_core.createdIdx);

   if(g_core.dir == 1)
   {
      if(r[n].close < btm)
      {
         g_core.mitigated = true;
         return;
      }
      if(after && !g_core.broken)
      {
         if(r[n].open > avg && r[n].open < top && r[n].close > top)
         {
            g_core.hasSignal  = true;
            g_core.signalTime = r[n].time;
         }
         else if(r[n].close < avg && r[n].close > btm)
            g_core.broken = true;
      }
   }
   else
   {
      if(r[n].close > top)
      {
         g_core.mitigated = true;
         return;
      }
      if(after && !g_core.broken)
      {
         if(r[n].open < avg && r[n].open > btm && r[n].close < btm)
         {
            g_core.hasSignal  = true;
            g_core.signalTime = r[n].time;
         }
         else if(r[n].close > avg && r[n].close < top)
            g_core.broken = true;
      }
   }
}

void UpdateZigZag(const int n, const int left, const MqlRates &r[])
{
   const int pivot = n - 1;
   if(pivot < left)
      return;

   if(IsPivotHigh(pivot, left, r, n))
   {
      const int dir = ZZDir(0);
      if(dir < 1)
         ZZUnshift(1, pivot, r[pivot].time, r[pivot].high);
      else if(dir == 1 && r[pivot].high > g_zz[0].price)
      {
         g_zz[0].idx   = pivot;
         g_zz[0].time  = r[pivot].time;
         g_zz[0].price = r[pivot].high;
      }
   }

   if(IsPivotLow(pivot, left, r, n))
   {
      const int dir = ZZDir(0);
      if(dir > -1)
         ZZUnshift(-1, pivot, r[pivot].time, r[pivot].low);
      else if(dir == -1 && r[pivot].low < g_zz[0].price)
      {
         g_zz[0].idx   = pivot;
         g_zz[0].time  = r[pivot].time;
         g_zz[0].price = r[pivot].low;
      }
   }
}

void TryCreateMSS(const int n, const int total, const MqlRates &r[])
{
   const int iH = (ZZDir(2) == 1) ? 2 : 1;
   const int iL = (ZZDir(2) == -1) ? 2 : 1;

   if(iH + 3 < g_zzCount &&
      r[n].close > ZZPrice(iH) && ZZDir(iH) == 1 && g_mssDir < 1)
   {
      const int    Ex = ZZIdx(iH - 1);
      const double Ey = ZZPrice(iH - 1);
      const int    Dx = ZZIdx(iH);
      const int    Cx = ZZIdx(iH + 1);
      const double Cy = ZZPrice(iH + 1);
      const int    Bx = ZZIdx(iH + 2);
      const int    Ax = ZZIdx(iH + 3);
      const double Ay = ZZPrice(iH + 3);

      if(Dx >= 0 && Dx < n && Cx >= 0 && Cx <= n && Bx >= 0 && Bx < n && Ax >= 0 && Ax < n && Ex >= 0 && Ex <= n)
      {
         const double yMax = MathMax(BodyHigh(r, Bx), BodyHigh(r, Dx));
         const double AyMn = BodyLow(r, Ax);
         const double mid  = AyMn + ((yMax - AyMn) / 2.0);
         const bool   isOK = InpOnlyWhenInPD ? (Ay < Cy && Ay < Ey && Ey < mid) : true;
         if(Ey < Cy && Cx != Dx && isOK)
         {
            for(int j = Dx; j >= Cx; j--)
            {
               if(r[j].close > r[j].open)
               {
                  int idx = j;
                  double top, bot;
                  FillRange(r, j, top, bot);
                  if(InpTwoCandles)
                     CombineSecond(r, j, true, idx, top, bot);
                  SetCoreBB(1, n, r, top, bot, Cy, Ey);
                  break;
               }
            }
         }
      }
      g_mssDir = 1;
   }
   else if(iL + 3 < g_zzCount &&
           r[n].close < ZZPrice(iL) && ZZDir(iL) == -1 && g_mssDir > -1)
   {
      const int    Ex = ZZIdx(iL - 1);
      const double Ey = ZZPrice(iL - 1);
      const int    Dx = ZZIdx(iL);
      const int    Cx = ZZIdx(iL + 1);
      const double Cy = ZZPrice(iL + 1);
      const int    Bx = ZZIdx(iL + 2);
      const int    Ax = ZZIdx(iL + 3);
      const double Ay = ZZPrice(iL + 3);

      if(Dx >= 0 && Dx < n && Cx >= 0 && Cx <= n && Bx >= 0 && Bx < n && Ax >= 0 && Ax < n && Ex >= 0 && Ex <= n)
      {
         const double yMin = MathMin(BodyLow(r, Bx), BodyLow(r, Dx));
         const double AyMx = BodyHigh(r, Ax);
         const double mid  = AyMx - ((AyMx - yMin) / 2.0);
         const bool   isOK = InpOnlyWhenInPD ? (Ay > Cy && Ay > Ey && Ey > mid) : true;
         if(Ey > Cy && Cx != Dx && isOK)
         {
            for(int j = Dx; j >= Cx; j--)
            {
               if(r[j].close < r[j].open)
               {
                  int idx = j;
                  double top, bot;
                  FillRange(r, j, top, bot);
                  if(InpTwoCandles)
                     CombineSecond(r, j, false, idx, top, bot);
                  SetCoreBB(-1, n, r, top, bot, Cy, Ey);
                  break;
               }
            }
         }
      }
      g_mssDir = -1;
   }
}

void CoreScan()
{
   g_zzCount = 0;
   g_mssDir  = 0;
   ZeroMemory(g_core);
   for(int i = 0; i < ZZ_SIZE; i++)
   {
      g_zz[i].dir   = 0;
      g_zz[i].idx   = 0;
      g_zz[i].time  = 0;
      g_zz[i].price = 0.0;
   }

   MqlRates r[];
   const int left = MathMax(InpLength, 1);
   int need = InpLookback + 80;
   if(need < 200)
      need = 200;
   const int copied = CopyRates(_Symbol, _Period, 0, need, r);
   if(copied < left + 10)
      return;
   ArraySetAsSeries(r, false);

   for(int n = left + 1; n < copied; n++)
   {
      UpdateZigZag(n, left, r);
      TryCreateMSS(n, copied, r);
      UpdateBB(n, r);
   }

   if(g_core.hasSignal)
   {
      datetime closed = iTime(_Symbol, _Period, 1);
      if(g_core.signalTime != closed)
         g_core.hasSignal = false;
   }
}

bool IsOurMagic(const long magic) { return (magic == (long)InpMagic); }

int CountOurPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)))
         continue;
      n++;
   }
   return n;
}

int CountOurPendings()
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(!IsOurMagic(OrderGetInteger(ORDER_MAGIC)))
         continue;
      n++;
   }
   return n;
}

int CountPendingComment(const string cmt)
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(!IsOurMagic(OrderGetInteger(ORDER_MAGIC)))
         continue;
      if(OrderGetString(ORDER_COMMENT) == cmt)
         n++;
   }
   return n;
}

int CountPositionComment(const string cmt)
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)))
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), cmt) == 0)
         n++;
   }
   return n;
}

string LayerComment(const string base, const BBSetup &s)
{
   int tag = (int)MathRound(MathAbs(s.sw2) / PointSize()) % 100000;
   return base + "_" + IntegerToString(tag);
}

bool LayerExists(const string cmt)
{
   return (CountPendingComment(cmt) > 0 || CountPositionComment(cmt) > 0);
}

void DeleteOurPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(!IsOurMagic(OrderGetInteger(ORDER_MAGIC)))
         continue;
      trade.OrderDelete(ticket);
   }
}

string SetupKey(const BBSetup &s)
{
   return IntegerToString(s.dir) + "|" +
          TimeToString(s.signalTime, TIME_DATE|TIME_MINUTES) + "|" +
          DoubleToString(s.pd1, _Digits) + "|" +
          DoubleToString(s.pd2, _Digits);
}

bool ReadSetup(BBSetup &s)
{
   s = g_core;
   return s.valid;
}

int TotalLayersPlanned() { return 2; }

double CalcLot(const ENUM_ORDER_TYPE type, const double entry, const double sl, const int layers)
{
   if(InpLotMode == LOT_FIXED || layers <= 0)
      return NormalizeLot(InpLotPerLayer);

   double profit = 0.0;
   if(!OrderCalcProfit(type, _Symbol, 1.0, entry, sl, profit))
      return NormalizeLot(InpLotPerLayer);
   double lossPerLot = MathAbs(profit);
   if(lossPerLot <= 0.0)
      return NormalizeLot(InpLotPerLayer);
   double riskMoney = GetRiskBase() * InpRiskPercent / 100.0;
   return NormalizeLot((riskMoney / (double)layers) / lossPerLot);
}

bool SetupSane(const BBSetup &s)
{
   double minDist = MinStopDistance();
   if(s.pd1 <= 0.0 || s.pd2 <= 0.0)
      return false;
   if(s.dir == -1)
   {
      if(s.sl <= s.sw2)
         return false;
      if(s.tp1 >= s.bbBot || s.tp2 >= s.bbBot)
         return false;
      if(s.sl - s.bbMid < minDist)
         return false;
   }
   else
   {
      if(s.sl >= s.sw2)
         return false;
      if(s.tp1 <= s.bbTop || s.tp2 <= s.bbTop)
         return false;
      if(s.bbMid - s.sl < minDist)
         return false;
   }
   return true;
}

bool IsMitigated(const BBSetup &s)
{
   double close0 = iClose(_Symbol, _Period, 0);
   if(s.dir == 1)
      return (close0 < s.bbBot);
   return (close0 > s.bbTop);
}

bool PlaceMarket(const bool buy, const double lot, const double sl, const double tp, const string comment)
{
   if(lot <= 0.0 || sl <= 0.0 || tp <= 0.0)
      return false;

   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sln = NormalizeDouble(sl, dg);
   double tpn = NormalizeDouble(tp, dg);
   double minDist = MinStopDistance();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(buy)
   {
      if(sln >= ask || tpn <= ask)
         return false;
      if(ask - sln < minDist)
         sln = NormalizeDouble(ask - minDist, dg);
      if(tpn - ask < minDist)
         return false;
      if(!trade.Buy(lot, _Symbol, ask, sln, tpn, comment))
      {
         Print("Buy gagal ", comment, ": ", trade.ResultRetcodeDescription());
         return false;
      }
      Print("BUY ", comment, " lot=", DoubleToString(lot, 2),
            " @ ", DoubleToString(ask, dg),
            " SL=", DoubleToString(sln, dg),
            " TP=", DoubleToString(tpn, dg));
   }
   else
   {
      if(sln <= bid || tpn >= bid)
         return false;
      if(sln - bid < minDist)
         sln = NormalizeDouble(bid + minDist, dg);
      if(bid - tpn < minDist)
         return false;
      if(!trade.Sell(lot, _Symbol, bid, sln, tpn, comment))
      {
         Print("Sell gagal ", comment, ": ", trade.ResultRetcodeDescription());
         return false;
      }
      Print("SELL ", comment, " lot=", DoubleToString(lot, 2),
            " @ ", DoubleToString(bid, dg),
            " SL=", DoubleToString(sln, dg),
            " TP=", DoubleToString(tpn, dg));
   }
   return true;
}

bool PlaceSetup(const BBSetup &s)
{
   if(!s.valid || !s.hasSignal || !SetupSane(s))
      return false;
   if(s.dir == 1 && !InpAllowBuy)
      return false;
   if(s.dir == -1 && !InpAllowSell)
      return false;
   if(!IsSpreadOk())
      return false;

   const bool buy = (s.dir == 1);
   const ENUM_ORDER_TYPE ot = buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const int layers = 2;
   double price = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                      : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   string c1 = LayerComment(CMT_L1, s);
   string c2 = LayerComment(CMT_L2, s);

   int placed = 0;
   if(!LayerExists(c1) && PlaceMarket(buy, CalcLot(ot, price, s.sl, layers), s.sl, s.tp1, c1))
      placed++;
   if(!LayerExists(c2) && PlaceMarket(buy, CalcLot(ot, price, s.sl, layers), s.sl, s.tp2, c2))
      placed++;

   if(placed > 0)
   {
      g_setupKey = SetupKey(s);
      Print("Signal ", (buy ? "UP" : "DN"),
            " ", placed, " layer | PD1=", DoubleToString(s.tp1, _Digits),
            " PD2=", DoubleToString(s.tp2, _Digits),
            " | key=", g_setupKey);
      return true;
   }
   return false;
}

void EaTrend(const string name, const datetime t1, const double p1,
             const datetime t2, const double p2, const color clr, const int width)
{
   if(t1 <= 0 || t2 <= 0 || p1 <= 0.0 || p2 <= 0.0)
      return;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void EaRect(const string name, const datetime t1, const double p1,
            const datetime t2, const double p2, const color clr)
{
   if(t1 <= 0 || t2 <= 0 || p1 <= 0.0 || p2 <= 0.0)
      return;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void EaHLine(const string name, const double price, const color clr, const ENUM_LINE_STYLE style)
{
   if(price <= 0.0)
      return;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

void HideEa(const string name)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

void DrawZigZagCore()
{
   int used = 0;
   if(InpShowZZ)
   {
      for(int i = 0; i < g_zzCount - 1 && used < MAX_ZZ_DRAW; i++)
      {
         if(g_zz[i].time <= 0 || g_zz[i + 1].time <= 0)
            continue;
         color col = (g_zz[i].dir == 1) ? clrDodgerBlue : clrDarkOrange;
         EaTrend(PREF + "ZZ_" + IntegerToString(used),
                 g_zz[i + 1].time, g_zz[i + 1].price,
                 g_zz[i].time, g_zz[i].price, col, 2);
         used++;
      }
   }
   for(int i = used; i < g_zzDrawn; i++)
      HideEa(PREF + "ZZ_" + IntegerToString(i));
   g_zzDrawn = used;
}

void DrawSetupVisuals(const BBSetup &s)
{
   datetime t1 = iTime(_Symbol, _Period, 40);
   datetime t2 = iTime(_Symbol, _Period, 0);
   if(t1 <= 0)
      t1 = TimeCurrent() - PeriodSeconds() * 40;
   if(t2 <= 0)
      t2 = TimeCurrent();

   if(!s.valid)
   {
      HideEa(PREF + "VIS_BOX");
      HideEa(PREF + "VIS_MID");
      HideEa(PREF + "VIS_SW1");
      HideEa(PREF + "VIS_SW2");
      HideEa(PREF + "VIS_TP1");
      HideEa(PREF + "VIS_TP2");
      HideEa(PREF + "VIS_SL");
      return;
   }

   const color boxClr = (s.dir == 1) ? C'12,181,26' : C'255,17,0';
   EaRect(PREF + "VIS_BOX", t1, s.bbTop, t2 + PeriodSeconds() * 8, s.bbBot, boxClr);
   EaHLine(PREF + "VIS_MID", s.bbMid, clrSilver, STYLE_DASH);
   EaHLine(PREF + "VIS_SW1", s.sw1, clrGold, STYLE_SOLID);
   EaHLine(PREF + "VIS_SW2", s.sw2, clrOrange, STYLE_SOLID);
   EaHLine(PREF + "VIS_TP1", s.tp1, C'33,87,243', STYLE_DOT);
   EaHLine(PREF + "VIS_TP2", s.tp2, C'33,87,243', STYLE_DOT);
   EaHLine(PREF + "VIS_SL",  s.sl,  clrRed, STYLE_DASH);
}

void ManageSetup()
{
   BBSetup s;
   if(!ReadSetup(s) || !s.hasSignal)
      return;

   const string key = SetupKey(s);
   if(key == g_setupKey)
      return;

   if(InpOneSetup && CountOurPositions() > 0)
      return;

   PlaceSetup(s);
}

void CreateLabel(const string name, const int x, const int y, const string text, const color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void UpdateDashboard()
{
   if(!InpShowDashboard)
      return;

   int y = DASH_Y;
   CreateLabel(PREF + "t", DASH_X, y, "Breaker Blocks EA", clrDodgerBlue);
   y += DASH_ROW;
   CreateLabel(PREF + "zz", DASH_X, y,
               "ZigZag: " + IntegerToString(g_zzCount) + " titik | MSS " + IntegerToString(g_mssDir),
               clrBlack);
   y += DASH_ROW;
   CreateLabel(PREF + "pos", DASH_X, y,
               "Pos " + IntegerToString(CountOurPositions()) +
               " | Pend " + IntegerToString(CountOurPendings()) +
               " | Spr " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)),
               clrBlack);
   y += DASH_ROW;

   if(!g_core.valid)
   {
      CreateLabel(PREF + "st", DASH_X, y, "Menunggu MSS + breaker candle...", clrGray);
      return;
   }

   string side = (g_core.dir == 1) ? "+BB" : "-BB";
   if(g_core.hasSignal)
      side += (g_core.dir == 1) ? "  SIGNAL UP" : "  SIGNAL DN";
   else if(g_core.mitigated)
      side += "  mitigated";
   else if(g_core.broken)
      side += "  cancel";
   else
      side += "  wait signal";

   color sc = clrGray;
   if(g_core.hasSignal)
      sc = (g_core.dir == 1) ? clrLime : clrOrange;
   else if(g_core.dir == 1)
      sc = clrForestGreen;
   else
      sc = clrFireBrick;

   CreateLabel(PREF + "st", DASH_X, y, side, sc);
   y += DASH_ROW;
   CreateLabel(PREF + "bb", DASH_X, y,
               "BB " + DoubleToString(g_core.bbBot, _Digits) + " .. " + DoubleToString(g_core.bbTop, _Digits),
               clrBlack);
   y += DASH_ROW;
   CreateLabel(PREF + "pd", DASH_X, y,
               "PD1 " + DoubleToString(g_core.tp1, _Digits) +
               " | PD2 " + DoubleToString(g_core.tp2, _Digits),
               clrTeal);
   y += DASH_ROW;
   CreateLabel(PREF + "sl", DASH_X, y,
               "SL " + DoubleToString(g_core.sl, _Digits) + "  (SW2 + wick M5)",
               clrOrangeRed);
}

int OnInit()
{
   PREF = "BBWSEA_" + IntegerToString(InpMagic) + "_";
   g_setupKey = "";
   g_zzDrawn  = 0;
   ZeroMemory(g_core);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviation);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_atrHandle = iATR(_Symbol, PERIOD_M5, InpSlAtrPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      g_atrHandle = iATR(_Symbol, _Period, InpSlAtrPeriod);

   TesterHideIndicators(true);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
   }
   ObjectsDeleteAll(0, PREF);
}

void OnTick()
{
   CoreScan();
   DrawZigZagCore();
   DrawSetupVisuals(g_core);
   UpdateDashboard();

   static datetime lastTry = 0;
   datetime now = TimeCurrent();
   if(!IsNewBar() && (now - lastTry < 1))
      return;
   lastTry = now;

   ManageSetup();
}
