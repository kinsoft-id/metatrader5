//+------------------------------------------------------------------+
//|                                      Pivot_And_Control_System.mq5|
//|                                  Copyright 2026, User            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, User"
#property description "Pivot and Control System"
#property strict
#include <Trade\Trade.mqh> 

//--- Input Parameters
input double InpBasingRatio    = 0.50; // Rasio maksimal body candle untuk Base
input double InpImpulsiveRatio = 0.62; // Rasio minimal body candle untuk Leg In/Out
input int    InpMaxBase     = 6;    // Maksimal candle base berurutan
input bool   InpShowRBR     = true;  // Tampilkan Rally Base Rally
input bool   InpShowDBD     = true;  // Tampilkan Drop Base Drop
input bool   InpShowDBR     = true;  // Tampilkan Drop Base Rally
input bool   InpShowRBD     = true;  // Tampilkan Rally Base Drop
input int InpMaxZones = 10; // Maksimal zona yang ditampilkan

input group "--- RISK & TRANSMISSION ---"
input ulong InpMagicNumber = 6060; // Magic Number (Harus beda tiap chart)


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
void DelPO(ENUM_ORDER_TYPE type, ulong magic=0);
void CloseAllPositions(ulong magic);
void CloseAllOrders(ulong magic);
void ApplyQuoteVisibility();
void DrawNativeLabel(string name, string text, int x, int y, color clr);
void ActionHide();
void ActionHideQuote();
void ActionDrawLine();
void ActionScanSD();
void ActionBuyLimit();
void ActionSellLimit();
void ActionDelBuy();
void ActionDelSell();
void ActionClosePositions();
void ActionCloseOrders();
void ActionReset();
void ActionBuyNow();
void ActionSellNow();
void ApplyScanSDUI();
bool HotkeyModifiersFree();
void HandleHotkey(const long key);
bool ZoneIsDemand(const string name);
bool ZoneIsSupply(const string name);
bool GetZonePrices(const string rectName, double &zLow, double &zHigh);
double FindOppositeCutPrice(const bool isBuy, const double fromPrice, const double tpLimit);
double ClipTpToOppositeZone(const bool isBuy, const double entry, const double tp);
void ManageOppositeZoneCutProfit();
void RecalcTpIfDrawn();

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
//    ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrLightGray);
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
   ObjectsDeleteAll(0, ZONE_PREF); // Menghapus semua kotak dan tombol S&D sekaligus
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
}

void OnTick() { 
   // CADANGAN: Jika OnTimer macet, jam akan tetap terupdate setiap kali ada tick harga baru
   datetime serverTime = TimeCurrent();
   string liveClock = TimeToString(serverTime, TIME_MINUTES | TIME_SECONDS);
   DrawNativeLabel(PREF + "Live_Clock", "Server Time: " + liveClock, (PANEL_W + 20), 50, clrBlack);
   ApplyQuoteVisibility();

   CheckCutLoss();
   ManageOppositeZoneCutProfit();

   if(IsSDScanning)
   {
      static datetime lastBarTime = 0;
      datetime curBarTime = iTime(_Symbol, _Period, 0);
      if(curBarTime != lastBarTime)
      {
         lastBarTime = curBarTime;
         ScanSD();
         RecalcTpIfDrawn();
      }
   }
}

