//+------------------------------------------------------------------+
//|                                             SND_Quick_Retest_System.mq5|
//|                                  Copyright 2026, User            |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh> 

//--- Input Parameters
input double InpBasingRatio    = 0.50; // Rasio maksimal body candle untuk Base
input double InpImpulsiveRatio = 0.55; // Rasio minimal body candle untuk Leg In/Out
input int    InpMaxBase     = 6;    // Maksimal candle base berurutan
input bool   InpShowRBR     = true;  // Tampilkan Rally Base Rally
input bool   InpShowDBD     = true;  // Tampilkan Drop Base Drop
input bool   InpShowDBR     = true;  // Tampilkan Drop Base Rally
input bool   InpShowRBD     = true;  // Tampilkan Rally Base Drop
input int InpMaxZones = 10; // Maksimal zona yang ditampilkan
input bool InpUseEmaFilter = true; // Filter EMA 50 vs 200 untuk auto limit
input int  InpEmaFast = 50;        // EMA cepat
input int  InpEmaSlow = 200;       // EMA lambat

enum ENUM_LOT_MODE
{
   LOT_MANUAL    = 0, // Lot manual
   LOT_AUTO_RISK = 1  // Auto lot dari risk %
};

input group "--- RISK & TRANSMISSION ---"
input ENUM_LOT_MODE InpLotMode     = LOT_AUTO_RISK; // Mode lot
input double        InpRiskPerSetup = 0.1;      // Risk % per setup (bukan per trade)
input double        InpSplitLot1    = 50.0;      // Split S&D order 1 %
input double        InpSplitLot2    = 30.0;      // Split S&D order 2 %
input double        InpSplitLot3    = 20.0;      // Split S&D order 3 %
input int           InpMaxTradesPerDay = 24;     // Max trades per hari (dari history)
input int           InpMaxOpenSimultaneous = 2;  // Max posisi/order terbuka bersamaan
input bool          InpHardDailyStop = false;     // Hard Daily Stop (close semua + disable)
input double        InpMaxDailyLossPercent = 2.0; // Hard stop jika Daily PnL+floating <= -%
input int           InpPendingExpireMinutes = 60; // Cancel pending jika tidak kejemput (menit)
input int           InpTp2CooldownMinutes = 5;   // Jeda setelah kena TP2 sebelum limit baru
input ulong InpMagicNumber = 1111; // Magic Number (Harus beda tiap chart)


CTrade trade;
int g_emaFastHandle = INVALID_HANDLE;
int g_emaSlowHandle = INVALID_HANDLE;
// Di bagian atas (ubah variabel global menjadi tanpa nilai instan dahulu)
string PREF;
string ZONE_PREF;

bool IsDashboardVisible = true;
bool IsQuoteVisible = true;
bool IsSDScanning = false;
bool IsAutoRBR = false;
bool IsAutoDBD = false;
bool IsAutoDBR = false;
bool IsAutoRBD = false;
datetime g_lastAutoZoneBar = 0;
datetime g_lastAutoRevBar = 0;
datetime g_lastTp2HitBuy = 0;
datetime g_lastTp2HitSell = 0;
ulong    g_notedL2PosBuy = 0;
ulong    g_notedL2PosSell = 0;
bool IsAutoLot = true;
double g_lastManualLot = 0.01;
double g_lastRiskPct = 0.12;
int UI_Y = 100;      
int HEADER_Y = 50;   
int PANEL_W = 520;   
int PANEL_H = 740;   
int UI_OFFSCREEN = -2000; 

// --- Function Declarations ---
void CreateDashboard();
void CreateDrawingLines();
void CalculateAndDrawAll();
void ScanSD();
bool IsImpulsive(int index);
bool IsBasing(int index);
void UpdateLine(string name, double price, color clr);
void UpdateInput(string name, double price);
double GetInputValue(string name);
void PlaceBuyOrder();
void PlaceSellOrder();
void PlaceBuyNow();
void PlaceSellNow();
bool DrawingLinesActive();
bool PriceInDrawArea(double price);
double GetDrawnLinePrice(string name);
void TryAutoLimitFromZone(const string type, const double baseLow, const double baseHigh);
int  GetInitialY(string name);
void CreateObject(string name, ENUM_OBJECT type, int win, int x, int y, int w, int h, color clr);
void CreateLabel(string name, int x, int y, string text, color clr);
void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color txtClr);
void CreateEdit(string name, int x, int y, int w, int h, string val);
void DelPO(ENUM_ORDER_TYPE type);
void CloseAllPositions();
void CloseAllOrders();
void ApplyQuoteVisibility();
void DrawNativeLabel(string name, string text, int x, int y, color clr);
void UpdateLiveClock();
void ApplyLotModeUI();
void CreateCalcLotLabel();
void UpdateLotRiskDisplay(double bEntry, double bSL, double sEntry, double sSL);
double CalcRiskUSD(ENUM_ORDER_TYPE orderType, double entry, double sl, double lot, int layers);
double NormalizeLot(double lot);
double GetRiskBaseAmount();
int    GetLayerCount();
double GetSplitWeight(int layerIndex, int layerCount);
double CalcLotPerSetup(ENUM_ORDER_TYPE orderType, double entry, double sl, double riskPct);
double GetResolvedLot(ENUM_ORDER_TYPE orderType, double entry, double sl);
double GetLayerLot(ENUM_ORDER_TYPE orderType, double entry, double sl, int layerIndex);
string FormatLayerLots(ENUM_ORDER_TYPE orderType, double entry, double sl);
double CalcSetupRiskUSD(ENUM_ORDER_TYPE orderType, double entry, double sl);
int    TodayKey();
datetime ServerNow();
datetime DayStartTime();
string GVDayName();
string GVStartEqName();
void   EnsureDayState();
int    CountPositionsOpenedToday();
int    CountOpenSimultaneous();
bool   WouldExceedDailyPositionLimit(const int extraPositions, string &reason);
double GetEADailyPnL();
double GetAccountDailyPnL();
double GetDailyPnLPercent();
datetime DayStartTime();
string GVHaltName();
bool   IsHardStopActive();
void   FlattenAccount();
void   TriggerHardDailyStop(const double pnlPct);
void   CheckHardDailyStop();
void   ManagePendingOrders();
bool   IsBuyPendingType(const long type);
bool   IsSellPendingType(const long type);
bool   PendingHitTp2(const bool isBuy, const double entry, const double sl);
void   NoteTp2Hit(const bool isBuy, const datetime when);
datetime LatestLayer2TpDealTime(const bool forBuy);
void   RefreshTp2HitTimes();
bool   IsTp2CooldownActive(const bool isBuy, string &reason);
void   UpdateHardStopLabel();
bool   IsTradingBlocked(string &reason, const int extraPositions = 0);
void   ActionDrawLine();
void   ActionScanSD();
void   ActionBuyOrder();
void   ActionSellOrder();
void   ActionDelBuy();
void   ActionDelSell();
void   ActionClosePositions();
void   ActionCloseOrders();
void   ActionToggleAuto(const int which);
void   ActionToggleDashboard();
void   ActionToggleQuote();
void   ActionReset();
void   ApplyAutoTypeUI(const string btn, const bool on, const string typeName, const string key);
void   ApplyAllAutoUI();
bool   AutoEnabledForType(const string type);
bool   EmaFilterAllows(const string type, string &reason);
bool   HotkeyModifiersFree();
void   HandleHotkey(const long key);

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() 
{ 
   // Membuat nama objek unik, contoh hasil: "SND_55555_"
   PREF = "SNDQR_" + IntegerToString(InpMagicNumber) + "_";
   ZONE_PREF = "SNDQR_Z_" + IntegerToString(InpMagicNumber) + "_";

   IsAutoLot = (InpLotMode == LOT_AUTO_RISK);
   g_lastRiskPct = (InpRiskPerSetup > 0.0) ? InpRiskPerSetup : 0.12;
   EnsureDayState();
   
   // Mengatur agar setiap kali EA ini mengirim order, Magic Number langsung terpasang otomatis
   trade.SetExpertMagicNumber(InpMagicNumber);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrBlack);
   g_emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   if(g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE)
   {
      Print("Gagal membuat handle EMA ", InpEmaFast, "/", InpEmaSlow);
      return INIT_FAILED;
   }

   CreateDashboard(); 
   CheckHardDailyStop(); 

   // --- KUNCI: Aktifkan timer 1 detik untuk detak jam ---
   // --- WAJIB DI PALING BAWAH SEBELUM RETURN ---
   ResetLastError();
   if(!EventSetTimer(1))
   {
      Print("Gagal mengaktifkan Timer! Error Code: ", GetLastError());
   }
    
   return(INIT_SUCCEEDED); 
}

