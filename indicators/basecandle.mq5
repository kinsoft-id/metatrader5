#property indicator_chart_window
#property indicator_plots 0

input group "Base Candle Settings"
input double InpBodyPercent = 63.0;      
input color  InpBoxColor    = clrYellow; 
input int    InpOpacity     = 150;       

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "BaseBox_");
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[]) 
{
   int limit = (prev_calculated > 0) ? prev_calculated - 1 : 0;

   for(int i = limit; i < rates_total - 1; i++) // rates_total - 1 agar bisa mengambil time[i+1]
   {
      double range = high[i] - low[i];
      double body  = MathAbs(open[i] - close[i]);
      double currentPercent = (range > 0) ? (body / range) * 100.0 : 0;

      string objName = "BaseBox_" + (string)time[i];

      if(currentPercent <= InpBodyPercent && range > 0)
      {
         // Gunakan time[i] sebagai titik kiri dan time[i+1] sebagai titik kanan
         // Jika bar terakhir, kita gunakan perkiraan waktu bar berikutnya
         datetime time_right = (i < rates_total - 1) ? time[i+1] : time[i] + PeriodSeconds();

         if(ObjectFind(0, objName) < 0)
         {
            // Membuat Box dengan koordinat: (Waktu Kiri, High) ke (Waktu Kanan, Low)
            ObjectCreate(0, objName, OBJ_RECTANGLE, 0, time[i], high[i], time_right, low[i]);
            
            ObjectSetInteger(0, objName, OBJPROP_COLOR, InpBoxColor);
            ObjectSetInteger(0, objName, OBJPROP_FILL, true);
            ObjectSetInteger(0, objName, OBJPROP_BACK, true); 
            ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
            ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
         }
         else 
         {
            // Update posisi jika sudah ada (antisipasi resize chart)
            ObjectSetInteger(0, objName, OBJPROP_TIME, 0, time[i]);
            ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, high[i]);
            ObjectSetInteger(0, objName, OBJPROP_TIME, 1, time_right);
            ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, low[i]);
         }
      }
      else
      {
         ObjectDelete(0, objName);
      }
   }
   ChartRedraw(0);
   return(rates_total);
}