void OnTimer()
{
   datetime serverTime = TimeCurrent();
   string liveClock = TimeToString(serverTime, TIME_MINUTES | TIME_SECONDS);
   DrawNativeLabel(PREF + "Live_Clock", "Server Time: " + liveClock, (PANEL_W + 20), 50, clrBlack);
   ApplyQuoteVisibility();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Event Handling                                                    |
//+------------------------------------------------------------------+
void ActionHide()
{
   IsDashboardVisible = !IsDashboardVisible;
   ObjectSetString(0, PREF+"Hide", OBJPROP_TEXT, IsDashboardVisible ? "Hide [H]" : "Show [H]");
   for(int i=0; i<ObjectsTotal(0); i++) {
      string name = ObjectName(0, i);
      if(StringFind(name, PREF) != 0) continue;
      if(StringFind(name, PREF+"Line_") == 0 ||
         StringFind(name, PREF+"Calc_") == 0 ||
         StringFind(name, PREF+"Layer_") == 0) continue;
      if(name == PREF+"Hide" ||
         name == PREF+"HideQuote" ||
         name == PREF+"HdrPanel" ||
         name == PREF+"Title" ||
         name == PREF+"Live_Clock" ||
         name == PREF+"Quote" ||
         name == PREF+"Quote2") continue;
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, IsDashboardVisible ? GetInitialY(name) : UI_OFFSCREEN);
   }
   ObjectSetInteger(0, PREF+"Hide", OBJPROP_YDISTANCE, HEADER_Y + 7);
   ObjectSetInteger(0, PREF+"HideQuote", OBJPROP_YDISTANCE, HEADER_Y + 7);
   ApplyQuoteVisibility();
}

void ActionHideQuote()
{
   IsQuoteVisible = !IsQuoteVisible;
   ObjectSetString(0, PREF+"HideQuote", OBJPROP_TEXT, IsQuoteVisible ? "Hide Q [U]" : "Show Q [U]");
   ApplyQuoteVisibility();
}

void ActionDrawLine()
{
   CreateDrawingLines();
   CalculateAndDrawAll();
}

void ApplyScanSDUI()
{
   if(ObjectFind(0, PREF+"BtnScanSD") < 0) return;
   if(IsSDScanning)
   {
      ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "S&D: ON [A]");
      ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrGreen);
   }
   else
   {
      ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "Scan S&D [A]");
      ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrDarkGreen);
   }
}

void ActionScanSD()
{
   IsSDScanning = !IsSDScanning;
   if(IsSDScanning) ScanSD();
   else ObjectsDeleteAll(0, ZONE_PREF);
   ApplyScanSDUI();
   RecalcTpIfDrawn();
}

void ActionBuyLimit()        { PlaceBuyLimit(); }
void ActionSellLimit()       { PlaceSellLimit(); }
void ActionDelBuy()          { DelPO(ORDER_TYPE_BUY_LIMIT, InpMagicNumber); }
void ActionDelSell()         { DelPO(ORDER_TYPE_SELL_LIMIT, InpMagicNumber); }
void ActionClosePositions()  { CloseAllPositions(InpMagicNumber); }
void ActionCloseOrders()     { CloseAllOrders(InpMagicNumber); }
void ActionBuyNow()          { PlaceBuyNow(); }
void ActionSellNow()         { PlaceSellNow(); }