void OnDeinit(const int reason) 
{ 
   EventKillTimer();
   if(g_emaFastHandle != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
   if(g_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
   ObjectsDeleteAll(0, PREF); 
   ObjectsDeleteAll(0, ZONE_PREF); 
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
}

void OnTick() { 
   CheckHardDailyStop();
   ManagePendingOrders();
   UpdateLiveClock();
   ApplyQuoteVisibility();

   static datetime lastBarTime = 0;
   datetime curBarTime = iTime(_Symbol, _Period, 0);
   if(curBarTime != lastBarTime) {
      lastBarTime = curBarTime;
      ScanSD();
   }
}

// --- FUNGSI TIMER UNTUK MENYETEL WARNA MULTI EMA DARI EA ---
void OnTimer()
{
   static bool quotesDrawn = false;
   if(!quotesDrawn)
   {
      DrawNativeLabel(PREF + "Skor1", "Skor 1: PLN, Whitespace, Flip, Kiss/Quick Retest, Front Running", (PANEL_W + 20), 75, clrBlack);
      DrawNativeLabel(PREF + "Skor2", "Skor 2: SR (Sering Respon), Profit Zone, Fibo, Curve/PAC, PPZ", (PANEL_W + 20), 100, clrBlack);
      DrawNativeLabel(PREF + "Quote1", "Re-Entry di Area yang sama Maksimal 3x Pantulan", (PANEL_W + 20), 125, clrBlack);
      DrawNativeLabel(PREF + "Quote2", "Jam Trading: 08-16 WIB, 20-22 WIB", (PANEL_W + 20), 150, clrBlack);
      quotesDrawn = true;
   }
   UpdateLiveClock();
   CheckHardDailyStop();
   ManagePendingOrders();
   ChartRedraw();
}

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
   DrawNativeLabel(PREF + "Live_Clock", txt, (PANEL_W + 20), 50, clr);
}

void ActionDrawLine()
{
   CreateDrawingLines();
   CalculateAndDrawAll();
}

void ActionScanSD()
{
   IsSDScanning = !IsSDScanning;
   if(IsSDScanning)
   {
      ScanSD();
      ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "S&D: ON [A]");
      ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrGreen);
   }
   else
   {
      ObjectsDeleteAll(0, ZONE_PREF);
      ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "Scan S&D [A]");
      ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrDarkGreen);
   }
}

void ActionBuyOrder()     { PlaceBuyOrder(); }
void ActionSellOrder()    { PlaceSellOrder(); }
void ActionDelBuy()
{
   DelPO(ORDER_TYPE_BUY_LIMIT);
   DelPO(ORDER_TYPE_BUY_STOP);
}
void ActionDelSell()
{
   DelPO(ORDER_TYPE_SELL_LIMIT);
   DelPO(ORDER_TYPE_SELL_STOP);
}
void ActionClosePositions() { CloseAllPositions(); }
void ActionCloseOrders()    { CloseAllOrders(); }
bool AutoEnabledForType(const string type)
{
   if(type == "RBR") return IsAutoRBR;
   if(type == "DBD") return IsAutoDBD;
   if(type == "DBR") return IsAutoDBR;
   if(type == "RBD") return IsAutoRBD;
   return false;
}

bool EmaFilterAllows(const string type, string &reason)
{
   if(!InpUseEmaFilter) return true;
   if(g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE)
   {
      reason = "handle EMA tidak valid";
      return false;
   }

   double fast[1], slow[1];
   if(CopyBuffer(g_emaFastHandle, 0, 1, 1, fast) < 1 || CopyBuffer(g_emaSlowHandle, 0, 1, 1, slow) < 1)
   {
      reason = "data EMA belum siap";
      return false;
   }
   if(fast[0] == 0.0 || slow[0] == 0.0)
   {
      reason = "nilai EMA kosong";
      return false;
   }

   bool bull = (fast[0] > slow[0]);
   bool bear = (fast[0] < slow[0]);
   bool demand = (type == "RBR" || type == "DBR");
   bool supply = (type == "DBD" || type == "RBD");

   if(demand && bull) return true;
   if(supply && bear) return true;

   reason = "EMA " + IntegerToString(InpEmaFast) + (bull ? " di atas " : " di bawah ")
          + IntegerToString(InpEmaSlow) + " (hanya "
          + (bull ? "RBR/DBR" : "DBD/RBD") + ")";
   return false;
}
void ApplyAutoTypeUI(const string btn, const bool on, const string typeName, const string key)
{
   if(ObjectFind(0, PREF+btn) < 0) return;
   ObjectSetString(0, PREF+btn, OBJPROP_TEXT, typeName + (on ? ": ON [" : ": OFF [") + key + "]");
   ObjectSetInteger(0, PREF+btn, OBJPROP_BGCOLOR, on ? clrGreen : clrGray);
   ObjectSetInteger(0, PREF+btn, OBJPROP_COLOR, on ? clrWhite : clrBlack);
}
void ApplyAllAutoUI()
{
   ApplyAutoTypeUI("BtnAutoRBR", IsAutoRBR, "RBR", "1");
   ApplyAutoTypeUI("BtnAutoDBD", IsAutoDBD, "DBD", "2");
   ApplyAutoTypeUI("BtnAutoDBR", IsAutoDBR, "DBR", "3");
   ApplyAutoTypeUI("BtnAutoRBD", IsAutoRBD, "RBD", "4");
}
void ActionToggleAuto(const int which)
{
   string name = "";
   bool on = false;
   if(which == 1) { IsAutoRBR = !IsAutoRBR; on = IsAutoRBR; name = "RBR"; }
   else if(which == 2) { IsAutoDBD = !IsAutoDBD; on = IsAutoDBD; name = "DBD"; }
   else if(which == 3) { IsAutoDBR = !IsAutoDBR; on = IsAutoDBR; name = "DBR"; }
   else if(which == 4) { IsAutoRBD = !IsAutoRBD; on = IsAutoRBD; name = "RBD"; }
   else return;
   ApplyAllAutoUI();
   Print("Auto Limit ", name, ": ", on ? "ON" : "OFF");
}
void ActionToggleDashboard()
{
   IsDashboardVisible = !IsDashboardVisible;
   ObjectSetString(0, PREF+"Hide", OBJPROP_TEXT, IsDashboardVisible ? "Hide [H]" : "Show [H]");
   for(int i = 0; i < ObjectsTotal(0); i++)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, PREF) == 0 &&
         name != PREF+"Hide" &&
         name != PREF+"HideQuote" &&
         name != PREF+"Live_Clock" &&
         name != PREF+"HardStop" &&
         name != PREF+"Skor1" &&
         name != PREF+"Skor2" &&
         name != PREF+"Quote1" &&
         name != PREF+"Quote2")
      {
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, IsDashboardVisible ? GetInitialY(name) : UI_OFFSCREEN);
      }
   }
   ObjectSetInteger(0, PREF+"Hide", OBJPROP_YDISTANCE, HEADER_Y + 7);
   ObjectSetInteger(0, PREF+"HideQuote", OBJPROP_YDISTANCE, HEADER_Y + 7);
   ObjectSetInteger(0, PREF+"Hide", OBJPROP_STATE, false);
}
void ActionToggleQuote()
{
   IsQuoteVisible = !IsQuoteVisible;
   ObjectSetString(0, PREF+"HideQuote", OBJPROP_TEXT, IsQuoteVisible ? "Hide Q [U]" : "Show Q [U]");
   ApplyQuoteVisibility();
   ObjectSetInteger(0, PREF+"HideQuote", OBJPROP_STATE, false);
}
void ActionReset()
{
   ObjectsDeleteAll(0, PREF+"Line_");
   ObjectsDeleteAll(0, PREF+"Calc_");
   ObjectsDeleteAll(0, PREF+"Layer_");
   ObjectsDeleteAll(0, ZONE_PREF);
   IsSDScanning = false;
   g_lastAutoZoneBar = 0;
   g_lastAutoRevBar = 0;
   g_lastTp2HitBuy = 0;
   g_lastTp2HitSell = 0;
   g_notedL2PosBuy = 0;
   g_notedL2PosSell = 0;
   ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "Scan S&D [A]");
   ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrDarkGreen);
   if(IsAutoLot && ObjectFind(0, PREF+"LblCalcLot") >= 0)
      ObjectSetString(0, PREF+"LblCalcLot", OBJPROP_TEXT, "Lot setup: (draw line)");
   ChartRedraw();
}

bool HotkeyModifiersFree()
{
   return ((TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL) & 0x8000) == 0 &&
           (TerminalInfoInteger(TERMINAL_KEYSTATE_MENU) & 0x8000) == 0 &&
           (TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT) & 0x8000) == 0);
}

