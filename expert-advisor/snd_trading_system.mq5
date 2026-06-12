//+------------------------------------------------------------------+
//|                                             SND_Trading_System.mq5|
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

input group "--- RISK & TRANSMISSION ---"
input ulong InpMagicNumber = 55555; // Magic Number (Harus beda tiap chart)


CTrade trade;
// Di bagian atas (ubah variabel global menjadi tanpa nilai instan dahulu)
string PREF;
string ZONE_PREF;

bool IsDashboardVisible = true;
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
int  GetInitialY(string name);
void CreateObject(string name, ENUM_OBJECT type, int win, int x, int y, int w, int h, color clr);
void CreateLabel(string name, int x, int y, string text, color clr);
void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color txtClr);
void CreateEdit(string name, int x, int y, int w, int h, string val);
void DelPO(ENUM_ORDER_TYPE type);
void CloseAllPositions();
void CloseAllOrders();

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() 
{ 
   // Membuat nama objek unik, contoh hasil: "SND_55555_"
   PREF = "SND_" + IntegerToString(InpMagicNumber) + "_";
   ZONE_PREF = "SND_Z_" + IntegerToString(InpMagicNumber) + "_";
   
   // Mengatur agar setiap kali EA ini mengirim order, Magic Number langsung terpasang otomatis
   trade.SetExpertMagicNumber(InpMagicNumber);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrLightGray);
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
   ObjectsDeleteAll(0, PREF); 
   ObjectsDeleteAll(0, ZONE_PREF); 
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
}

void OnTick() { 
   // CADANGAN: Jika OnTimer macet, jam akan tetap terupdate setiap kali ada tick harga baru
   datetime serverTime = TimeCurrent();
   string liveClock = TimeToString(serverTime, TIME_MINUTES | TIME_SECONDS);
   DrawNativeLabel(PREF + "Live_Clock", "Server Time: " + liveClock, 20, 25, clrBlack);
}

