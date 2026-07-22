//+------------------------------------------------------------------+
//|                                              Pivot_Trading_System.mq5|
//|                                  Copyright 2026, User            |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh> 

//--- Input Parameters
input double InpBasingRatio = 0.618; // Rasio maksimal body candle untuk dianggap Base
input int    InpMaxBase     = 13;    // Maksimal candle base berurutan
input bool   InpShowRBR     = true;  // Tampilkan Rally Base Rally
input bool   InpShowDBD     = true;  // Tampilkan Drop Base Drop
input bool   InpShowDBR     = false;  // Tampilkan Drop Base Rally
input bool   InpShowRBD     = false;  // Tampilkan Rally Base Drop
input int InpMaxZones = 20; // Maksimal zona yang ditampilkan

input group "--- MULTI EMA SETTINGS ---"
input bool   InpShowMultiEMA = true;        // Show Multi EMA (200, 100, 50, 20)
input color  clrEMA200       = clrBlack;      // Warna EMA 200
input color  clrEMA100       = clrOrange;   // Warna EMA 100
input color  clrEMA50        = clrRed;     // Warna EMA 50
input color  clrEMA20        = clrDarkGreen; // Warna EMA 20

input group "--- NEWS FILTER SETTINGS ---"
input bool InpShowNews = true; // Tampilkan Berita USD High Impact

// Struktur untuk menyimpan data berita yang sudah disaring
struct USDNewsData {
   datetime time;
   string   name;
};

USDNewsData listNews[3]; // Maksimal menampung 3 berita terdekat

// Variabel global untuk menyimpan handle indikator MT5
int handleMultiEMA;
input group "--- RISK & TRANSMISSION ---"
input ulong InpMagicNumber = 11111; // Magic Number (Harus beda tiap chart)


CTrade trade;
// Di bagian atas (ubah variabel global menjadi tanpa nilai instan dahulu)
string PREF;
string ZONE_PREF;

bool IsDashboardVisible = true;
bool IsQuoteVisible = true;
bool IsSDScanning = false;
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
void CheckCutLoss();
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

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() 
{ 
   // Membuat nama objek unik, contoh hasil: "PAC_12345_"
   PREF = "PIVOT_" + IntegerToString(InpMagicNumber) + "_";
   ZONE_PREF = "PIVOT_Z_" + IntegerToString(InpMagicNumber) + "_";
   
   // Mengatur agar setiap kali EA ini mengirim order, Magic Number langsung terpasang otomatis
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // --- KUNCI SOLUSI PERMANEN: Memanggil Indikator Pembantu Sambil Mengirim Data Warna ---
   handleMultiEMA = iCustom(_Symbol, _Period, "MultiEMA", 
                            clrEMA200, 
                            clrEMA100, 
                            clrEMA50, 
                            clrEMA20);
   
   // Jika user memilih TRUE, langsung tempel ke chart utama
   if(InpShowMultiEMA && handleMultiEMA != INVALID_HANDLE)
   {
      ChartIndicatorAdd(0, 0, handleMultiEMA);
   }
   
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrLightGray);
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
   // --- KUNCI: Matikan timer saat EA dilepas ---
   EventKillTimer();
   
   // Hapus semua objek garis EMA saat EA dimatikan/dilepas dari chart
   string name200 = PREF + "EMA_200";
   string name100 = PREF + "EMA_100";
   string name50  = PREF + "EMA_50";
   string name20  = PREF + "EMA_20";
   
   // Bersihkan handle indikator kustom dari chart
   if(handleMultiEMA != INVALID_HANDLE)
   {
      IndicatorRelease(handleMultiEMA);
   }
   
   ObjectsDeleteAll(0, PREF); 
   ObjectsDeleteAll(0, ZONE_PREF); // Menghapus semua kotak dan tombol S&D sekaligus
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
}

