//+------------------------------------------------------------------+
//|                                 momentum_candle_fibo_system.mq5 |
//|                                                                  |
//|  Sinyal = momentum candle (aturan sama dengan momentumcandle).   |
//|  Saat candle itu close (auto) atau Setup (manual):               |
//|    limit di fibo 23.6 dan 50                                     |
//|    semua kaki SL 74.5, TP -27                                    |
//|    tanpa market buy/sell saat close candle                       |
//|                                                                  |
//|  0% ada di ujung momentum (bullish = high, bearish = low)        |
//|  supaya 23.6 / 50 adalah retrace, 74.5 di belakang entry,        |
//|  dan -27 adalah ekstensi profit.                                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "Momentum candle: limit 23.6 & 50, SL 74.5, TP -27. Tanpa market close."

#include <Trade\Trade.mqh>

enum ENUM_MOM_SHOW
{
   MOM_SHOW_BOTH    = 0, // Bullish & Bearish
   MOM_SHOW_BULLISH = 1, // Bullish saja
   MOM_SHOW_BEARISH = 2  // Bearish saja
};

enum ENUM_EXEC_MODE
{
   EXEC_MANUAL = 0, // Manual
   EXEC_AUTO   = 1  // Auto (limit 23.6 & 50 saat close)
};

enum ENUM_LOT_MODE
{
   LOT_MANUAL    = 0, // Lot manual
   LOT_AUTO_RISK = 1  // Auto lot dari risk %
};

input group "--- EKSEKUSI ---"
input ENUM_EXEC_MODE InpExecMode = EXEC_MANUAL; // Mode awal
input int            InpLimitExpireMinutes = 60; // Umur limit (menit), 0 = tidak batal karena waktu

input group "--- MOMENTUM CANDLE ---"
input ENUM_MOM_SHOW InpShowSide    = MOM_SHOW_BOTH; // Tampilkan sisi
input double        InpBodyPercent = 60.0;          // Minimal body vs range (%)
input int           InpBreakCandles = 2;            // Minimal break candle sebelumnya
input int           InpAtrPeriod   = 14;            // Period ATR filter ukuran
input double        InpMinAtrMult  = 0.6;           // Minimal range = ATR x multiplier
input int           InpScanBars    = 300;           // Kedalaman scan momentum candle

input group "--- FIBO ---"
input double InpFiboLimit236 = 23.6;  // Limit 23.6
input double InpFiboLimit50  = 50.0;  // Limit 50
input double InpSlLevel      = 74.5;  // SL semua kaki
input double InpTpLevel      = -27.0; // TP semua kaki
input color  InpFiboColor    = clrDodgerBlue;
input int    InpFiboWidth    = 2;
input bool   InpFiboRayRight = true;  // Ray ke kanan

input group "--- RISK ---"
input ENUM_LOT_MODE InpLotMode            = LOT_AUTO_RISK; // Mode lot
input double        InpRiskPercent        = 0.1;           // Risk % (max 1%, dibagi 2 kaki)
input bool          InpHardDailyStop      = true;          // Hard Daily Stop (close semua + disable)
input double        InpMaxDailyLossPercent = 1.0;          // Hard stop jika Daily PnL+floating <= -%
input int           InpMaxTradesPerDay    = 16;            // Max trades per hari (dari history)
input int           InpMaxOpenSimultaneous = 6;            // Max posisi/order terbuka bersamaan
input ulong         InpMagicNumber        = 23018;         // Magic (beda tiap chart)
input int           InpDeviation          = 20;            // Slippage (points)
input group "--- TAMPILAN DASHBOARD ---"
input int InpHeaderY  = 6;   // Posisi header dari atas (kecilkan jika kepotong)
input int InpFieldGap = 25;  // Jarak baris Layers-Risk
input int InpBtnH     = 26;  // Tinggi tombol

CTrade   trade;
string   PREF;
string   FIBO_PREF;

bool     IsDashboardVisible = true;
bool     IsQuoteVisible = true;
bool     IsAutoLot = true;
bool     g_auto = false;
bool     g_pickCandle = false;
double   g_lastManualLot = 0.01;
double   g_lastRiskPct = 0.1;

int      UI_Y = 100;
int      HEADER_Y = 6;
int      PANEL_W = 520;
int      PANEL_H = 380;
int      UI_OFFSCREEN = -2000;
int      g_hdrH = 32;
int      g_btnH = 26;
int      g_fieldGap = 25;
int      g_editH = 22;
int      g_col1 = 20;
int      g_col2 = 270;
int      g_colW = 230;
int      g_yLayers = 0;
int      g_yRisk = 0;
int      g_yMode = 0;
int      g_yScan = 0;
int      g_ySetup = 0;
int      g_yLim = 0;
int      g_yDel = 0;
int      g_yClose = 0;
int      g_yReset = 0;

int      atrHandle = INVALID_HANDLE;
string   g_lastReject = "";

bool     g_fiboActive = false;
bool     g_fiboBullish = true;
double   g_fiboHigh = 0.0;
double   g_fiboLow = 0.0;
datetime g_fiboTime = 0;
datetime g_handledCandle = 0;
datetime g_lastBar = 0;

bool     g_colorsSaved = false;
color    g_saveBg = clrWhite;
color    g_saveFg = clrBlack;
color    g_saveBull = clrWhite;
color    g_saveBear = clrBlack;
long     g_saveForeground = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   PREF = "MOMFC_" + IntegerToString(InpMagicNumber) + "_";
   FIBO_PREF = PREF + "FB_";

   IsAutoLot = (InpLotMode == LOT_AUTO_RISK);
   g_lastRiskPct = (InpRiskPercent > 0.0) ? InpRiskPercent : 0.1;
   g_auto = (InpExecMode == EXEC_AUTO);
   g_pickCandle = false;
   g_handledCandle = 0;
   g_fiboActive = false;

   atrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("ATR gagal dibuat. Error: ", GetLastError());
      return(INIT_FAILED);
   }

   g_saveBg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   g_saveFg = (color)ChartGetInteger(0, CHART_COLOR_FOREGROUND);
   g_saveBull = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BULL);
   g_saveBear = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BEAR);
   g_saveForeground = ChartGetInteger(0, CHART_FOREGROUND);
   g_colorsSaved = true;

   ChartSetInteger(0, CHART_FOREGROUND, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrBlack);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviation);

   EnsureDayState();
   InitLayout();
   CreateDashboard();
   ApplyExecModeUI();
   CheckHardDailyStop();
   UpdateLiveClock();
   RefreshRiskDisplay();

   g_lastBar = iTime(_Symbol, _Period, 0);

   ResetLastError();
   if(!EventSetTimer(1))
      Print("Gagal mengaktifkan timer. Error: ", GetLastError());

   Print("Momentum Candle Fibo siap. ",
         (g_auto ? "AUTO" : "MANUAL"),
         " | limit ", DoubleToString(InpFiboLimit236, 1),
         " & ", DoubleToString(InpFiboLimit50, 1),
         " | SL ", DoubleToString(InpSlLevel, 1),
         " TP ", DoubleToString(InpTpLevel, 1));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(atrHandle);
      atrHandle = INVALID_HANDLE;
   }
   ObjectsDeleteAll(0, PREF);
   if(g_colorsSaved)
   {
      ChartSetInteger(0, CHART_COLOR_BACKGROUND, g_saveBg);
      ChartSetInteger(0, CHART_COLOR_FOREGROUND, g_saveFg);
      ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, g_saveBull);
      ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, g_saveBear);
      ChartSetInteger(0, CHART_FOREGROUND, g_saveForeground);
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckHardDailyStop();
   ManagePendingLimits();
   if(g_auto)
      TryAutoEntry();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateLiveClock();
   CheckHardDailyStop();
   ManagePendingLimits();
   if(g_fiboActive)
      RefreshRiskDisplay();
   ChartRedraw();
}

//+------------------------------------------------------------------+
void TryAutoEntry()
{
   datetime bar = iTime(_Symbol, _Period, 0);
   if(bar <= 0 || bar == g_lastBar)
      return;
   g_lastBar = bar;

   int signal = DetectSignal(1);
   if(signal == 0)
      return;

   datetime candle = iTime(_Symbol, _Period, 1);
   if(candle <= 0 || candle == g_handledCandle)
      return;

   if(!DrawFibo(1, signal > 0))
      return;

   Print("Auto: momentum candle close ", TimeToString(candle),
         " ", (signal > 0 ? "BUY" : "SELL"));
   PlaceSetup();
}