// --- FUNGSI TIMER UNTUK MENYETEL WARNA MULTI EMA DARI EA ---
void OnTimer()
{
   // Matikan timer agar fungsi ini hanya berjalan 1x saat start
   EventKillTimer();
   
   // 1. UPDATE JAM DIGITAL (Berjalan murni setiap 1 detik)
   datetime serverTime = TimeCurrent(); // Gunakan TimeCurrent agar singkron dengan market, atau TimeLocal() untuk jam PC
   string liveClock = TimeToString(serverTime, TIME_MINUTES | TIME_SECONDS);
   
   DrawNativeLabel(PREF + "Live_Clock", "Server Time: " + liveClock, 20, 25, clrBlack);
   
   ChartRedraw();
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
            if(StringFind(name, PREF) == 0 && name != PREF+"Hide") { 
               ObjectSetInteger(0, name, OBJPROP_YDISTANCE, IsDashboardVisible ? GetInitialY(name) : UI_OFFSCREEN); 
            } 
         }
         ObjectSetInteger(0, PREF+"Hide", OBJPROP_YDISTANCE, HEADER_Y + 7); 
         ObjectSetInteger(0, PREF+"Hide", OBJPROP_STATE, false);
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
      else if(sparam == PREF+"Reset") { 
         ObjectsDeleteAll(0, PREF+"Line_"); ObjectsDeleteAll(0, PREF+"Calc_"); ObjectsDeleteAll(0, PREF+"Layer_"); ObjectsDeleteAll(0, ZONE_PREF); 
         IsSDScanning = false; 
         ObjectSetString(0, PREF+"BtnScanSD", OBJPROP_TEXT, "Scan S&D"); ObjectSetInteger(0, PREF+"BtnScanSD", OBJPROP_BGCOLOR, clrDarkGreen);
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
void PlaceBuyLimit() { 
   int layers = (int)GetInputValue("InpLayers"); double lot = GetInputValue("InpLot"); 
   double entry = GetInputValue("Buy_Entry"); double sl = GetInputValue("Buy_Stoploss"); 
   double tp1 = GetInputValue("Buy_TP1"); double tp2 = GetInputValue("Buy_TP2"); double tp3 = GetInputValue("Buy_TP3"); 
   if(entry == 0 || lot == 0) return; 
   for(int i=0; i<layers; i++) { 
      double tp = (i == 0) ? tp1 : (i == 1) ? tp2 : tp3; 
      trade.BuyLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Buy L"+IntegerToString(i+1)); 
   } 
}

void PlaceSellLimit() { 
   int layers = (int)GetInputValue("InpLayers"); double lot = GetInputValue("InpLot"); 
   double entry = GetInputValue("Sell_Entry"); double sl = GetInputValue("Sell_Stoploss"); 
   double tp1 = GetInputValue("Sell_TP1"); double tp2 = GetInputValue("Sell_TP2"); double tp3 = GetInputValue("Sell_TP3"); 
   if(entry == 0 || lot == 0) return; 
   for(int i=0; i<layers; i++) { 
      double tp = (i == 0) ? tp1 : (i == 1) ? tp2 : tp3; 
      trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Sell L"+IntegerToString(i+1)); 
   } 
}

void PlaceBuyNow() { 
   double lot = GetInputValue("InpLot");
   double sl  = GetInputValue("Buy_Stoploss");
   double tp  = GetInputValue("Buy_TP3");
   if(lot <= 0) {
      Print("Lot size is zero or negative, cannot execute Buy trade.");
      return;
   }
   if(trade.Buy(lot, _Symbol, 0, sl, tp, "BuyNow"))
      Print("Buy order executed: Lot=", lot, ", SL=", sl, ", TP=", tp);
   else
      Print("Failed to execute Buy order. Error: ", GetLastError());
}

void PlaceSellNow() { 
   double lot = GetInputValue("InpLot");
   double sl  = GetInputValue("Sell_Stoploss");
   double tp  = GetInputValue("Sell_TP3");
   if(lot <= 0) {
      Print("Lot size is zero or negative, cannot execute Sell trade.");
      return;
   }
   if(trade.Sell(lot, _Symbol, 0, sl, tp, "SellNow"))
      Print("Sell order executed: Lot=", lot, ", SL=", sl, ", TP=", tp);
   else
      Print("Failed to execute Sell order. Error: ", GetLastError());
}

// --- Layout ---
void CalculateAndDrawAll() {
   if(ObjectFind(0, PREF+"Line_Floor") < 0 || ObjectFind(0, PREF+"Line_Ceiling") < 0) return;
   double pFloor = ObjectGetDouble(0, PREF+"Line_Floor", OBJPROP_PRICE); 
   double pCeiling = ObjectGetDouble(0, PREF+"Line_Ceiling", OBJPROP_PRICE);
   double range = MathAbs(pCeiling - pFloor);
   double buffer = 0.3 * range;
   double bEntry = pCeiling; double bSL = pFloor - buffer; double bRisk = bEntry - bSL;
   double sEntry = pFloor; double sSL = pCeiling + buffer; double sRisk = sSL - sEntry;
   
   ObjectsDeleteAll(0, PREF+"Calc_");
   UpdateLine(PREF+"Calc_B_SL", bSL, clrBlue);
   UpdateLine(PREF+"Calc_S_SL", sSL, clrRed); 

   UpdateLine(PREF+"Calc_B_TP1", bEntry + bRisk, clrGreen); UpdateLine(PREF+"Calc_B_TP2", bEntry + (2 * bRisk), clrGreen); UpdateLine(PREF+"Calc_B_TP3", bEntry + (3 * bRisk), clrGreen);
   UpdateLine(PREF+"Calc_S_TP1", sEntry - sRisk, clrGreen); UpdateLine(PREF+"Calc_S_TP2", sEntry - (2 * sRisk), clrGreen); UpdateLine(PREF+"Calc_S_TP3", sEntry - (3 * sRisk), clrGreen);
   
   UpdateInput("Buy_Floor", pFloor); UpdateInput("Buy_Entry", bEntry); UpdateInput("Buy_Stoploss", bSL); 
   UpdateInput("Buy_TP1", bEntry+bRisk); UpdateInput("Buy_TP2", bEntry+(2*bRisk)); UpdateInput("Buy_TP3", bEntry+(3*bRisk));
   UpdateInput("Sell_Ceiling", pCeiling); UpdateInput("Sell_Entry", sEntry); UpdateInput("Sell_Stoploss", sSL); 
   UpdateInput("Sell_TP1", sEntry-sRisk); UpdateInput("Sell_TP2", sEntry-(2*sRisk)); UpdateInput("Sell_TP3", sEntry-(3*sRisk));
}

void CreateDashboard() {
   CreateObject("HdrPanel", OBJ_RECTANGLE_LABEL, 0, 10, HEADER_Y, PANEL_W, 40, clrBlack);
   ObjectSetInteger(0, PREF+"HdrPanel", OBJPROP_BGCOLOR, clrDarkSlateGray);
   CreateButton("Hide", 15, HEADER_Y + 7, 50, 25, "Hide", clrGray, clrWhite);
   CreateLabel("Title", (PANEL_W / 2) + 10 - 40, HEADER_Y + 2, "SND Trading System", clrWhite); 
   CreateObject("Panel", OBJ_RECTANGLE_LABEL, 0, 10, UI_Y, PANEL_W, PANEL_H, clrDarkSlateGray);
   
   CreateLabel("LblLayers", 20, UI_Y+12, "Layers:", clrOrange); CreateEdit("InpLayers", 130, UI_Y+18, 100, 25, "1");
   CreateLabel("LblLot", 270, UI_Y+12, "Lot/Layer:", clrOrange); CreateEdit("InpLot", 370, UI_Y+18, 100, 25, "0.01");
   
   CreateButton("BtnDraw", 20, UI_Y+80, 180, 30, "Draw Line", clrPurple, clrWhite);
   CreateButton("BtnScanSD", 270, UI_Y+80, 180, 30, "Scan S&D", clrDarkGreen, clrWhite);
   
   string bL[]={"Floor","Entry","Stoploss","TP1","TP2","TP3"}; 
   string sL[]={"Ceiling","Entry","Stoploss","TP1","TP2","TP3"};
   for(int i=0; i<6; i++) {
      CreateLabel("LB_"+bL[i], 20, UI_Y+130+(i*30), bL[i], clrOrange); CreateEdit("Buy_"+bL[i], 130, UI_Y+134+(i*30), 100, 25, "0.00");
      CreateLabel("LS_"+sL[i], 270, UI_Y+130+(i*30), sL[i], clrOrange); CreateEdit("Sell_"+sL[i], 370, UI_Y+134+(i*30), 100, 25, "0.00");
   }
   CreateButton("BtnBuyL", 20, UI_Y + 320, 200, 30, "Buy Limit", clrBlue, clrWhite);
   CreateButton("BtnSellL", 270, UI_Y + 320, 200, 30, "Sell Limit", clrOrange, clrWhite);
   CreateButton("DelBuy", 20, UI_Y + 360, 200, 30, "Del Buy", clrBlue, clrWhite);
   CreateButton("DelSell", 270, UI_Y + 360, 200, 30, "Del Sell", clrBrown, clrWhite);
   CreateButton("ClosePos", 20, UI_Y + 400, PANEL_W-40, 30, "Close Positions", clrDarkRed, clrWhite);
   CreateButton("CloseOrd", 20, UI_Y + 440, PANEL_W-40, 30, "Close All Orders", clrMaroon, clrWhite);
   CreateButton("Reset", 20, UI_Y + 480, PANEL_W-40, 30, "ResetLines & Calc", clrGray, clrBlack);
   CreateButton("BuyNow", 20, UI_Y + 520, 200, 30, "Buy Now", clrDodgerBlue, clrWhite);
   CreateButton("SellNow", 270, UI_Y + 520, 200, 30, "Sell Now", clrOrangeRed, clrWhite);
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
void CloseAllPositions() { for(int i=PositionsTotal()-1; i>=0; i--) { ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t) && PositionGetString(POSITION_SYMBOL)==_Symbol) trade.PositionClose(t); } }
void CloseAllOrders() { for(int i=OrdersTotal()-1; i>=0; i--) { ulong t=OrderGetTicket(i); if(OrderSelect(t) && OrderGetString(ORDER_SYMBOL)==_Symbol) trade.OrderDelete(t); } }

