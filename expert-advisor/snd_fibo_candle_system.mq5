//+------------------------------------------------------------------+
//|                                             SND_Fibo_Candle_System.mq5|
//|                                  Copyright 2026, User            |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh> 

//--- Input Parameters
input double InpBasingRatio    = 0.618; // Rasio maksimal body candle untuk Base
input double InpImpulsiveRatio = 0.55; // Rasio minimal body candle untuk Leg In/Out
input int    InpMaxBase     = 5;    // Maksimal candle base berurutan
input bool   InpShowRBR     = true;  // Tampilkan Rally Base Rally
input bool   InpShowDBD     = true;  // Tampilkan Drop Base Drop
input bool   InpShowDBR     = false;  // Tampilkan Drop Base Rally
input bool   InpShowRBD     = false;  // Tampilkan Rally Base Drop
input int InpMaxZones = 10; // Maksimal zona yang ditampilkan

input group "--- FIBO CANDLE ---"
input int    InpCloseCandle     = 1;      // Close candle (1=terakhir, 2=sebelumnya)
input double InpFiboTarget      = -27.2;  // Target Fibo (lawannya 1.272)
input double InpFiboLevel1      = 23.6;   // Level Fibo 1
input double InpFiboLevel2      = 38.2;   // Level Fibo 2
input double InpFiboLevel3      = 50.0;   // Level Fibo 3
input double InpFiboLevel4      = 61.8;   // Level Fibo 4
input double InpFiboLevel5      = 78.6;   // Level Fibo 5
input color  InpFiboColor       = clrDodgerBlue;
input int    InpFiboWidth       = 2;
input bool   InpFiboRayRight    = true;   // Ray ke kanan
input bool   InpFiboCutLoss     = true;   // Cut loss: close body vs garis 78.6
input bool   InpFiboCutProfit   = true;   // Cut profit: pending 78.6 kebuka, tutup saat melewati 50

input group "--- ZIGZAG SEGMENT ---"
input bool   InpLoadZigZagSeg   = true;              // Auto-load indikator ZigZag Segment
input string InpZigZagPath      = "zigzag_segment";  // Nama file indikator (folder Indicators)

#define ZZSEG_PREFIX "ZZSEG_"

// Struktur untuk menyimpan data berita yang sudah disaring
struct USDNewsData {
   datetime time;
   string   name;
};

USDNewsData listNews[3]; // Maksimal menampung 3 berita terdekat

enum ENUM_LOT_MODE
{
   LOT_MANUAL    = 0, // Lot manual
   LOT_AUTO_RISK = 1  // Auto lot dari risk %
};

input group "--- RISK & TRANSMISSION ---"
input ENUM_LOT_MODE InpLotMode     = LOT_AUTO_RISK; // Mode lot
input double        InpRiskPercent = 1.0;        // Risk % auto (default 1, max 1%)
input ulong InpMagicNumber = 1515; // Magic Number (Harus beda tiap chart)


CTrade trade;
// Di bagian atas (ubah variabel global menjadi tanpa nilai instan dahulu)
string PREF;
string ZONE_PREF;
string FIBO_PREF;

bool IsDashboardVisible = true;
bool IsQuoteVisible = true;
bool IsSDScanning = false;
bool IsAutoLot = true;
double g_lastManualLot = 0.01;
double g_lastRiskPct = 1.0;
int UI_Y = 100;      
int HEADER_Y = 50;   
int PANEL_W = 500;   
int PANEL_H = 790;   
int UI_OFFSCREEN = -2000;

bool     g_fiboActive = false;
bool     g_pickFiboCandle = false;
bool     g_pickZzSeg = false;
int      g_zzSegHandle = INVALID_HANDLE;
bool     g_fiboBullish = true;
double   g_fiboHigh = 0.0;
double   g_fiboLow  = 0.0;
datetime g_fiboTime = 0;
bool     g_fiboCutProfitArmed = false;
datetime g_fiboCutProfitArmBar = 0;
bool     g_fiboLvOn[6];

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
void PlaceBuyLimit();
void PlaceSellLimit();
void PlaceBuyNow();
void PlaceSellNow();
void GetHighImpactUSDNews();
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
double CalcLotPerLayer(ENUM_ORDER_TYPE orderType, double entry, double sl, int layerCount, double riskPct);
double GetResolvedLot(ENUM_ORDER_TYPE orderType, double entry, double sl);
void ScanFiboCandle(const int shiftParam=-1);
void ScanFiboFromZzSegment(const string zzSegName);
void SetupFiboObjectLevels(const string fiboName);
void RemoveZigZagSegmentFromChart();
void LoadZigZagSegmentIndicator();
bool ChartHasZigZagSegment();
void CleanupZzSegFiboObjects();
void ApplyZzSegPickStyle(const bool pickOn);
void SetPickFiboMode(const bool on);
void SetPickZzSegMode(const bool on);
void PickFiboAtChart(const int x, const int y);
void PickZzSegAtChart(const int x, const int y);
bool FindZzSegmentAtClick(const int x, const int y, string &outSegName);
void ClearFiboCandle();
void PlaceFiboBuyLimit(const int levelIdx);
void PlaceFiboSellLimit(const int levelIdx);
void PlaceFiboBuyAll();
void PlaceFiboSellAll();
void PlaceFiboDirLimit(const int kind);
void CreateFiboLevelToggles();
void ApplyFiboLevelToggleStyle(const int lv);
bool IsFiboLevelSelected(const int lv);
void ToggleFiboLevel(const int lv);
double FiboRatio(const double v);
double FiboOppTarget();
double FiboPriceFromLow(const double levelInput);
double FiboChartPrice(const double levelInput);
double GetFiboLevelInput(const int levelIdx);
void CreateFiboTradeButton(const string name, const datetime t, const double price, const string text, const color clr);
void SyncFiboFromObject();
void UpdateFiboTradeButtons();
void ApplyFiboObjectStyle(const string fiboName);
void OnFiboObjectMoved(const string fiboName);
void CreateFiboAnchorLines();
void SyncFiboAnchorLines();
void UpdateFiboObjectFromGlobals();
void OnFiboAnchorDragged();
void PlaceLimitOrder(const bool isBuy, const double entry, const double sl, const double tp, const string comment, const double lotMult=1.0);
void CheckFiboCutLoss();
void CheckFiboCutProfit();
bool FiboPriceTouchesLevel(const double level);
bool FiboCutProfitLevelReached();
void CutFiboTrades(const bool isBuy);
bool HasFiboPositionSide(const bool isBuy);
bool HasFibo786Position();
bool Fibo786FilledOnLastBar();
bool IsFiboOnChart();
void EnsureFiboScanned();
void DeleteFiboPending(const bool isBuy);

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() 
{ 
   // Membuat nama objek unik, contoh hasil: "SND_55555_"
   PREF = "SNDFC_" + IntegerToString(InpMagicNumber) + "_";
   ZONE_PREF = "SNDFC_Z_" + IntegerToString(InpMagicNumber) + "_";
   FIBO_PREF = PREF + "FB_";

   IsAutoLot = (InpLotMode == LOT_AUTO_RISK);
   g_lastRiskPct = (InpRiskPercent > 0.0) ? InpRiskPercent : 1.0;
   
   // Mengatur agar setiap kali EA ini mengirim order, Magic Number langsung terpasang otomatis
   trade.SetExpertMagicNumber(InpMagicNumber);
   ChartSetInteger(0, CHART_FOREGROUND, false);
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrBlack);
   for(int lv = 1; lv <= 5; lv++)
      g_fiboLvOn[lv] = true;

   CreateDashboard(); 

   if(IsFiboOnChart())
   {
      SyncFiboFromObject();
      CreateFiboAnchorLines();
      UpdateFiboTradeButtons();
   }

   if(InpLoadZigZagSeg)
      LoadZigZagSegmentIndicator();

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
   ObjectsDeleteAll(0, PREF); 
   ObjectsDeleteAll(0, ZONE_PREF); 
   RemoveZigZagSegmentFromChart();
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
}