void ActionReset()
{
   ObjectsDeleteAll(0, PREF+"Line_");
   ObjectsDeleteAll(0, PREF+"Calc_");
   ObjectsDeleteAll(0, PREF+"Layer_");
   ObjectsDeleteAll(0, ZONE_PREF);
   IsSDScanning = false;
   ApplyScanSDUI();
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

   if(key == 72) ActionHide();                 // H
   else if(key == 85) ActionHideQuote();       // U
   else if(key == 68) ActionDrawLine();        // D
   else if(key == 65) ActionScanSD();          // A
   else if(key == 66) ActionBuyLimit();        // B
   else if(key == 83) ActionSellLimit();       // S
   else if(key == 81) ActionDelBuy();          // Q
   else if(key == 87) ActionDelSell();         // W
   else if(key == 80) ActionClosePositions();  // P
   else if(key == 79) ActionCloseOrders();     // O
   else if(key == 82) ActionReset();           // R
   else if(key == 78) ActionBuyNow();          // N
   else if(key == 77) ActionSellNow();         // M
   else return;

   ChartRedraw();
}

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
      if(sparam == PREF+"Hide") { ActionHide(); ObjectSetInteger(0, PREF+"Hide", OBJPROP_STATE, false); ChartRedraw(); }
      else if(sparam == PREF+"HideQuote") { ActionHideQuote(); ObjectSetInteger(0, PREF+"HideQuote", OBJPROP_STATE, false); ChartRedraw(); }
      else if(sparam == PREF+"BtnDraw") { ActionDrawLine(); ObjectSetInteger(0, PREF+"BtnDraw", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnScanSD") { ActionScanSD(); ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnBuyL")  { ActionBuyLimit(); ObjectSetInteger(0, PREF+"BtnBuyL", OBJPROP_STATE, false); }
      else if(sparam == PREF+"BtnSellL") { ActionSellLimit(); ObjectSetInteger(0, PREF+"BtnSellL", OBJPROP_STATE, false); }
      else if(sparam == PREF+"DelBuy") { ActionDelBuy(); ObjectSetInteger(0, PREF+"DelBuy", OBJPROP_STATE, false); }
      else if(sparam == PREF+"DelSell") { ActionDelSell(); ObjectSetInteger(0, PREF+"DelSell", OBJPROP_STATE, false); }
      else if(sparam == PREF+"ClosePos") { ActionClosePositions(); ObjectSetInteger(0, PREF+"ClosePos", OBJPROP_STATE, false); }
      else if(sparam == PREF+"CloseOrd") { ActionCloseOrders(); ObjectSetInteger(0, PREF+"CloseOrd", OBJPROP_STATE, false); }
      else if(sparam == PREF+"Reset") { ActionReset(); ObjectSetInteger(0, PREF+"Reset", OBJPROP_STATE, false); ChartRedraw(); }
      else if(sparam == PREF+"BuyNow") { ActionBuyNow(); ObjectSetInteger(0, PREF+"BuyNow", OBJPROP_STATE, false); }
      else if(sparam == PREF+"SellNow") { ActionSellNow(); ObjectSetInteger(0, PREF+"SellNow", OBJPROP_STATE, false); }
      
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
   
   int yArea   = IsDashboardVisible ? 140 : UI_OFFSCREEN;

   DrawNativeLabel(PREF + "Lbl_Buy_Area_Width", buyPipsText, 20, yArea, clrDarkSlateGray); 
   DrawNativeLabel(PREF + "Lbl_Sell_Area_Width", sellPipsText, 160, yArea, clrDarkSlateGray);
}