void OnTick() { 
   // CADANGAN: Jika OnTimer macet, jam akan tetap terupdate setiap kali ada tick harga baru
   datetime serverTime = TimeCurrent();
   string liveClock = TimeToString(serverTime, TIME_MINUTES | TIME_SECONDS);
   DrawNativeLabel(PREF + "Live_Clock", "Server Time: " + liveClock, (PANEL_W + 20), 50, clrBlack);
   DrawNativeLabel(PREF + "Quote", "Re-Entry di Area yang sama Maksimal 3x Pantulan", (PANEL_W + 20), 75, clrBlack);
   DrawNativeLabel(PREF + "Quote2", "Jam Trading: 05-08 WIB, 16-19 WIB", (PANEL_W + 20), 100, clrBlack);
   ApplyQuoteVisibility();
   
   CheckCutLoss(); 

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
   // Matikan timer agar fungsi ini hanya berjalan 1x saat start
   EventKillTimer();
   
   // Ambil total indikator yang ada di subwindow 0 (Chart Utama)
   int totalIndicators = ChartIndicatorsTotal(0, 0);
   
   for(int i = 0; i < totalIndicators; i++)
   {
      string shortName = ChartIndicatorName(0, 0, i);
      
      // Cari nama indikator bawaan MA berdasarkan periodenya
      if(StringFind(shortName, "EMA(200)") >= 0 || StringFind(shortName, "Moving Average(200)") >= 0)
         ObjectSetInteger(0, shortName, OBJPROP_COLOR, clrEMA200);
         
      else if(StringFind(shortName, "EMA(100)") >= 0 || StringFind(shortName, "Moving Average(100)") >= 0)
         ObjectSetInteger(0, shortName, OBJPROP_COLOR, clrEMA100);
         
      else if(StringFind(shortName, "EMA(50)") >= 0 || StringFind(shortName, "Moving Average(50)") >= 0)
         ObjectSetInteger(0, shortName, OBJPROP_COLOR, clrEMA50);
         
      else if(StringFind(shortName, "EMA(20)") >= 0 || StringFind(shortName, "Moving Average(20)") >= 0)
         ObjectSetInteger(0, shortName, OBJPROP_COLOR, clrEMA20);
   }
   
   // 1. UPDATE JAM DIGITAL (Berjalan murni setiap 1 detik)
   datetime serverTime = TimeCurrent(); // Gunakan TimeCurrent agar singkron dengan market, atau TimeLocal() untuk jam PC
   string liveClock = TimeToString(serverTime, TIME_MINUTES | TIME_SECONDS);
   
   DrawNativeLabel(PREF + "Live_Clock", "Server Time: " + liveClock, 20, 25, clrBlack);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Event Handling                                                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_DRAG) { 
      if(sparam == PREF+"Line_Floor" || sparam == PREF+"Line_Ceiling") CalculateAndDrawAll(); 
      ChartRedraw(); 
   }
   
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // --- LOGIKA KLIK UTAMA DASHBOARD ---
      if(sparam == PREF+"Hide") { 
         IsDashboardVisible = !IsDashboardVisible; 
         ObjectSetString(0, PREF+"Hide", OBJPROP_TEXT, IsDashboardVisible ? "Hide" : "Show");
         for(int i=0; i<ObjectsTotal(0); i++) { 
            string name = ObjectName(0, i); 
            if(StringFind(name, PREF) == 0 &&
               name != PREF+"Hide" &&
               name != PREF+"HideQuote" &&
               name != PREF+"Live_Clock" &&
               name != PREF+"Quote" &&
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
      else if(sparam == PREF+"BtnDraw") { CreateDrawingLines(); CalculateAndDrawAll(); ObjectSetInteger(0, PREF+"BtnDraw", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnScanSD") { 
         IsSDScanning = !IsSDScanning;
         if(IsSDScanning) {
            ScanSD();
            ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "S&D: ON");
            ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrGreen);
         } else {
            ObjectsDeleteAll(0, ZONE_PREF);
            ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "Scan S&D");
            ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrDarkGreen);
         }
         ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_STATE, false); 
      }
      // --- MODIFIKASI FILTER MAGIC NUMBER PADA TOMBOL TRANSAKSI ---
      else if(sparam == PREF+"BtnBuyL")  { PlaceBuyLimit(); ObjectSetInteger(0, PREF+"BtnBuyL", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnSellL") { PlaceSellLimit(); ObjectSetInteger(0, PREF+"BtnSellL", OBJPROP_STATE, false); }
      
      else if(sparam == PREF+"DelBuy") { 
         // PENTING: Fungsi DelPO Anda harus diubah agar menerima parameter Magic Number
         DelPO(ORDER_TYPE_BUY_LIMIT, InpMagicNumber); 
         ObjectSetInteger(0, PREF+"DelBuy", OBJPROP_STATE, false); 
      }
      else if(sparam == PREF+"DelSell") { 
         DelPO(ORDER_TYPE_SELL_LIMIT, InpMagicNumber); 
         ObjectSetInteger(0, PREF+"DelSell", OBJPROP_STATE, false); 
      }
      else if(sparam == PREF+"ClosePos") { 
         // PENTING: Fungsi Close All harus difilter berdasarkan Magic Number chart ini
         CloseAllPositions(InpMagicNumber); 
         ObjectSetInteger(0, PREF+"ClosePos", OBJPROP_STATE, false); 
      }
      else if(sparam == PREF+"CloseOrd") { 
         CloseAllOrders(InpMagicNumber); 
         ObjectSetInteger(0, PREF+"CloseOrd", OBJPROP_STATE, false); 
      }
      else if(sparam == PREF+"Reset") { 
         ObjectsDeleteAll(0, PREF+"Line_"); ObjectsDeleteAll(0, PREF+"Calc_"); ObjectsDeleteAll(0, PREF+"Layer_"); ObjectsDeleteAll(0, ZONE_PREF); 
         IsSDScanning = false; 
         ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "Scan S&D"); 
         ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrDarkGreen);
         ChartRedraw(); 
         ObjectSetInteger(0, PREF+"Reset", OBJPROP_STATE, false); 
      }
      else if(sparam == PREF+"BuyNow") { PlaceBuyNow(); ObjectSetInteger(0, PREF+"BuyNow", OBJPROP_STATE, false); }
      else if(sparam == PREF+"SellNow") { PlaceSellNow(); ObjectSetInteger(0, PREF+"SellNow", OBJPROP_STATE, false); }
      
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
            
            // Mengamankan penentuan Distal Line agar tidak terbalik antara Index 0 dan 1
            double distalLow  = MathMin(price1, price2);
            double distalHigh = MathMax(price1, price2);
            
            // Jika Demand (RBR/DBR), pindahkan garis Floor ke area bawah (distalLow)
            if(StringFind(sparam, "_RBR_") >= 0 || StringFind(sparam, "_DBR_") >= 0) {
               ObjectSetDouble(0, PREF+"Line_Floor", OBJPROP_PRICE, distalLow);
            }
            // Jika Supply (DBD/RBD), pindahkan garis Ceiling ke area atas (distalHigh)
            else if(StringFind(sparam, "_DBD_") >= 0 || StringFind(sparam, "_RBD_") >= 0) {
               ObjectSetDouble(0, PREF+"Line_Ceiling", OBJPROP_PRICE, distalHigh);
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
}