void OnTick() { 
   UpdateLiveClock();
   ApplyQuoteVisibility();
   CheckFiboCutProfit();

   static datetime lastBarTime = 0;
   datetime curBarTime = iTime(_Symbol, _Period, 0);
   if(curBarTime != lastBarTime) {
      lastBarTime = curBarTime;
      CheckFiboCutLoss();
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

//+------------------------------------------------------------------+
//| Event Handling                                                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_DRAG) { 
      if(sparam == PREF+"Line_Floor" || sparam == PREF+"Line_Ceiling")
         CalculateAndDrawAll();
      else if(sparam == FIBO_PREF + "AnchorHigh" || sparam == FIBO_PREF + "AnchorLow")
         OnFiboAnchorDragged();
      else if(StringFind(sparam, FIBO_PREF + "OBJ") == 0)
         OnFiboObjectMoved(sparam);
      ChartRedraw(); 
   }
   if(id == CHARTEVENT_OBJECT_CHANGE)
   {
      if(sparam == FIBO_PREF + "AnchorHigh" || sparam == FIBO_PREF + "AnchorLow")
         OnFiboAnchorDragged();
      else if(StringFind(sparam, FIBO_PREF + "OBJ") == 0)
         OnFiboObjectMoved(sparam);
      ChartRedraw();
   }
   
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(g_pickZzSeg && StringFind(sparam, ZZSEG_PREFIX) == 0)
      {
         ScanFiboFromZzSegment(sparam);
         SetPickZzSegMode(false);
         ChartRedraw();
      }
      else if(sparam == PREF+"Hide") { 
         IsDashboardVisible = !IsDashboardVisible; 
         ObjectSetString(0, PREF+"Hide", OBJPROP_TEXT, IsDashboardVisible ? "Hide" : "Show");
         for(int i=0; i<ObjectsTotal(0); i++) { 
            string name = ObjectName(0, i); 
            if(StringFind(name, PREF) == 0 &&
               StringFind(name, FIBO_PREF) != 0 &&
               name != PREF+"Hide" &&
               name != PREF+"HideQuote" &&
               name != PREF+"Live_Clock" &&
               name != PREF+"Skor1" &&
               name != PREF+"Skor2" &&
               name != PREF+"Quote1" &&
               name != PREF+"Quote2") { 
               ObjectSetInteger(0, name, OBJPROP_YDISTANCE, IsDashboardVisible ? GetInitialY(name) : UI_OFFSCREEN); 
            } 
         }
         ObjectSetInteger(0, PREF+"Hide", OBJPROP_YDISTANCE, HEADER_Y + 7); 
         ObjectSetInteger(0, PREF+"HideQuote", OBJPROP_YDISTANCE, HEADER_Y + 7);
         ObjectSetInteger(0, PREF+"Hide", OBJPROP_STATE, false);
         ChartRedraw();
      }
      else if(sparam == PREF+"HideQuote") {
         IsQuoteVisible = !IsQuoteVisible;
         ObjectSetString(0, PREF+"HideQuote", OBJPROP_TEXT, IsQuoteVisible ? "Hide Q" : "Show Q");
         ApplyQuoteVisibility();
         ObjectSetInteger(0, PREF+"HideQuote", OBJPROP_STATE, false);
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
      else if(sparam == PREF+"BtnDraw") { CreateDrawingLines(); CalculateAndDrawAll(); ObjectSetInteger(0, PREF+"BtnDraw", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnScanFibo") {
         SetPickFiboMode(false);
         SetPickZzSegMode(false);
         ScanFiboCandle();
         ObjectSetInteger(0, PREF+"BtnScanFibo", OBJPROP_STATE, false);
      }
      else if(sparam == PREF+"BtnPickFibo") {
         SetPickZzSegMode(false);
         SetPickFiboMode(!g_pickFiboCandle);
         ObjectSetInteger(0, PREF+"BtnPickFibo", OBJPROP_STATE, false);
         ChartRedraw();
      }
      else if(sparam == PREF+"BtnPickZzSeg") {
         SetPickFiboMode(false);
         SetPickZzSegMode(!g_pickZzSeg);
         ObjectSetInteger(0, PREF+"BtnPickZzSeg", OBJPROP_STATE, false);
         ChartRedraw();
      }
      else if(sparam == PREF+"BtnScanSD") { 
         IsSDScanning = !IsSDScanning;
         if(IsSDScanning) { ScanSD(); ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "S&D: ON"); ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrGreen); } 
         else { ObjectsDeleteAll(0, ZONE_PREF); ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "Scan S&D"); ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrDarkGreen); }
         ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_STATE, false); 
      }
      else if(sparam == PREF+"BtnBuyL") { PlaceBuyLimit(); ObjectSetInteger(0, PREF+"BtnBuyL", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnSellL") { PlaceSellLimit(); ObjectSetInteger(0, PREF+"BtnSellL", OBJPROP_STATE, false); }
      else if(StringFind(sparam, PREF+"ChkFiboLv") == 0) {
         int lv = (int)StringToInteger(StringSubstr(sparam, StringLen(PREF+"ChkFiboLv")));
         ToggleFiboLevel(lv);
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      else if(sparam == PREF+"BtnBuyLFibo") { PlaceFiboBuyAll(); ObjectSetInteger(0, PREF+"BtnBuyLFibo", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnSellLFibo") { PlaceFiboSellAll(); ObjectSetInteger(0, PREF+"BtnSellLFibo", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnLim382") { PlaceFiboDirLimit(1); ObjectSetInteger(0, PREF+"BtnLim382", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnLim50")  { PlaceFiboDirLimit(3); ObjectSetInteger(0, PREF+"BtnLim50", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnLim618") { PlaceFiboDirLimit(2); ObjectSetInteger(0, PREF+"BtnLim618", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BuyNow") { PlaceBuyNow(); ObjectSetInteger(0, PREF+"BuyNow", OBJPROP_STATE, false); }
      else if(sparam == PREF+"SellNow") { PlaceSellNow(); ObjectSetInteger(0, PREF+"SellNow", OBJPROP_STATE, false); }
      else if(sparam == PREF+"DelBuy") { DelPO(ORDER_TYPE_BUY_LIMIT); ObjectSetInteger(0, PREF+"DelBuy", OBJPROP_STATE, false); }
      else if(sparam == PREF+"DelSell") { DelPO(ORDER_TYPE_SELL_LIMIT); ObjectSetInteger(0, PREF+"DelSell", OBJPROP_STATE, false); }
      else if(sparam == PREF+"ClosePos") { CloseAllPositions(); ObjectSetInteger(0, PREF+"ClosePos", OBJPROP_STATE, false); }
      else if(sparam == PREF+"CloseOrd") { CloseAllOrders(); ObjectSetInteger(0, PREF+"CloseOrd", OBJPROP_STATE, false); }
      else if(sparam == PREF+"GetNews") { GetHighImpactUSDNews(); ObjectSetInteger(0, PREF+"GetNews", OBJPROP_STATE, false); }
      else if(sparam == PREF+"Reset") { 
         ObjectsDeleteAll(0, PREF+"Line_"); ObjectsDeleteAll(0, PREF+"Calc_"); ObjectsDeleteAll(0, PREF+"Layer_"); ObjectsDeleteAll(0, ZONE_PREF);
         ClearFiboCandle();
         SetPickFiboMode(false);
         SetPickZzSegMode(false);
         IsSDScanning = false; 
         ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "Scan S&D"); ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrDarkGreen);
         if(IsAutoLot && ObjectFind(0, PREF+"LblCalcLot") >= 0)
            ObjectSetString(0, PREF+"LblCalcLot", OBJPROP_TEXT, "Lot/layer: (draw line)");
         ChartRedraw(); 
         ObjectSetInteger(0, PREF+"Reset", OBJPROP_STATE, false); 
      }
      else if(StringFind(sparam, FIBO_PREF + "BUY_") == 0) {
         int lvl = (int)StringToInteger(StringSubstr(sparam, StringLen(FIBO_PREF + "BUY_")));
         PlaceFiboBuyLimit(lvl);
         ObjectSetInteger(0, sparam, OBJPROP_SELECTED, false);
         ObjectSetInteger(0, sparam, OBJPROP_SELECTABLE, false);
         ChartRedraw();
         ObjectSetInteger(0, sparam, OBJPROP_SELECTABLE, true);
      }
      else if(StringFind(sparam, FIBO_PREF + "SELL_") == 0) {
         int lvl = (int)StringToInteger(StringSubstr(sparam, StringLen(FIBO_PREF + "SELL_")));
         PlaceFiboSellLimit(lvl);
         ObjectSetInteger(0, sparam, OBJPROP_SELECTED, false);
         ObjectSetInteger(0, sparam, OBJPROP_SELECTABLE, false);
         ChartRedraw();
         ObjectSetInteger(0, sparam, OBJPROP_SELECTABLE, true);
      }
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

   if(id == CHARTEVENT_CLICK && g_pickZzSeg)
   {
      PickZzSegAtChart((int)lparam, (int)dparam);
      return;
   }

   if(id == CHARTEVENT_CLICK && g_pickFiboCandle)
   {
      PickFiboAtChart((int)lparam, (int)dparam);
      return;
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


// --- FUNGSI SEARCH BERITA USD HIGH IMPACT (VERSI 100% UNIVERSAL & ANTI-ERROR) ---
void GetHighImpactUSDNews()
{
   // 1. Kosongkan data lama
   for(int k=0; k<3; k++) { listNews[k].time = 0; listNews[k].name = ""; }

   MqlCalendarValue values[];
   datetime fromTime = TimeCurrent();         
   datetime toTime   = fromTime + 24 * 3600;  // 24 jam ke depan

   // Ambil data kalender dari server
   int totalEvents = CalendarValueHistory(values, fromTime, toTime);
   if(totalEvents <= 0) return;

   int newsCount = 0;
   
   // 2. Loop data berita yang masuk
   for(int i = 0; i < totalEvents && newsCount < 3; i++)
   {
      MqlCalendarEvent event;
      
      // Ambil detail event berdasarkan event_id
      if(CalendarEventById(values[i].event_id, event))
      {
         // Trik Utama: Ambil data negara menggunakan fungsi terpisah untuk menghindari error properti struct
         MqlCalendarCountry country;
         if(CalendarCountryById(event.country_id, country))
         {
            // Cek apakah mata uangnya USD (country.currency) ATAU kode negaranya US (country.code)
            // Dan pastikan dampaknya adalah HIGH IMPACT
            if((country.code == "US" || country.currency == "USD") && event.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               listNews[newsCount].time = values[i].time;
               listNews[newsCount].name = event.name;
               newsCount++;
            }
         }
      }
   }

   for(int i = 0; i < 3; i++)
   {
      string labelName = PREF + "Lbl_News_Row_" + IntegerToString(i);
      string newsText  = "- No Upcoming High USD News -";

      if(listNews[i].time > 0)
      {
         string timeStr = TimeToString(listNews[i].time, TIME_MINUTES);
         newsText = timeStr + " | " + listNews[i].name;
         
         if(StringLen(newsText) > 38) newsText = StringSubstr(newsText, 0, 38) + "...";
      }
      else if(i > 0)
      {
         newsText = ""; // Kosongkan baris 2 & 3 jika tidak ada event berita lagi
      }

      // Cetak berurutan ke bawah (kelipatan 18 pixel dari koordinat Y=200)
      DrawNativeLabel(labelName, newsText, 20, 795 + (i * 18), clrRed);
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

            if(!shouldDraw) continue;

            // RBR: Close Leg Out di atas base | DBD: Close Leg Out di bawah base
            if(type == "RBR" && legOutClose <= baseHigh) continue;
            if(type == "DBD" && legOutClose >= baseLow) continue;

            // --- KUNCI LOGIKA BARU: MENGHITUNG JUMLAH SENTUHAN (RETEST) ---
            int touchCount = 0;
            bool isFullMitigated = false;

            // Lakukan ke belakang dari candle i-1 sampai candle terbaru (index 0)
            for(int k = i - 1; k >= 0; k--) {
               double candleHigh = iHigh(_Symbol, _Period, k);
               double candleLow  = iLow(_Symbol, _Period, k);

               if(legOutUp) { 
                  // Untuk Demand Zone (RBR/DBR):
                  // Jika Low menembus Base Low, artinya area jebol total (Full Mitigated)
                  if(candleLow < baseLow) { 
                     isFullMitigated = true; 
                     break; 
                  }
                  // Jika Low sempat masuk ke dalam area Base High, hitung sebagai sentuhan
                  if(candleLow <= baseHigh) { 
                     touchCount++; 
                  }
               } else { 
                  // Untuk Supply Zone (DBD/RBD):
                  // Jika High menembus Base High, artinya area jebol total (Full Mitigated)
                  if(candleHigh > baseHigh) { 
                     isFullMitigated = true; 
                     break; 
                  }
                  // Jika High sempat masuk ke dalam area Base Low, hitung sebagai sentuhan
                  if(candleHigh >= baseLow) { 
                     touchCount++; 
                  }
               }
            }
            
            // Jika area sudah tertembus total (Broken Zone), lewati dan jangan digambar
            if(isFullMitigated) continue; 
            
            // --- MENENTUKAN TEKS LABEL BERDASARKAN SENTUHAN ---
            string labelText = "  ● Fresh";
            if(touchCount > 0) {
               labelText = "  ● Tested " + IntegerToString(touchCount) + "x";
            }
            
            datetime startTime = iTime(_Symbol, _Period, i);
            datetime endTime = TimeCurrent() + (PeriodSeconds() * 100);
            
            // Gambar Kotak S&D
            string name = ZONE_PREF + type + "_" + IntegerToString(i);
            if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, startTime, baseLow, endTime, baseHigh)) {
               color clr = legOutUp ? clrSkyBlue : clrLightSalmon;
               ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
               ObjectSetInteger(0, name, OBJPROP_FILL, true);
               ObjectSetInteger(0, name, OBJPROP_BACK, true);
               ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
               
               // --- TOMBOL INTERAKTIF DENGAN LABEL DINAMIS ---
               string btnName = ZONE_PREF + "BTN_" + type + "_" + IntegerToString(i);
               double btnPrice = legOutUp ? baseLow : baseHigh; 
               
               ObjectCreate(0, btnName, OBJ_TEXT, 0, endTime, btnPrice);
               ObjectSetString(0, btnName, OBJPROP_TEXT, labelText); // Menampilkan "Fresh" atau "Tested 1x, 2x, dst"
               ObjectSetString(0, btnName, OBJPROP_FONT, "Arial Bold");
               ObjectSetInteger(0, btnName, OBJPROP_FONTSIZE, 9); // Ukuran teks sedikit diperkecil agar pas di layar
               
               // Warna tombol: Fresh diberi warna cerah, Tested diberi warna abu-abu/redup (opsional agar kontras)
               color btnColor = legOutUp ? clrBlue : clrRed;
               if(touchCount > 0) btnColor = clrSlateGray; // Mengubah warna ke abu-abu jika sudah tersentuh
               
               ObjectSetInteger(0, btnName, OBJPROP_COLOR, btnColor);
               
               ObjectSetInteger(0, btnName, OBJPROP_SELECTABLE, true);
               ObjectSetInteger(0, btnName, OBJPROP_SELECTED, false);
               
               zonesFound++; 
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
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

double CalcLotPerLayer(ENUM_ORDER_TYPE orderType, double entry, double sl, int layerCount, double riskPct)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(layerCount <= 0 || entry <= 0.0 || sl <= 0.0 || MathAbs(entry - sl) <= 0.0)
      return NormalizeLot(minLot);

   double base = GetRiskBaseAmount();
   if(base <= 0.0) return NormalizeLot(minLot);

   double totalRiskMoney = base * riskPct / 100.0;
   double riskPerLayer   = totalRiskMoney / (double)layerCount;

   double profit = 0.0;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entry, sl, profit))
   {
      Print("OrderCalcProfit gagal. Error: ", GetLastError());
      return NormalizeLot(minLot);
   }

   double lossPerLot = MathAbs(profit);
   if(lossPerLot <= 0.0) return NormalizeLot(minLot);

   return NormalizeLot(riskPerLayer / lossPerLot);
}

double GetResolvedLot(ENUM_ORDER_TYPE orderType, double entry, double sl)
{
   int layers = (int)GetInputValue("InpLayers");
   if(layers < 1) layers = 1;

   if(!IsAutoLot)
   {
      double lot = GetInputValue("InpLot");
      if(lot <= 0.0) return 0.0;
      return NormalizeLot(lot);
   }

   double riskPct = GetInputValue("InpLot");
   if(riskPct <= 0.0) riskPct = (InpRiskPercent > 0.0) ? InpRiskPercent : 1.0;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   // Risk di atas 1% → lot terkecil
   if(riskPct > 1.0)
   {
      Print("Risk ", DoubleToString(riskPct, 2), "% > 1%. Memakai lot terkecil ", minLot);
      return NormalizeLot(minLot);
   }

   return CalcLotPerLayer(orderType, entry, sl, layers, riskPct);
}

void ApplyLotModeUI()
{
   if(ObjectFind(0, PREF+"BtnLotMode") < 0) return;

   if(IsAutoLot)
   {
      ObjectSetString(0, PREF+"BtnLotMode", OBJPROP_TEXT, "Risk %");
      ObjectSetInteger(0, PREF+"BtnLotMode", OBJPROP_BGCOLOR, clrDarkGreen);
      double riskVal = (g_lastRiskPct > 0.0) ? g_lastRiskPct : 1.0;
      ObjectSetString(0, PREF+"InpLot", OBJPROP_TEXT, DoubleToString(riskVal, 2));
      if(ObjectFind(0, PREF+"Line_Floor") < 0 && ObjectFind(0, PREF+"LblCalcLot") >= 0)
         ObjectSetString(0, PREF+"LblCalcLot", OBJPROP_TEXT, "Lot/layer: (draw line)");
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
   ObjectSetString(0, name, OBJPROP_TEXT, IsAutoLot ? "Lot/layer: (draw line)" : "");
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
   int layers = (int)GetInputValue("InpLayers");
   if(layers < 1) layers = 1;

   double buyLot  = GetResolvedLot(ORDER_TYPE_BUY, bEntry, bSL);
   double sellLot = GetResolvedLot(ORDER_TYPE_SELL, sEntry, sSL);

   double buyRiskUSD  = CalcRiskUSD(ORDER_TYPE_BUY, bEntry, bSL, buyLot, layers);
   double sellRiskUSD = CalcRiskUSD(ORDER_TYPE_SELL, sEntry, sSL, sellLot, layers);

   if(ObjectFind(0, PREF+"Buy_Risk") >= 0)
      ObjectSetString(0, PREF+"Buy_Risk", OBJPROP_TEXT, DoubleToString(buyRiskUSD, 2));
   if(ObjectFind(0, PREF+"Sell_Risk") >= 0)
      ObjectSetString(0, PREF+"Sell_Risk", OBJPROP_TEXT, DoubleToString(sellRiskUSD, 2));

   string name = PREF + "LblCalcLot";
   if(ObjectFind(0, name) < 0)
      CreateCalcLotLabel();

   string calcText = "";
   if(IsAutoLot)
      calcText = "Lot/layer: B " + DoubleToString(buyLot, 2) + " / S " + DoubleToString(sellLot, 2);

   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10 + PANEL_W / 2);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, IsDashboardVisible ? UI_Y + 45 : UI_OFFSCREEN);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 11);
   ObjectSetString(0, name, OBJPROP_TEXT, calcText);
}

void PlaceBuyLimit() { 
   int layers = (int)GetInputValue("InpLayers"); 
   if(layers < 1) layers = 1;
   double proximal = GetInputValue("Buy_Entry"); 
   double sl = GetInputValue("Buy_Stoploss"); 
   // Semua layer entry di harga yang sama; SL satu; TP dinamis per layer
   double entry = NormalizeDouble(proximal + GetSpreadPrice() * 2.0, _Digits);
   double lot = GetResolvedLot(ORDER_TYPE_BUY, entry, sl);

   if(proximal == 0 || lot == 0) return; 
   Print("Buy Limit: ", layers, " layer x ", DoubleToString(lot, 2), " lot", IsAutoLot ? " (auto risk)" : " (manual)");
   for(int i=0; i<layers; i++) { 
      double tp = BuyTPByLayer(i, entry, sl);
      trade.BuyLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Buy L"+IntegerToString(i+1)); 
   } 
}

void PlaceSellLimit() { 
   int layers = (int)GetInputValue("InpLayers"); 
   if(layers < 1) layers = 1;
   double proximal = GetInputValue("Sell_Entry"); 
   double sl = GetInputValue("Sell_Stoploss"); 
   // Semua layer entry di harga yang sama; SL satu; TP dinamis per layer
   double entry = NormalizeDouble(proximal - GetSpreadPrice() * 2.0, _Digits);
   double lot = GetResolvedLot(ORDER_TYPE_SELL, entry, sl);

   if(proximal == 0 || lot == 0) return; 
   Print("Sell Limit: ", layers, " layer x ", DoubleToString(lot, 2), " lot", IsAutoLot ? " (auto risk)" : " (manual)");
   for(int i=0; i<layers; i++) { 
      double tp = SellTPByLayer(i, entry, sl);
      trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Sell L"+IntegerToString(i+1)); 
   } 
}

void PlaceBuyNow() {
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = GetInputValue("Buy_Stoploss");
   double tp = 0.0;

   if(g_fiboActive)
   {
      if(sl <= 0.0 || sl >= entry)
         sl = FiboPriceFromLow(InpFiboTarget);
      tp = FiboChartPrice(FiboOppTarget());
      if(tp <= entry)
         tp = FiboChartPrice(InpFiboTarget);
   }
   else
      tp = BuyTPByLayer(4, entry, sl);

   double lot = GetResolvedLot(ORDER_TYPE_BUY, entry, sl);

   if(lot <= 0) {
      Print("Lot size is zero or negative, cannot execute Buy trade.");
      return;
   }
   if(sl <= 0.0 || sl >= entry || tp <= entry)
   {
      Print("Buy Now: butuh SL < Entry < TP. SL=", sl, " Entry=", entry, " TP=", tp);
      return;
   }
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   UpdateInput("Buy_TP1", tp);
   if(trade.Buy(lot, _Symbol, 0, sl, tp, "BuyNow"))
      Print("Buy Now: Lot=", lot, ", SL=", sl, ", TP=", tp);
   else
      Print("Failed to execute Buy order. Error: ", GetLastError());
}

void PlaceSellNow() {
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = GetInputValue("Sell_Stoploss");
   double tp = 0.0;

   if(g_fiboActive)
   {
      if(sl <= entry)
         sl = FiboPriceFromLow(FiboOppTarget());
      tp = FiboChartPrice(InpFiboTarget);
      if(tp >= entry)
         tp = FiboChartPrice(FiboOppTarget());
   }
   else
      tp = SellTPByLayer(4, entry, sl);

   double lot = GetResolvedLot(ORDER_TYPE_SELL, entry, sl);

   if(lot <= 0) {
      Print("Lot size is zero or negative, cannot execute Sell trade.");
      return;
   }
   if(sl <= entry || tp >= entry)
   {
      Print("Sell Now: butuh TP < Entry < SL. SL=", sl, " Entry=", entry, " TP=", tp);
      return;
   }
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   UpdateInput("Sell_TP1", tp);
   if(trade.Sell(lot, _Symbol, 0, sl, tp, "SellNow"))
      Print("Sell Now: Lot=", lot, ", SL=", sl, ", TP=", tp);
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
   CreateButton("Hide", 15, HEADER_Y + 7, 65, 25, "Hide", clrGray, clrWhite);
   CreateButton("HideQuote", 85, HEADER_Y + 7, 90, 25, "Hide Q", clrGray, clrWhite);
   CreateLabel("Title", (PANEL_W / 2) + 20, HEADER_Y + 2, "SND Fibo Candle", clrWhite);
   CreateObject("Panel", OBJ_RECTANGLE_LABEL, 0, 10, UI_Y, PANEL_W, PANEL_H, clrDarkSlateGray);
   
   CreateLabel("LblLayers", 20, UI_Y+12, "Layers", clrOrange); CreateEdit("InpLayers", 130, UI_Y+18, 100, 25, "1");
   CreateButton("BtnLotMode", 260, UI_Y+12, 100, 25, "Lot", clrDarkSlateGray, clrOrange);
   CreateEdit("InpLot", 370, UI_Y+18, 100, 25, "1.00");
   CreateCalcLotLabel();
   ApplyLotModeUI();
   
   CreateButton("BtnScanSD", 20, UI_Y+80, 230, 30, "Scan S&D", clrDarkGreen, clrWhite);
   CreateButton("BtnDraw", 270, UI_Y+80, 210, 30, "Draw Line", clrPurple, clrWhite);
   
   string bL[]={"Floor","Entry","Stoploss","TP1","TP2","TP3","Area","Risk"}; 
   string sL[]={"Ceiling","Entry","Stoploss","TP1","TP2","TP3","Area","Risk"};
   for(int i=0; i<8; i++) {
      CreateLabel("LB_"+bL[i], 20, UI_Y+130+(i*30), bL[i], clrOrange); CreateEdit("Buy_"+bL[i], 130, UI_Y+134+(i*30), 110, 25, "0.00");
      CreateLabel("LS_"+sL[i], 270, UI_Y+130+(i*30), sL[i], clrOrange); CreateEdit("Sell_"+sL[i], 370, UI_Y+134+(i*30), 110, 25, "0.00");
   }
   CreateButton("BtnScanFibo", 20, UI_Y + 375, 150, 30, "Scan Fibo", clrTeal, clrWhite);
   CreateButton("BtnPickFibo", 175, UI_Y + 375, 150, 30, "Pilih Candle", clrDarkOrange, clrWhite);
   CreateButton("BtnPickZzSeg", 330, UI_Y + 375, 150, 30, "Pilih ZZ", clrMediumPurple, clrWhite);
   CreateFiboLevelToggles();
   CreateButton("BtnBuyLFibo", 20, UI_Y + 453, 200, 30, "Buy L Fibo", clrDodgerBlue, clrWhite);
   CreateButton("BtnSellLFibo", 270, UI_Y + 453, 200, 30, "Sell L Fibo", clrOrangeRed, clrWhite);
   CreateButton("BtnBuyL", 20, UI_Y + 493, 200, 30, "Buy Limit", clrBlue, clrWhite);
   CreateButton("BtnSellL", 270, UI_Y + 493, 200, 30, "Sell Limit", clrOrange, clrWhite);
   CreateButton("DelBuy", 20, UI_Y + 533, 200, 30, "Del Buy", clrBlue, clrWhite);
   CreateButton("DelSell", 270, UI_Y + 533, 200, 30, "Del Sell", clrBrown, clrWhite);
   CreateButton("BtnLim382", 20, UI_Y + 573, 150, 30, "Limit 38.2", clrDodgerBlue, clrWhite);
   CreateButton("BtnLim50", 175, UI_Y + 573, 150, 30, "Limit 50", clrTeal, clrWhite);
   CreateButton("BtnLim618", 330, UI_Y + 573, 150, 30, "Limit 61.8", clrOrangeRed, clrWhite);
   CreateButton("ClosePos", 20, UI_Y + 613, 200, 30, "Close Positions", clrDarkRed, clrWhite);
   CreateButton("CloseOrd", 270, UI_Y + 613, 200, 30, "Close Orders", clrMaroon, clrWhite);
   CreateButton("BuyNow", 20, UI_Y + 653, 200, 30, "Buy Now", clrDodgerBlue, clrWhite);
   CreateButton("SellNow", 270, UI_Y + 653, 200, 30, "Sell Now", clrOrangeRed, clrWhite);
   CreateButton("GetNews", 20, UI_Y + 693, 200, 30, "Get News", clrGray, clrBlack);
   CreateButton("Reset", 270, UI_Y + 693, 200, 30, "Reset", clrGray, clrBlack);
   ObjectSetInteger(0, PREF+"BtnLotMode", OBJPROP_ZORDER, 10);

   // Tambahkan ini di setiap fungsi pembuatan tombol/label dashboard Anda
   ObjectSetInteger(0, PREF+"BtnBuyLFibo", OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, PREF+"BtnSellLFibo", OBJPROP_ZORDER, 10);
   for(int lv = 1; lv <= 5; lv++)
      ObjectSetInteger(0, PREF+"ChkFiboLv"+IntegerToString(lv), OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, PREF+"BtnBuyL", OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, PREF+"BtnSellL", OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, PREF+"BtnLim382", OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, PREF+"BtnLim50", OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, PREF+"BtnLim618", OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, "DelBuy", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "DelSell", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "ClosePos", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "CloseOrd", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "BuyNow", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "SellNow", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "GetNews", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "Reset", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan


}

//+------------------------------------------------------------------+
//| Bullish: 0% High, 100% Low (23.6 dekat high, 78.6 dekat low).    |
//| Bearish: 0% Low, 100% High (23.6 dekat low, 78.6 dekat high).    |
//| FiboChartPrice mengikuti garis di chart.                         |
//| FiboPriceFromLow: 0% Low / 100% High (ekstensi di atas/bawah).   |
//+------------------------------------------------------------------+
double FiboRatio(const double v)
{
   if(MathAbs(v) > 2.0)
      return v / 100.0;
   return v;
}

double FiboOppTarget()
{
   return 1.0 - FiboRatio(InpFiboTarget);
}

double FiboPriceFromLow(const double levelInput)
{
   string name = FIBO_PREF + "OBJ";
   if(ObjectFind(0, name) >= 0)
   {
      double p0 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
      double p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
      double low  = MathMin(p0, p1);
      double high = MathMax(p0, p1);
      return low + FiboRatio(levelInput) * (high - low);
   }
   return g_fiboLow + FiboRatio(levelInput) * (g_fiboHigh - g_fiboLow);
}

double FiboChartPrice(const double levelInput)
{
   string name = FIBO_PREF + "OBJ";
   if(ObjectFind(0, name) >= 0)
   {
      double p0 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
      double p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
      return p1 + (p0 - p1) * FiboRatio(levelInput);
   }
   if(g_fiboBullish)
      return g_fiboHigh - FiboRatio(levelInput) * (g_fiboHigh - g_fiboLow);
   return g_fiboLow + FiboRatio(levelInput) * (g_fiboHigh - g_fiboLow);
}

double GetFiboLevelInput(const int levelIdx)
{
   if(levelIdx == 1) return InpFiboLevel1;
   if(levelIdx == 2) return InpFiboLevel2;
   if(levelIdx == 3) return InpFiboLevel3;
   if(levelIdx == 4) return InpFiboLevel4;
   if(levelIdx == 5) return InpFiboLevel5;
   return 0.0;
}

void CreateFiboTradeButton(const string name, const datetime t, const double price, const string text, const color clr)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 108);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 25);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, text);
}

