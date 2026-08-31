//+------------------------------------------------------------------+
//|                                             SND_Quick_Retest_System.mq5|
//|                                  Copyright 2026, User            |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh> 

//--- Input Parameters
input double InpBasingRatio    = 0.618; // Rasio maksimal body candle untuk Base
input double InpImpulsiveRatio = 0.55; // Rasio minimal body candle untuk Leg In/Out
input int    InpMaxBase     = 13;    // Maksimal candle base berurutan
input bool   InpShowRBR     = true;  // Tampilkan Rally Base Rally
input bool   InpShowDBD     = true;  // Tampilkan Drop Base Drop
input bool   InpShowDBR     = false;  // Tampilkan Drop Base Rally
input bool   InpShowRBD     = false;  // Tampilkan Rally Base Drop
input int InpMaxZones = 10; // Maksimal zona yang ditampilkan

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
input ulong InpMagicNumber = 1111; // Magic Number (Harus beda tiap chart)


CTrade trade;
// Di bagian atas (ubah variabel global menjadi tanpa nilai instan dahulu)
string PREF;
string ZONE_PREF;

bool IsDashboardVisible = true;
bool IsQuoteVisible = true;
bool IsSDScanning = false;
bool IsAutoLot = true;
double g_lastManualLot = 0.01;
double g_lastRiskPct = 1.0;
int UI_Y = 100;      
int HEADER_Y = 50;   
int PANEL_W = 500;   
int PANEL_H = 750;   
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
void PlaceBuyLimit();
void PlaceSellLimit();
void PlaceBuyNow();
void PlaceSellNow();
bool DrawingLinesActive();
double GetDrawnLinePrice(string name);
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

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() 
{ 
   // Membuat nama objek unik, contoh hasil: "SND_55555_"
   PREF = "SNDQR_" + IntegerToString(InpMagicNumber) + "_";
   ZONE_PREF = "SNDQR_Z_" + IntegerToString(InpMagicNumber) + "_";

   IsAutoLot = (InpLotMode == LOT_AUTO_RISK);
   g_lastRiskPct = (InpRiskPercent > 0.0) ? InpRiskPercent : 1.0;
   
   // Mengatur agar setiap kali EA ini mengirim order, Magic Number langsung terpasang otomatis
   trade.SetExpertMagicNumber(InpMagicNumber);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrBlack);
   CreateDashboard(); 

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
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
}

void OnTick() { 
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
      if(sparam == PREF+"Line_Floor" || sparam == PREF+"Line_Ceiling") CalculateAndDrawAll(); 
      ChartRedraw(); 
   }
   
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == PREF+"Hide") { 
         IsDashboardVisible = !IsDashboardVisible; 
         ObjectSetString(0, PREF+"Hide", OBJPROP_TEXT, IsDashboardVisible ? "Hide" : "Show");
         for(int i=0; i<ObjectsTotal(0); i++) { 
            string name = ObjectName(0, i); 
            if(StringFind(name, PREF) == 0 &&
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
      else if(sparam == PREF+"BtnScanSD") { 
         IsSDScanning = !IsSDScanning;
         if(IsSDScanning) { ScanSD(); ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "S&D: ON"); ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrGreen); } 
         else { ObjectsDeleteAll(0, ZONE_PREF); ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "Scan S&D"); ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrDarkGreen); }
         ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_STATE, false); 
      }
      else if(sparam == PREF+"BtnBuyL") { PlaceBuyLimit(); ObjectSetInteger(0, PREF+"BtnBuyL", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnSellL") { PlaceSellLimit(); ObjectSetInteger(0, PREF+"BtnSellL", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BuyNow") { PlaceBuyNow(); ObjectSetInteger(0, PREF+"BuyNow", OBJPROP_STATE, false); }
      else if(sparam == PREF+"SellNow") { PlaceSellNow(); ObjectSetInteger(0, PREF+"SellNow", OBJPROP_STATE, false); }
      else if(sparam == PREF+"DelBuy") { DelPO(ORDER_TYPE_BUY_LIMIT); ObjectSetInteger(0, PREF+"DelBuy", OBJPROP_STATE, false); }
      else if(sparam == PREF+"DelSell") { DelPO(ORDER_TYPE_SELL_LIMIT); ObjectSetInteger(0, PREF+"DelSell", OBJPROP_STATE, false); }
      else if(sparam == PREF+"ClosePos") { CloseAllPositions(); ObjectSetInteger(0, PREF+"ClosePos", OBJPROP_STATE, false); }
      else if(sparam == PREF+"CloseOrd") { CloseAllOrders(); ObjectSetInteger(0, PREF+"CloseOrd", OBJPROP_STATE, false); }
      else if(sparam == PREF+"GetNews") { GetHighImpactUSDNews(); ObjectSetInteger(0, PREF+"GetNews", OBJPROP_STATE, false); }
      else if(sparam == PREF+"Reset") { 
         ObjectsDeleteAll(0, PREF+"Line_"); ObjectsDeleteAll(0, PREF+"Calc_"); ObjectsDeleteAll(0, PREF+"Layer_"); ObjectsDeleteAll(0, ZONE_PREF); 
         IsSDScanning = false; 
         ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "Scan S&D"); ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrDarkGreen);
         if(IsAutoLot && ObjectFind(0, PREF+"LblCalcLot") >= 0)
            ObjectSetString(0, PREF+"LblCalcLot", OBJPROP_TEXT, "Lot/layer: (draw line)");
         ChartRedraw(); 
         ObjectSetInteger(0, PREF+"Reset", OBJPROP_STATE, false); 
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
      DrawNativeLabel(labelName, newsText, 20, 740 + (i * 18), clrRed);
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

   CalculateAndDrawAll();

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = GetInputValue("Buy_Stoploss");
   double tp = GetDrawnLinePrice(PREF+"Calc_B_TP5");

   if(sl <= 0.0 || sl >= entry || tp <= entry) {
      Print("Buy Now: butuh SL < Entry < TP5. SL=", sl, " Entry=", entry, " TP=", tp);
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
      Print("Buy Now: Lot=", lot, ", SL=", sl, ", TP5=", tp);
   else
      Print("Failed to execute Buy order. Error: ", GetLastError());
}