void UpdateDashboard()
{
   // 1. Ambil nilai harga dari input/dashboard Anda (Sesuaikan fungsinya jika berbeda)
   double bFloor   = GetInputValue("Buy_Floor");
   double bEntry   = GetInputValue("Buy_Entry");
   double sCeiling = GetInputValue("Sell_Ceiling");
   double sEntry   = GetInputValue("Sell_Entry");
   
   // Kalkulasi ukuran pips dinamis aman 4/5 digit broker
   double pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
   if(pipSize == 0) pipSize = 0.1;

   double buyPips  = (bFloor > 0 && bEntry > 0) ? MathAbs(bFloor - bEntry) / pipSize : 0.0;
   double sellPips = (sCeiling > 0 && sEntry > 0) ? MathAbs(sCeiling - sEntry) / pipSize : 0.0;

   // --- [RENDER KODE DASHBOARD UTAMA ANDA SEBELUMNYA DI SINI] ---
   // Atur agar Z_ORDER tombol dashboard Anda bernilai tinggi (misal: 10) agar anti-terhalang kotak S&D
   // ObjectSetInteger(0, nama_tombol, OBJPROP_ZORDER, 10);
   

   // 2. RENDER BARIS BARU: AREA WIDTH PIPS (Di bawah TP)
   string buyPipsText  = "Area Width: " + DoubleToString(buyPips, 1) + " Pips";
   string sellPipsText = "Area Width: " + DoubleToString(sellPips, 1) + " Pips";
   
   // Gunakan fungsi native agar anti-error token
   DrawNativeLabel(PREF + "Lbl_Buy_Area_Width", buyPipsText, 20, 140, clrDarkSlateGray); 
   DrawNativeLabel(PREF + "Lbl_Sell_Area_Width", sellPipsText, 160, 140, clrDarkSlateGray); // Sesuaikan X untuk kolom sell


   // 3. RENDER DATA BERITA HIGH IMPACT USD (Maksimal 3 Baris)
   GetHighImpactUSDNews();

   DrawNativeLabel(PREF + "Lbl_News_Header", "=== TODAY'S HIGH USD NEWS ===", 20, 720, clrRed);

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

// --- FUNGSI SEARCH BERITA USD HIGH IMPACT (VERSI 100% UNIVERSAL & ANTI-ERROR) ---
void GetHighImpactUSDNews()
{
   // 1. Kosongkan data lama
   for(int k=0; k<3; k++) { listNews[k].time = 0; listNews[k].name = ""; }
   if(!InpShowNews) return;

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
}

// --- SHOW / HIDE QUOTE LABELS ---
void ApplyQuoteVisibility()
{
   int yQuote  = IsQuoteVisible ? 75  : UI_OFFSCREEN;
   int yQuote2 = IsQuoteVisible ? 100 : UI_OFFSCREEN;

   if(ObjectFind(0, PREF + "Quote")  >= 0) ObjectSetInteger(0, PREF + "Quote",  OBJPROP_YDISTANCE, yQuote);
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
            
            string type = "";
            bool shouldDraw = false;

            if(legInUp && legOutUp)   { type = "RBR"; shouldDraw = InpShowRBR; }
            if(!legInUp && !legOutUp) { type = "DBD"; shouldDraw = InpShowDBD; }
            if(!legInUp && legOutUp)  { type = "DBR"; shouldDraw = InpShowDBR; }
            if(legInUp && !legOutUp)  { type = "RBD"; shouldDraw = InpShowRBD; }

            if(!shouldDraw) continue;

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
   UpdateDashboard();
}

bool IsImpulsive(int idx) { 
   double body = MathAbs(iClose(_Symbol, _Period, idx) - iOpen(_Symbol, _Period, idx)); 
   double range = MathAbs(iHigh(_Symbol, _Period, idx) - iLow(_Symbol, _Period, idx)); 
   return (body > (range * InpBasingRatio)); 
}

bool IsBasing(int idx) { 
   double body = MathAbs(iClose(_Symbol, _Period, idx) - iOpen(_Symbol, _Period, idx)); 
   double range = MathAbs(iHigh(_Symbol, _Period, idx) - iLow(_Symbol, _Period, idx)); 
   return (body <= (range * InpBasingRatio)); 
}

// --- Logic Trading ---
void PlaceBuyLimit()
{
   // Pastikan objek trade menggunakan magic number chart ini sebelum mengeksekusi buy limit
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   int layers = (int)GetInputValue("InpLayers");
   double lot = GetInputValue("InpLot");
   double entry = GetInputValue("Buy_Entry");
   double floor = GetInputValue("Buy_Floor");
   double sl = GetInputValue("Buy_Stoploss");
   double tp = GetInputValue("Sell_Entry");
   if(entry == 0 || floor == 0 || lot == 0) return;
   double step = (layers > 1) ? (entry - floor) / (layers - 1) : 0;
   for(int i=0; i<layers; i++) trade.BuyLimit(lot, NormalizeDouble(entry - (step * i), _Digits), _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Buy L"+IntegerToString(i+1));
}

void PlaceSellLimit()
{
   // Pastikan objek trade menggunakan magic number chart ini sebelum mengeksekusi buy limit
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   int layers = (int)GetInputValue("InpLayers");
   double lot = GetInputValue("InpLot");
   double entry = GetInputValue("Sell_Entry");
   double ceiling = GetInputValue("Sell_Ceiling");
   double sl = GetInputValue("Sell_Stoploss");
   double tp = GetInputValue("Buy_Entry");
   if(entry == 0 || ceiling == 0 || lot == 0) return;
   double step = (layers > 1) ? (ceiling - entry) / (layers - 1) : 0;
   for(int i=0; i<layers; i++) trade.SellLimit(lot, NormalizeDouble(entry + (step * i), _Digits), _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Sell L"+IntegerToString(i+1));
}

void PlaceBuyNow() { trade.Buy(GetInputValue("InpLot")); }
void PlaceSellNow() { trade.Sell(GetInputValue("InpLot")); }

void CheckCutLoss()
{
   double bCL = GetInputValue("Buy_CutLoss");
   double sCL = GetInputValue("Sell_CutLoss");
   double bFloor = GetInputValue("Buy_Floor");
   double sCeiling = GetInputValue("Sell_Ceiling");
   double bEntry = GetInputValue("Buy_Entry");
   double sEntry = GetInputValue("Sell_Entry");
   double tp = GetInputValue("Buy_TP");
   
   // MENGGUNAKAN CLOSE CANDLE (Index 1 = Candle yang baru saja selesai/Close)
   double lastClose = iClose(_Symbol, _Period, 1);
   
   double closePrice = iClose(_Symbol, _Period, 0); // Menggunakan harga running saat ini
   
   // --- LOGIKA BUY ---
   // 1. Cut Loss Standar (Jika harga tembus ke bawah CutLoss Line) - Menyertakan InpMagicNumber
   if(bCL > 0 && lastClose < bCL) { 
      ClosePositionsByType(POSITION_TYPE_BUY, InpMagicNumber); 
   }
   // 2. Cut Profit/BEP (Jika harga sudah menyentuh Floor, lalu balik ke Entry awal)
   static bool buyFloorTouched = false;
   if(closePrice <= bFloor && bFloor > 0) buyFloorTouched = true; 
   
   if(buyFloorTouched && closePrice >= tp) {
      ClosePositionsByType(POSITION_TYPE_BUY, InpMagicNumber);
      buyFloorTouched = false; // Reset flag setelah close
   }

   // --- LOGIKA SELL ---
   // 1. Cut Loss Standar (Jika harga tembus ke atas CutLoss Line) - Menyertakan InpMagicNumber
   if(sCL > 0 && lastClose > sCL) { 
      ClosePositionsByType(POSITION_TYPE_SELL, InpMagicNumber); 
   }
   // 2. Cut Profit/BEP (Jika harga sudah menyentuh Ceiling, lalu balik ke Entry awal)
   static bool sellCeilingTouched = false;
   if(closePrice >= sCeiling && sCeiling > 0) sellCeilingTouched = true;
   
   if(sellCeilingTouched && closePrice <= tp) {
      ClosePositionsByType(POSITION_TYPE_SELL, InpMagicNumber);
      sellCeilingTouched = false; // Reset flag setelah close
   }
   
   // --- PERBAIKAN RESET FLAG MULTI-CHART ---
   // Menghitung total posisi hanya yang berasal dari Magic Number chart ini saja
   int activePositionsThisChart = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            activePositionsThisChart++;
         }
      }
   }
   
   // Reset flag jika khusus chart dengan Magic Number ini tidak punya posisi lagi
   if(activePositionsThisChart == 0) {
      buyFloorTouched = false;
      sellCeilingTouched = false;
   }
}