void ApplyFiboObjectStyle(const string fiboName)
{
   ObjectSetInteger(0, fiboName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, fiboName, OBJPROP_READONLY, true);
   ObjectSetInteger(0, fiboName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, fiboName, OBJPROP_BACK, false);
   ObjectSetInteger(0, fiboName, OBJPROP_ZORDER, 0);
}

void OnFiboObjectMoved(const string fiboName)
{
   SyncFiboFromObject();
   SyncFiboAnchorLines();
   UpdateFiboTradeButtons();
}

void SetFiboAnchorLine(const string name, const double price, const color clr, const string tip)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 30);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

void CreateFiboAnchorLines()
{
   SetFiboAnchorLine(FIBO_PREF + "AnchorHigh", g_fiboHigh, clrOrange, "Fibo High - drag");
   SetFiboAnchorLine(FIBO_PREF + "AnchorLow", g_fiboLow, clrDodgerBlue, "Fibo Low - drag");
}

void SyncFiboAnchorLines()
{
   string highName = FIBO_PREF + "AnchorHigh";
   string lowName  = FIBO_PREF + "AnchorLow";
   if(ObjectFind(0, highName) >= 0)
      ObjectSetDouble(0, highName, OBJPROP_PRICE, g_fiboHigh);
   if(ObjectFind(0, lowName) >= 0)
      ObjectSetDouble(0, lowName, OBJPROP_PRICE, g_fiboLow);
}