int GetInitialY(string name) {
   if(name == PREF+"HdrPanel") return HEADER_Y;
   if(name == PREF+"Hide") return HEADER_Y + 7;
   if(name == PREF+"Title") return HEADER_Y + 2;
   if(name == PREF+"Panel") return UI_Y;
   if(name == PREF+"LblLayers" || name == PREF+"InpLayers" || name == PREF+"LblLot" || name == PREF+"InpLot") return UI_Y + 12;
   if(name == PREF+"BtnDraw" || name == PREF+"BtnScanSD") return UI_Y + 80;
   
   string bL[]={"Floor","Entry","Stoploss","TP1","TP2","TP3"};
   string sL[]={"Ceiling","Entry","Stoploss","TP1","TP2","TP3"};
   for(int i=0; i<6; i++) {
      if(name == PREF+"LB_"+bL[i] || name == PREF+"Buy_"+bL[i]) return UI_Y + 130 + (i*30);
      if(name == PREF+"LS_"+sL[i] || name == PREF+"Sell_"+sL[i]) return UI_Y + 130 + (i*30);
   }
   
   if(name == PREF+"BtnBuyL" || name == PREF+"BtnSellL") return UI_Y + 320;
   if(name == PREF+"DelBuy" || name == PREF+"DelSell") return UI_Y + 360;
   if(name == PREF+"ClosePos") return UI_Y + 400;
   if(name == PREF+"CloseOrd") return UI_Y + 440;
   if(name == PREF+"Reset") return UI_Y + 480;
   if(name == PREF+"BuyNow" || name == PREF+"SellNow") return UI_Y + 520;
   return UI_Y;
}