//+------------------------------------------------------------------+
bool HotkeyModifiersFree()
{
   return ((TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) & 0x8000) == 0 &&
           (TerminalInfoInteger(TERMINAL_KEYSTATE_MENU) & 0x8000) == 0 &&
           (TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT) & 0x8000) == 0);
}

//+------------------------------------------------------------------+
void HandleHotkey(const long key)
{
   if(!HotkeyModifiersFree())
      return;

   if(key == 70)      ActionScanFibo();        // F
   else if(key == 67) ActionPickCandle();      // C
   else if(key == 77) ActionToggleAuto();      // M
   else if(key == 66) ActionSetup();           // B
   else if(key == 50) ActionLimit(InpFiboLimit236, "236"); // 2
   else if(key == 53) ActionLimit(InpFiboLimit50, "50");  // 5
   else if(key == 81) ActionDelBuy();          // Q
   else if(key == 87) ActionDelSell();         // W
   else if(key == 80) ActionClosePositions();  // P
   else if(key == 79) ActionCloseOrders();     // O
   else if(key == 82) ActionReset();           // R
   else if(key == 72) ActionTogglePanel();     // H
   else if(key == 84) ActionToggleQuote();     // T
   else return;

   ChartRedraw();
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      HandleHotkey(lparam);
      return;
   }

   if(id == CHARTEVENT_CLICK && g_pickCandle)
   {
      PickCandleAt((int)lparam, (int)dparam);
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == PREF + "Hide")
      {
         ActionTogglePanel();
         ObjectSetInteger(0, PREF + "Hide", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "HideQuote")
      {
         ActionToggleQuote();
         ObjectSetInteger(0, PREF + "HideQuote", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "BtnLotMode")
      {
         if(IsAutoLot) g_lastRiskPct = GetInputValue("InpLot");
         else          g_lastManualLot = GetInputValue("InpLot");
         IsAutoLot = !IsAutoLot;
         ApplyLotModeUI();
         RefreshRiskDisplay();
         ObjectSetInteger(0, PREF + "BtnLotMode", OBJPROP_STATE, false);
         ChartRedraw();
      }
      else if(sparam == PREF + "BtnMode")
      {
         ActionToggleAuto();
         ObjectSetInteger(0, PREF + "BtnMode", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "BtnScanFibo")
      {
         ActionScanFibo();
         ObjectSetInteger(0, PREF + "BtnScanFibo", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "BtnPickCandle")
      {
         ActionPickCandle();
         ObjectSetInteger(0, PREF + "BtnPickCandle", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "BtnSetup")
      {
         ActionSetup();
         ObjectSetInteger(0, PREF + "BtnSetup", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "BtnLim236")
      {
         ActionLimit(InpFiboLimit236, "236");
         ObjectSetInteger(0, PREF + "BtnLim236", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "BtnLim50")
      {
         ActionLimit(InpFiboLimit50, "50");
         ObjectSetInteger(0, PREF + "BtnLim50", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "DelBuy")
      {
         ActionDelBuy();
         ObjectSetInteger(0, PREF + "DelBuy", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "DelSell")
      {
         ActionDelSell();
         ObjectSetInteger(0, PREF + "DelSell", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "ClosePos")
      {
         ActionClosePositions();
         ObjectSetInteger(0, PREF + "ClosePos", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "CloseOrd")
      {
         ActionCloseOrders();
         ObjectSetInteger(0, PREF + "CloseOrd", OBJPROP_STATE, false);
      }
      else if(sparam == PREF + "Reset")
      {
         ActionReset();
         ObjectSetInteger(0, PREF + "Reset", OBJPROP_STATE, false);
      }
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == PREF + "InpLayers" || sparam == PREF + "InpLot")
      {
         RefreshRiskDisplay();
         ChartRedraw();
      }
   }
}

//+------------------------------------------------------------------+
void ActionScanFibo()
{
   SetPickMode(false);
   ScanLatestMomentum();
}

//+------------------------------------------------------------------+
void ActionPickCandle()
{
   SetPickMode(!g_pickCandle);
}

//+------------------------------------------------------------------+
void ActionToggleAuto()
{
   g_auto = !g_auto;
   ApplyExecModeUI();
   if(g_auto)
      Print("Auto ON. Limit ", DoubleToString(InpFiboLimit236, 1), " dan ",
            DoubleToString(InpFiboLimit50, 1), " dipasang saat momentum candle berikutnya close.");
   else
      Print("Manual. Scan [F] atau pilih candle [C], lalu Setup [B].");
   ChartRedraw();
}

//+------------------------------------------------------------------+
void ActionTogglePanel()
{
   IsDashboardVisible = !IsDashboardVisible;
   if(ObjectFind(0, PREF + "Hide") >= 0)
      ObjectSetString(0, PREF + "Hide", OBJPROP_TEXT, IsDashboardVisible ? "Hide [H]" : "Show [H]");
   ApplyDashboardVisibility();
   ChartRedraw();
}

//+------------------------------------------------------------------+
void ActionToggleQuote()
{
   IsQuoteVisible = !IsQuoteVisible;
   if(ObjectFind(0, PREF + "HideQuote") >= 0)
      ObjectSetString(0, PREF + "HideQuote", OBJPROP_TEXT, IsQuoteVisible ? "Hide Q [T]" : "Show Q [T]");
   ApplyQuoteVisibility();
   ChartRedraw();
}

//+------------------------------------------------------------------+
void ActionSetup()
{
   SetPickMode(false);
   PlaceSetup();
}

//+------------------------------------------------------------------+
void ActionLimit(const double level, const string leg)
{
   SetPickMode(false);
   PlaceOneLeg(leg, false, level);
}

//+------------------------------------------------------------------+
void ActionDelBuy()
{
   DeletePending(true);
}

//+------------------------------------------------------------------+
void ActionDelSell()
{
   DeletePending(false);
}

//+------------------------------------------------------------------+
void ActionClosePositions()
{
   CloseAllPositions();
}

//+------------------------------------------------------------------+
void ActionCloseOrders()
{
   CloseAllOrders();
}

//+------------------------------------------------------------------+
void ActionReset()
{
   ClearFibo();
   g_handledCandle = 0;
   SetPickMode(false);
   RefreshRiskDisplay();
   Print("Reset fibo. Posisi dan order tidak ditutup.");
   ChartRedraw();
}

//+------------------------------------------------------------------+
bool IsMomentumBody(const double open, const double high, const double low,
                    const double close, const double atr)
{
   double range = high - low;
   if(range <= 0.0 || atr <= 0.0)
   {
      g_lastReject = "range candle 0";
      return false;
   }
   if(range < atr * InpMinAtrMult)
   {
      g_lastReject = "range lebih kecil dari ATR x " + DoubleToString(InpMinAtrMult, 2);
      return false;
   }
   double body = MathAbs(close - open);
   double pct = (body / range) * 100.0;
   if(pct < InpBodyPercent)
   {
      g_lastReject = "body " + DoubleToString(pct, 1) + "% < " + DoubleToString(InpBodyPercent, 1) + "%";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool BreaksPrevious(const int shift, const bool bullish)
{
   if(InpBreakCandles < 1)
      return false;
   int bars = Bars(_Symbol, _Period);
   if(shift + InpBreakCandles >= bars)
      return false;

   if(bullish)
   {
      double maxHigh = iHigh(_Symbol, _Period, shift + 1);
      for(int j = 2; j <= InpBreakCandles; j++)
         maxHigh = MathMax(maxHigh, iHigh(_Symbol, _Period, shift + j));
      if(iClose(_Symbol, _Period, shift) > maxHigh)
         return true;
      g_lastReject = "close tidak break high " + IntegerToString(InpBreakCandles) + " candle sebelumnya";
      return false;
   }

   double minLow = iLow(_Symbol, _Period, shift + 1);
   for(int j = 2; j <= InpBreakCandles; j++)
      minLow = MathMin(minLow, iLow(_Symbol, _Period, shift + j));
   if(iClose(_Symbol, _Period, shift) < minLow)
      return true;
   g_lastReject = "close tidak break low " + IntegerToString(InpBreakCandles) + " candle sebelumnya";
   return false;
}

//+------------------------------------------------------------------+
int DetectSignal(const int shift)
{
   g_lastReject = "";
   if(shift < 1)
   {
      g_lastReject = "candle belum close";
      return 0;
   }

   int bars = Bars(_Symbol, _Period);
   if(shift + MathMax(InpBreakCandles, InpAtrPeriod) >= bars)
   {
      g_lastReject = "sejarah candle kurang";
      return 0;
   }

   double atr[1];
   if(CopyBuffer(atrHandle, 0, shift + 1, 1, atr) != 1)
   {
      g_lastReject = "ATR belum siap";
      return 0;
   }

   double open  = iOpen(_Symbol, _Period, shift);
   double high  = iHigh(_Symbol, _Period, shift);
   double low   = iLow(_Symbol, _Period, shift);
   double close = iClose(_Symbol, _Period, shift);
   if(!IsMomentumBody(open, high, low, close, atr[0]))
      return 0;

   if(close > open && BreaksPrevious(shift, true))
   {
      if(InpShowSide == MOM_SHOW_BEARISH)
      {
         g_lastReject = "sinyal bullish dimatikan di input";
         return 0;
      }
      return 1;
   }

   if(close < open && BreaksPrevious(shift, false))
   {
      if(InpShowSide == MOM_SHOW_BULLISH)
      {
         g_lastReject = "sinyal bearish dimatikan di input";
         return 0;
      }
      return -1;
   }

   if(g_lastReject == "")
      g_lastReject = "bukan momentum candle";
   return 0;
}

//+------------------------------------------------------------------+
bool ScanLatestMomentum()
{
   int bars = Bars(_Symbol, _Period);
   int last = bars - MathMax(InpBreakCandles, InpAtrPeriod) - 1;
   if(last > InpScanBars)
      last = InpScanBars;
   if(last < 1)
   {
      Print("Scan Fibo Candle: sejarah kurang.");
      return false;
   }

   for(int shift = 1; shift <= last; shift++)
   {
      int signal = DetectSignal(shift);
      if(signal == 0)
         continue;
      return DrawFibo(shift, signal > 0);
   }

   Print("Scan Fibo Candle: tidak ada momentum candle dalam ", last, " bar.");
   return false;
}

//+------------------------------------------------------------------+
void PickCandleAt(const int x, const int y)
{
   if(IsDashboardVisible &&
      x >= 10 && x <= 10 + PANEL_W &&
      y >= HEADER_Y && y <= UI_Y + PANEL_H)
      return;

   int wnd = 0;
   datetime t = 0;
   double price = 0.0;
   if(!ChartXYToTimePrice(0, x, y, wnd, t, price) || wnd != 0 || t <= 0)
      return;

   int shift = iBarShift(_Symbol, _Period, t, false);
   if(shift < 0)
   {
      Print("Pilih candle: bar tidak ditemukan.");
      return;
   }
   if(shift == 0)
   {
      Print("Pilih candle: candle berjalan belum close.");
      return;
   }

   int signal = DetectSignal(shift);
   if(signal == 0)
   {
      Print("Pilih candle shift ", shift, " (", TimeToString(iTime(_Symbol, _Period, shift)), "): ", g_lastReject);
      return;
   }

   DrawFibo(shift, signal > 0);
   SetPickMode(false);
}

//+------------------------------------------------------------------+
double FiboRatio(const double v)
{
   if(MathAbs(v) > 2.0)
      return v / 100.0;
   return v;
}

// Bullish: 0 di high, 100 di low. Bearish: 0 di low, 100 di high.
double FiboPrice(const double level)
{
   double ratio = FiboRatio(level);
   double range = g_fiboHigh - g_fiboLow;
   if(range <= 0.0)
      return 0.0;
   if(g_fiboBullish)
      return g_fiboHigh - ratio * range;
   return g_fiboLow + ratio * range;
}

//+------------------------------------------------------------------+
void ClearFibo()
{
   ObjectsDeleteAll(0, FIBO_PREF);
   g_fiboActive = false;
   g_fiboBullish = true;
   g_fiboHigh = 0.0;
   g_fiboLow = 0.0;
   g_fiboTime = 0;
}

//+------------------------------------------------------------------+
void SetupFiboLevels(const string fiboName)
{
   double vals[7];
   string txt[7];
   color  clr[7];

   vals[0] = 0.0;                              txt[0] = "0";                                          clr[0] = clrDimGray;
   vals[1] = 1.0;                              txt[1] = "100";                                        clr[1] = clrDimGray;
   vals[2] = FiboRatio(InpFiboLimit236);       txt[2] = DoubleToString(InpFiboLimit236, 1);           clr[2] = InpFiboColor;
   vals[3] = 0.50;                             txt[3] = "50.0";                                       clr[3] = InpFiboColor;
   vals[4] = FiboRatio(InpFiboLimit50);        txt[4] = "L " + DoubleToString(InpFiboLimit50, 1);     clr[4] = InpFiboColor;
   vals[5] = FiboRatio(InpSlLevel);            txt[5] = "SL " + DoubleToString(InpSlLevel, 1);        clr[5] = clrOrangeRed;
   vals[6] = FiboRatio(InpTpLevel);            txt[6] = "TP " + DoubleToString(InpTpLevel, 1);        clr[6] = clrSeaGreen;

   if(MathAbs(FiboRatio(InpFiboLimit50) - 0.50) < 0.0001)
      txt[4] = " ";

   ObjectSetInteger(0, fiboName, OBJPROP_COLOR, clrNONE);
   ObjectSetInteger(0, fiboName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, fiboName, OBJPROP_WIDTH, 0);
   ObjectSetInteger(0, fiboName, OBJPROP_LEVELS, 0);
   ObjectSetInteger(0, fiboName, OBJPROP_LEVELS, 7);
   ObjectSetInteger(0, fiboName, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, fiboName, OBJPROP_RAY_RIGHT, InpFiboRayRight);
   ObjectSetInteger(0, fiboName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, fiboName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, fiboName, OBJPROP_BACK, false);
   ObjectSetInteger(0, fiboName, OBJPROP_ZORDER, 0);

   for(int i = 0; i < 7; i++)
   {
      ObjectSetDouble(0, fiboName, OBJPROP_LEVELVALUE, i, vals[i]);
      ObjectSetInteger(0, fiboName, OBJPROP_LEVELSTYLE, i, STYLE_DOT);
      ObjectSetInteger(0, fiboName, OBJPROP_LEVELWIDTH, i, InpFiboWidth);
      ObjectSetInteger(0, fiboName, OBJPROP_LEVELCOLOR, i, clr[i]);
      ObjectSetString(0, fiboName, OBJPROP_LEVELTEXT, i, " " + txt[i]);
   }
}

//+------------------------------------------------------------------+
bool DrawFibo(const int shift, const bool bullish)
{
   double high = iHigh(_Symbol, _Period, shift);
   double low  = iLow(_Symbol, _Period, shift);
   datetime t1 = iTime(_Symbol, _Period, shift);
   if(high <= low || t1 <= 0)
   {
      Print("Fibo candle: range tidak valid.");
      return false;
   }

   datetime t2 = (shift > 0) ? iTime(_Symbol, _Period, shift - 1) : (t1 + PeriodSeconds(_Period));
   ClearFibo();

   g_fiboBullish = bullish;
   g_fiboHigh = high;
   g_fiboLow = low;
   g_fiboTime = t1;

   string fiboName = FIBO_PREF + "OBJ";
   // Garis 0 di MT5 ada di titik kedua. Bullish: 0 di high. Bearish: 0 di low.
   bool created = false;
   if(bullish)
      created = ObjectCreate(0, fiboName, OBJ_FIBO, 0, t1, low, t2, high);
   else
      created = ObjectCreate(0, fiboName, OBJ_FIBO, 0, t1, high, t2, low);

   if(!created)
   {
      Print("Fibo object gagal. Error: ", GetLastError());
      ClearFibo();
      return false;
   }

   if(bullish)
   {
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 0, low);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 1, high);
   }
   else
   {
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 0, high);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 1, low);
   }

   SetupFiboLevels(fiboName);
   g_fiboActive = true;
   RefreshRiskDisplay();

   Print("Fibo candle ", (bullish ? "BUY" : "SELL"),
         " ", TimeToString(t1),
         " close=", DoubleToString(iClose(_Symbol, _Period, shift), _Digits),
         " L1=", DoubleToString(FiboPrice(InpFiboLimit236), _Digits),
         " L2=", DoubleToString(FiboPrice(InpFiboLimit50), _Digits),
         " SL=", DoubleToString(FiboPrice(InpSlLevel), _Digits),
         " TP=", DoubleToString(FiboPrice(InpTpLevel), _Digits));
   ChartRedraw();
   return true;
}

//+------------------------------------------------------------------+
double MinStopDistance()
{
   double dist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(dist < _Point)
      dist = _Point;
   return dist;
}

//+------------------------------------------------------------------+
double MarketEntry(const bool isBuy)
{
   if(isBuy)
      return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

//+------------------------------------------------------------------+
bool GeometryOk(const bool isBuy, const double entry, const double sl, const double tp, string &why)
{
   why = "";
   if(entry <= 0.0 || sl <= 0.0 || tp <= 0.0)
   {
      why = "harga entry/SL/TP tidak valid";
      return false;
   }

   double minDist = MinStopDistance();
   if(isBuy)
   {
      if(!(sl < entry && entry < tp))
      {
         why = "Buy butuh SL < Entry < TP. E=" + DoubleToString(entry, _Digits)
             + " SL=" + DoubleToString(sl, _Digits)
             + " TP=" + DoubleToString(tp, _Digits);
         return false;
      }
      if((entry - sl) < minDist || (tp - entry) < minDist)
      {
         why = "jarak SL/TP lebih kecil dari stops level";
         return false;
      }
      return true;
   }

   if(!(tp < entry && entry < sl))
   {
      why = "Sell butuh TP < Entry < SL. E=" + DoubleToString(entry, _Digits)
          + " SL=" + DoubleToString(sl, _Digits)
          + " TP=" + DoubleToString(tp, _Digits);
      return false;
   }
   if((sl - entry) < minDist || (entry - tp) < minDist)
   {
      why = "jarak SL/TP lebih kecil dari stops level";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool PendingSideOk(const bool isBuy, const double entry, string &why)
{
   why = "";
   double minDist = MinStopDistance();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(isBuy)
   {
      if(entry <= ask - minDist)
         return true;
      why = "Buy limit harus di bawah Ask";
      return false;
   }
   if(entry >= bid + minDist)
      return true;
   why = "Sell limit harus di atas Bid";
   return false;
}

//+------------------------------------------------------------------+
string CommentFor(const string leg)
{
   return (g_fiboBullish ? "MB" : "MS") + leg + IntegerToString((long)g_fiboTime);
}

//+------------------------------------------------------------------+
bool SameMagicSymbol(const ulong magic, const string symbol)
{
   return (magic == InpMagicNumber && symbol == _Symbol);
}

//+------------------------------------------------------------------+
bool LegExists(const string leg)
{
   string key = CommentFor(leg);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!SameMagicSymbol((ulong)PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), key) >= 0)
         return true;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(!SameMagicSymbol((ulong)OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), key) >= 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool TradeAllowed(string &why)
{
   why = "";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      why = "Algo trading mati";
      return false;
   }
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED)
   {
      why = "simbol tidak bisa ditrade";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool SendLeg(const string leg, const bool isMarket, const double entry)
{
   if(!g_fiboActive || g_fiboTime <= 0)
   {
      Print(leg, ": scan fibo candle dulu.");
      return false;
   }

   string why = "";
   if(!TradeAllowed(why))
   {
      Print(leg, ": ", why);
      return false;
   }
   if(LegExists(leg))
   {
      Print(leg, ": kaki candle ini sudah ada.");
      return false;
   }

   bool isBuy = g_fiboBullish;
   double sl = NormalizeDouble(FiboPrice(InpSlLevel), _Digits);
   double tp = NormalizeDouble(FiboPrice(InpTpLevel), _Digits);
   double en = NormalizeDouble(entry, _Digits);

   if(!GeometryOk(isBuy, en, sl, tp, why))
   {
      Print(leg, ": ", why);
      return false;
   }
   if(!isMarket && !PendingSideOk(isBuy, en, why))
   {
      Print(leg, ": ", why);
      return false;
   }

   int copies = Layers();
   double lot = LotForSetup(isBuy, true);
   if(lot <= 0.0)
   {
      Print(leg, ": lot 0, batal.");
      return false;
   }

   string base = CommentFor(leg);
   bool any = false;
   for(int i = 0; i < copies; i++)
   {
      string cmt = base;
      if(copies > 1)
         cmt = base + "L" + IntegerToString(i + 1);

      bool ok = false;
      if(isMarket)
         ok = isBuy ? trade.Buy(lot, _Symbol, 0.0, sl, tp, cmt)
                    : trade.Sell(lot, _Symbol, 0.0, sl, tp, cmt);
      else if(isBuy)
         ok = trade.BuyLimit(lot, en, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
      else
         ok = trade.SellLimit(lot, en, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);

      if(ok)
      {
         any = true;
         Print(leg, " OK ", (isMarket ? "market" : "limit"),
               " ", (isBuy ? "BUY" : "SELL"),
               " lot=", DoubleToString(lot, 2),
               " E=", DoubleToString(en, _Digits),
               " SL=", DoubleToString(sl, _Digits),
               " TP=", DoubleToString(tp, _Digits));
      }
      else
         Print(leg, " gagal copy ", i + 1, ". ", trade.ResultRetcodeDescription());
   }
   return any;
}

//+------------------------------------------------------------------+
void PlaceSetup()
{
   if(!g_fiboActive)
   {
      Print("Setup: scan fibo candle dulu [F].");
      return;
   }
   if(g_handledCandle == g_fiboTime)
   {
      Print("Setup candle ini sudah dikirim. Kaki yang gagal bisa diulang dengan [2] atau [5]. Reset [R] untuk paksa ulang.");
      return;
   }

   string block = "";
   if(IsTradingBlocked(block, 2 * Layers()))
   {
      Print("Setup: ", block);
      return;
   }

   g_handledCandle = g_fiboTime;
   double p236 = FiboPrice(InpFiboLimit236);
   double p50  = FiboPrice(InpFiboLimit50);
   Print("Setup harga: 23.6=", DoubleToString(p236, _Digits),
         " 50=", DoubleToString(p50, _Digits),
         " (bukan 61.8=", DoubleToString(FiboPrice(61.8), _Digits), ")");
   int sent = 0;
   if(SendLeg("236", false, p236))
      sent++;
   if(SendLeg("50", false, p50))
      sent++;

   Print("Setup ", (g_fiboBullish ? "BUY" : "SELL"),
         " ", TimeToString(g_fiboTime),
         " terkirim ", sent, "/2.");
   if(sent < 2)
      Print("Kaki yang belum masuk: [2] limit ", DoubleToString(InpFiboLimit236, 1),
            ", [5] limit ", DoubleToString(InpFiboLimit50, 1), ".");
   RefreshRiskDisplay();
}

//+------------------------------------------------------------------+
void PlaceOneLeg(const string leg, const bool isMarket, const double level)
{
   if(!g_fiboActive)
   {
      Print("Scan fibo candle dulu [F].");
      return;
   }

   string block = "";
   if(IsTradingBlocked(block, Layers()))
   {
      Print(leg, ": ", block);
      return;
   }

   double entry = isMarket ? MarketEntry(g_fiboBullish) : FiboPrice(level);
   if(SendLeg(leg, isMarket, entry))
      g_handledCandle = g_fiboTime;
   RefreshRiskDisplay();
}

//+------------------------------------------------------------------+
bool IsOurLimit(const ulong ticket)
{
   if(ticket == 0 || !OrderSelect(ticket))
      return false;
   if(!SameMagicSymbol((ulong)OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
      return false;
   ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   return (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT);
}

//+------------------------------------------------------------------+
bool PriceReachedTp(const ulong ticket)
{
   double tp = OrderGetDouble(ORDER_TP);
   if(tp <= 0.0)
      return false;

   ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(type == ORDER_TYPE_BUY_LIMIT)
      return (bid >= tp);
   if(type == ORDER_TYPE_SELL_LIMIT)
      return (ask <= tp);
   return false;
}

//+------------------------------------------------------------------+
string SetupKeyFromComment(const string comment)
{
   int atMB = StringFind(comment, "MB");
   int atMS = StringFind(comment, "MS");
   int at = -1;
   if(atMB >= 0 && (atMS < 0 || atMB < atMS))
      at = atMB;
   else if(atMS >= 0)
      at = atMS;
   if(at < 0)
      return "";

   string rest = StringSubstr(comment, at + 2);
   if(StringFind(rest, "618") == 0)
      rest = StringSubstr(rest, 3);
   else if(StringFind(rest, "236") == 0)
      rest = StringSubstr(rest, 3);
   else if(StringFind(rest, "50") == 0)
      rest = StringSubstr(rest, 2);
   else if(StringLen(rest) > 0 && StringGetCharacter(rest, 0) == 'C')
      rest = StringSubstr(rest, 1);
   else
      return "";

   string digits = "";
   int len = StringLen(rest);
   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(rest, i);
      if(ch < '0' || ch > '9')
         break;
      digits += ShortToString(ch);
   }
   if(StringLen(digits) < 9)
      return "";
   return digits;
}

//+------------------------------------------------------------------+
void AddSetupKey(string &keys[], const string key)
{
   if(key == "")
      return;
   int n = ArraySize(keys);
   for(int i = 0; i < n; i++)
   {
      if(keys[i] == key)
         return;
   }
   ArrayResize(keys, n + 1);
   keys[n] = key;
}

//+------------------------------------------------------------------+
int CollectTpSetupKeys(const datetime from, string &keys[])
{
   ArrayResize(keys, 0);
   datetime now = TimeCurrent();
   if(from <= 0 || now < from)
      return 0;
   if(!HistorySelect(from, now + 60))
      return 0;

   ulong posIds[];
   int posCount = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
         continue;
      if((ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON) != DEAL_REASON_TP)
         continue;

      ulong posId = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      bool seen = false;
      for(int p = 0; p < posCount; p++)
      {
         if(posIds[p] == posId)
         {
            seen = true;
            break;
         }
      }
      if(seen)
         continue;

      ArrayResize(posIds, posCount + 1);
      posIds[posCount] = posId;
      posCount++;
      AddSetupKey(keys, SetupKeyFromComment(HistoryDealGetString(ticket, DEAL_COMMENT)));
   }

   if(posCount == 0)
      return 0;
   if(ArraySize(keys) >= posCount)
      return ArraySize(keys);

   if(!HistorySelect(now - 90 * 86400, now + 60))
      return ArraySize(keys);

   total = HistoryDealsTotal();
   for(int p = 0; p < posCount; p++)
   {
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0)
            continue;
         if((ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID) != posIds[p])
            continue;

         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT)
            continue;

         AddSetupKey(keys, SetupKeyFromComment(HistoryDealGetString(ticket, DEAL_COMMENT)));
         break;
      }
   }
   return ArraySize(keys);
}

//+------------------------------------------------------------------+
void DeleteLimitsForSetup(const string key, const string why)
{
   if(key == "")
      return;

   int deleted = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!IsOurLimit(ticket))
         continue;
      if(SetupKeyFromComment(OrderGetString(ORDER_COMMENT)) != key)
         continue;
      if(trade.OrderDelete(ticket))
         deleted++;
      else
         Print("Batal limit gagal #", ticket, " ", trade.ResultRetcodeDescription());
   }
   if(deleted > 0)
      Print("Limit candle ", TimeToString((datetime)StringToInteger(key)),
            " dibatalkan (", why, "): ", deleted);
}

//+------------------------------------------------------------------+
void ManagePendingLimits()
{
   bool anyLimit = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(IsOurLimit(OrderGetTicket(i)))
      {
         anyLimit = true;
         break;
      }
   }
   if(!anyLimit)
      return;

   static datetime lastTpCheck = 0;
   datetime now = TimeCurrent();
   if(lastTpCheck <= 0)
      lastTpCheck = now - 60;

   string tpKeys[];
   int tpCount = CollectTpSetupKeys(lastTpCheck, tpKeys);
   lastTpCheck = now;
   for(int k = 0; k < tpCount; k++)
      DeleteLimitsForSetup(tpKeys[k], "TP posisi candle ini kena");

   int expireSec = InpLimitExpireMinutes * 60;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!IsOurLimit(ticket))
         continue;

      string why = "";
      if(PriceReachedTp(ticket))
         why = "harga sudah TP order ini";
      else if(expireSec > 0)
      {
         datetime placed = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         if(placed > 0 && now - placed >= expireSec)
            why = "lewat " + IntegerToString(InpLimitExpireMinutes) + " menit";
      }

      if(why == "")
         continue;
      if(!trade.OrderDelete(ticket))
         Print("Batal limit gagal #", ticket, " ", trade.ResultRetcodeDescription());
      else
         Print("Limit #", ticket, " dibatalkan: ", why);
   }
}

//+------------------------------------------------------------------+
void DeletePending(const bool isBuy)
{
   int deleted = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(!SameMagicSymbol((ulong)OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool match = isBuy ? (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP)
                         : (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP);
      if(!match)
         continue;
      if(trade.OrderDelete(ticket))
         deleted++;
   }
   Print(isBuy ? "Del Buy: " : "Del Sell: ", deleted, " order.");
}

//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!SameMagicSymbol((ulong)PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
         continue;
      if(trade.PositionClose(ticket))
         closed++;
      else
         Print("Close posisi gagal #", ticket, " ", trade.ResultRetcodeDescription());
   }
   Print("Close Positions: ", closed);
}