void UpdateFiboObjectFromGlobals()
{
   string fiboName = FIBO_PREF + "OBJ";
   if(ObjectFind(0, fiboName) < 0)
      return;

   if(g_fiboBullish)
   {
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 0, g_fiboLow);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 1, g_fiboHigh);
   }
   else
   {
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 0, g_fiboHigh);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 1, g_fiboLow);
   }
}

void OnFiboAnchorDragged()
{
   string highName = FIBO_PREF + "AnchorHigh";
   string lowName  = FIBO_PREF + "AnchorLow";
   if(ObjectFind(0, highName) < 0 || ObjectFind(0, lowName) < 0)
      return;

   double high = ObjectGetDouble(0, highName, OBJPROP_PRICE);
   double low  = ObjectGetDouble(0, lowName, OBJPROP_PRICE);
   if(high <= low)
   {
      SyncFiboAnchorLines();
      return;
   }

   g_fiboHigh = high;
   g_fiboLow  = low;
   g_fiboActive = true;
   UpdateFiboObjectFromGlobals();
   UpdateFiboTradeButtons();
}

void SyncFiboFromObject()
{
   string fiboName = FIBO_PREF + "OBJ";
   if(ObjectFind(0, fiboName) < 0)
      return;

   double p0 = ObjectGetDouble(0, fiboName, OBJPROP_PRICE, 0);
   double p1 = ObjectGetDouble(0, fiboName, OBJPROP_PRICE, 1);
   if(p0 <= 0.0 || p1 <= 0.0 || MathAbs(p0 - p1) < _Point)
      return;

   g_fiboHigh = MathMax(p0, p1);
   g_fiboLow  = MathMin(p0, p1);
   g_fiboBullish = (p1 > p0);
   g_fiboTime = (datetime)ObjectGetInteger(0, fiboName, OBJPROP_TIME, 0);
   g_fiboActive = true;
}