void PlaceSellNow() {
   if(!DrawingLinesActive()) {
      Print("Sell Now: drawing line belum aktif. Klik Draw Line dulu.");
      return;
   }

   CalculateAndDrawAll();

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = GetInputValue("Sell_Stoploss");
   double tp = GetDrawnLinePrice(PREF+"Calc_S_TP5");

   if(sl <= entry || tp >= entry || tp <= 0.0) {
      Print("Sell Now: butuh TP5 < Entry < SL. SL=", sl, " Entry=", entry, " TP=", tp);
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
      Print("Sell Now: Lot=", lot, ", SL=", sl, ", TP5=", tp);
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
   CreateLabel("Title", (PANEL_W / 2) + 20, HEADER_Y + 2, "SND Quick Retest", clrWhite);
   CreateObject("Panel", OBJ_RECTANGLE_LABEL, 0, 10, UI_Y, PANEL_W, PANEL_H, clrDarkSlateGray);
   
   CreateLabel("LblLayers", 20, UI_Y+12, "Layers", clrOrange); CreateEdit("InpLayers", 130, UI_Y+18, 100, 25, "1");
   CreateButton("BtnLotMode", 260, UI_Y+12, 100, 25, "Lot", clrDarkSlateGray, clrOrange);
   CreateEdit("InpLot", 370, UI_Y+18, 100, 25, "1.00");
   CreateCalcLotLabel();
   ApplyLotModeUI();
   
   CreateButton("BtnDraw", 20, UI_Y+80, 180, 30, "Draw Line", clrPurple, clrWhite);
   CreateButton("BtnScanSD", 270, UI_Y+80, 180, 30, "Scan S&D", clrDarkGreen, clrWhite);
   
   string bL[]={"Floor","Entry","Stoploss","TP1","TP2","TP3","Area","Risk"}; 
   string sL[]={"Ceiling","Entry","Stoploss","TP1","TP2","TP3","Area","Risk"};
   for(int i=0; i<8; i++) {
      CreateLabel("LB_"+bL[i], 20, UI_Y+130+(i*30), bL[i], clrOrange); CreateEdit("Buy_"+bL[i], 130, UI_Y+134+(i*30), 110, 25, "0.00");
      CreateLabel("LS_"+sL[i], 270, UI_Y+130+(i*30), sL[i], clrOrange); CreateEdit("Sell_"+sL[i], 370, UI_Y+134+(i*30), 110, 25, "0.00");
   }
   CreateButton("BtnBuyL", 20, UI_Y + 400, 200, 30, "Buy Limit", clrBlue, clrWhite);
   CreateButton("BtnSellL", 270, UI_Y + 400, 200, 30, "Sell Limit", clrOrange, clrWhite);
   CreateButton("DelBuy", 20, UI_Y + 440, 200, 30, "Del Buy", clrBlue, clrWhite);
   CreateButton("DelSell", 270, UI_Y + 440, 200, 30, "Del Sell", clrBrown, clrWhite);
   CreateButton("ClosePos", 20, UI_Y + 480, PANEL_W-40, 30, "Close Positions", clrDarkRed, clrWhite);
   CreateButton("CloseOrd", 20, UI_Y + 520, PANEL_W-40, 30, "Close All Orders", clrMaroon, clrWhite);
   CreateButton("BuyNow", 20, UI_Y + 560, 200, 30, "Buy Now", clrDodgerBlue, clrWhite);
   CreateButton("SellNow", 270, UI_Y + 560, 200, 30, "Sell Now", clrOrangeRed, clrWhite);
   CreateButton("GetNews", 20, UI_Y + 600, 200, 30, "Get News", clrGray, clrBlack);
   CreateButton("Reset", 270, UI_Y + 600, 200, 30, "Reset", clrGray, clrBlack);
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
   ObjectSetInteger(0, "GetNews", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "Reset", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan


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
   if(name == PREF+"Reset" || name == PREF+"GetNews") return UI_Y + 600;
   return UI_Y;
}