void HandleHotkey(const long key)
{
   if(!HotkeyModifiersFree()) return;

   if(key == 68) ActionDrawLine();           // D
   else if(key == 65) ActionScanSD();        // A
   else if(key == 66) ActionBuyOrder();      // B
   else if(key == 83) ActionSellOrder();     // S
   else if(key == 81) ActionDelBuy();        // Q
   else if(key == 87) ActionDelSell();       // W
   else if(key == 80) ActionClosePositions(); // P
   else if(key == 79) ActionCloseOrders();   // O
   else if(key == 49) ActionToggleAuto(1);   // 1 RBR
   else if(key == 50) ActionToggleAuto(2);   // 2 DBD
   else if(key == 51) ActionToggleAuto(3);   // 3 DBR
   else if(key == 52) ActionToggleAuto(4);   // 4 RBD
   else if(key == 72) ActionToggleDashboard(); // H
   else if(key == 85) ActionToggleQuote();   // U
   else if(key == 82) ActionReset();         // R
   else return;

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Event Handling                                                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      HandleHotkey(lparam);
      return;
   }

   if(id == CHARTEVENT_OBJECT_DRAG) { 
      if(sparam == PREF+"Line_Floor" || sparam == PREF+"Line_Ceiling") CalculateAndDrawAll(); 
      ChartRedraw(); 
   }
   
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == PREF+"Hide") { 
         ActionToggleDashboard();
         ChartRedraw();
      }
      else if(sparam == PREF+"HideQuote") {
         ActionToggleQuote();
         ChartRedraw();
      }
      else if(sparam == PREF+"BtnLotMode") {
         if(IsAutoLot) g_lastRiskPct = GetInputValue("InpLot");
         else          g_lastManualLot = GetInputValue("InpLot");
         IsAutoLot = !IsAutoLot;
         ApplyLotModeUI();
         if(ObjectFind(0, PREF+"Line_Floor") >= 0 && ObjectFind(0, PREF+"Line_Ceiling") >= 0)
            CalculateAndDrawAll();
         ObjectSetInteger(0, PREF+"BtnLotMode", OBJPROP_STATE, false);
         ChartRedraw();
      }
      else if(sparam == PREF+"BtnDraw") { ActionDrawLine(); ObjectSetInteger(0, PREF+"BtnDraw", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnScanSD") {
         ActionScanSD();
         ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_STATE, false);
      }
      else if(sparam == PREF+"BtnBuyL") { ActionBuyOrder(); ObjectSetInteger(0, PREF+"BtnBuyL", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnSellL") { ActionSellOrder(); ObjectSetInteger(0, PREF+"BtnSellL", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BuyNow") { PlaceBuyNow(); ObjectSetInteger(0, PREF+"BuyNow", OBJPROP_STATE, false); }
      else if(sparam == PREF+"SellNow") { PlaceSellNow(); ObjectSetInteger(0, PREF+"SellNow", OBJPROP_STATE, false); }
      else if(sparam == PREF+"DelBuy") {
         ActionDelBuy();
         ObjectSetInteger(0, PREF+"DelBuy", OBJPROP_STATE, false);
      }
      else if(sparam == PREF+"DelSell") {
         ActionDelSell();
         ObjectSetInteger(0, PREF+"DelSell", OBJPROP_STATE, false);
      }
      else if(sparam == PREF+"ClosePos") { ActionClosePositions(); ObjectSetInteger(0, PREF+"ClosePos", OBJPROP_STATE, false); }
      else if(sparam == PREF+"CloseOrd") { ActionCloseOrders(); ObjectSetInteger(0, PREF+"CloseOrd", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnAutoRBR") { ActionToggleAuto(1); ObjectSetInteger(0, PREF+"BtnAutoRBR", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnAutoDBD") { ActionToggleAuto(2); ObjectSetInteger(0, PREF+"BtnAutoDBD", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnAutoDBR") { ActionToggleAuto(3); ObjectSetInteger(0, PREF+"BtnAutoDBR", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnAutoRBD") { ActionToggleAuto(4); ObjectSetInteger(0, PREF+"BtnAutoRBD", OBJPROP_STATE, false); }
      else if(sparam == PREF+"Reset") { ActionReset(); ObjectSetInteger(0, PREF+"Reset", OBJPROP_STATE, false); }
      // --- DETEKSI KLIK TOMBOL BULAT S&D ---
      else if(StringFind(sparam, ZONE_PREF + "BTN_") == 0) {
         if(ObjectFind(0, PREF+"Line_Floor") < 0 || ObjectFind(0, PREF+"Line_Ceiling") < 0) {
            CreateDrawingLines();
         }
         
         // Ambil nama kotak pasangan dengan memotong prefiks nama tombol
         string zoneSuffix = StringSubstr(sparam, StringLen(ZONE_PREF) + 4); 
         string rectName = ZONE_PREF + zoneSuffix;
         
         if(ObjectFind(0, rectName) >= 0) {
            double price1 = ObjectGetDouble(0, rectName, OBJPROP_PRICE, 0);
            double price2 = ObjectGetDouble(0, rectName, OBJPROP_PRICE, 1);

            // Proximal lebih dekat dengan harga terkini/open leg in, distal lebih jauh.
            double distal = (price1 < price2) ? price1 : price2;
            double proximal = (price1 > price2) ? price1 : price2;

            // Jika Demand (RBR)
            if(StringFind(sparam, "_RBR_") >= 0) {
               // Floor dari distal (garis bawah), Ceiling dari proximal (garis atas)
               ObjectSetDouble(0, PREF+"Line_Floor", OBJPROP_PRICE, distal);
               ObjectSetDouble(0, PREF+"Line_Ceiling", OBJPROP_PRICE, proximal);
            }
            // Jika Supply (DBD)
            else if(StringFind(sparam, "_DBD_") >= 0) {
               // Ceiling dari distal (garis atas), Floor dari proximal (garis bawah)
               ObjectSetDouble(0, PREF+"Line_Ceiling", OBJPROP_PRICE, proximal);
               ObjectSetDouble(0, PREF+"Line_Floor", OBJPROP_PRICE, distal);
            }
            // Jika DBR (Demand), Floor = distal, Ceiling = proximal
            else if(StringFind(sparam, "_DBR_") >= 0) {
               ObjectSetDouble(0, PREF+"Line_Floor", OBJPROP_PRICE, distal);
               ObjectSetDouble(0, PREF+"Line_Ceiling", OBJPROP_PRICE, proximal);
            }
            // Jika RBD (Supply), Ceiling = distal, Floor = proximal
            else if(StringFind(sparam, "_RBD_") >= 0) {
               ObjectSetDouble(0, PREF+"Line_Ceiling", OBJPROP_PRICE, proximal);
               ObjectSetDouble(0, PREF+"Line_Floor", OBJPROP_PRICE, distal);
            }

            CalculateAndDrawAll();
         }
         
         // Refresh status agar tombol teks siap menerima klik berulang tanpa macet
         ObjectSetInteger(0, sparam, OBJPROP_SELECTED, false);
         ObjectSetInteger(0, sparam, OBJPROP_SELECTABLE, false);
         ChartRedraw();
         ObjectSetInteger(0, sparam, OBJPROP_SELECTABLE, true);
         ChartRedraw();
      }
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == PREF+"InpLayers" || sparam == PREF+"InpLot")
      {
         if(ObjectFind(0, PREF+"Line_Floor") >= 0 && ObjectFind(0, PREF+"Line_Ceiling") >= 0)
            CalculateAndDrawAll();
         ChartRedraw();
      }
   }
}

void TryAutoLimitFromZone(const string type, const double baseLow, const double baseHigh)
{
   bool isSnd = (type == "RBR" || type == "DBD");
   bool isRev = (type == "DBR" || type == "RBD");
   if(!AutoEnabledForType(type)) return;
   if(!isSnd && !isRev) return;
   if(baseLow <= 0.0 || baseHigh <= 0.0 || baseHigh <= baseLow) return;

   string emaReason = "";
   if(!EmaFilterAllows(type, emaReason))
   {
      Print("Auto Limit skip ", type, ": ", emaReason);
      return;
   }

   datetime zoneBar = iTime(_Symbol, _Period, 1);
   if(isSnd)
   {
      if(zoneBar > 0 && zoneBar == g_lastAutoZoneBar) return;
      g_lastAutoZoneBar = zoneBar;
   }
   else
   {
      if(zoneBar > 0 && zoneBar == g_lastAutoRevBar) return;
      g_lastAutoRevBar = zoneBar;
   }

   bool isBuy = (type == "RBR" || type == "DBR");
   string waitReason = "";
   RefreshTp2HitTimes();
   if(IsTp2CooldownActive(isBuy, waitReason))
   {
      Print("Auto Limit skip ", type, ": ", waitReason);
      return;
   }

   if(ObjectFind(0, PREF+"Line_Floor") < 0 || ObjectFind(0, PREF+"Line_Ceiling") < 0)
      CreateDrawingLines();

   ObjectSetDouble(0, PREF+"Line_Floor", OBJPROP_PRICE, baseLow);
   ObjectSetDouble(0, PREF+"Line_Ceiling", OBJPROP_PRICE, baseHigh);
   CalculateAndDrawAll();

   if(isBuy)
   {
      Print("Auto Limit: ", type, " terbentuk. Pasang Buy Order.");
      PlaceBuyOrder();
   }
   else
   {
      Print("Auto Limit: ", type, " terbentuk. Pasang Sell Order.");
      PlaceSellOrder();
   }
}

// --- SHOW / HIDE QUOTE LABELS ---
void ApplyQuoteVisibility()
{
   int ySkor1  = IsQuoteVisible ? 75  : UI_OFFSCREEN;
   int ySkor2  = IsQuoteVisible ? 100 : UI_OFFSCREEN;
   int yQuote1 = IsQuoteVisible ? 125 : UI_OFFSCREEN;
   int yQuote2 = IsQuoteVisible ? 150 : UI_OFFSCREEN;

   if(ObjectFind(0, PREF + "Skor1")  >= 0) ObjectSetInteger(0, PREF + "Skor1",  OBJPROP_YDISTANCE, ySkor1);
   if(ObjectFind(0, PREF + "Skor2")  >= 0) ObjectSetInteger(0, PREF + "Skor2",  OBJPROP_YDISTANCE, ySkor2);
   if(ObjectFind(0, PREF + "Quote1") >= 0) ObjectSetInteger(0, PREF + "Quote1", OBJPROP_YDISTANCE, yQuote1);
   if(ObjectFind(0, PREF + "Quote2") >= 0) ObjectSetInteger(0, PREF + "Quote2", OBJPROP_YDISTANCE, yQuote2);
}

// --- HELPER MAKER OBJEK DASHBOARD NATIVE (ANTI-TEKS KEPOTONG) ---
void DrawNativeLabel(string name, string text, int x, int y, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 11); // Set paling depan agar tidak tertutup objek S&D
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