void UpdateFiboTradeButtons()
{
   if(!g_fiboActive)
      return;

   datetime tBuy  = g_fiboTime - PeriodSeconds() * 2;
   datetime tSell = g_fiboTime - PeriodSeconds();

   for(int lv = 1; lv <= 5; lv++)
   {
      double price = FiboChartPrice(GetFiboLevelInput(lv));
      string buyName  = FIBO_PREF + "BUY_"  + IntegerToString(lv);
      string sellName = FIBO_PREF + "SELL_" + IntegerToString(lv);

      if(ObjectFind(0, buyName) >= 0)
      {
         ObjectMove(0, buyName, 0, tBuy, price);
         ObjectSetInteger(0, buyName, OBJPROP_COLOR, clrLime);
         ObjectSetInteger(0, buyName, OBJPROP_WIDTH, 1);
      }
      else
         CreateFiboTradeButton(buyName, tBuy, price, "Buy L", clrLime);

      if(ObjectFind(0, sellName) >= 0)
      {
         ObjectMove(0, sellName, 0, tSell, price);
         ObjectSetInteger(0, sellName, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, sellName, OBJPROP_WIDTH, 1);
      }
      else
         CreateFiboTradeButton(sellName, tSell, price, "Sell L", clrRed);
   }
}

void ClearFiboCandle()
{
   ObjectsDeleteAll(0, FIBO_PREF);
   g_fiboActive = false;
   g_fiboBullish = true;
   g_fiboHigh = 0.0;
   g_fiboLow  = 0.0;
   g_fiboTime = 0;
   g_fiboCutProfitArmed = false;
   g_fiboCutProfitArmBar = 0;
}

void ScanFiboCandle(const int shiftParam)
{
   int shift = shiftParam;
   if(shift < 0)
      shift = InpCloseCandle;
   if(shift < 0)
      shift = 1;

   int bars = Bars(_Symbol, _Period);
   if(shift >= bars)
   {
      Print("Scan Fibo: shift ", shift, " melebihi jumlah bar.");
      return;
   }

   ClearFiboCandle();

   g_fiboTime = iTime(_Symbol, _Period, shift);
   g_fiboHigh = iHigh(_Symbol, _Period, shift);
   g_fiboLow  = iLow(_Symbol, _Period, shift);
   if(g_fiboHigh <= g_fiboLow)
   {
      Print("Scan Fibo: range candle 0, batal.");
      return;
   }

   datetime t2 = (shift > 0) ? iTime(_Symbol, _Period, shift - 1) : g_fiboTime + PeriodSeconds();
   string fiboName = FIBO_PREF + "OBJ";

   g_fiboBullish = (iClose(_Symbol, _Period, shift) >= iOpen(_Symbol, _Period, shift));
   if(g_fiboBullish)
   {
      ObjectCreate(0, fiboName, OBJ_FIBO, 0, g_fiboTime, g_fiboLow, t2, g_fiboHigh);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 0, g_fiboLow);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 1, g_fiboHigh);
   }
   else
   {
      ObjectCreate(0, fiboName, OBJ_FIBO, 0, g_fiboTime, g_fiboHigh, t2, g_fiboLow);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 0, g_fiboHigh);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 1, g_fiboLow);
   }
   ObjectSetInteger(0, fiboName, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, fiboName, OBJPROP_RAY_RIGHT, InpFiboRayRight);
   ApplyFiboObjectStyle(fiboName);
   SetupFiboObjectLevels(fiboName);

   g_fiboActive = true;
   UpdateFiboTradeButtons();
   CreateFiboAnchorLines();

   Print("Scan Fibo Candle shift=", shift,
         " ", (g_fiboBullish ? "bullish" : "bearish"),
         " time=", TimeToString(g_fiboTime),
         " high=", DoubleToString(g_fiboHigh, _Digits),
         " low=", DoubleToString(g_fiboLow, _Digits));
   ChartRedraw();
}

void SetupFiboObjectLevels(const string fiboName)
{
   ObjectSetInteger(0, fiboName, OBJPROP_COLOR, clrNONE);
   ObjectSetInteger(0, fiboName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, fiboName, OBJPROP_WIDTH, 0);
   ObjectSetInteger(0, fiboName, OBJPROP_LEVELS, 9);

   double levelVals[9];
   string levelTxt[9];
   levelVals[0]  = 0.0;                            levelTxt[0]  = "0";
   levelVals[1]  = 1.0;                            levelTxt[1]  = "100";
   levelVals[2]  = FiboRatio(InpFiboLevel1);       levelTxt[2]  = DoubleToString(InpFiboLevel1, 1);
   levelVals[3]  = FiboRatio(InpFiboLevel2);       levelTxt[3]  = DoubleToString(InpFiboLevel2, 1);
   levelVals[4]  = FiboRatio(InpFiboLevel3);       levelTxt[4]  = DoubleToString(InpFiboLevel3, 1);
   levelVals[5]  = FiboRatio(InpFiboLevel4);       levelTxt[5]  = DoubleToString(InpFiboLevel4, 1);
   levelVals[6]  = FiboRatio(InpFiboLevel5);       levelTxt[6]  = DoubleToString(InpFiboLevel5, 1);
   levelVals[7]  = FiboRatio(InpFiboTarget);       levelTxt[7]  = DoubleToString(InpFiboTarget, 1);
   levelVals[8]  = FiboRatio(FiboOppTarget());     levelTxt[8]  = DoubleToString(FiboOppTarget(), 3);

   for(int i = 0; i < 9; i++)
   {
      ObjectSetDouble(0, fiboName, OBJPROP_LEVELVALUE, i, levelVals[i]);
      ObjectSetInteger(0, fiboName, OBJPROP_LEVELSTYLE, i, STYLE_DOT);
      ObjectSetInteger(0, fiboName, OBJPROP_LEVELWIDTH, i, InpFiboWidth);
      ObjectSetInteger(0, fiboName, OBJPROP_LEVELCOLOR, i, InpFiboColor);
      ObjectSetString(0, fiboName, OBJPROP_LEVELTEXT, i, " " + levelTxt[i]);
   }
}

bool ChartHasZigZagSegment()
{
   int total = ChartIndicatorsTotal(0, 0);
   for(int i = 0; i < total; i++)
   {
      string indName = ChartIndicatorName(0, 0, i);
      if(StringFind(indName, "zigzag_segment") >= 0)
         return true;
   }
   return false;
}

