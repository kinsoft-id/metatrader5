//+------------------------------------------------------------------+
//|                                     Zigzag_MultiFibo_5Lines.mq5   |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   1

// Pengaturan Plot Zigzag
#property indicator_label1  "ZigZag"
#property indicator_type1   DRAW_COLOR_ZIGZAG
#property indicator_color1  clrLimeGreen, clrRed  // Index 0: Hijau, Index 1: Merah
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2                     

input int      InpDepth     = 60;    
input int      InpDeviation = 5;     
input int      InpBackstep  = 3;     
input color    InpFiboColor = clrDodgerBlue; 
input int      InpMaxBars   = 500;   

// Buffer Indikator
double         zzHighBuffer[];           
double         zzLowBuffer[];           
double         zzColorBuffer[]; 

int            handleZZ;             

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, zzHighBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, zzLowBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, zzColorBuffer, INDICATOR_COLOR_INDEX); 
   
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   
   handleZZ = iCustom(_Symbol, _Period, "Examples\\ZigZag", InpDepth, InpDeviation, InpBackstep);
   if(handleZZ == INVALID_HANDLE) return(INIT_FAILED);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Bersihkan semua objek Fibonacci saat indikator dihapus dari chart
   ObjectsDeleteAll(0, "Fibo_ZZ_");
}

//+------------------------------------------------------------------+
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
   double tempZZ[];
   ArraySetAsSeries(tempZZ, true);
   if(CopyBuffer(handleZZ, 0, 0, rates_total, tempZZ) < 0) return(0);

   ArrayInitialize(zzHighBuffer, 0.0);
   ArrayInitialize(zzLowBuffer, 0.0);
   ArrayInitialize(zzColorBuffer, 0.0);

   // Array untuk menampung struktur titik koordinat Zigzag
   double swingPrices[6];
   datetime swingTimes[6];
   int found = 0;
   
   double last_val = 0;
   int last_color = 0; 

   // 1. Distribusi buffer dan kumpulkan titik koordinat
   for(int i = 0; i < rates_total; i++)
   {
      int shift = rates_total - 1 - i;
      double val = tempZZ[i];

      if(val > 0)
      {
         zzHighBuffer[shift] = val;
         zzLowBuffer[shift]  = val;
         
         if(last_val > 0)
         {
            if(val > last_val) last_color = 0; // Naik (Hijau)
            else if(val < last_val) last_color = 1; // Turun (Merah)
         }
         zzColorBuffer[shift] = (double)last_color;
         last_val = val;

         // Kumpulkan maksimal 6 titik (untuk membentuk 5 garis/segmen)
         if(i < InpMaxBars && found < 6)
         {
            swingPrices[found] = val;
            swingTimes[found]  = time[shift];
            found++;
         }
      }
   }

   // Hapus objek lama yang tipenya Fibo_ZZ sebelum digambar ulang (mencegah ghosting)
   ObjectsDeleteAll(0, "Fibo_ZZ_");

   // 2. Gambar Fibonacci untuk setiap pasang titik (Maksimal 5 Objek Fibo)
   for(int k = 0; k < found - 1; k++)
   {
      string name = "Fibo_ZZ_" + IntegerToString(k);
      
      // Ambil dua titik berurutan: k dan k+1
      double priceStart = swingPrices[k+1];
      datetime timeStart = swingTimes[k+1];
      double priceEnd   = swingPrices[k];
      datetime timeEnd   = swingTimes[k];

      // Buat Objek Fibonacci baru
      ObjectCreate(0, name, OBJ_FIBO, 0, timeStart, priceStart, timeEnd, priceEnd);
      
      // Atur properti visual
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpFiboColor);
      ObjectSetInteger(0, name, OBJPROP_LEVELS, 6);
      
      double levels[] = {0.0, 0.236, 0.382, 0.618, 0.786, 1.0};
      for(int i = 0; i < 6; i++)
      {
         ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, i, levels[i]);
         ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, i, InpFiboColor);
         ObjectSetString(0, name, OBJPROP_LEVELTEXT, i, DoubleToString(levels[i], 3));
      }
      
      // Matikan RAY_RIGHT agar garis Fibo tidak melesat memanjang ke kanan chart 
      // dan menumpuk berantakan dengan Fibo lainnya.
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }

   return(rates_total);
}