//+------------------------------------------------------------------+
void CloseAllOrders()
{
   int deleted = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(!SameMagicSymbol((ulong)OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
         continue;
      if(trade.OrderDelete(ticket))
         deleted++;
   }
   Print("Close Orders: ", deleted);
}

//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0)
      stepLot = 0.01;

   lot = MathFloor(lot / stepLot + 0.0000001) * stepLot;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return lot;
}

//+------------------------------------------------------------------+
double GetRiskBaseAmount()
{
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

//+------------------------------------------------------------------+
int Layers()
{
   int n = (int)GetInputValue("InpLayers");
   if(n < 1) n = 1;
   if(n > 20) n = 20;
   return n;
}

//+------------------------------------------------------------------+
double RiskPct()
{
   double risk = GetInputValue("InpLot");
   if(risk <= 0.0)
      risk = (InpRiskPercent > 0.0) ? InpRiskPercent : 0.1;
   return risk;
}

//+------------------------------------------------------------------+
double LossPerLot(const ENUM_ORDER_TYPE orderType, const double entry, const double sl)
{
   if(entry <= 0.0 || sl <= 0.0 || MathAbs(entry - sl) <= 0.0)
      return 0.0;
   double profit = 0.0;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entry, sl, profit))
      return 0.0;
   return MathAbs(profit);
}