// --- Logic S&D Scanner ---
void ScanSD() { 
   ObjectsDeleteAll(0, ZONE_PREF);
   int limit = 2000; 
   int zonesFound = 0; 
   
   for(int i = 1; i < limit; i++) {
      if(zonesFound >= InpMaxZones) break;

      if(!IsImpulsive(i)) continue;
      
      int baseCount = 0;
      double baseHigh = 0, baseLow = 999999;
      
      for(int j = i + 1; j < i + 1 + InpMaxBase; j++) {
         if(IsBasing(j)) {
            baseCount++;
            baseHigh = (baseHigh == 0) ? iHigh(_Symbol, _Period, j) : MathMax(baseHigh, iHigh(_Symbol, _Period, j));
            baseLow = MathMin(baseLow, iLow(_Symbol, _Period, j));
         } else {
            break; 
         }
      }
      
      if(baseCount >= 1) {
         int legInIdx = i + 1 + baseCount;
         if(IsImpulsive(legInIdx)) {
            
            bool legInUp  = (iClose(_Symbol, _Period, legInIdx) > iOpen(_Symbol, _Period, legInIdx));
            bool legOutUp = (iClose(_Symbol, _Period, i) > iOpen(_Symbol, _Period, i));
            double legOutClose = iClose(_Symbol, _Period, i);
            
            string type = "";
            bool shouldDraw = false;

            if(legInUp && legOutUp)   { type = "RBR"; shouldDraw = InpShowRBR; }
            if(!legInUp && !legOutUp) { type = "DBD"; shouldDraw = InpShowDBD; }
            if(!legInUp && legOutUp)  { type = "DBR"; shouldDraw = InpShowDBR; }
            if(legInUp && !legOutUp)  { type = "RBD"; shouldDraw = InpShowRBD; }

            string emaReason = "";
            bool autoWanted = (i == 1) && AutoEnabledForType(type) && EmaFilterAllows(type, emaReason);
            if(!shouldDraw && !autoWanted) continue;

            // RBR/DBR: Close Leg Out di atas base | DBD/RBD: Close Leg Out di bawah base
            if((type == "RBR" || type == "DBR") && legOutClose <= baseHigh) continue;
            if((type == "DBD" || type == "RBD") && legOutClose >= baseLow) continue;

            // --- MITIGASI: PERSEN DARI LEBAR AREA YANG SUDAH TERMASUK HARGA ---
            double zoneWidth = baseHigh - baseLow;
            if(zoneWidth <= 0.0) continue;

            double deepestMit = 0.0;
            bool isFullMitigated = false;

            for(int k = i - 1; k >= 0; k--) {
               double candleHigh = iHigh(_Symbol, _Period, k);
               double candleLow  = iLow(_Symbol, _Period, k);

               if(legOutUp) {
                  if(candleLow < baseLow) {
                     isFullMitigated = true;
                     break;
                  }
                  if(candleLow <= baseHigh) {
                     double pen = baseHigh - MathMax(candleLow, baseLow);
                     if(pen > deepestMit) deepestMit = pen;
                  }
               } else {
                  if(candleHigh > baseHigh) {
                     isFullMitigated = true;
                     break;
                  }
                  if(candleHigh >= baseLow) {
                     double pen = MathMin(candleHigh, baseHigh) - baseLow;
                     if(pen > deepestMit) deepestMit = pen;
                  }
               }
            }

            if(isFullMitigated) continue;

            int mitPct = (int)MathRound(deepestMit / zoneWidth * 100.0);
            if(mitPct > 100) mitPct = 100;

            string labelText = "● Fresh " + type;
            if(mitPct > 0)
               labelText = "● " + IntegerToString(mitPct) + "% " + type;

            datetime startTime = iTime(_Symbol, _Period, i);
            datetime endTime = TimeCurrent() + (PeriodSeconds() * 8);

            string name = ZONE_PREF + type + "_" + IntegerToString(i);
            if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, startTime, baseLow, endTime, baseHigh)) {
               color clr = legOutUp ? clrSkyBlue : clrLightSalmon;
               ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
               ObjectSetInteger(0, name, OBJPROP_FILL, true);
               ObjectSetInteger(0, name, OBJPROP_BACK, true);
               ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

               string btnName = ZONE_PREF + "BTN_" + type + "_" + IntegerToString(i);
               datetime btnTime = iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period) * 3;
               double lastPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               double btnPrice = lastPrice;
               if(lastPrice > baseHigh) btnPrice = baseHigh;
               else if(lastPrice < baseLow) btnPrice = baseLow;

               ObjectCreate(0, btnName, OBJ_TEXT, 0, btnTime, btnPrice);
               ObjectSetString(0, btnName, OBJPROP_TEXT, labelText);
               ObjectSetString(0, btnName, OBJPROP_FONT, "Arial Bold");
               ObjectSetInteger(0, btnName, OBJPROP_FONTSIZE, 10);
               ObjectSetInteger(0, btnName, OBJPROP_ANCHOR, ANCHOR_LEFT);

               color btnColor = legOutUp ? clrBlue : clrRed;
               if(mitPct > 0) btnColor = clrSlateGray;

               ObjectSetInteger(0, btnName, OBJPROP_COLOR, btnColor);
               ObjectSetInteger(0, btnName, OBJPROP_SELECTABLE, true);
               ObjectSetInteger(0, btnName, OBJPROP_SELECTED, false);

               zonesFound++;
               if(i == 1)
                  TryAutoLimitFromZone(type, baseLow, baseHigh);
            }
         }
      }
   }
   ChartRedraw();
}

bool IsImpulsive(int idx) { 
   double body = MathAbs(iClose(_Symbol, _Period, idx) - iOpen(_Symbol, _Period, idx)); 
   double range = MathAbs(iHigh(_Symbol, _Period, idx) - iLow(_Symbol, _Period, idx)); 
   if(range <= 0.0) return false;
   return (body > (range * InpImpulsiveRatio)); 
}

bool IsBasing(int idx) { 
   double body = MathAbs(iClose(_Symbol, _Period, idx) - iOpen(_Symbol, _Period, idx)); 
   double range = MathAbs(iHigh(_Symbol, _Period, idx) - iLow(_Symbol, _Period, idx)); 
   if(range <= 0.0) return false;
   if(body > (range * InpImpulsiveRatio)) return false;
   return (body <= (range * InpBasingRatio)); 
}

// --- Logic Trading ---
double GetSpreadPrice()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   if(spread <= 0.0)
      spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   return spread;
}

double BuyTPByLayer(int layerIndex, double entry, double sl)
{
   double risk = entry - sl;
   if(risk <= 0.0) return 0.0;
   if(layerIndex == 0) return GetInputValue("Buy_TP1");
   if(layerIndex == 1) return GetInputValue("Buy_TP2");
   if(layerIndex == 2) return GetInputValue("Buy_TP3");
   if(layerIndex == 3) return entry + 4.0 * risk;
   return entry + 5.0 * risk;
}

double SellTPByLayer(int layerIndex, double entry, double sl)
{
   double risk = sl - entry;
   if(risk <= 0.0) return 0.0;
   if(layerIndex == 0) return GetInputValue("Sell_TP1");
   if(layerIndex == 1) return GetInputValue("Sell_TP2");
   if(layerIndex == 2) return GetInputValue("Sell_TP3");
   if(layerIndex == 3) return entry - 4.0 * risk;
   return entry - 5.0 * risk;
}

double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0) stepLot = 0.01;

   lot = MathFloor(lot / stepLot + 0.0000001) * stepLot;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return lot;
}

double GetRiskBaseAmount()
{
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

int GetLayerCount()
{
   int layers = (int)GetInputValue("InpLayers");
   if(layers < 1) layers = 1;
   if(layers > 3) layers = 3;
   return layers;
}

double GetSplitWeight(int layerIndex, int layerCount)
{
   if(layerCount <= 1)
      return (layerIndex == 0) ? 1.0 : 0.0;

   if(layerCount == 2)
      return (layerIndex == 0 || layerIndex == 1) ? 0.5 : 0.0;

   double w1 = (InpSplitLot1 > 0.0) ? InpSplitLot1 : 0.0;
   double w2 = (InpSplitLot2 > 0.0) ? InpSplitLot2 : 0.0;
   double w3 = (InpSplitLot3 > 0.0) ? InpSplitLot3 : 0.0;
   double sum3 = w1 + w2 + w3;
   if(sum3 <= 0.0) sum3 = 100.0;

   if(layerIndex == 0) return w1 / sum3;
   if(layerIndex == 1) return w2 / sum3;
   if(layerIndex == 2) return w3 / sum3;
   return 0.0;
}

double CalcLotPerSetup(ENUM_ORDER_TYPE orderType, double entry, double sl, double riskPct)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(entry <= 0.0 || sl <= 0.0 || MathAbs(entry - sl) <= 0.0)
      return NormalizeLot(minLot);

   double base = GetRiskBaseAmount();
   if(base <= 0.0) return NormalizeLot(minLot);

   double totalRiskMoney = base * riskPct / 100.0;

   double profit = 0.0;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entry, sl, profit))
   {
      Print("OrderCalcProfit gagal. Error: ", GetLastError());
      return NormalizeLot(minLot);
   }

   double lossPerLot = MathAbs(profit);
   if(lossPerLot <= 0.0) return NormalizeLot(minLot);

   return NormalizeLot(totalRiskMoney / lossPerLot);
}