// Helper function untuk merapikan kode closing (Sudah di-filter Magic Number)
void ClosePositionsByType(ENUM_POSITION_TYPE type, ulong magic) {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t)) {
         // Validasi tiga lapis: Tipe Posisi cocok, Symbol cocok, DAN Magic Number cocok
         if(PositionGetInteger(POSITION_TYPE) == type && 
            PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == magic) {
            
            trade.PositionClose(t);
         }
      }
   }
}

void CalculateAndDrawAll()
{
   if(ObjectFind(0, PREF+"Line_Floor") < 0 || ObjectFind(0, PREF+"Line_Ceiling") < 0) return;
   double pFloor = ObjectGetDouble(0, PREF+"Line_Floor", OBJPROP_PRICE);
   double pCeiling = ObjectGetDouble(0, PREF+"Line_Ceiling", OBJPROP_PRICE);
   int layers = (int)GetInputValue("InpLayers");
   double range = MathAbs(pCeiling - pFloor);
   ObjectsDeleteAll(0, PREF+"Layer_"); ObjectsDeleteAll(0, PREF+"Calc_");
   double tp = pFloor + 0.5 * range;
   double bEntry = pFloor + 0.24 * range; double bSL = pFloor - 0.08 * range; double bCL = pFloor - 0.16 * range; 
   double sEntry = pCeiling - 0.24 * range; double sSL = pCeiling + 0.08 * range; double sCL = pCeiling + 0.16 * range;
   
   double stepB = (layers > 1) ? (bEntry - pFloor) / (layers - 1) : 0;
   for(int i=0; i<layers; i++) UpdateLine(PREF+"Layer_Buy_"+IntegerToString(i), bEntry - (stepB * i), clrBlue);
   double stepS = (layers > 1) ? (pCeiling - sEntry) / (layers - 1) : 0;
   for(int i=0; i<layers; i++) UpdateLine(PREF+"Layer_Sell_"+IntegerToString(i), sEntry + (stepS * i), clrRed);
   
   UpdateLine(PREF+"Calc_TP", tp, clrDarkGreen);
   UpdateLine(PREF+"Calc_B_SL", bSL, clrBlue); UpdateLine(PREF+"Calc_B_CL", bCL, clrDarkBlue);
   UpdateLine(PREF+"Calc_S_SL", sSL, clrRed); UpdateLine(PREF+"Calc_S_CL", sCL, clrDarkRed);
   
   UpdateInput("Buy_Floor", pFloor); UpdateInput("Buy_Entry", bEntry); UpdateInput("Buy_Stoploss", bSL); UpdateInput("Buy_CutLoss", bCL); UpdateInput("Buy_TP", tp);
   UpdateInput("Sell_Ceiling", pCeiling); UpdateInput("Sell_Entry", sEntry); UpdateInput("Sell_Stoploss", sSL); UpdateInput("Sell_CutLoss", sCL); UpdateInput("Sell_TP", tp);
   
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
}