// Lot sama untuk 23.6 dan 50. Risk % = total kedua kaki, bukan per kaki.
double LotForSetup(const bool isBuy, const bool verbose)
{
   if(!IsAutoLot)
   {
      double lot = GetInputValue("InpLot");
      if(lot <= 0.0)
         return 0.0;
      return NormalizeLot(lot);
   }

   double risk = RiskPct();
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(risk > 1.0)
   {
      if(verbose)
         Print("Risk ", DoubleToString(risk, 2), "% > 1%. Pakai lot terkecil ", DoubleToString(minLot, 2));
      return NormalizeLot(minLot);
   }

   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double sl = NormalizeDouble(FiboPrice(InpSlLevel), _Digits);
   double tp = NormalizeDouble(FiboPrice(InpTpLevel), _Digits);
   double entries[2];
   entries[0] = NormalizeDouble(FiboPrice(InpFiboLimit236), _Digits);
   entries[1] = NormalizeDouble(FiboPrice(InpFiboLimit50), _Digits);

   double sumLoss = 0.0;
   int n = 0;
   for(int i = 0; i < 2; i++)
   {
      string why = "";
      if(!GeometryOk(isBuy, entries[i], sl, tp, why))
         continue;
      if(!PendingSideOk(isBuy, entries[i], why))
         continue;
      double loss = LossPerLot(type, entries[i], sl);
      if(loss <= 0.0)
         continue;
      sumLoss += loss;
      n++;
   }

   if(n < 1 || sumLoss <= 0.0)
      return 0.0;

   double base = GetRiskBaseAmount();
   if(base <= 0.0)
      return 0.0;

   double riskMoney = base * risk / 100.0;
   int copies = Layers();
   if(copies < 1)
      copies = 1;
   double lot = NormalizeLot(riskMoney / (sumLoss * (double)copies));
   if(verbose)
      Print("Lot sama kedua limit: ", DoubleToString(lot, 2),
            " | risk $", DoubleToString(riskMoney, 2),
            " / ", n, " kaki | saldo ", DoubleToString(base, 2));
   return lot;
}