double GetResolvedLot(ENUM_ORDER_TYPE orderType, double entry, double sl)
{
   if(!IsAutoLot)
   {
      double lot = GetInputValue("InpLot");
      if(lot <= 0.0) return 0.0;
      return NormalizeLot(lot);
   }

   double riskPct = GetInputValue("InpLot");
   if(riskPct <= 0.0) riskPct = (InpRiskPerSetup > 0.0) ? InpRiskPerSetup : 0.12;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(riskPct > 1.0)
   {
      Print("Risk ", DoubleToString(riskPct, 2), "% > 1%. Memakai lot terkecil ", minLot);
      return NormalizeLot(minLot);
   }

   return CalcLotPerSetup(orderType, entry, sl, riskPct);
}

double GetLayerLot(ENUM_ORDER_TYPE orderType, double entry, double sl, int layerIndex)
{
   double setupLot = GetResolvedLot(orderType, entry, sl);
   if(setupLot <= 0.0) return 0.0;
   double w = GetSplitWeight(layerIndex, GetLayerCount());
   if(w <= 0.0) return 0.0;
   return NormalizeLot(setupLot * w);
}

string FormatLayerLots(ENUM_ORDER_TYPE orderType, double entry, double sl)
{
   int n = GetLayerCount();
   string s = "";
   for(int i = 0; i < n; i++)
   {
      if(i > 0) s += "/";
      s += DoubleToString(GetLayerLot(orderType, entry, sl, i), 2);
   }
   return s;
}

double CalcSetupRiskUSD(ENUM_ORDER_TYPE orderType, double entry, double sl)
{
   int n = GetLayerCount();
   double total = 0.0;
   for(int i = 0; i < n; i++)
      total += CalcRiskUSD(orderType, entry, sl, GetLayerLot(orderType, entry, sl, i), 1);
   return total;
}

datetime ServerNow()
{
   datetime t = TimeTradeServer();
   if(t <= 0) t = TimeGMT();
   if(t <= 0) t = TimeCurrent();
   return t;
}

int TodayKey()
{
   MqlDateTime dt;
   TimeToStruct(ServerNow(), dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

datetime DayStartTime()
{
   MqlDateTime dt;
   TimeToStruct(ServerNow(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

string GVDayName()     { return "SNDQR_DAY_" + IntegerToString(InpMagicNumber); }
string GVStartEqName() { return "SNDQR_STARTEQ_" + IntegerToString(InpMagicNumber); }
string GVHaltName()    { return "SNDQR_HALT_" + IntegerToString(InpMagicNumber); }

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

int CountPositionsOpenedToday()
{
   datetime from = DayStartTime();
   int count = 0;
   if(!HistorySelect(from, ServerNow()))
      return 0;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;

      long dtype = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;

      count++;
   }
   return count;
}

int CountOpenSimultaneous()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      n++;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(!OrderSelect(t)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
      n++;
   }
   return n;
}

bool WouldExceedDailyPositionLimit(const int extraPositions, string &reason)
{
   int extra = (extraPositions > 0) ? extraPositions : 1;

   int trades = CountPositionsOpenedToday();
   if(InpMaxTradesPerDay > 0 && (trades >= InpMaxTradesPerDay || trades + extra > InpMaxTradesPerDay))
   {
      reason = "Max trades per hari tercapai (" + IntegerToString(trades) + "/"
             + IntegerToString(InpMaxTradesPerDay) + ", history hari ini)";
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

double GetEADailyPnL()
{
   datetime from = DayStartTime();
   double pnl = 0.0;
   if(HistorySelect(from, ServerNow()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
         if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
         long dtype = HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL) continue;
         pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         pnl += HistoryDealGetDouble(ticket, DEAL_SWAP);
         pnl += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      pnl += PositionGetDouble(POSITION_PROFIT);
      pnl += PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

double GetAccountDailyPnL()
{
   datetime from = DayStartTime();
   double pnl = 0.0;
   if(HistorySelect(from, ServerNow()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         long dtype = HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL) continue;
         pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         pnl += HistoryDealGetDouble(ticket, DEAL_SWAP);
         pnl += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      pnl += PositionGetDouble(POSITION_PROFIT);
      pnl += PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

double GetDailyPnLPercent()
{
   EnsureDayState();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double startEq = GlobalVariableCheck(GVStartEqName()) ? GlobalVariableGet(GVStartEqName()) : 0.0;
   if(startEq <= 0.0) startEq = equity;
   if(startEq <= 0.0) return 0.0;
   return (equity - startEq) / startEq * 100.0;
}

bool IsHardStopActive()
{
   if(!InpHardDailyStop) return false;
   EnsureDayState();
   if(!GlobalVariableCheck(GVHaltName())) return false;
   return ((int)GlobalVariableGet(GVHaltName()) == TodayKey());
}

void FlattenAccount()
{
   for(int pass = 0; pass < 3; pass++)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(!trade.PositionClose(t))
            Print("Hard Daily Stop: gagal close posisi #", t, " ", trade.ResultRetcodeDescription());
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong t = OrderGetTicket(i);
         if(!OrderSelect(t)) continue;
         if(!trade.OrderDelete(t))
            Print("Hard Daily Stop: gagal hapus order #", t, " ", trade.ResultRetcodeDescription());
      }
   }
}

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
      txt = "HARD DAILY STOP " + DoubleToString(pct, 2) + "%  | OFF until 00:00 server" + posTxt;
      clr = clrOrangeRed;
   }
   else
   {
      txt = "Daily PnL " + DoubleToString(pct, 2) + "%  (incl. floating)" + posTxt;
      if((CountPositionsOpenedToday() >= InpMaxTradesPerDay && InpMaxTradesPerDay > 0) ||
         (CountOpenSimultaneous() >= InpMaxOpenSimultaneous && InpMaxOpenSimultaneous > 0))
         clr = clrOrangeRed;
      else if(pct <= -InpMaxDailyLossPercent * 0.7) clr = clrOrange;
      else if(pct < 0.0) clr = clrDarkOrange;
      else clr = clrForestGreen;
   }
   DrawNativeLabel(PREF + "HardStop", txt, (PANEL_W + 20), 25, clr);
}

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

bool IsBuyPendingType(const long type)
{
   return (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);
}

bool IsSellPendingType(const long type)
{
   return (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT);
}

bool PendingHitTp2(const bool isBuy, const double entry, const double sl)
{
   if(entry <= 0.0 || sl <= 0.0) return false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(isBuy)
   {
      double risk = entry - sl;
      if(risk <= 0.0) return false;
      return (bid >= entry + 2.0 * risk);
   }
   double risk = sl - entry;
   if(risk <= 0.0) return false;
   return (ask <= entry - 2.0 * risk);
}

void NoteTp2Hit(const bool isBuy, const datetime when)
{
   if(when <= 0) return;
   if(isBuy)
   {
      if(when > g_lastTp2HitBuy) g_lastTp2HitBuy = when;
   }
   else if(when > g_lastTp2HitSell)
      g_lastTp2HitSell = when;
}

datetime LatestLayer2TpDealTime(const bool forBuy)
{
   datetime latest = 0;
   if(!HistorySelect(DayStartTime(), ServerNow() + 1)) return 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY) continue;
      if((ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON) != DEAL_REASON_TP) continue;
      string cmt = HistoryDealGetString(ticket, DEAL_COMMENT);
      if(StringFind(cmt, "L2") < 0) continue;
      long dtype = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(forBuy && dtype != DEAL_TYPE_SELL) continue;
      if(!forBuy && dtype != DEAL_TYPE_BUY) continue;
      datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(t > latest) latest = t;
   }
   return latest;
}

void RefreshTp2HitTimes()
{
   datetime now = ServerNow();
   NoteTp2Hit(true, LatestLayer2TpDealTime(true));
   NoteTp2Hit(false, LatestLayer2TpDealTime(false));

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      string cmt = PositionGetString(POSITION_COMMENT);
      if(StringFind(cmt, "L2") < 0) continue;
      long ptype = PositionGetInteger(POSITION_TYPE);
      double tp = PositionGetDouble(POSITION_TP);
      if(tp <= 0.0) continue;

      bool isBuy = (ptype == POSITION_TYPE_BUY);
      bool atTp = isBuy ? (bid >= tp) : (ask <= tp);
      if(!atTp) continue;

      ulong noted = isBuy ? g_notedL2PosBuy : g_notedL2PosSell;
      if(t == noted) continue;
      if(isBuy) g_notedL2PosBuy = t;
      else g_notedL2PosSell = t;
      NoteTp2Hit(isBuy, now);
   }
}

bool IsTp2CooldownActive(const bool isBuy, string &reason)
{
   int sec = InpTp2CooldownMinutes * 60;
   if(sec <= 0) return false;
   datetime hit = isBuy ? g_lastTp2HitBuy : g_lastTp2HitSell;
   if(hit <= 0) return false;
   datetime until = hit + sec;
   datetime now = ServerNow();
   if(now >= until) return false;
   int left = (int)(until - now);
   reason = "jeda " + IntegerToString(InpTp2CooldownMinutes) + " menit setelah TP2 ("
          + IntegerToString(left) + "s lagi)";
   return true;
}

void ManagePendingOrders()
{
   int expireSec = InpPendingExpireMinutes * 60;
   if(expireSec < 0) expireSec = 0;
   datetime now = ServerNow();
   RefreshTp2HitTimes();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;

      long type = OrderGetInteger(ORDER_TYPE);
      bool isBuy = IsBuyPendingType(type);
      bool isSell = IsSellPendingType(type);
      if(!isBuy && !isSell) continue;

      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      double entry = OrderGetDouble(ORDER_PRICE_OPEN);
      double sl = OrderGetDouble(ORDER_SL);
      datetime tp2Hit = isBuy ? g_lastTp2HitBuy : g_lastTp2HitSell;

      bool expired = (expireSec > 0 && setup > 0 && now >= setup + expireSec);
      bool ownTp2 = PendingHitTp2(isBuy, entry, sl);
      bool leftoverAfterTp2 = (tp2Hit > 0 && setup > 0 && setup <= tp2Hit);
      if(!expired && !ownTp2 && !leftoverAfterTp2) continue;

      if(ownTp2)
         NoteTp2Hit(isBuy, now);

      string why = expired ? "tidak kejemput " + IntegerToString(InpPendingExpireMinutes) + " menit"
                           : "sudah terkena TP2";
      if(trade.OrderDelete(ticket))
         Print("Pending dibatalkan (", why, "): ticket ", ticket, " ", EnumToString((ENUM_ORDER_TYPE)type));
      else
         Print("Gagal batal pending ticket ", ticket, ". Error: ", GetLastError());
   }
}

bool IsTradingBlocked(string &reason, const int extraPositions = 0)
{
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

void ApplyLotModeUI()
{
   if(ObjectFind(0, PREF+"BtnLotMode") < 0) return;

   if(IsAutoLot)
   {
      ObjectSetString(0, PREF+"BtnLotMode", OBJPROP_TEXT, "Risk %");
      ObjectSetInteger(0, PREF+"BtnLotMode", OBJPROP_BGCOLOR, clrDarkGreen);
      double riskVal = (g_lastRiskPct > 0.0) ? g_lastRiskPct : 0.12;
      ObjectSetString(0, PREF+"InpLot", OBJPROP_TEXT, DoubleToString(riskVal, 2));
      if(ObjectFind(0, PREF+"Line_Floor") < 0 && ObjectFind(0, PREF+"LblCalcLot") >= 0)
         ObjectSetString(0, PREF+"LblCalcLot", OBJPROP_TEXT, "Lot setup: (draw line)");
   }
   else
   {
      ObjectSetString(0, PREF+"BtnLotMode", OBJPROP_TEXT, "Lot");
      ObjectSetInteger(0, PREF+"BtnLotMode", OBJPROP_BGCOLOR, clrDarkSlateGray);
      double lotVal = (g_lastManualLot > 0.0) ? g_lastManualLot : 0.05;
      ObjectSetString(0, PREF+"InpLot", OBJPROP_TEXT, DoubleToString(lotVal, 2));
      if(ObjectFind(0, PREF+"LblCalcLot") >= 0)
         ObjectSetString(0, PREF+"LblCalcLot", OBJPROP_TEXT, "");
   }
}

void CreateCalcLotLabel()
{
   string name = PREF + "LblCalcLot";
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10 + PANEL_W / 2);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, UI_Y + 45);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 11);
   ObjectSetString(0, name, OBJPROP_TEXT, IsAutoLot ? "Lot setup: (draw line)" : "");
}