void CreateDashboard() {
   CreateObject("HdrPanel", OBJ_RECTANGLE_LABEL, 0, 10, HEADER_Y, PANEL_W, 40, clrBlack);
   ObjectSetInteger(0, PREF+"HdrPanel", OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, PREF+"HdrPanel", OBJPROP_BORDER_TYPE, BORDER_SUNKEN);
   
   CreateButton("Hide", 15, HEADER_Y + 7, 65, 25, "Hide", clrGray, clrWhite);
   CreateButton("HideQuote", 85, HEADER_Y + 7, 90, 25, "Hide Q", clrGray, clrWhite);
   
   int titleCenterX = (PANEL_W / 2) + 20; 
   CreateLabel("Title", titleCenterX, HEADER_Y + 2, "Pivot in Control", clrWhite); 
   ObjectSetInteger(0, PREF+"Title", OBJPROP_FONTSIZE, 12);
   ObjectSetString(0, PREF+"Title", OBJPROP_FONT, "Arial Bold");
   
   CreateObject("Panel", OBJ_RECTANGLE_LABEL, 0, 10, UI_Y, PANEL_W, PANEL_H, clrDarkSlateGray);
   ObjectSetInteger(0, PREF+"Panel", OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, PREF+"Panel", OBJPROP_BORDER_TYPE, BORDER_SUNKEN);
   
   int sellColumnX = 270;
   int editW = 120;
   
   CreateLabel("LblLayers", 20, UI_Y+12, "Layers:", clrOrange);
   CreateEdit("InpLayers", 130, UI_Y+18, editW, 25, "1");
   
   CreateLabel("LblLot", sellColumnX, UI_Y+12, "Lot/Lyr:", clrOrange);
   CreateEdit("InpLot", sellColumnX + 110, UI_Y+18, editW, 25, "0.01");
   
   CreateButton("BtnDraw", 20, UI_Y+80, 230, 30, "Draw Line", clrPurple, clrWhite);
   CreateButton("BtnScanSD", sellColumnX, UI_Y+80, 230, 30, "Scan S&D", clrDarkGreen, clrWhite);
   
   CreateLabel("HdrBuy", 20, UI_Y + 130, "--- Buy Limit ---", clrOrange);
   CreateLabel("HdrSell", sellColumnX, UI_Y + 130, "--- Sell Limit ---", clrOrange);
   
   string bLabels[]={"Floor","Entry","Stoploss","CutLoss","TP","Area"};
   string sLabels[]={"Ceiling","Entry","Stoploss","CutLoss","TP","Area"};
   
   for(int i=0; i<6; i++) {
      int rowY = UI_Y + 165 + (i * 30);
      int editY = rowY + 4;
      
      CreateLabel("LB_"+bLabels[i], 20, rowY, bLabels[i], clrOrange);
      CreateEdit("Buy_"+bLabels[i], 130, editY, editW, 25, "0.00");
      
      CreateLabel("LS_"+sLabels[i], sellColumnX, rowY, sLabels[i], clrOrange);
      CreateEdit("Sell_"+sLabels[i], sellColumnX + 110, editY, editW, 25, "0.00");
   }
   
   CreateButton("BtnBuyL", 20, UI_Y + 370, 230, 30, "Buy Limit", clrBlue, clrWhite);
   CreateButton("BtnSellL", sellColumnX, UI_Y + 370, 230, 30, "Sell Limit", clrOrange, clrWhite);
   
   CreateButton("DelBuy", 20, UI_Y + 410, 230, 30, "Del Buy", clrBlue, clrWhite);
   CreateButton("DelSell", sellColumnX, UI_Y + 410, 230, 30, "Del Sell", clrBrown, clrWhite);
   
   CreateButton("ClosePos", 20, UI_Y + 450, PANEL_W-20, 30, "Close Positions", clrDarkRed, clrWhite);
   CreateButton("CloseOrd", 20, UI_Y + 490, PANEL_W-20, 30, "Close All Orders", clrMaroon, clrWhite);
   CreateButton("Reset", 20, UI_Y + 530, PANEL_W-20, 30, "ResetLines & Calc", clrGray, clrBlack);
   CreateButton("BuyNow", 20, UI_Y + 570, 230, 30, "Buy Now", clrDodgerBlue, clrWhite);
   CreateButton("SellNow", sellColumnX, UI_Y + 570, 230, 30, "Sell Now", clrOrangeRed, clrWhite);
   
   // Tambahkan ini di setiap fungsi pembuatan tombol/label dashboard Anda
   ObjectSetInteger(0, "BtnBuyL", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "BtnSellL", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "DelBuy", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "DelSell", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "ClosePos", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "CloseOrd", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "Reset", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "BuyNow", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
   ObjectSetInteger(0, "SellNow", OBJPROP_ZORDER, 10); // Angka 10 memastikan dashboard berada di paling depan
}

void CreateDrawingLines() { 
   double p=SymbolInfoDouble(_Symbol, SYMBOL_BID); 
   ObjectCreate(0, PREF+"Line_Floor", OBJ_HLINE, 0, 0, p-200*_Point); 
   ObjectSetInteger(0, PREF+"Line_Floor", OBJPROP_SELECTABLE, true); 
   ObjectSetInteger(0, PREF+"Line_Floor", OBJPROP_SELECTED, true);
   ObjectSetInteger(0, PREF+"Line_Floor", OBJPROP_COLOR, clrBlue);
   ObjectSetInteger(0, PREF+"Line_Floor", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, PREF+"Line_Floor", OBJPROP_WIDTH, 2);
   
   ObjectCreate(0, PREF+"Line_Ceiling", OBJ_HLINE, 0, 0, p+200*_Point); 
   ObjectSetInteger(0, PREF+"Line_Ceiling", OBJPROP_SELECTABLE, true); 
   ObjectSetInteger(0, PREF+"Line_Ceiling", OBJPROP_SELECTED, true);
   ObjectSetInteger(0, PREF+"Line_Ceiling", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, PREF+"Line_Ceiling", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, PREF+"Line_Ceiling", OBJPROP_WIDTH, 2);
   ChartRedraw();
}

double GetInputValue(string name) { return StringToDouble(ObjectGetString(0, PREF+name, OBJPROP_TEXT)); }
void UpdateLine(string name, double price, color clr) { if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, price); ObjectSetDouble(0, name, OBJPROP_PRICE, price); ObjectSetInteger(0, name, OBJPROP_COLOR, clr); ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT); }
void UpdateInput(string name, double price) { ObjectSetString(0, PREF+name, OBJPROP_TEXT, DoubleToString(price, _Digits)); }
void CreateObject(string name, ENUM_OBJECT type, int win, int x, int y, int w, int h, color clr) { ObjectCreate(0, PREF+name, type, win, 0, 0); ObjectSetInteger(0, PREF+name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, PREF+name, OBJPROP_YDISTANCE, y); ObjectSetInteger(0, PREF+name, OBJPROP_XSIZE, w); ObjectSetInteger(0, PREF+name, OBJPROP_YSIZE, h); }
void CreateLabel(string name, int x, int y, string text, color clr) { CreateObject(name, OBJ_LABEL, 0, x, y, 0, 0, clr); ObjectSetString(0, PREF+name, OBJPROP_TEXT, text); ObjectSetString(0, PREF+name, OBJPROP_FONT, "Arial"); }
void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color txtClr) { CreateObject(name, OBJ_BUTTON, 0, x, y, w, h, bg); ObjectSetString(0, PREF+name, OBJPROP_TEXT, text); ObjectSetInteger(0, PREF+name, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, PREF+name, OBJPROP_COLOR, txtClr); ObjectSetString(0, PREF+name, OBJPROP_FONT, "Arial Bold"); }
void CreateEdit(string name, int x, int y, int w, int h, string val) { 
   CreateObject(name, OBJ_EDIT, 0, x, y, w, h, clrWhite); 
   ObjectSetString(0, PREF+name, OBJPROP_TEXT, val); 
   ObjectSetInteger(0, PREF+name, OBJPROP_BGCOLOR, clrWhite); 
   ObjectSetInteger(0, PREF+name, OBJPROP_COLOR, clrBlack);   
   ObjectSetString(0, PREF+name, OBJPROP_FONT, "Consolas"); 
}
// KODE BARU: Menambahkan parameter ulong magic dengan nilai default
void DelPO(ENUM_ORDER_TYPE type, ulong magic = 0)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            // Saring berdasarkan tipe order dan Magic Number chart aktif
            if(OrderGetInteger(ORDER_TYPE) == type && OrderGetInteger(ORDER_MAGIC) == magic)
            {
               // trade adalah nama objek CTrade bawaan EA Anda
               trade.OrderDelete(ticket); 
            }
         }
      }
   }
}
// Contoh modifikasi fungsi Close Position agar hanya menutup milik chart aktif
void CloseAllPositions(ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         // Saring berdasarkan Magic Number
         if(PositionGetInteger(POSITION_MAGIC) == magic)
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            trade.PositionClose(ticket); // trade adalah object dari CTrade
         }
      }
   }
}