void LoadZigZagSegmentIndicator()
{
   RemoveZigZagSegmentFromChart();

   g_zzSegHandle = iCustom(_Symbol, _Period, InpZigZagPath);
   if(g_zzSegHandle == INVALID_HANDLE)
   {
      Print("ZigZag Segment gagal load (", InpZigZagPath, "). Error: ", GetLastError());
      return;
   }

   if(!ChartIndicatorAdd(0, 0, g_zzSegHandle))
      Print("ChartIndicatorAdd ZigZag Segment gagal. Error: ", GetLastError());
   else
      Print("ZigZag Segment loaded: ", InpZigZagPath);
}

void RemoveZigZagSegmentFromChart()
{
   for(int i = ChartIndicatorsTotal(0, 0) - 1; i >= 0; i--)
   {
      string indName = ChartIndicatorName(0, 0, i);
      if(StringFind(indName, "zigzag_segment") >= 0)
         ChartIndicatorDelete(0, 0, indName);
   }

   if(g_zzSegHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_zzSegHandle);
      g_zzSegHandle = INVALID_HANDLE;
   }

   CleanupZzSegFiboObjects();
}

void CleanupZzSegFiboObjects()
{
   ObjectsDeleteAll(0, ZZSEG_PREFIX);
}

void ApplyZzSegPickStyle(const bool pickOn)
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, ZZSEG_PREFIX + "BX_") != 0)
         continue;
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, pickOn);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, !pickOn);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, pickOn ? 5 : 0);
   }
}

void ScanFiboFromZzSegment(const string zzSegName)
{
   string idx = "";
   if(StringFind(zzSegName, ZZSEG_PREFIX + "BX_") == 0)
      idx = StringSubstr(zzSegName, StringLen(ZZSEG_PREFIX + "BX_"));
   else if(StringFind(zzSegName, ZZSEG_PREFIX + "LN_") == 0)
      idx = StringSubstr(zzSegName, StringLen(ZZSEG_PREFIX + "LN_"));
   else if(StringFind(zzSegName, ZZSEG_PREFIX + "FB_") == 0)
      idx = StringSubstr(zzSegName, StringLen(ZZSEG_PREFIX + "FB_"));
   else
   {
      Print("Pilih ZZ: objek segmen tidak valid (", zzSegName, ").");
      return;
   }

   string lnName = ZZSEG_PREFIX + "LN_" + idx;
   if(ObjectFind(0, lnName) < 0)
   {
      Print("Pilih ZZ: garis segmen ", lnName, " tidak ditemukan.");
      return;
   }

   ClearFiboCandle();

   datetime t0 = (datetime)ObjectGetInteger(0, lnName, OBJPROP_TIME, 0);
   datetime t1 = (datetime)ObjectGetInteger(0, lnName, OBJPROP_TIME, 1);
   double p0 = ObjectGetDouble(0, lnName, OBJPROP_PRICE, 0);
   double p1 = ObjectGetDouble(0, lnName, OBJPROP_PRICE, 1);

   g_fiboTime = (datetime)MathMin((long)t0, (long)t1);
   g_fiboHigh = MathMax(p0, p1);
   g_fiboLow  = MathMin(p0, p1);
   if(g_fiboHigh <= g_fiboLow)
   {
      Print("Pilih ZZ: range segmen 0, batal.");
      return;
   }

   g_fiboBullish = (p1 > p0);

   string fiboName = FIBO_PREF + "OBJ";
   if(g_fiboBullish)
   {
      ObjectCreate(0, fiboName, OBJ_FIBO, 0, t0, p0, t1, p1);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 0, g_fiboLow);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 1, g_fiboHigh);
   }
   else
   {
      ObjectCreate(0, fiboName, OBJ_FIBO, 0, t0, p0, t1, p1);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 0, g_fiboHigh);
      ObjectSetDouble(0, fiboName, OBJPROP_PRICE, 1, g_fiboLow);
   }

   ObjectSetInteger(0, fiboName, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, fiboName, OBJPROP_RAY_RIGHT, InpFiboRayRight);
   ApplyFiboObjectStyle(fiboName);
   SetupFiboObjectLevels(fiboName);

   g_fiboActive = true;
   UpdateFiboTradeButtons();
   CreateFiboAnchorLines();

   Print("Fibo dari ZZ seg ", lnName,
         " ", (g_fiboBullish ? "bullish" : "bearish"),
         " time=", TimeToString(g_fiboTime),
         " high=", DoubleToString(g_fiboHigh, _Digits),
         " low=", DoubleToString(g_fiboLow, _Digits));
   ChartRedraw();
}

bool FindZzSegmentAtClick(const int x, const int y, string &outSegName)
{
   int wnd = 0;
   datetime t = 0;
   double price = 0.0;
   if(!ChartXYToTimePrice(0, x, y, wnd, t, price) || wnd != 0 || t <= 0)
      return false;

   string bestSeg = "";
   double bestScore = DBL_MAX;
   int total = ObjectsTotal(0, 0, -1);

   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, ZZSEG_PREFIX + "BX_") != 0)
         continue;

      datetime t0 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
      datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
      double p0 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
      double p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);

      datetime tMin = (datetime)MathMin((long)t0, (long)t1);
      datetime tMax = (datetime)MathMax((long)t0, (long)t1);
      double pMin = MathMin(p0, p1);
      double pMax = MathMax(p0, p1);

      bool inside = (t >= tMin && t <= tMax && price >= pMin && price <= pMax);
      double midP = (pMin + pMax) * 0.5;
      long midT = ((long)tMin + (long)tMax) / 2;
      double score = MathAbs(price - midP) + MathAbs((double)((long)t - midT)) * _Point;

      if(inside)
         score *= 0.01;

      if(score >= bestScore)
         continue;

      string idx = StringSubstr(name, StringLen(ZZSEG_PREFIX + "BX_"));
      string boxName = ZZSEG_PREFIX + "BX_" + idx;
      if(ObjectFind(0, boxName) < 0)
         continue;

      bestScore = score;
      bestSeg = boxName;
   }

   if(bestSeg == "")
   {
      for(int i = 0; i < total; i++)
      {
         string name = ObjectName(0, i, 0, -1);
         if(StringFind(name, ZZSEG_PREFIX + "LN_") != 0)
            continue;

         datetime t0 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
         datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
         double p0 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
         double p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
         double midP = (p0 + p1) * 0.5;
         long midT = ((long)t0 + (long)t1) / 2;
         double score = MathAbs(price - midP) + MathAbs((double)((long)t - midT)) * _Point;

         if(score < bestScore)
         {
            bestScore = score;
            bestSeg = name;
         }
      }
   }

   if(bestSeg == "")
      return false;

   outSegName = bestSeg;
   return true;
}

void SetPickFiboMode(const bool on)
{
   g_pickFiboCandle = on;
   if(on)
      SetPickZzSegMode(false);
   if(ObjectFind(0, PREF+"BtnPickFibo") < 0)
      return;
   if(on)
   {
      ObjectSetString(0, PREF+"BtnPickFibo", OBJPROP_TEXT, "Klik Candle");
      ObjectSetInteger(0, PREF+"BtnPickFibo", OBJPROP_BGCOLOR, clrOrangeRed);
   }
   else
   {
      ObjectSetString(0, PREF+"BtnPickFibo", OBJPROP_TEXT, "Pilih Candle");
      ObjectSetInteger(0, PREF+"BtnPickFibo", OBJPROP_BGCOLOR, clrDarkOrange);
   }
}

void SetPickZzSegMode(const bool on)
{
   g_pickZzSeg = on;
   if(on)
      SetPickFiboMode(false);
   if(ObjectFind(0, PREF+"BtnPickZzSeg") < 0)
      return;
   if(on)
   {
      ObjectSetString(0, PREF+"BtnPickZzSeg", OBJPROP_TEXT, "Klik Segmen");
      ObjectSetInteger(0, PREF+"BtnPickZzSeg", OBJPROP_BGCOLOR, clrOrangeRed);
   }
   else
   {
      ObjectSetString(0, PREF+"BtnPickZzSeg", OBJPROP_TEXT, "Pilih ZZ");
      ObjectSetInteger(0, PREF+"BtnPickZzSeg", OBJPROP_BGCOLOR, clrMediumPurple);
   }
   ApplyZzSegPickStyle(on);
}

void PickFiboAtChart(const int x, const int y)
{
   if(x >= 10 && x <= 10 + PANEL_W && y >= HEADER_Y && y <= UI_Y + PANEL_H)
      return;

   int wnd = 0;
   datetime t = 0;
   double price = 0.0;
   if(!ChartXYToTimePrice(0, x, y, wnd, t, price))
      return;
   if(wnd != 0 || t <= 0)
      return;

   int shift = iBarShift(_Symbol, _Period, t, true);
   if(shift < 0)
      shift = iBarShift(_Symbol, _Period, t, false);
   if(shift < 0)
   {
      Print("Pilih candle: bar tidak ditemukan.");
      return;
   }

   ScanFiboCandle(shift);
   SetPickFiboMode(false);
   Print("Fibo dipasang di candle shift ", shift, " (", TimeToString(iTime(_Symbol, _Period, shift)), ")");
}

void PickZzSegAtChart(const int x, const int y)
{
   if(x >= 10 && x <= 10 + PANEL_W && y >= HEADER_Y && y <= UI_Y + PANEL_H)
      return;

   string zzSegName = "";
   if(!FindZzSegmentAtClick(x, y, zzSegName))
   {
      Print("Pilih ZZ: klik di dalam kotak segmen ZigZag (hijau/merah).");
      return;
   }

   ScanFiboFromZzSegment(zzSegName);
   SetPickZzSegMode(false);
   Print("Fibo dipasang dari segmen ", zzSegName);
}

