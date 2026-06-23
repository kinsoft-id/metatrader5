//+------------------------------------------------------------------+
//|                                                 MultiEMA.mq5 |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

// Setelan Visual Garis Meliuk
#property indicator_label1  "EMA 200"
#property indicator_type1   DRAW_LINE
#property indicator_style1  STYLE_SOLID

#property indicator_label2  "EMA 100"
#property indicator_type2   DRAW_LINE
#property indicator_style2  STYLE_SOLID

#property indicator_label3  "EMA 50"
#property indicator_type3   DRAW_LINE
#property indicator_style3  STYLE_SOLID

#property indicator_label4  "EMA 20"
#property indicator_type4   DRAW_LINE
#property indicator_style4  STYLE_SOLID

// Input Parameter yang dikirim dari EA
input color  InpClr200 = clrBlack;
input color  InpClr100 = clrMediumPurple;
input color  InpClr50  = clrRed;
input color  InpClr20  = clrDarkGreen;

// Buffer Data
double buf200[], buf100[], buf50[], buf20[];
int    h200, h100, h50, h20;

int OnInit()
{
   // Set Buffer
   SetIndexBuffer(0, buf200, INDICATOR_DATA);
   SetIndexBuffer(1, buf100, INDICATOR_DATA);
   SetIndexBuffer(2, buf50,  INDICATOR_DATA);
   SetIndexBuffer(3, buf20,  INDICATOR_DATA);
   
   // --- KUNCI PERBAIKAN: Menggunakan PLOT_LINE_COLOR (Dua Garis Bawah) ---
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpClr200);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpClr100);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpClr50);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpClr20);

   // Ambil data internal MA
   h200 = iMA(_Symbol, _Period, 200, 0, MODE_EMA, PRICE_CLOSE);
   h100 = iMA(_Symbol, _Period, 100, 0, MODE_EMA, PRICE_CLOSE);
   h50  = iMA(_Symbol, _Period, 50,  0, MODE_EMA, PRICE_CLOSE);
   h20  = iMA(_Symbol, _Period, 20,  0, MODE_EMA, PRICE_CLOSE);
   
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
{
   // Copy data bergerak ke buffer chart
   if(CopyBuffer(h200, 0, 0, rates_total, buf200) < 0) return(0);
   if(CopyBuffer(h100, 0, 0, rates_total, buf100) < 0) return(0);
   if(CopyBuffer(h50,  0, 0, rates_total, buf50)  < 0) return(0);
   if(CopyBuffer(h20,  0, 0, rates_total, buf20)  < 0) return(0);
   
   return(rates_total);
}