double CalcRiskUSD(ENUM_ORDER_TYPE orderType, double entry, double sl, double lot, int layers)
{
   if(lot <= 0.0 || layers < 1 || entry <= 0.0 || sl <= 0.0 || MathAbs(entry - sl) <= 0.0)
      return 0.0;

   double profit = 0.0;
   if(OrderCalcProfit(orderType, _Symbol, 1.0, entry, sl, profit))
      return MathAbs(profit) * lot * (double)layers;

   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0 || tickVal <= 0.0) return 0.0;
   return MathAbs(entry - sl) * lot * (double)layers * tickVal / tickSize;
}

void UpdateLotRiskDisplay(double bEntry, double bSL, double sEntry, double sSL)
{
   double buyRiskUSD  = CalcSetupRiskUSD(ORDER_TYPE_BUY, bEntry, bSL);
   double sellRiskUSD = CalcSetupRiskUSD(ORDER_TYPE_SELL, sEntry, sSL);

   if(ObjectFind(0, PREF+"Buy_Risk") >= 0)
      ObjectSetString(0, PREF+"Buy_Risk", OBJPROP_TEXT, DoubleToString(buyRiskUSD, 2));
   if(ObjectFind(0, PREF+"Sell_Risk") >= 0)
      ObjectSetString(0, PREF+"Sell_Risk", OBJPROP_TEXT, DoubleToString(sellRiskUSD, 2));

   string name = PREF + "LblCalcLot";
   if(ObjectFind(0, name) < 0)
      CreateCalcLotLabel();

   string calcText = "";
   if(IsAutoLot)
      calcText = "Lot setup: B " + FormatLayerLots(ORDER_TYPE_BUY, bEntry, bSL)
               + " / S " + FormatLayerLots(ORDER_TYPE_SELL, sEntry, sSL);

   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10 + PANEL_W / 2);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, IsDashboardVisible ? UI_Y + 45 : UI_OFFSCREEN);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 11);
   ObjectSetString(0, name, OBJPROP_TEXT, calcText);
}

bool PriceInDrawArea(double price)
{
   if(!DrawingLinesActive()) return false;
   double pFloor = ObjectGetDouble(0, PREF+"Line_Floor", OBJPROP_PRICE);
   double pCeiling = ObjectGetDouble(0, PREF+"Line_Ceiling", OBJPROP_PRICE);
   double lo = MathMin(pFloor, pCeiling);
   double hi = MathMax(pFloor, pCeiling);
   return (price >= lo && price <= hi);
}