// --- SHOW / HIDE QUOTE LABELS ---
void ApplyQuoteVisibility()
{
   int yQuote  = IsQuoteVisible ? 75  : UI_OFFSCREEN;
   int yQuote2 = IsQuoteVisible ? 100 : UI_OFFSCREEN;

   DrawNativeLabel(PREF + "Quote",  "Re-Entry di Area yang sama Maksimal 3x Pantulan", (PANEL_W + 20), yQuote,  clrBlack);
   DrawNativeLabel(PREF + "Quote2", "Jam Trading: 05-08 WIB, 16-19 WIB",              (PANEL_W + 20), yQuote2, clrBlack);
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

            // RBR/DBR: Close Leg Out di atas base | DBD/RBD: Close Leg Out di bawah base
            if((type == "RBR" || type == "DBR") && legOutClose <= baseHigh) continue;
            if((type == "DBD" || type == "RBD") && legOutClose >= baseLow) continue;

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
void PlaceBuyLimit()
{
   // Pastikan objek trade menggunakan magic number chart ini sebelum mengeksekusi buy limit
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   int layers = (int)GetInputValue("InpLayers");
   double lot = GetInputValue("InpLot");
   double entry = GetInputValue("Buy_Entry");
   double floor = GetInputValue("Buy_Floor");
   double sl = GetInputValue("Buy_Stoploss");
   double tp = GetInputValue("Buy_TP");
   if(entry == 0 || floor == 0 || lot == 0 || tp == 0) return;
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
   double tp = GetInputValue("Sell_TP");
   if(entry == 0 || ceiling == 0 || lot == 0 || tp == 0) return;
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
   
   double bTP = GetInputValue("Buy_TP");
   double sTP = GetInputValue("Sell_TP");
   if(bTP <= 0.0) bTP = tp;
   if(sTP <= 0.0) sTP = tp;

   if(buyFloorTouched && closePrice >= bTP) {
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
   
   if(sellCeilingTouched && closePrice <= sTP) {
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
   double tpMid = pFloor + 0.5 * range;
   double bEntry = pFloor + 0.24 * range; double bSL = pFloor - 0.08 * range; double bCL = pFloor - 0.16 * range; 
   double sEntry = pCeiling - 0.24 * range; double sSL = pCeiling + 0.08 * range; double sCL = pCeiling + 0.16 * range;
   double bTP = ClipTpToOppositeZone(true,  bEntry, tpMid);
   double sTP = ClipTpToOppositeZone(false, sEntry, tpMid);
   
   double stepB = (layers > 1) ? (bEntry - pFloor) / (layers - 1) : 0;
   for(int i=0; i<layers; i++) UpdateLine(PREF+"Layer_Buy_"+IntegerToString(i), bEntry - (stepB * i), clrBlue);
   double stepS = (layers > 1) ? (pCeiling - sEntry) / (layers - 1) : 0;
   for(int i=0; i<layers; i++) UpdateLine(PREF+"Layer_Sell_"+IntegerToString(i), sEntry + (stepS * i), clrRed);
   
   UpdateLine(PREF+"Calc_B_TP", bTP, clrDarkGreen);
   UpdateLine(PREF+"Calc_S_TP", sTP, clrLimeGreen);
   UpdateLine(PREF+"Calc_B_SL", bSL, clrBlue); UpdateLine(PREF+"Calc_B_CL", bCL, clrDarkBlue);
   UpdateLine(PREF+"Calc_S_SL", sSL, clrRed); UpdateLine(PREF+"Calc_S_CL", sCL, clrDarkRed);
   
   UpdateInput("Buy_Floor", pFloor); UpdateInput("Buy_Entry", bEntry); UpdateInput("Buy_Stoploss", bSL); UpdateInput("Buy_CutLoss", bCL); UpdateInput("Buy_TP", bTP);
   UpdateInput("Sell_Ceiling", pCeiling); UpdateInput("Sell_Entry", sEntry); UpdateInput("Sell_Stoploss", sSL); UpdateInput("Sell_CutLoss", sCL); UpdateInput("Sell_TP", sTP);
   
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
   
   CreateButton("Hide", 15, HEADER_Y + 7, 95, 25, "Hide [H]", clrGray, clrWhite);
   CreateButton("HideQuote", 115, HEADER_Y + 7, 120, 25, "Hide Q [U]", clrGray, clrWhite);
   ObjectSetInteger(0, PREF+"Hide", OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, PREF+"HideQuote", OBJPROP_FONTSIZE, 9);
   
   CreateLabel("Title", 250, HEADER_Y + 8, "Pivot and Control", clrWhite); 
   ObjectSetInteger(0, PREF+"Title", OBJPROP_FONTSIZE, 12);
   ObjectSetString(0, PREF+"Title", OBJPROP_FONT, "Arial Bold");
   
   CreateObject("Panel", OBJ_RECTANGLE_LABEL, 0, 10, UI_Y, PANEL_W, PANEL_H, clrDarkSlateGray);
   ObjectSetInteger(0, PREF+"Panel", OBJPROP_BGCOLOR, clrDarkSlateGray);
   ObjectSetInteger(0, PREF+"Panel", OBJPROP_BORDER_TYPE, BORDER_SUNKEN);
   
   int sellColumnX = 270;
   int editW = 120;
   
   CreateLabel("LblLayers", 20, UI_Y+12, "Layers:", clrOrange);
   CreateEdit("InpLayers", 130, UI_Y+18, editW, 25, "5");
   
   CreateLabel("LblLot", sellColumnX, UI_Y+12, "Lot/Lyr:", clrOrange);
   CreateEdit("InpLot", sellColumnX + 110, UI_Y+18, editW, 25, "0.01");
   
   CreateButton("BtnDraw", 20, UI_Y+80, 230, 30, "Draw Line [D]", clrPurple, clrWhite);
   CreateButton("BtnScanSD", sellColumnX, UI_Y+80, 230, 30, "Scan S&D [A]", clrDarkGreen, clrWhite);
   
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
   
   CreateButton("BtnBuyL", 20, UI_Y + 370, 230, 30, "Buy Limit [B]", clrBlue, clrWhite);
   CreateButton("BtnSellL", sellColumnX, UI_Y + 370, 230, 30, "Sell Limit [S]", clrOrange, clrWhite);
   
   CreateButton("DelBuy", 20, UI_Y + 410, 230, 30, "Del Buy [Q]", clrBlue, clrWhite);
   CreateButton("DelSell", sellColumnX, UI_Y + 410, 230, 30, "Del Sell [W]", clrBrown, clrWhite);
   
   CreateButton("ClosePos", 20, UI_Y + 450, PANEL_W-20, 30, "Close Positions [P]", clrDarkRed, clrWhite);
   CreateButton("CloseOrd", 20, UI_Y + 490, PANEL_W-20, 30, "Close All Orders [O]", clrMaroon, clrWhite);
   CreateButton("Reset", 20, UI_Y + 530, PANEL_W-20, 30, "Reset Lines & Calc [R]", clrGray, clrBlack);
   CreateButton("BuyNow", 20, UI_Y + 570, 230, 30, "Buy Now [N]", clrDodgerBlue, clrWhite);
   CreateButton("SellNow", sellColumnX, UI_Y + 570, 230, 30, "Sell Now [M]", clrOrangeRed, clrWhite);
   ApplyQuoteVisibility();

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
void CloseAllPositions(ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic) continue;
      trade.PositionClose(ticket);
   }
}

void CloseAllOrders(ulong magic)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != magic) continue;
      trade.OrderDelete(ticket);
   }
}