// --- PERBAIKAN TOTAL: FUNGSI HAPUS SEMUA PENDING ORDER BERDASARKAN MAGIC NUMBER ---
void CloseAllOrders(ulong magic)
{
   // Lakukan loop mundur dari order paling akhir ke awal
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      // 1. Ambil ticket order berdasarkan posisinya di daftar antrean
      ulong ticket = OrderGetTicket(i);
      
      if(ticket > 0)
      {
         // 2. Wajib gunakan OrderSelect() atau ambil data via properti ticket di MT5
         string orderSymbol = OrderGetString(ORDER_SYMBOL);
         ulong  orderMagic  = OrderGetInteger(ORDER_MAGIC);
         long   orderType   = OrderGetInteger(ORDER_TYPE);
         
         // 3. Pastikan hanya menghapus order yang sesuai dengan Symbol dan Magic Number chart ini
         if(orderSymbol == _Symbol && orderMagic == magic)
         {
            // 4. Filter ekstra: Pastikan yang dihapus adalah LIMIT ORDER (bukan posisi running)
            if(orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_SELL_LIMIT ||
               orderType == ORDER_TYPE_BUY_STOP  || orderType == ORDER_TYPE_SELL_STOP)
            {
               // trade adalah objek CTrade bawaan EA Anda
               trade.OrderDelete(ticket);
            }
         }
      }
   }
}