void PlaceLimitOrder(const bool isBuy, const double entry, const double sl, const double tp, const string comment, const double lotMult)
{
   int layers = (int)GetInputValue("InpLayers");
   if(layers < 1) layers = 1;

   double nEntry = NormalizeDouble(entry, _Digits);
   double nSL    = NormalizeDouble(sl, _Digits);
   double nTP    = NormalizeDouble(tp, _Digits);

   if(nEntry <= 0.0 || nSL <= 0.0 || nTP <= 0.0)
   {
      Print(comment, ": harga entry/SL/TP tidak valid.");
      return;
   }
   if(isBuy && !(nSL < nEntry && nEntry < nTP))
   {
      Print(comment, ": Buy butuh SL < Entry < TP. E=", nEntry, " SL=", nSL, " TP=", nTP);
      return;
   }
   if(!isBuy && !(nTP < nEntry && nEntry < nSL))
   {
      Print(comment, ": Sell butuh TP < Entry < SL. E=", nEntry, " SL=", nSL, " TP=", nTP);
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   ENUM_ORDER_TYPE lotType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double lot = GetResolvedLot(lotType, nEntry, nSL);
   if(lotMult > 0.0 && lotMult != 1.0)
      lot = NormalizeLot(lot * lotMult);
   if(lot <= 0.0)
   {
      Print(comment, ": lot 0, batal.");
      return;
   }

   if(isBuy)
   {
      UpdateInput("Buy_Entry", nEntry);
      UpdateInput("Buy_Stoploss", nSL);
      UpdateInput("Buy_TP1", nTP);
   }
   else
   {
      UpdateInput("Sell_Entry", nEntry);
      UpdateInput("Sell_Stoploss", nSL);
      UpdateInput("Sell_TP1", nTP);
   }

   bool useLimit = isBuy ? (nEntry < ask) : (nEntry > bid);
   string kind = useLimit ? "Limit" : "Stop";
   Print(comment, " ", kind, ": ", layers, " layer x ", DoubleToString(lot, 2),
         " E=", DoubleToString(nEntry, _Digits),
         " SL=", DoubleToString(nSL, _Digits),
         " TP=", DoubleToString(nTP, _Digits));

   for(int i = 0; i < layers; i++)
   {
      string cmt = comment + " L" + IntegerToString(i + 1);
      bool ok = false;
      if(isBuy)
      {
         if(useLimit)
            ok = trade.BuyLimit(lot, nEntry, _Symbol, nSL, nTP, ORDER_TIME_GTC, 0, cmt);
         else
            ok = trade.BuyStop(lot, nEntry, _Symbol, nSL, nTP, ORDER_TIME_GTC, 0, cmt);
      }
      else
      {
         if(useLimit)
            ok = trade.SellLimit(lot, nEntry, _Symbol, nSL, nTP, ORDER_TIME_GTC, 0, cmt);
         else
            ok = trade.SellStop(lot, nEntry, _Symbol, nSL, nTP, ORDER_TIME_GTC, 0, cmt);
      }

      if(!ok)
         Print(comment, " gagal layer ", i + 1, ". Error: ", GetLastError(), " ", trade.ResultRetcodeDescription());
   }
}

void PlaceFiboBuyLimit(const int levelIdx)
{
   if(!g_fiboActive)
   {
      Print("Klik Scan Fibo Candle dulu.");
      return;
   }

   double levelInput = GetFiboLevelInput(levelIdx);
   if(levelInput == 0.0) return;

   double entry = FiboChartPrice(levelInput);
   double sl    = FiboPriceFromLow(InpFiboTarget);
   double tp    = 0.0;

   if(g_fiboBullish)
   {
      // 0=High: 23.6 → -27.2 | 38.2 → 1.272 di atas | 50 → 0 | 61.8 & 78.6 → 23.6
      if(levelIdx == 1)
         tp = FiboChartPrice(InpFiboTarget);
      else if(levelIdx == 2)
         tp = FiboPriceFromLow(FiboOppTarget());
      else if(levelIdx == 3)
         tp = FiboChartPrice(0.0);
      else
         tp = FiboChartPrice(InpFiboLevel1);
   }
   else
   {
      // 0=Low: 23.6 → -27.2 | 38.2 → 1.272 | 50 → 100 (high) | 61.8 & 78.6 → 1.272
      if(levelIdx == 1)
         tp = FiboChartPrice(InpFiboTarget);
      else if(levelIdx == 2)
         tp = FiboChartPrice(FiboOppTarget());
      else if(levelIdx == 3)
         tp = FiboChartPrice(100.0);
      else
         tp = FiboPriceFromLow(FiboOppTarget());
   }

   PlaceLimitOrder(true, entry, sl, tp, "FiboBuy " + DoubleToString(levelInput, 1),
                   (levelIdx == 4 || levelIdx == 5) ? 2.0 : 1.0);
}

void PlaceFiboSellLimit(const int levelIdx)
{
   if(!g_fiboActive)
   {
      Print("Klik Scan Fibo Candle dulu.");
      return;
   }

   double levelInput = GetFiboLevelInput(levelIdx);
   if(levelInput == 0.0) return;

   double entry = FiboChartPrice(levelInput);
   double sl    = FiboPriceFromLow(FiboOppTarget());
   double tp    = 0.0;

   if(g_fiboBullish)
   {
      // 0=High: 23.6 → -27.2 | 38.2 → 1.272 di bawah | 50 → 100 | 61.8 & 78.6 → 1.272
      if(levelIdx == 1)
         tp = FiboChartPrice(InpFiboTarget);
      else if(levelIdx == 2)
         tp = FiboChartPrice(FiboOppTarget());
      else if(levelIdx == 3)
         tp = FiboChartPrice(100.0);
      else
         tp = FiboChartPrice(FiboOppTarget());
   }
   else
   {
      // 0=Low: 23.6 → -27.2 | 38.2 → -27.2 | 50 → 0 | 61.8 & 78.6 → 23.6
      if(levelIdx == 1)
         tp = FiboChartPrice(InpFiboTarget);
      else if(levelIdx == 2)
         tp = FiboPriceFromLow(InpFiboTarget);
      else if(levelIdx == 3)
         tp = FiboChartPrice(0.0);
      else
         tp = FiboChartPrice(InpFiboLevel1);
   }

   PlaceLimitOrder(false, entry, sl, tp, "FiboSell " + DoubleToString(levelInput, 1),
                   (levelIdx == 4 || levelIdx == 5) ? 2.0 : 1.0);
}

void PlaceFiboBuyAll()
{
   EnsureFiboScanned();
   if(!g_fiboActive)
   {
      Print("Buy L Fibo: scan fibo gagal.");
      return;
   }

   DeleteFiboPending(true);
   DeleteFiboPending(false);
   g_fiboCutProfitArmed = false;
   g_fiboCutProfitArmBar = 0;

   int placed = 0;
   string sel = "";
   for(int lv = 1; lv <= 5; lv++)
   {
      if(!IsFiboLevelSelected(lv))
         continue;
      PlaceFiboBuyLimit(lv);
      sel += (sel == "" ? "" : ", ") + DoubleToString(GetFiboLevelInput(lv), 1);
      placed++;
   }
   if(placed == 0)
      Print("Buy L Fibo: pilih minimal 1 level fibo di dashboard.");
   else
      Print("Buy L Fibo: order level ", sel);
}

void PlaceFiboSellAll()
{
   EnsureFiboScanned();
   if(!g_fiboActive)
   {
      Print("Sell L Fibo: scan fibo gagal.");
      return;
   }

   DeleteFiboPending(false);
   DeleteFiboPending(true);
   g_fiboCutProfitArmed = false;
   g_fiboCutProfitArmBar = 0;

   int placed = 0;
   string sel = "";
   for(int lv = 1; lv <= 5; lv++)
   {
      if(!IsFiboLevelSelected(lv))
         continue;
      PlaceFiboSellLimit(lv);
      sel += (sel == "" ? "" : ", ") + DoubleToString(GetFiboLevelInput(lv), 1);
      placed++;
   }
   if(placed == 0)
      Print("Sell L Fibo: pilih minimal 1 level fibo di dashboard.");
   else
      Print("Sell L Fibo: order level ", sel);
}

void PlaceFiboDirLimit(const int kind)
{
   EnsureFiboScanned();
   if(!g_fiboActive)
   {
      Print("Limit Fibo: scan / pilih fibo dulu.");
      return;
   }

   double entryLv = 0.0;
   double slLv    = 0.0;
   double tpLv    = 0.0;
   if(kind == 1)
   {
      entryLv = InpFiboLevel2;
      slLv    = InpFiboLevel3;
      tpLv    = 0.0;
   }
   else if(kind == 3)
   {
      entryLv = InpFiboLevel3;
      slLv    = InpFiboLevel5;
      tpLv    = 0.0;
   }
   else
   {
      entryLv = InpFiboLevel4;
      slLv    = InpFiboLevel5;
      tpLv    = InpFiboLevel1;
   }

   double entry = FiboChartPrice(entryLv);
   double sl    = FiboChartPrice(slLv);
   double tp    = FiboChartPrice(tpLv);
   bool isBuy   = g_fiboBullish;
   string tag   = isBuy ? "FiboBuy " : "FiboSell ";

   Print("Limit ", DoubleToString(entryLv, 1),
         isBuy ? " BUY" : " SELL",
         " (arah fibo ", (g_fiboBullish ? "bullish" : "bearish"), ")");
   PlaceLimitOrder(isBuy, entry, sl, tp, tag + DoubleToString(entryLv, 1));
}

void CreateFiboLevelToggles()
{
   int xs[5] = {20, 112, 204, 296, 388};
   for(int lv = 1; lv <= 5; lv++)
   {
      string name = "ChkFiboLv" + IntegerToString(lv);
      CreateButton(name, xs[lv - 1], UI_Y + 412, 88, 28,
                   DoubleToString(GetFiboLevelInput(lv), 1), clrTeal, clrWhite);
      ApplyFiboLevelToggleStyle(lv);
   }
}

void ApplyFiboLevelToggleStyle(const int lv)
{
   if(lv < 1 || lv > 5)
      return;
   string name = PREF + "ChkFiboLv" + IntegerToString(lv);
   if(ObjectFind(0, name) < 0)
      return;
   bool on = g_fiboLvOn[lv];
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, on ? clrTeal : clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
}

bool IsFiboLevelSelected(const int lv)
{
   if(lv < 1 || lv > 5)
      return false;
   return g_fiboLvOn[lv];
}

void ToggleFiboLevel(const int lv)
{
   if(lv < 1 || lv > 5)
      return;
   g_fiboLvOn[lv] = !g_fiboLvOn[lv];
   ApplyFiboLevelToggleStyle(lv);
   ChartRedraw();
}

bool IsFiboOnChart()
{
   if(!g_fiboActive)
      return false;
   if(ObjectFind(0, FIBO_PREF + "OBJ") < 0)
   {
      g_fiboActive = false;
      g_fiboHigh = 0.0;
      g_fiboLow  = 0.0;
      g_fiboTime = 0;
      return false;
   }
   return true;
}

void EnsureFiboScanned()
{
   if(IsFiboOnChart())
   {
      if(ObjectFind(0, FIBO_PREF + "AnchorHigh") < 0)
      {
         SyncFiboFromObject();
         CreateFiboAnchorLines();
      }
      return;
   }
   ScanFiboCandle(-1);
}

void DeleteFiboPending(const bool isBuy)
{
   string tag = isBuy ? "FiboBuy" : "FiboSell";
   int deletedOrd = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), tag) < 0)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool match = false;
      if(isBuy)
         match = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP);
      else
         match = (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP);
      if(!match)
         continue;

      if(trade.OrderDelete(ticket))
         deletedOrd++;
   }

   if(deletedOrd > 0)
      Print("Hapus pending ", tag, ": ", deletedOrd);
}