void RecalcTpIfDrawn()
{
   if(ObjectFind(0, PREF+"Line_Floor") >= 0 && ObjectFind(0, PREF+"Line_Ceiling") >= 0)
      CalculateAndDrawAll();
}

bool ZoneIsDemand(const string name)
{
   return (StringFind(name, "_RBR_") >= 0 || StringFind(name, "_DBR_") >= 0);
}

bool ZoneIsSupply(const string name)
{
   return (StringFind(name, "_DBD_") >= 0 || StringFind(name, "_RBD_") >= 0);
}

bool GetZonePrices(const string rectName, double &zLow, double &zHigh)
{
   double p1 = ObjectGetDouble(0, rectName, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, rectName, OBJPROP_PRICE, 1);
   zLow  = MathMin(p1, p2);
   zHigh = MathMax(p1, p2);
   return (zLow > 0.0 && zHigh > zLow);
}

// Buy: supply proximal (base low). Sell: demand proximal (base high).
double FindOppositeCutPrice(const bool isBuy, const double fromPrice, const double tpLimit)
{
   double cut = 0.0;
   int total = ObjectsTotal(0, 0, OBJ_RECTANGLE);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, OBJ_RECTANGLE);
      if(StringFind(name, ZONE_PREF) != 0) continue;

      double zLow = 0.0, zHigh = 0.0;
      if(!GetZonePrices(name, zLow, zHigh)) continue;

      if(isBuy)
      {
         if(!ZoneIsSupply(name)) continue;
         double proximal = zLow;
         if(proximal > fromPrice && proximal < tpLimit)
         {
            if(cut == 0.0 || proximal < cut) cut = proximal;
         }
      }
      else
      {
         if(!ZoneIsDemand(name)) continue;
         double proximal = zHigh;
         if(proximal < fromPrice && proximal > tpLimit)
         {
            if(cut == 0.0 || proximal > cut) cut = proximal;
         }
      }
   }
   return cut;
}