//+------------------------------------------------------------------+
double CalcRiskUSD(const ENUM_ORDER_TYPE orderType, const double entry, const double sl,
                   const double lot, const int copies)
{
   if(lot <= 0.0 || copies < 1 || entry <= 0.0 || sl <= 0.0 || MathAbs(entry - sl) <= 0.0)
      return 0.0;

   double profit = 0.0;
   if(OrderCalcProfit(orderType, _Symbol, 1.0, entry, sl, profit))
      return MathAbs(profit) * lot * (double)copies;

   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0 || tickVal <= 0.0)
      return 0.0;
   return MathAbs(entry - sl) * lot * (double)copies * tickVal / tickSize;
}

//+------------------------------------------------------------------+
int ValidLegCount(double &riskUSD)
{
   riskUSD = 0.0;
   if(!g_fiboActive)
      return 0;

   bool isBuy = g_fiboBullish;
   double sl = NormalizeDouble(FiboPrice(InpSlLevel), _Digits);
   double tp = NormalizeDouble(FiboPrice(InpTpLevel), _Digits);
   double entries[2];
   entries[0] = NormalizeDouble(FiboPrice(InpFiboLimit236), _Digits);
   entries[1] = NormalizeDouble(FiboPrice(InpFiboLimit50), _Digits);

   int copies = Layers();
   int n = 0;
   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double lot = LotForSetup(isBuy, false);
   for(int i = 0; i < 2; i++)
   {
      string why = "";
      if(!GeometryOk(isBuy, entries[i], sl, tp, why))
         continue;
      if(!PendingSideOk(isBuy, entries[i], why))
         continue;
      riskUSD += CalcRiskUSD(type, entries[i], sl, lot, copies);
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
void RefreshRiskDisplay()
{
   double riskUSD = 0.0;
   int legs = ValidLegCount(riskUSD);
   string buyTxt = "0.00";
   string sellTxt = "0.00";
   if(g_fiboActive && g_fiboBullish)
      buyTxt = DoubleToString(riskUSD, 2);
   else if(g_fiboActive)
      sellTxt = DoubleToString(riskUSD, 2);

   if(ObjectFind(0, PREF + "Buy_Risk") >= 0)
      ObjectSetString(0, PREF + "Buy_Risk", OBJPROP_TEXT, buyTxt);
   if(ObjectFind(0, PREF + "Sell_Risk") >= 0)
      ObjectSetString(0, PREF + "Sell_Risk", OBJPROP_TEXT, sellTxt);

   string status = "Scan fibo candle [F]";
   color clr = clrBlack;
   if(g_fiboActive)
   {
      status = (g_fiboBullish ? "BUY " : "SELL ")
             + TimeToString(g_fiboTime, TIME_DATE | TIME_MINUTES)
             + " | kaki " + IntegerToString(legs) + "/2"
             + " | risk $ " + DoubleToString(riskUSD, 2);
      clr = g_fiboBullish ? clrDodgerBlue : clrOrangeRed;
   }
   DrawNativeLabel(PREF + "Status", status, PANEL_W + 20, 72, clr);
}

//+------------------------------------------------------------------+
datetime ServerNow()
{
   datetime t = TimeTradeServer();
   if(t <= 0) t = TimeGMT();
   if(t <= 0) t = TimeCurrent();
   return t;
}

//+------------------------------------------------------------------+
int TodayKey()
{
   MqlDateTime dt;
   TimeToStruct(ServerNow(), dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

//+------------------------------------------------------------------+
string GVDayName()     { return "MOMFC_DAY_" + IntegerToString(InpMagicNumber); }
string GVStartEqName() { return "MOMFC_STARTEQ_" + IntegerToString(InpMagicNumber); }
string GVHaltName()    { return "MOMFC_HALT_" + IntegerToString(InpMagicNumber); }

//+------------------------------------------------------------------+
datetime DayStartTime()
{
   MqlDateTime dt;
   TimeToStruct(ServerNow(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
void EnsureDayState()
{
   int today = TodayKey();
   string dayName = GVDayName();
   if(!GlobalVariableCheck(dayName) || (int)GlobalVariableGet(dayName) != today)
   {
      int haltDay = GlobalVariableCheck(GVHaltName()) ? (int)GlobalVariableGet(GVHaltName()) : 0;
      GlobalVariableSet(dayName, (double)today);
      GlobalVariableSet(GVStartEqName(), AccountInfoDouble(ACCOUNT_EQUITY));
      if(haltDay != 0 && haltDay != today)
      {
         GlobalVariableSet(GVHaltName(), 0.0);
         Print("Hard Daily Stop reset. Trading aktif lagi (hari baru server 00:00).");
      }
   }
}

//+------------------------------------------------------------------+
int CountPositionsOpenedToday()
{
   datetime from = DayStartTime();
   datetime to = ServerNow();
   if(to < from || !HistorySelect(from, to))
      return 0;

   int count = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if((datetime)HistoryDealGetInteger(ticket, DEAL_TIME) < from)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;

      long dtype = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL)
         continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT)
         continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
int CountOpenSimultaneous()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!SameMagicSymbol((ulong)PositionGetInteger(POSITION_MAGIC), PositionGetString(POSITION_SYMBOL)))
         continue;
      n++;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(!SameMagicSymbol((ulong)OrderGetInteger(ORDER_MAGIC), OrderGetString(ORDER_SYMBOL)))
         continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
bool WouldExceedDailyPositionLimit(const int extraPositions, string &reason)
{
   int extra = (extraPositions > 0) ? extraPositions : 1;
   int trades = CountPositionsOpenedToday();
   if(InpMaxTradesPerDay > 0 && (trades >= InpMaxTradesPerDay || trades + extra > InpMaxTradesPerDay))
   {
      reason = "Max trades per hari tercapai (" + IntegerToString(trades) + "/"
             + IntegerToString(InpMaxTradesPerDay) + ")";
      return true;
   }

   int openNow = CountOpenSimultaneous();
   if(InpMaxOpenSimultaneous > 0 && (openNow >= InpMaxOpenSimultaneous || openNow + extra > InpMaxOpenSimultaneous))
   {
      reason = "Max open simultan tercapai (" + IntegerToString(openNow) + "/"
             + IntegerToString(InpMaxOpenSimultaneous) + ")";
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
double GetAccountDailyPnL()
{
   datetime from = DayStartTime();
   datetime to = ServerNow();
   double pnl = 0.0;
   if(to >= from && HistorySelect(from, to))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0)
            continue;
         if((datetime)HistoryDealGetInteger(ticket, DEAL_TIME) < from)
            continue;
         long dtype = HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL)
            continue;
         pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         pnl += HistoryDealGetDouble(ticket, DEAL_SWAP);
         pnl += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      pnl += PositionGetDouble(POSITION_PROFIT);
      pnl += PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

//+------------------------------------------------------------------+
double GetDailyPnLPercent()
{
   EnsureDayState();
   double pnl = GetAccountDailyPnL();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double startEq = equity - pnl;
   if(startEq <= 0.0)
      startEq = GlobalVariableCheck(GVStartEqName()) ? GlobalVariableGet(GVStartEqName()) : equity;
   if(startEq <= 0.0)
      return 0.0;
   return pnl / startEq * 100.0;
}

//+------------------------------------------------------------------+
bool IsHardStopActive()
{
   if(!InpHardDailyStop)
      return false;
   EnsureDayState();
   if(!GlobalVariableCheck(GVHaltName()))
      return false;
   return ((int)GlobalVariableGet(GVHaltName()) == TodayKey());
}

//+------------------------------------------------------------------+
void FlattenAccount()
{
   for(int pass = 0; pass < 3; pass++)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(!trade.PositionClose(ticket))
            Print("Hard Daily Stop: gagal close posisi #", ticket, " ", trade.ResultRetcodeDescription());
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(!OrderSelect(ticket))
            continue;
         if(!trade.OrderDelete(ticket))
            Print("Hard Daily Stop: gagal hapus order #", ticket, " ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
void UpdateHardStopLabel()
{
   double pct = GetDailyPnLPercent();
   string posTxt = "  |  trades " + IntegerToString(CountPositionsOpenedToday()) + "/"
                 + IntegerToString(InpMaxTradesPerDay)
                 + "  |  open " + IntegerToString(CountOpenSimultaneous()) + "/"
                 + IntegerToString(InpMaxOpenSimultaneous);
   string txt;
   color clr;
   if(IsHardStopActive())
   {
      txt = "HARD DAILY STOP " + DoubleToString(pct, 2) + "%  | OFF sampai 00:00 server" + posTxt;
      clr = clrOrangeRed;
   }
   else
   {
      txt = "Daily PnL " + DoubleToString(pct, 2) + "%  (incl. floating)" + posTxt;
      if((CountPositionsOpenedToday() >= InpMaxTradesPerDay && InpMaxTradesPerDay > 0) ||
         (CountOpenSimultaneous() >= InpMaxOpenSimultaneous && InpMaxOpenSimultaneous > 0))
         clr = clrOrangeRed;
      else if(pct <= -InpMaxDailyLossPercent * 0.7)
         clr = clrOrange;
      else if(pct < 0.0)
         clr = clrDarkOrange;
      else
         clr = clrForestGreen;
   }
   DrawNativeLabel(PREF + "HardStop", txt, PANEL_W + 20, 25, clr);
}

//+------------------------------------------------------------------+
void TriggerHardDailyStop(const double pnlPct)
{
   bool firstTrigger = !IsHardStopActive();
   GlobalVariableSet(GVHaltName(), (double)TodayKey());
   FlattenAccount();
   UpdateHardStopLabel();
   if(firstTrigger)
   {
      string msg = "HARD DAILY STOP: Daily PnL (incl. floating) "
                 + DoubleToString(pnlPct, 2) + "% <= -"
                 + DoubleToString(InpMaxDailyLossPercent, 2)
                 + "%. Semua posisi/order ditutup. Trading disable sampai 00:00 server.";
      Print(msg);
      Alert(msg);
   }
}

//+------------------------------------------------------------------+
void CheckHardDailyStop()
{
   EnsureDayState();
   if(!InpHardDailyStop || InpMaxDailyLossPercent <= 0.0)
   {
      if(GlobalVariableCheck(GVHaltName()) && GlobalVariableGet(GVHaltName()) != 0.0)
      {
         GlobalVariableSet(GVHaltName(), 0.0);
         Print("Hard Daily Stop OFF. Kunci harian dilepas, trading aktif lagi.");
      }
      UpdateHardStopLabel();
      return;
   }

   if(IsHardStopActive())
   {
      if(PositionsTotal() > 0 || OrdersTotal() > 0)
         FlattenAccount();
      UpdateHardStopLabel();
      return;
   }

   double pnlPct = GetDailyPnLPercent();
   if(pnlPct <= -InpMaxDailyLossPercent)
      TriggerHardDailyStop(pnlPct);
   else
      UpdateHardStopLabel();
}

//+------------------------------------------------------------------+
bool IsTradingBlocked(string &reason, const int extraPositions)
{
   reason = "";
   EnsureDayState();
   CheckHardDailyStop();

   if(InpHardDailyStop && IsHardStopActive())
   {
      reason = "Hard Daily Stop aktif sampai 00:00 server";
      return true;
   }
   if(WouldExceedDailyPositionLimit(extraPositions, reason))
      return true;
   return false;
}

//+------------------------------------------------------------------+
void UpdateLiveClock()
{
   datetime wib = TimeGMT() + 7 * 3600;
   string wibClock = TimeToString(wib, TIME_MINUTES | TIME_SECONDS);

   datetime barTime = iTime(_Symbol, _Period, 0);
   int periodSec = PeriodSeconds(_Period);
   int remain = 0;
   if(barTime > 0 && periodSec > 0)
   {
      remain = (int)((barTime + periodSec) - TimeCurrent());
      if(remain < 0)
         remain = 0;
   }

   int hh = remain / 3600;
   int mm = (remain % 3600) / 60;
   int ss = remain % 60;
   string cd = (hh > 0)
      ? StringFormat("%d:%02d:%02d", hh, mm, ss)
      : StringFormat("%02d:%02d", mm, ss);

   string txt = "WIB " + wibClock + "   Candle close in " + cd;
   color clr = (remain <= 10) ? clrOrangeRed : clrBlack;
   DrawNativeLabel(PREF + "Live_Clock", txt, PANEL_W + 20, 50, clr);
}

//+------------------------------------------------------------------+
void DrawNativeLabel(const string name, const string text, const int x, const int y, const color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 11);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
void CreateObject(const string name, const ENUM_OBJECT type, const int x, const int y, const int w, const int h)
{
   string full = PREF + name;
   if(ObjectFind(0, full) >= 0)
      ObjectDelete(0, full);
   ObjectCreate(0, full, type, 0, 0, 0);
   ObjectSetInteger(0, full, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, full, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, full, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, full, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, full, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void CreateLabel(const string name, const int x, const int y, const string text, const color clr)
{
   CreateObject(name, OBJ_LABEL, x, y, 0, 0);
   ObjectSetString(0, PREF + name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, PREF + name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, PREF + name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, PREF + name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, PREF + name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, PREF + name, OBJPROP_ZORDER, 15);
}

//+------------------------------------------------------------------+
void CreateButton(const string name, const int x, const int y, const int w, const int h,
                  const string text, const color bg, const color txtClr)
{
   CreateObject(name, OBJ_BUTTON, x, y, w, h);
   ObjectSetString(0, PREF + name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, PREF + name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, PREF + name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, PREF + name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, PREF + name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, PREF + name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, PREF + name, OBJPROP_ZORDER, 20);
}

//+------------------------------------------------------------------+
void CreateEdit(const string name, const int x, const int y, const int w, const int h, const string val, const bool readonlyFlag)
{
   CreateObject(name, OBJ_EDIT, x, y, w, h);
   ObjectSetString(0, PREF + name, OBJPROP_TEXT, val);
   ObjectSetInteger(0, PREF + name, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, PREF + name, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, PREF + name, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, PREF + name, OBJPROP_READONLY, readonlyFlag);
   ObjectSetInteger(0, PREF + name, OBJPROP_SELECTABLE, !readonlyFlag);
   ObjectSetInteger(0, PREF + name, OBJPROP_ZORDER, 20);
}

//+------------------------------------------------------------------+
double GetInputValue(const string name)
{
   if(ObjectFind(0, PREF + name) < 0)
      return 0.0;
   return StringToDouble(ObjectGetString(0, PREF + name, OBJPROP_TEXT));
}

//+------------------------------------------------------------------+
void ApplyLotModeUI()
{
   if(ObjectFind(0, PREF + "BtnLotMode") < 0)
      return;

   if(IsAutoLot)
   {
      ObjectSetString(0, PREF + "BtnLotMode", OBJPROP_TEXT, "Risk %");
      ObjectSetInteger(0, PREF + "BtnLotMode", OBJPROP_BGCOLOR, clrDarkGreen);
      double riskVal = (g_lastRiskPct > 0.0) ? g_lastRiskPct : 0.1;
      ObjectSetString(0, PREF + "InpLot", OBJPROP_TEXT, DoubleToString(riskVal, 2));
   }
   else
   {
      ObjectSetString(0, PREF + "BtnLotMode", OBJPROP_TEXT, "Lot");
      ObjectSetInteger(0, PREF + "BtnLotMode", OBJPROP_BGCOLOR, clrDarkSlateGray);
      double lotVal = (g_lastManualLot > 0.0) ? g_lastManualLot : 0.01;
      ObjectSetString(0, PREF + "InpLot", OBJPROP_TEXT, DoubleToString(lotVal, 2));
   }
}

//+------------------------------------------------------------------+
void ApplyExecModeUI()
{
   if(ObjectFind(0, PREF + "BtnMode") < 0)
      return;
   if(g_auto)
   {
      ObjectSetString(0, PREF + "BtnMode", OBJPROP_TEXT, "Auto: ON  [M]");
      ObjectSetInteger(0, PREF + "BtnMode", OBJPROP_BGCOLOR, clrGreen);
      ObjectSetInteger(0, PREF + "BtnMode", OBJPROP_COLOR, clrWhite);
   }
   else
   {
      ObjectSetString(0, PREF + "BtnMode", OBJPROP_TEXT, "Manual  [M]");
      ObjectSetInteger(0, PREF + "BtnMode", OBJPROP_BGCOLOR, clrDimGray);
      ObjectSetInteger(0, PREF + "BtnMode", OBJPROP_COLOR, clrWhite);
   }
}

//+------------------------------------------------------------------+
void SetPickMode(const bool on)
{
   g_pickCandle = on;
   if(ObjectFind(0, PREF + "BtnPickCandle") < 0)
      return;
   if(on)
   {
      ObjectSetString(0, PREF + "BtnPickCandle", OBJPROP_TEXT, "Klik Candle [C]");
      ObjectSetInteger(0, PREF + "BtnPickCandle", OBJPROP_BGCOLOR, clrOrangeRed);
   }
   else
   {
      ObjectSetString(0, PREF + "BtnPickCandle", OBJPROP_TEXT, "Pilih Candle [C]");
      ObjectSetInteger(0, PREF + "BtnPickCandle", OBJPROP_BGCOLOR, clrDarkOrange);
   }
}

//+------------------------------------------------------------------+
bool IsPanelObject(const string name)
{
   if(StringFind(name, PREF) != 0)
      return false;
   if(StringFind(name, FIBO_PREF) == 0)
      return false;
   if(name == PREF + "Hide" || name == PREF + "HideQuote")
      return false;
   if(name == PREF + "Live_Clock" || name == PREF + "HardStop" || name == PREF + "Status")
      return false;
   if(name == PREF + "Check1" || name == PREF + "Check2" || name == PREF + "Check3" ||
      name == PREF + "Check4" || name == PREF + "Check5")
      return false;
   return true;
}

//+------------------------------------------------------------------+
int GetInitialY(const string name)
{
   if(name == PREF + "HdrPanel") return HEADER_Y;
   if(name == PREF + "Hide" || name == PREF + "HideQuote") return HEADER_Y + 4;
   if(name == PREF + "Title") return HEADER_Y + 8;
   if(name == PREF + "Panel") return UI_Y;
   if(name == PREF + "LblLayers") return g_yLayers + 4;
   if(name == PREF + "InpLayers" || name == PREF + "BtnLotMode" || name == PREF + "InpLot")
      return g_yLayers;
   if(name == PREF + "LB_Risk" || name == PREF + "LS_Risk") return g_yRisk + 4;
   if(name == PREF + "Buy_Risk" || name == PREF + "Sell_Risk") return g_yRisk;
   if(name == PREF + "BtnMode") return g_yMode;
   if(name == PREF + "BtnScanFibo" || name == PREF + "BtnPickCandle") return g_yScan;
   if(name == PREF + "BtnSetup") return g_ySetup;
   if(name == PREF + "BtnLim236" || name == PREF + "BtnLim50") return g_yLim;
   if(name == PREF + "DelBuy" || name == PREF + "DelSell") return g_yDel;
   if(name == PREF + "ClosePos" || name == PREF + "CloseOrd") return g_yClose;
   if(name == PREF + "Reset") return g_yReset;
   return UI_Y;
}

//+------------------------------------------------------------------+
void ApplyDashboardVisibility()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      if(!IsPanelObject(name))
         continue;
      int y = IsDashboardVisible ? GetInitialY(name) : UI_OFFSCREEN;
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   }
}

//+------------------------------------------------------------------+
void ApplyQuoteVisibility()
{
   int qy = UI_Y + PANEL_H + 12;
   for(int i = 1; i <= 5; i++)
   {
      string name = PREF + "Check" + IntegerToString(i);
      if(ObjectFind(0, name) < 0)
         continue;
      int y = IsQuoteVisible ? (qy + (i - 1) * 18) : UI_OFFSCREEN;
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   }
}

//+------------------------------------------------------------------+
void CreateQuotes()
{
   int qy = UI_Y + PANEL_H + 12;
   DrawNativeLabel(PREF + "Check1", "1. Close momentum = dua limit: 23.6 dan 50. Tanpa market close.", 20, qy, clrBlack);
   DrawNativeLabel(PREF + "Check2", "2. SL 74.5, TP -27. Limit batal 1 jam, atau saat TP posisi candle itu sendiri kena.", 20, qy + 18, clrBlack);
   DrawNativeLabel(PREF + "Check3", "3. Bullish: 0 di high. Bearish: 0 di low. 74.5 di belakang limit.", 20, qy + 36, clrBlack);
   DrawNativeLabel(PREF + "Check4", "4. [F] scan  [C] pilih  [M] auto/manual  [B] dua limit  [H] panel  [T] quote", 20, qy + 54, clrBlack);
   DrawNativeLabel(PREF + "Check5", "5. [2] limit 23.6  [5] limit 50  [Q]/[W] hapus  [P]/[O] close  [R] reset", 20, qy + 72, clrBlack);
}

//+------------------------------------------------------------------+
void InitLayout()
{
   HEADER_Y = MathMax(0, InpHeaderY);
   g_hdrH = 32;
   g_btnH = MathMax(20, InpBtnH);
   g_fieldGap = MathMax(18, InpFieldGap);
   g_editH = MathMin(22, g_fieldGap - 2);
   if(g_editH < 18)
      g_editH = 18;
   PANEL_W = 520;
   g_col1 = 20;
   g_col2 = 270;
   g_colW = 230;
   UI_Y = HEADER_Y + g_hdrH + 2;

   g_yLayers = UI_Y + 6;
   g_yRisk   = g_yLayers + g_editH + 8;
   g_yMode   = g_yRisk + g_editH + 8;
   g_yScan   = g_yMode + g_btnH + 3;
   g_ySetup  = g_yScan + g_btnH + 3;
   g_yLim    = g_ySetup + g_btnH + 3;
   g_yDel    = g_yLim + g_btnH + 3;
   g_yClose  = g_yDel + g_btnH + 3;
   g_yReset  = g_yClose + g_btnH + 3;
   PANEL_H   = (g_yReset - UI_Y) + g_btnH + 8;
}

//+------------------------------------------------------------------+
void CreateDashboard()
{
   int fullW = PANEL_W - 40;

   CreateObject("HdrPanel", OBJ_RECTANGLE_LABEL, 10, HEADER_Y, PANEL_W, g_hdrH);
   ObjectSetInteger(0, PREF + "HdrPanel", OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, PREF + "HdrPanel", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, PREF + "HdrPanel", OBJPROP_ZORDER, 2);

   CreateButton("Hide", 15, HEADER_Y + 4, 90, 24, "Hide [H]", clrGray, clrWhite);
   CreateButton("HideQuote", 110, HEADER_Y + 4, 115, 24, "Hide Q [T]", clrGray, clrWhite);

   CreateLabel("Title", 240, HEADER_Y + 8, "Momentum Candle", clrWhite);
   ObjectSetInteger(0, PREF + "Title", OBJPROP_ZORDER, 16);

   CreateObject("Panel", OBJ_RECTANGLE_LABEL, 10, UI_Y, PANEL_W, PANEL_H);
   ObjectSetInteger(0, PREF + "Panel", OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, PREF + "Panel", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, PREF + "Panel", OBJPROP_ZORDER, 1);

   CreateLabel("LblLayers", g_col1, g_yLayers + 4, "Layers", clrOrange);
   CreateEdit("InpLayers", 130, g_yLayers + 2, 100, g_editH, "1", false);
   CreateButton("BtnLotMode", 260, g_yLayers, 100, g_editH + 2, "Risk %", clrDarkGreen, clrWhite);
   CreateEdit("InpLot", 370, g_yLayers + 2, 100, g_editH, DoubleToString(g_lastRiskPct, 2), false);
   ApplyLotModeUI();

   CreateLabel("LB_Risk", g_col1, g_yRisk + 4, "Risk $", clrOrange);
   CreateEdit("Buy_Risk", 130, g_yRisk + 2, 110, g_editH, "0.00", true);
   CreateLabel("LS_Risk", 260, g_yRisk + 4, "Risk $", clrOrange);
   CreateEdit("Sell_Risk", 370, g_yRisk + 2, 110, g_editH, "0.00", true);

   CreateButton("BtnMode", g_col1, g_yMode, fullW, g_btnH, "Manual  [M]", clrDimGray, clrWhite);
   CreateButton("BtnScanFibo", g_col1, g_yScan, g_colW, g_btnH, "Scan Fibo Candle [F]", clrTeal, clrWhite);
   CreateButton("BtnPickCandle", g_col2, g_yScan, g_colW, g_btnH, "Pilih Candle [C]", clrDarkOrange, clrWhite);
   CreateButton("BtnSetup", g_col1, g_ySetup, fullW, g_btnH, "Setup Limit 23.6 + 50 [B]", clrDodgerBlue, clrWhite);
   CreateButton("BtnLim236", g_col1, g_yLim, g_colW, g_btnH, "Limit " + DoubleToString(InpFiboLimit236, 1) + " [2]", clrDodgerBlue, clrWhite);
   CreateButton("BtnLim50", g_col2, g_yLim, g_colW, g_btnH, "Limit " + DoubleToString(InpFiboLimit50, 1) + " [5]", clrOrangeRed, clrWhite);
   CreateButton("DelBuy", g_col1, g_yDel, g_colW, g_btnH, "Del Buy [Q]", clrBlue, clrWhite);
   CreateButton("DelSell", g_col2, g_yDel, g_colW, g_btnH, "Del Sell [W]", clrBrown, clrWhite);
   CreateButton("ClosePos", g_col1, g_yClose, g_colW, g_btnH, "Close Positions [P]", clrDarkRed, clrWhite);
   CreateButton("CloseOrd", g_col2, g_yClose, g_colW, g_btnH, "Close Orders [O]", clrMaroon, clrWhite);
   CreateButton("Reset", g_col1, g_yReset, fullW, g_btnH, "Reset [R]", clrGray, clrBlack);

   CreateQuotes();
   ApplyExecModeUI();
}