void CheckFiboCutLoss()
{
   if(!InpFiboCutLoss || !g_fiboActive)
      return;

   datetime closedTime = iTime(_Symbol, _Period, 1);
   if(closedTime <= 0 || closedTime <= g_fiboTime)
      return;

   double closePx = iClose(_Symbol, _Period, 1);
   double level78 = FiboChartPrice(InpFiboLevel5);

   if(closePx > level78)
   {
      if(!HasFiboPositionSide(false))
         return;
      Print("Cut loss SELL: close body ", DoubleToString(closePx, _Digits),
            " di atas garis ", DoubleToString(InpFiboLevel5, 1),
            " (", DoubleToString(level78, _Digits), ")");
      CutFiboTrades(false);
   }
   else if(closePx < level78)
   {
      if(!HasFiboPositionSide(true))
         return;
      Print("Cut loss BUY: close body ", DoubleToString(closePx, _Digits),
            " di bawah garis ", DoubleToString(InpFiboLevel5, 1),
            " (", DoubleToString(level78, _Digits), ")");
      CutFiboTrades(true);
   }
}

bool HasFiboPositionSide(const bool isBuy)
{
   string tag = isBuy ? "FiboBuy" : "FiboSell";
   long posType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(PositionGetInteger(POSITION_TYPE) != posType)
         continue;

      string cmt = PositionGetString(POSITION_COMMENT);
      if(StringFind(cmt, tag) < 0)
         continue;
      if(g_fiboTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < g_fiboTime)
         continue;
      return true;
   }

   return false;
}

bool HasFibo786Position()
{
   string lvl786 = DoubleToString(InpFiboLevel5, 1);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      string cmt = PositionGetString(POSITION_COMMENT);
      if(StringFind(cmt, "FiboBuy") < 0 && StringFind(cmt, "FiboSell") < 0)
         continue;
      if(g_fiboTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < g_fiboTime)
         continue;
      if(StringFind(cmt, lvl786) >= 0)
         return true;
   }

   return false;
}

bool Fibo786FilledOnLastBar()
{
   if(!g_fiboActive)
      return false;

   datetime barTime = iTime(_Symbol, _Period, 1);
   if(barTime <= 0 || barTime <= g_fiboTime)
      return false;

   datetime barEnd = barTime + (datetime)PeriodSeconds();
   if(!HistorySelect(barTime, barEnd))
      return false;

   string lvl786 = DoubleToString(InpFiboLevel5, 1);
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;

      string cmt = HistoryDealGetString(deal, DEAL_COMMENT);
      if(StringFind(cmt, "FiboBuy") < 0 && StringFind(cmt, "FiboSell") < 0)
         continue;
      if(StringFind(cmt, lvl786) >= 0)
         return true;
   }

   return false;
}

bool FiboPriceTouchesLevel(const double level)
{
   if(level <= 0.0)
      return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return false;

   return (bid <= level && ask >= level);
}

bool FiboCutProfitLevelReached()
{
   double level50  = FiboChartPrice(InpFiboLevel3);
   double level786 = FiboChartPrice(InpFiboLevel5);
   if(level50 <= 0.0 || level786 <= 0.0)
      return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return false;

   // 50 di atas 78.6: cut profit saat harga naik melewati 50
   if(level50 > level786)
      return (bid > level50);

   // 50 di bawah 78.6: cut profit saat harga turun melewati 50
   return (ask < level50);
}

void CheckFiboCutProfit()
{
   if(!InpFiboCutProfit || !g_fiboActive)
      return;

   if(HasFibo786Position() || Fibo786FilledOnLastBar())
   {
      if(!g_fiboCutProfitArmed)
         g_fiboCutProfitArmBar = iTime(_Symbol, _Period, 0);
      g_fiboCutProfitArmed = true;
   }

   if(!g_fiboCutProfitArmed)
      return;

   // Bar fill 78.6: jangan cut profit di bar yang sama (hindari false trigger)
   if(g_fiboCutProfitArmBar > 0 && iTime(_Symbol, _Period, 0) == g_fiboCutProfitArmBar)
      return;

   if(!FiboCutProfitLevelReached())
      return;

   double level50 = FiboChartPrice(InpFiboLevel3);
   Print("Cut profit: pending 78.6 sudah kebuka, harga melewati garis ",
         DoubleToString(InpFiboLevel3, 1), " (", DoubleToString(level50, _Digits),
         "). Tutup semua posisi/order EA.");
   CloseAllPositions();
   CloseAllOrders();
   g_fiboCutProfitArmed = false;
   g_fiboCutProfitArmBar = 0;
}

void CutFiboTrades(const bool isBuy)
{
   int closedPos = 0;
   int deletedOrd = 0;
   string tag = isBuy ? "FiboBuy" : "FiboSell";
   long posType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(PositionGetInteger(POSITION_TYPE) != posType)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), tag) < 0)
         continue;
      if(trade.PositionClose(ticket))
         closedPos++;
      else
         Print("Cut loss gagal close #", ticket, " ", trade.ResultRetcodeDescription());
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), tag) < 0)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool match = false;
      if(isBuy)
         match = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP);
      else
         match = (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP);
      if(!match)
         continue;
      if(trade.OrderDelete(ticket))
         deletedOrd++;
      else
         Print("Cut loss gagal hapus order #", ticket, " ", trade.ResultRetcodeDescription());
   }

   Print("Cut loss ", tag, " selesai. Posisi ditutup: ", closedPos, ", pending dihapus: ", deletedOrd);
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
void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color txtClr) { CreateObject(name, OBJ_BUTTON, 0, x, y, w, h, bg); ObjectSetString(0, PREF+name, OBJPROP_TEXT, text); ObjectSetInteger(0, PREF+name, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, PREF+name, OBJPROP_COLOR, txtClr); }
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
   if(name == PREF+"Skor1") return 75;
   if(name == PREF+"Skor2") return 100;
   if(name == PREF+"Quote1") return 125;
   if(name == PREF+"Quote2") return 150;
   if(name == PREF+"Panel") return UI_Y;
   if(name == PREF+"LblLayers" || name == PREF+"InpLayers" || name == PREF+"BtnLotMode" || name == PREF+"InpLot") return UI_Y + 12;
   if(name == PREF+"LblCalcLot") return UI_Y + 45;
   if(name == PREF+"BtnScanSD" || name == PREF+"BtnDraw") return UI_Y + 80;
   
   string bL[]={"Floor","Entry","Stoploss","TP1","TP2","TP3","Area","Risk"};
   string sL[]={"Ceiling","Entry","Stoploss","TP1","TP2","TP3","Area","Risk"};
   for(int i=0; i<8; i++) {
      if(name == PREF+"LB_"+bL[i] || name == PREF+"Buy_"+bL[i]) return UI_Y + 130 + (i*30);
      if(name == PREF+"LS_"+sL[i] || name == PREF+"Sell_"+sL[i]) return UI_Y + 130 + (i*30);
   }
   
   if(name == PREF+"BtnScanFibo" || name == PREF+"BtnPickFibo" || name == PREF+"BtnPickZzSeg") return UI_Y + 375;
   if(StringFind(name, PREF+"ChkFiboLv") == 0) return UI_Y + 412;
   if(name == PREF+"BtnBuyLFibo" || name == PREF+"BtnSellLFibo") return UI_Y + 453;
   if(name == PREF+"BtnBuyL" || name == PREF+"BtnSellL") return UI_Y + 493;
   if(name == PREF+"DelBuy" || name == PREF+"DelSell") return UI_Y + 533;
   if(name == PREF+"BtnLim382" || name == PREF+"BtnLim50" || name == PREF+"BtnLim618") return UI_Y + 573;
   if(name == PREF+"ClosePos" || name == PREF+"CloseOrd") return UI_Y + 613;
   if(name == PREF+"BuyNow" || name == PREF+"SellNow") return UI_Y + 653;
   if(name == PREF+"Reset" || name == PREF+"GetNews") return UI_Y + 693;
   return UI_Y;
}