int GetInitialY(string name) {
   if(StringFind(name, "HdrPanel") != -1) return HEADER_Y;
   if(StringFind(name, "HideQuote") != -1 || name == PREF+"Hide") return HEADER_Y + 7;
   if(StringFind(name, "Title") != -1) return HEADER_Y + 2; 
   if(StringFind(name, "Panel") != -1) return UI_Y;
   if(StringFind(name, "LblLayers") != -1 || StringFind(name, "InpLayers") != -1 || StringFind(name, "LblLot") != -1 || StringFind(name, "InpLot") != -1) return UI_Y + 18;
   if(StringFind(name, "BtnDraw") != -1 || StringFind(name, "BtnScanSD") != -1) return UI_Y + 80;
   if(StringFind(name, "HdrBuy") != -1 || StringFind(name, "HdrSell") != -1) return UI_Y + 130;
   string keywords[] = {"Floor", "Ceiling", "Entry", "Stoploss", "CutLoss", "TP", "Area"};
   int rows[]        = { 0,       0,         1,       2,          3,         4,         5     };
   for(int i=0; i<7; i++) {
      if(StringFind(name, keywords[i]) != -1) return UI_Y + 165 + (rows[i] * 30);
   }
   if(StringFind(name, "BtnBuyL") != -1 || StringFind(name, "BtnSellL") != -1) return UI_Y + 370;
   if(StringFind(name, "DelBuy") != -1 || StringFind(name, "DelSell") != -1) return UI_Y + 410;
   if(StringFind(name, "ClosePos") != -1) return UI_Y + 450;
   if(StringFind(name, "CloseOrd") != -1) return UI_Y + 490;
   if(StringFind(name, "Reset") != -1) return UI_Y + 530;
   if(StringFind(name, "BuyNow") != -1) return UI_Y + 570;
   if(StringFind(name, "SellNow") != -1) return UI_Y + 570;
   return UI_Y;
}