double ClipTpToOppositeZone(const bool isBuy, const double entry, const double tp)
{
   if(!IsSDScanning) return tp;
   double cut = FindOppositeCutPrice(isBuy, entry, tp);
   if(cut <= 0.0) return tp;

   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(stops <= 0.0) stops = _Point;
   if(MathAbs(cut - entry) < stops) return tp;

   return NormalizeDouble(cut, _Digits);
}

void ManageOppositeZoneCutProfit()
{
   if(!IsSDScanning) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double mark  = isBuy ? bid : ask;
      double tpLimit = tp;

      if(tpLimit <= 0.0)
         tpLimit = isBuy ? GetInputValue("Buy_TP") : GetInputValue("Sell_TP");
      if(tpLimit <= 0.0)
         tpLimit = isBuy ? (mark + 100000 * _Point) : (mark - 100000 * _Point);

      double cut = FindOppositeCutPrice(isBuy, mark, tpLimit);
      if(cut <= 0.0) continue;

      if((isBuy && bid >= cut) || (!isBuy && ask <= cut))
      {
         if(trade.PositionClose(ticket))
            Print("Cut profit di S&D lawan @ ", DoubleToString(cut, _Digits), " ticket ", ticket);
         continue;
      }

      if(tp <= 0.0 || (isBuy && cut < tp - _Point) || (!isBuy && cut > tp + _Point))
      {
         if(trade.PositionModify(ticket, sl, NormalizeDouble(cut, _Digits)))
            Print("TP dipotong ke S&D lawan @ ", DoubleToString(cut, _Digits), " ticket ", ticket);
      }
   }
}

int GetInitialY(string name) {
   if(name == PREF+"HdrPanel") return HEADER_Y;
   if(name == PREF+"Hide" || name == PREF+"HideQuote") return HEADER_Y + 7;
   if(name == PREF+"Title") return HEADER_Y + 2;
   if(name == PREF+"Live_Clock") return 50;
   if(name == PREF+"Quote") return 75;
   if(name == PREF+"Quote2") return 100;
   if(name == PREF+"Panel") return UI_Y;
   if(name == PREF+"LblLayers" || name == PREF+"LblLot") return UI_Y + 12;
   if(name == PREF+"InpLayers" || name == PREF+"InpLot") return UI_Y + 18;
   if(name == PREF+"BtnDraw" || name == PREF+"BtnScanSD") return UI_Y + 80;
   if(name == PREF+"HdrBuy" || name == PREF+"HdrSell") return UI_Y + 130;
   if(name == PREF+"Lbl_Buy_Area_Width" || name == PREF+"Lbl_Sell_Area_Width") return 140;

   string bLabels[]={"Floor","Entry","Stoploss","CutLoss","TP","Area"};
   string sLabels[]={"Ceiling","Entry","Stoploss","CutLoss","TP","Area"};
   for(int i=0; i<6; i++) {
      int rowY = UI_Y + 165 + (i * 30);
      if(name == PREF+"LB_"+bLabels[i] || name == PREF+"LS_"+sLabels[i]) return rowY;
      if(name == PREF+"Buy_"+bLabels[i] || name == PREF+"Sell_"+sLabels[i]) return rowY + 4;
   }

   if(name == PREF+"BtnBuyL" || name == PREF+"BtnSellL") return UI_Y + 370;
   if(name == PREF+"DelBuy" || name == PREF+"DelSell") return UI_Y + 410;
   if(name == PREF+"ClosePos") return UI_Y + 450;
   if(name == PREF+"CloseOrd") return UI_Y + 490;
   if(name == PREF+"Reset") return UI_Y + 530;
   if(name == PREF+"BuyNow" || name == PREF+"SellNow") return UI_Y + 570;
   return UI_Y;
}