void PlaceBuyOrder() {
   if(!DrawingLinesActive()) {
      Print("Buy Order: drawing line belum aktif. Klik Draw Line dulu.");
      return;
   }
   string blockReason = "";
   int layers = GetLayerCount();
   if(IsTradingBlocked(blockReason, layers)) {
      Print("Buy Order diblok: ", blockReason);
      return;
   }
   RefreshTp2HitTimes();
   if(IsTp2CooldownActive(true, blockReason)) {
      Print("Buy Order diblok: ", blockReason);
      return;
   }
   CalculateAndDrawAll();

   double proximal = GetInputValue("Buy_Entry");
   double sl = GetInputValue("Buy_Stoploss");
   double entry = NormalizeDouble(proximal + GetSpreadPrice() * 2.0, _Digits);
   if(proximal == 0.0) {
      Print("Buy Order: Entry masih 0. Klik Draw Line / geser Floor-Ceiling dulu.");
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool inArea = PriceInDrawArea(ask);
   bool useStop = inArea;

   if(entry == ask) {
      Print("Buy Order: entry sama dengan Ask, tidak bisa pending. Pakai Buy Now.");
      return;
   }
   if(useStop && entry < ask) {
      Print("Buy Order: di dalam area tapi entry < Ask, memakai Limit.");
      useStop = false;
   }
   if(!useStop && entry > ask) {
      Print("Buy Order: di luar area tapi entry > Ask, memakai Stop.");
      useStop = true;
   }

   sl = NormalizeDouble(sl, _Digits);
   string kind = useStop ? "Stop" : "Limit";
   Print("Buy ", kind, " setup: ", layers, " order split ",
         DoubleToString(InpSplitLot1, 0), "/", DoubleToString(InpSplitLot2, 0), "/", DoubleToString(InpSplitLot3, 0),
         " lots ", FormatLayerLots(ORDER_TYPE_BUY, entry, sl),
         IsAutoLot ? " (risk per setup)" : " (manual)",
         inArea ? " [in area]" : " [out area]");

   int placed = 0;
   for(int i = 0; i < layers; i++) {
      double lot = GetLayerLot(ORDER_TYPE_BUY, entry, sl, i);
      if(lot <= 0.0) {
         Print("Buy ", kind, " layer ", i + 1, " lot 0, dilewati.");
         continue;
      }
      double tp = NormalizeDouble(BuyTPByLayer(i, entry, sl), _Digits);
      string cmt = "Buy " + kind + " L" + IntegerToString(i + 1);
      bool ok = useStop
         ? trade.BuyStop(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt)
         : trade.BuyLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
      if(!ok)
         Print("Buy ", kind, " layer ", i + 1, " gagal. Error: ", GetLastError());
      else
         placed++;
   }
   if(placed > 0)
      Print("Buy ", kind, " terpasang: ", placed, " order. Posisi dibuka hari ini: ",
            CountPositionsOpenedToday(), "/", InpMaxTradesPerDay);
}

void PlaceSellOrder() {
   if(!DrawingLinesActive()) {
      Print("Sell Order: drawing line belum aktif. Klik Draw Line dulu.");
      return;
   }
   string blockReason = "";
   int layers = GetLayerCount();
   if(IsTradingBlocked(blockReason, layers)) {
      Print("Sell Order diblok: ", blockReason);
      return;
   }
   RefreshTp2HitTimes();
   if(IsTp2CooldownActive(false, blockReason)) {
      Print("Sell Order diblok: ", blockReason);
      return;
   }
   CalculateAndDrawAll();

   double proximal = GetInputValue("Sell_Entry");
   double sl = GetInputValue("Sell_Stoploss");
   double entry = NormalizeDouble(proximal - GetSpreadPrice() * 2.0, _Digits);
   if(proximal == 0.0) {
      Print("Sell Order: Entry masih 0. Klik Draw Line / geser Floor-Ceiling dulu.");
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool inArea = PriceInDrawArea(bid);
   bool useStop = inArea;

   if(entry == bid) {
      Print("Sell Order: entry sama dengan Bid, tidak bisa pending. Pakai Sell Now.");
      return;
   }
   if(useStop && entry > bid) {
      Print("Sell Order: di dalam area tapi entry > Bid, memakai Limit.");
      useStop = false;
   }
   if(!useStop && entry < bid) {
      Print("Sell Order: di luar area tapi entry < Bid, memakai Stop.");
      useStop = true;
   }

   sl = NormalizeDouble(sl, _Digits);
   string kind = useStop ? "Stop" : "Limit";
   Print("Sell ", kind, " setup: ", layers, " order split ",
         DoubleToString(InpSplitLot1, 0), "/", DoubleToString(InpSplitLot2, 0), "/", DoubleToString(InpSplitLot3, 0),
         " lots ", FormatLayerLots(ORDER_TYPE_SELL, entry, sl),
         IsAutoLot ? " (risk per setup)" : " (manual)",
         inArea ? " [in area]" : " [out area]");

   int placed = 0;
   for(int i = 0; i < layers; i++) {
      double lot = GetLayerLot(ORDER_TYPE_SELL, entry, sl, i);
      if(lot <= 0.0) {
         Print("Sell ", kind, " layer ", i + 1, " lot 0, dilewati.");
         continue;
      }
      double tp = NormalizeDouble(SellTPByLayer(i, entry, sl), _Digits);
      string cmt = "Sell " + kind + " L" + IntegerToString(i + 1);
      bool ok = useStop
         ? trade.SellStop(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt)
         : trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
      if(!ok)
         Print("Sell ", kind, " layer ", i + 1, " gagal. Error: ", GetLastError());
      else
         placed++;
   }
   if(placed > 0)
      Print("Sell ", kind, " terpasang: ", placed, " order. Posisi dibuka hari ini: ",
            CountPositionsOpenedToday(), "/", InpMaxTradesPerDay);
}

bool DrawingLinesActive()
{
   return (ObjectFind(0, PREF+"Line_Floor") >= 0 && ObjectFind(0, PREF+"Line_Ceiling") >= 0);
}

double GetDrawnLinePrice(string name)
{
   if(ObjectFind(0, name) < 0) return 0.0;
   return ObjectGetDouble(0, name, OBJPROP_PRICE);
}

void PlaceBuyNow() {
   if(!DrawingLinesActive()) {
      Print("Buy Now: drawing line belum aktif. Klik Draw Line dulu.");
      return;
   }
   string blockReason = "";
   if(IsTradingBlocked(blockReason, 1)) {
      Print("Buy Now diblok: ", blockReason);
      return;
   }

   CalculateAndDrawAll();

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = GetInputValue("Buy_Stoploss");
   double tp = GetDrawnLinePrice(PREF+"Calc_B_TP2");

   if(sl <= 0.0 || sl >= entry || tp <= entry) {
      Print("Buy Now: butuh SL < Entry < TP2. SL=", sl, " Entry=", entry, " TP=", tp);
      return;
   }

   double lot = GetResolvedLot(ORDER_TYPE_BUY, entry, sl);
   if(lot <= 0) {
      Print("Lot size is zero or negative, cannot execute Buy trade.");
      return;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   if(trade.Buy(lot, _Symbol, 0, sl, tp, "BuyNow"))
      Print("Buy Now: Lot=", lot, ", SL=", sl, ", TP2=", tp,
            " | posisi hari ini ", CountPositionsOpenedToday(), "/", InpMaxTradesPerDay);
   else
      Print("Failed to execute Buy order. Error: ", GetLastError());
}

void PlaceSellNow() {
   if(!DrawingLinesActive()) {
      Print("Sell Now: drawing line belum aktif. Klik Draw Line dulu.");
      return;
   }
   string blockReason = "";
   if(IsTradingBlocked(blockReason, 1)) {
      Print("Sell Now diblok: ", blockReason);
      return;
   }

   CalculateAndDrawAll();

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = GetInputValue("Sell_Stoploss");
   double tp = GetDrawnLinePrice(PREF+"Calc_S_TP2");

   if(sl <= entry || tp >= entry || tp <= 0.0) {
      Print("Sell Now: butuh TP2 < Entry < SL. SL=", sl, " Entry=", entry, " TP=", tp);
      return;
   }

   double lot = GetResolvedLot(ORDER_TYPE_SELL, entry, sl);
   if(lot <= 0) {
      Print("Lot size is zero or negative, cannot execute Sell trade.");
      return;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   if(trade.Sell(lot, _Symbol, 0, sl, tp, "SellNow"))
      Print("Sell Now: Lot=", lot, ", SL=", sl, ", TP2=", tp,
            " | posisi hari ini ", CountPositionsOpenedToday(), "/", InpMaxTradesPerDay);
   else
      Print("Failed to execute Sell order. Error: ", GetLastError());
}

// --- Layout ---
void CalculateAndDrawAll() {
   if(ObjectFind(0, PREF+"Line_Floor") < 0 || ObjectFind(0, PREF+"Line_Ceiling") < 0) return;
   double pFloor = ObjectGetDouble(0, PREF+"Line_Floor", OBJPROP_PRICE); 
   double pCeiling = ObjectGetDouble(0, PREF+"Line_Ceiling", OBJPROP_PRICE);
   double range = MathAbs(pCeiling - pFloor);
   double buffer = 0.4 * range;
   double spreadBuf = GetSpreadPrice() * 2.0;
   double bEntry = pCeiling;
   double bEntry1 = bEntry + spreadBuf;
   double bSL = pFloor - buffer;
   double bRisk = bEntry1 - bSL;
   double sEntry = pFloor;
   double sEntry1 = sEntry - spreadBuf;
   double sSL = pCeiling + buffer;
   double sRisk = sSL - sEntry1;
   
   ObjectsDeleteAll(0, PREF+"Calc_");
   UpdateLine(PREF+"Calc_B_SL", bSL, clrBlue);
   UpdateLine(PREF+"Calc_S_SL", sSL, clrRed); 

   UpdateLine(PREF+"Calc_B_TP1", bEntry1 + bRisk, clrGreen);
   UpdateLine(PREF+"Calc_B_TP2", bEntry1 + (2 * bRisk), clrGreen);
   UpdateLine(PREF+"Calc_B_TP3", bEntry1 + (3 * bRisk), clrGreen);
   UpdateLine(PREF+"Calc_B_TP4", bEntry1 + (4 * bRisk), clrGreen);
   UpdateLine(PREF+"Calc_B_TP5", bEntry1 + (5 * bRisk), clrGreen);
   UpdateLine(PREF+"Calc_S_TP1", sEntry1 - sRisk, clrGreen);
   UpdateLine(PREF+"Calc_S_TP2", sEntry1 - (2 * sRisk), clrGreen);
   UpdateLine(PREF+"Calc_S_TP3", sEntry1 - (3 * sRisk), clrGreen);
   UpdateLine(PREF+"Calc_S_TP4", sEntry1 - (4 * sRisk), clrGreen);
   UpdateLine(PREF+"Calc_S_TP5", sEntry1 - (5 * sRisk), clrGreen);
   
   UpdateInput("Buy_Floor", pFloor); UpdateInput("Buy_Entry", bEntry); UpdateInput("Buy_Stoploss", bSL); 
   UpdateInput("Buy_TP1", bEntry1 + bRisk);
   UpdateInput("Buy_TP2", bEntry1 + (2 * bRisk));
   UpdateInput("Buy_TP3", bEntry1 + (3 * bRisk));
   UpdateInput("Sell_Ceiling", pCeiling); UpdateInput("Sell_Entry", sEntry); UpdateInput("Sell_Stoploss", sSL); 
   UpdateInput("Sell_TP1", sEntry1 - sRisk);
   UpdateInput("Sell_TP2", sEntry1 - (2 * sRisk));
   UpdateInput("Sell_TP3", sEntry1 - (3 * sRisk));

   // Kalkulasi ukuran pips dinamis
   double pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
   if(pipSize == 0) pipSize = 0.1;

   // 2. Hitung Nilai Pips
   double buyPips = 0.0;
   if(pFloor > 0 && bEntry > 0) buyPips = MathAbs(pFloor - bEntry) / pipSize;

   double sellPips = 0.0;
   if(pCeiling > 0 && sEntry > 0) sellPips = MathAbs(pCeiling - sEntry) / pipSize;
   
   UpdateInput("Buy_Area", buyPips);
   UpdateInput("Sell_Area", sellPips);

   UpdateLotRiskDisplay(bEntry1, bSL, sEntry1, sSL);
}

void CreateDashboard() {
   CreateObject("HdrPanel", OBJ_RECTANGLE_LABEL, 0, 10, HEADER_Y, PANEL_W, 40, clrBlack);
   ObjectSetInteger(0, PREF+"HdrPanel", OBJPROP_BGCOLOR, clrDarkSlateGray);
   CreateButton("Hide", 15, HEADER_Y + 7, 90, 25, "Hide [H]", clrGray, clrWhite);
   CreateButton("HideQuote", 110, HEADER_Y + 7, 115, 25, "Hide Q [U]", clrGray, clrWhite);
   CreateLabel("Title", (PANEL_W / 2) + 20, HEADER_Y + 2, "SND Quick Retest", clrWhite);
   CreateObject("Panel", OBJ_RECTANGLE_LABEL, 0, 10, UI_Y, PANEL_W, PANEL_H, clrDarkSlateGray);
   
   CreateLabel("LblLayers", 20, UI_Y+12, "Layers", clrOrange); CreateEdit("InpLayers", 130, UI_Y+18, 100, 25, "2");
   CreateButton("BtnLotMode", 260, UI_Y+12, 100, 25, "Lot", clrDarkSlateGray, clrOrange);
   CreateEdit("InpLot", 370, UI_Y+18, 100, 25, "0.12");
   CreateCalcLotLabel();
   ApplyLotModeUI();
   
   CreateButton("BtnDraw", 20, UI_Y+80, 230, 32, "Draw Line [D]", clrPurple, clrWhite);
   CreateButton("BtnScanSD", 270, UI_Y+80, 230, 32, "Scan S&D [A]", clrDarkGreen, clrWhite);
   
   string bL[]={"Floor","Entry","Stoploss","TP1","TP2","TP3","Area","Risk"}; 
   string sL[]={"Ceiling","Entry","Stoploss","TP1","TP2","TP3","Area","Risk"};
   for(int i=0; i<8; i++) {
      CreateLabel("LB_"+bL[i], 20, UI_Y+130+(i*30), bL[i], clrOrange); CreateEdit("Buy_"+bL[i], 130, UI_Y+134+(i*30), 110, 25, "0.00");
      CreateLabel("LS_"+sL[i], 270, UI_Y+130+(i*30), sL[i], clrOrange); CreateEdit("Sell_"+sL[i], 370, UI_Y+134+(i*30), 110, 25, "0.00");
   }
   CreateButton("BtnBuyL", 20, UI_Y + 400, 230, 32, "Buy Order [B]", clrBlue, clrWhite);
   CreateButton("BtnSellL", 270, UI_Y + 400, 230, 32, "Sell Order [S]", clrOrange, clrWhite);
   CreateButton("DelBuy", 20, UI_Y + 440, 230, 32, "Del Buy [Q]", clrBlue, clrWhite);
   CreateButton("DelSell", 270, UI_Y + 440, 230, 32, "Del Sell [W]", clrBrown, clrWhite);
   CreateButton("ClosePos", 20, UI_Y + 480, PANEL_W-40, 30, "Close Positions [P]", clrDarkRed, clrWhite);
   CreateButton("CloseOrd", 20, UI_Y + 520, PANEL_W-40, 30, "Close All Orders [O]", clrMaroon, clrWhite);
   CreateButton("BuyNow", 20, UI_Y + 560, 230, 32, "Buy Now", clrDodgerBlue, clrWhite);
   CreateButton("SellNow", 270, UI_Y + 560, 230, 32, "Sell Now", clrOrangeRed, clrWhite);
   CreateButton("BtnAutoRBR", 20, UI_Y + 600, 230, 32, "RBR: OFF [1]", clrGray, clrBlack);
   CreateButton("BtnAutoDBD", 270, UI_Y + 600, 230, 32, "DBD: OFF [2]", clrGray, clrBlack);
   CreateButton("BtnAutoDBR", 20, UI_Y + 640, 230, 32, "DBR: OFF [3]", clrGray, clrBlack);
   CreateButton("BtnAutoRBD", 270, UI_Y + 640, 230, 32, "RBD: OFF [4]", clrGray, clrBlack);
   CreateButton("Reset", 20, UI_Y + 680, PANEL_W-40, 32, "Reset [R]", clrGray, clrBlack);
   ApplyAllAutoUI();
   ObjectSetInteger(0, PREF+"BtnLotMode", OBJPROP_ZORDER, 10);

   // Tambahkan ini di setiap fungsi pembuatan tombol/label dashboard Anda
   ObjectSetInteger(0, "BtnBuyL", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "BtnSellL", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "DelBuy", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "DelSell", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "ClosePos", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "CloseOrd", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "BuyNow", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "SellNow", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, PREF+"BtnAutoRBR", OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, PREF+"BtnAutoDBD", OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, PREF+"BtnAutoDBR", OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, PREF+"BtnAutoRBD", OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, PREF+"Reset", OBJPROP_ZORDER, 10);


}

void CreateDrawingLines() { 
   double p=SymbolInfoDouble(_Symbol, SYMBOL_BID); 
   ObjectCreate(0, PREF+"Line_Floor", OBJ_HLINE, 0, 0, p-200*_Point); 
   ObjectSetInteger(0, PREF+"Line_Floor", OBJPROP_SELECTABLE, true); 
   ObjectSetInteger(0, PREF+"Line_Floor", OBJPROP_SELECTED, true);
   
   ObjectCreate(0, PREF+"Line_Ceiling", OBJ_HLINE, 0, 0, p+200*_Point); 
   ObjectSetInteger(0, PREF+"Line_Ceiling", OBJPROP_SELECTABLE, true); 
   ObjectSetInteger(0, PREF+"Line_Ceiling", OBJPROP_SELECTED, true);
}

double GetInputValue(string name) { return StringToDouble(ObjectGetString(0, PREF+name, OBJPROP_TEXT)); }
void UpdateLine(string name, double price, color clr) { if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, price); ObjectSetDouble(0, name, OBJPROP_PRICE, price); ObjectSetInteger(0, name, OBJPROP_COLOR, clr); ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT); }
void UpdateInput(string name, double price) { ObjectSetString(0, PREF+name, OBJPROP_TEXT, DoubleToString(price, _Digits)); }
void CreateObject(string name, ENUM_OBJECT type, int win, int x, int y, int w, int h, color clr) { ObjectCreate(0, PREF+name, type, win, 0, 0); ObjectSetInteger(0, PREF+name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, PREF+name, OBJPROP_YDISTANCE, y); ObjectSetInteger(0, PREF+name, OBJPROP_XSIZE, w); ObjectSetInteger(0, PREF+name, OBJPROP_YSIZE, h); }
void CreateLabel(string name, int x, int y, string text, color clr) { CreateObject(name, OBJ_LABEL, 0, x, y, 0, 0, clr); ObjectSetString(0, PREF+name, OBJPROP_TEXT, text); }
void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color txtClr) { CreateObject(name, OBJ_BUTTON, 0, x, y, w, h, bg); ObjectSetString(0, PREF+name, OBJPROP_TEXT, text); ObjectSetInteger(0, PREF+name, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, PREF+name, OBJPROP_COLOR, txtClr); ObjectSetInteger(0, PREF+name, OBJPROP_FONTSIZE, 9); ObjectSetString(0, PREF+name, OBJPROP_FONT, "Arial"); }
void CreateEdit(string name, int x, int y, int w, int h, string val) { CreateObject(name, OBJ_EDIT, 0, x, y, w, h, clrWhite); ObjectSetString(0, PREF+name, OBJPROP_TEXT, val); }
void DelPO(ENUM_ORDER_TYPE type) { for(int i=OrdersTotal()-1; i>=0; i--) { ulong t=OrderGetTicket(i); if(OrderSelect(t) && OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_TYPE)==type) trade.OrderDelete(t); } }
void CloseAllPositions() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      trade.PositionClose(t);
   }
}
void CloseAllOrders() {
   for(int i=OrdersTotal()-1; i>=0; i--) {
      ulong t=OrderGetTicket(i);
      if(!OrderSelect(t)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;
      trade.OrderDelete(t);
   }
}

int GetInitialY(string name) {
   if(name == PREF+"HdrPanel") return HEADER_Y;
   if(name == PREF+"Hide") return HEADER_Y + 7;
   if(name == PREF+"HideQuote") return HEADER_Y + 7;
   if(name == PREF+"Title") return HEADER_Y + 2;
   if(name == PREF+"Live_Clock") return 50;
   if(name == PREF+"HardStop") return 25;
   if(name == PREF+"Skor1") return 75;
   if(name == PREF+"Skor2") return 100;
   if(name == PREF+"Quote1") return 125;
   if(name == PREF+"Quote2") return 150;
   if(name == PREF+"Panel") return UI_Y;
   if(name == PREF+"LblLayers" || name == PREF+"InpLayers" || name == PREF+"BtnLotMode" || name == PREF+"InpLot") return UI_Y + 12;
   if(name == PREF+"LblCalcLot") return UI_Y + 45;
   if(name == PREF+"BtnDraw" || name == PREF+"BtnScanSD") return UI_Y + 80;
   
   string bL[]={"Floor","Entry","Stoploss","TP1","TP2","TP3","Area","Risk"};
   string sL[]={"Ceiling","Entry","Stoploss","TP1","TP2","TP3","Area","Risk"};
   for(int i=0; i<8; i++) {
      if(name == PREF+"LB_"+bL[i] || name == PREF+"Buy_"+bL[i]) return UI_Y + 130 + (i*30);
      if(name == PREF+"LS_"+sL[i] || name == PREF+"Sell_"+sL[i]) return UI_Y + 130 + (i*30);
   }
   
   if(name == PREF+"BtnBuyL" || name == PREF+"BtnSellL") return UI_Y + 400;
   if(name == PREF+"DelBuy" || name == PREF+"DelSell") return UI_Y + 440;
   if(name == PREF+"ClosePos") return UI_Y + 480;
   if(name == PREF+"CloseOrd") return UI_Y + 520;
   if(name == PREF+"BuyNow" || name == PREF+"SellNow") return UI_Y + 560;
   if(name == PREF+"BtnAutoRBR" || name == PREF+"BtnAutoDBD") return UI_Y + 600;
   if(name == PREF+"BtnAutoDBR" || name == PREF+"BtnAutoRBD") return UI_Y + 640;
   if(name == PREF+"Reset") return UI_Y + 680;
   return UI_Y;
}