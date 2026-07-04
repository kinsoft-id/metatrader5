//+------------------------------------------------------------------+
//|                                        RSI5_GridLimit_EA.mq5     |
//|                                  Copyright 2026, User            |
//|                                        Version 1.09              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, User"
#property version   "1.09"
#property strict

#include <Trade\Trade.mqh>

//--- Sinyal RSI
input group "=== Sinyal RSI ==="
input int                InpRsiPeriod        = 5;           // InpRsiPeriod
input ENUM_TIMEFRAMES    InpRsiTF            = PERIOD_M1;   // InpRsiTF
input double             InpRsiBuyLevel      = 40.0;        // InpRsiBuyLevel
input double             InpRsiSellLevel     = 60.0;        // InpRsiSellLevel
input bool               InpAllowBuy         = false;        // InpAllowBuy
input bool               InpAllowSell        = true;        // InpAllowSell
input int                InpMaxCycles        = 0;          // InpMaxCycles (0 = tidak dibatasi)
input int                InpCycleCooldownMin = 5;           // InpCycleCooldownMin
input bool               InpCycleResetDaily   = true;       // Reset cycle jam 00:00 srv (jika cap)

//--- Grid / Layer
input group "=== Grid / Layer ==="
input int                InpMaxLayers        = 50;          // InpMaxLayers
input int                InpLayerDistance    = 1000;         // InpLayerDistance
input int                InpNoStackGapPts    = 50;          // InpNoStackGapPts
input double             InpLotPerLayer      = 0.05;        // InpLotPerLayer
input double             InpLotIncrement     = 0.05;        // InpLotIncrement
input int                InpBepExitMinLayers = 30;          // Close di BEP jika layer >= ini (0=off)

//--- Virtual TP (Trailing dari BEP)
input group "=== Virtual TP (Trailing dari BEP) ==="
input int                InpTrailingStart    = 1888;        // InpTrailingStart
input int                InpTrailingStop     = 888;         // InpTrailingStop
input double             InpTargetProfitUSD  = 400.0;       // InpTargetProfitUSD (0 = nonaktif)
input bool               InpIncludeManual    = true;        // InpIncludeManual

//--- Virtual SL
input group "=== Virtual SL ==="
input int                InpVirtualSL        = 0;           // InpVirtualSL

//--- News Filter
input group "=== News Filter (MQL5 Built-in Calendar) ==="
input bool               InpNewsFilter       = true;        // InpNewsFilter
input int                InpNewsMinBefore    = 60;          // InpNewsMinBefore
input int                InpNewsMinAfter     = 60;           // InpNewsMinAfter
input bool               InpNewsHigh         = true;        // InpNewsHigh
input bool               InpNewsMedium       = false;       // InpNewsMedium
input bool               InpNewsLow          = false;       // InpNewsLow
input string             InpNewsCurrencies   = "USD,XAU";   // InpNewsCurrencies

//--- Filter Waktu
input group "=== Filter Waktu (Server Broker) ==="
input bool               InpTimeFilter       = true;        // InpTimeFilter
input int                InpStartHour        = 0;           // InpStartHour
input int                InpStartMinute      = 0;           // InpStartMinute
input int                InpEndHour          = 23;          // InpEndHour
input int                InpEndMinute        = 59;          // InpEndMinute

//--- Filter Jumat
input group "=== Filter Jumat ==="
input bool               InpFridayFilter     = true;        // InpFridayFilter
input int                InpFridayOffHour    = 13;          // InpFridayOffHour
input int                InpFridayOffMin     = 0;           // InpFridayOffMin

//--- Telegram Bot
input group "=== Telegram Bot ==="
input bool               InpTgEnable         = false;       // InpTgEnable
input string             InpTgToken          = "";          // InpTgToken
input string             InpTgChatId         = "";          // InpTgChatId

//--- Lainnya
input group "=== Lainnya ==="
input ulong              InpMagic            = 97362;       // InpMagic
input string             InpComment          = "GRIDER";    // (legacy, tidak dipakai)
input int                InpMaxSpread      = 0;           // InpMaxSpread (0 = tanpa batas)
input string             InpLicenseExpiry    = "01-10-2026"; // Lisensi s/d (dd-mm-yyyy)

//--- Globals
CTrade         trade;
string         PREF              = "";
int            g_rsiHandle       = INVALID_HANDLE;
datetime       g_lastRsiBarTime  = 0;
int            g_completedCycles = 0;
datetime       g_lastCycleClose  = 0;
int            g_cycleDayKey     = 0;
bool           g_buyTrailingOn   = false;
bool           g_sellTrailingOn  = false;
double         g_buyTrailExtreme = 0.0;
double         g_sellTrailExtreme = 0.0;

//--- Dashboard layout (kiri atas)
const int      DASH_X            = 8;
const int      DASH_Y            = 18;
const int      DASH_LINE_H       = 16;
const int      DASH_ROWS         = 15;
const int      DASH_W            = 310;
const int      DASH_H            = DASH_ROWS * DASH_LINE_H + 12;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
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

bool PositionMatches(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   if(InpIncludeManual) return true;
   return (PositionGetInteger(POSITION_MAGIC) == (long)InpMagic);
}

bool OrderMatches(ulong ticket)
{
   if(!OrderSelect(ticket)) return false;
   if(OrderGetString(ORDER_SYMBOL) != _Symbol) return false;
   if(InpIncludeManual) return true;
   return (OrderGetInteger(ORDER_MAGIC) == (long)InpMagic);
}

bool IsSpreadOk()
{
   if(InpMaxSpread <= 0) return true;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= InpMaxSpread);
}

bool IsWithinDailyTime()
{
   if(!InpTimeFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   int nowMin   = dt.hour * 60 + dt.min;
   int startMin = InpStartHour * 60 + InpStartMinute;
   int endMin   = InpEndHour * 60 + InpEndMinute;

   if(startMin <= endMin)
      return (nowMin >= startMin && nowMin <= endMin);

   return (nowMin >= startMin || nowMin <= endMin);
}

bool IsFridayBlocked()
{
   if(!InpFridayFilter) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week != 5) return false;

   int nowMin    = dt.hour * 60 + dt.min;
   int offMin    = InpFridayOffHour * 60 + InpFridayOffMin;
   return (nowMin >= offMin);
}

bool CurrencyInNewsFilter(string currency)
{
   string list = InpNewsCurrencies;
   StringReplace(list, " ", "");
   StringToUpper(list);
   StringToUpper(currency);

   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i = 0; i < n; i++)
   {
      if(parts[i] == currency) return true;
   }
   return false;
}

bool ImportanceMatches(ENUM_CALENDAR_EVENT_IMPORTANCE imp)
{
   if(imp == CALENDAR_IMPORTANCE_HIGH   && InpNewsHigh)   return true;
   if(imp == CALENDAR_IMPORTANCE_MODERATE && InpNewsMedium) return true;
   if(imp == CALENDAR_IMPORTANCE_LOW    && InpNewsLow)    return true;
   return false;
}

bool IsNewsBlocking()
{
   if(!InpNewsFilter) return false;

   datetime now = TimeCurrent();
   datetime fromTime = now - (datetime)InpNewsMinBefore * 60;
   datetime toTime   = now + (datetime)InpNewsMinAfter * 60 + 86400;

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, fromTime, toTime);
   if(total <= 0) return false;

   for(int i = 0; i < total; i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event)) continue;
      if(!ImportanceMatches(event.importance)) continue;

      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country)) continue;
      if(!CurrencyInNewsFilter(country.currency)) continue;

      datetime eventTime = values[i].time;
      datetime blockStart = eventTime - (datetime)InpNewsMinBefore * 60;
      datetime blockEnd   = eventTime + (datetime)InpNewsMinAfter * 60;

      if(now >= blockStart && now <= blockEnd)
         return true;
   }
   return false;
}

bool IsTradingAllowed()
{
   if(!IsSpreadOk()) return false;
   if(!IsWithinDailyTime()) return false;
   if(IsFridayBlocked()) return false;
   if(IsNewsBlocking()) return false;
   return true;
}

bool IsCycleCapped()
{
   return (InpMaxCycles > 0 && g_completedCycles >= InpMaxCycles);
}

string CycleMaxLabel()
{
   return (InpMaxCycles > 0 ? IntegerToString(InpMaxCycles) : "OFF");
}

bool CanStartNewCycle()
{
   if(IsCycleCapped()) return false;
   if(g_lastCycleClose == 0) return true;
   datetime cooldownEnd = g_lastCycleClose + (datetime)InpCycleCooldownMin * 60;
   return (TimeCurrent() >= cooldownEnd);
}

int ServerDayKey(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

void CheckDailyCycleReset()
{
   if(!InpCycleResetDaily) return;
   if(InpMaxCycles <= 0) return;
   if(g_completedCycles < InpMaxCycles) return;

   int todayKey = ServerDayKey(TimeCurrent());
   if(g_cycleDayKey == 0)
   {
      g_cycleDayKey = todayKey;
      return;
   }

   if(todayKey == g_cycleDayKey) return;

   g_cycleDayKey = todayKey;
   g_completedCycles = 0;
   g_lastCycleClose = 0;

   string msg = _Symbol + " Cycle reset 00:00 server (0/" + IntegerToString(InpMaxCycles) + ")";
   Print(msg);
   SendTelegram(msg);
}

void SendTelegram(string message)
{
   if(!InpTgEnable || InpTgToken == "" || InpTgChatId == "") return;

   string url  = "https://api.telegram.org/bot" + InpTgToken + "/sendMessage";
   string body = "chat_id=" + InpTgChatId + "&text=" + message;

   char post[];
   char result[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8);

   ResetLastError();
   WebRequest("POST", url, headers, 5000, post, result, headers);
}

double GetRSI(int shift = 1)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_rsiHandle, 0, shift, 1, buf) != 1) return -1.0;
   return buf[0];
}

bool IsNewRsiBar()
{
   datetime barTime = iTime(_Symbol, InpRsiTF, 0);
   if(barTime == 0) return false;
   if(barTime != g_lastRsiBarTime)
   {
      g_lastRsiBarTime = barTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Basket stats                                                     |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionMatches(ticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         count++;
   }
   return count;
}

int CountPendingOrders(ENUM_ORDER_TYPE type)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderMatches(ticket)) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == type)
         count++;
   }
   return count;
}

int CountTotalLayers(ENUM_POSITION_TYPE type)
{
   ENUM_ORDER_TYPE pendType = (type == POSITION_TYPE_BUY)
                              ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   return CountPositions(type) + CountPendingOrders(pendType);
}

double BasketVolume(ENUM_POSITION_TYPE type)
{
   double vol = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionMatches(ticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;
      vol += PositionGetDouble(POSITION_VOLUME);
   }
   return vol;
}

double CalculateBEP(ENUM_POSITION_TYPE type)
{
   double sumPV = 0.0;
   double sumV  = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionMatches(ticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;

      double vol  = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      sumPV += price * vol;
      sumV  += vol;
   }

   if(sumV <= 0.0) return 0.0;
   return sumPV / sumV;
}

double GetExtremeEntry(ENUM_POSITION_TYPE type, bool lowest)
{
   double extreme = 0.0;
   bool found = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionMatches(ticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;

      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      if(!found)
      {
         extreme = price;
         found = true;
      }
      else if(type == POSITION_TYPE_BUY)
      {
         if(lowest  && price < extreme) extreme = price;
         if(!lowest && price > extreme) extreme = price;
      }
      else
      {
         if(lowest  && price < extreme) extreme = price;
         if(!lowest && price > extreme) extreme = price;
      }
   }
   return extreme;
}

bool HasNearbyPending(ENUM_ORDER_TYPE type, double targetPrice)
{
   double gap = InpNoStackGapPts * _Point;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderMatches(ticket)) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != type) continue;

      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(price - targetPrice) < gap)
         return true;
   }
   return false;
}

bool HasNearbyPosition(ENUM_POSITION_TYPE type, double targetPrice)
{
   double gap = InpNoStackGapPts * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionMatches(ticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;

      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(price - targetPrice) < gap)
         return true;
   }
   return false;
}

double LayerLot(int layerIndex)
{
   return NormalizeLot(InpLotPerLayer + (layerIndex - 1) * InpLotIncrement);
}

void DeletePendingByType(ENUM_ORDER_TYPE type)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderMatches(ticket)) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != type) continue;
      trade.OrderDelete(ticket);
   }
}

void ClosePositionsByType(ENUM_POSITION_TYPE type, string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionMatches(ticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;
      trade.PositionClose(ticket);
   }

   if(type == POSITION_TYPE_BUY)
      DeletePendingByType(ORDER_TYPE_BUY_LIMIT);
   else
      DeletePendingByType(ORDER_TYPE_SELL_LIMIT);

   SendTelegram(_Symbol + " " + reason);
}

void ResetTrailingState(ENUM_POSITION_TYPE type)
{
   if(type == POSITION_TYPE_BUY)
   {
      g_buyTrailingOn = false;
      g_buyTrailExtreme = 0.0;
   }
   else
   {
      g_sellTrailingOn = false;
      g_sellTrailExtreme = 0.0;
   }
}

void OnBasketClosed(ENUM_POSITION_TYPE type)
{
   ResetTrailingState(type);

   int otherCount = (type == POSITION_TYPE_BUY)
                    ? CountPositions(POSITION_TYPE_SELL)
                    : CountPositions(POSITION_TYPE_BUY);

   if(otherCount == 0)
   {
      g_completedCycles++;
      g_lastCycleClose = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Entry & Grid                                                     |
//+------------------------------------------------------------------+
string LayerComment(ENUM_POSITION_TYPE type, int layerIndex)
{
   if(type == POSITION_TYPE_BUY)
      return "buy layer " + IntegerToString(layerIndex);
   return "sell layer " + IntegerToString(layerIndex);
}

bool OpenMarketLayer(ENUM_POSITION_TYPE type, int layerIndex)
{
   double lot = LayerLot(layerIndex);
   string comment = LayerComment(type, layerIndex);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);

   bool ok = false;
   if(type == POSITION_TYPE_BUY)
      ok = trade.Buy(lot, _Symbol, 0, 0, 0, comment);
   else
      ok = trade.Sell(lot, _Symbol, 0, 0, 0, comment);

   if(ok)
      SendTelegram(_Symbol + " Layer " + IntegerToString(layerIndex) + " "
                   + (type == POSITION_TYPE_BUY ? "BUY" : "SELL")
                   + " lot=" + DoubleToString(lot, 2));

   return ok;
}

bool PlaceGridLimit(ENUM_POSITION_TYPE type, int layerIndex, double price)
{
   if(HasNearbyPending(type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT, price))
      return false;
   if(HasNearbyPosition(type, price))
      return false;

   double lot = LayerLot(layerIndex);
   string comment = LayerComment(type, layerIndex);
   trade.SetExpertMagicNumber(InpMagic);

   bool ok = false;
   if(type == POSITION_TYPE_BUY)
      ok = trade.BuyLimit(lot, price, _Symbol, 0, 0, ORDER_TIME_GTC, 0, comment);
   else
      ok = trade.SellLimit(lot, price, _Symbol, 0, 0, ORDER_TIME_GTC, 0, comment);

   return ok;
}

void ManageGrid(ENUM_POSITION_TYPE type)
{
   int posCount = CountPositions(type);
   int pendCount = CountPendingOrders(type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT);
   int totalLayers = posCount + pendCount;
   if(totalLayers >= InpMaxLayers) return;

   double anchor = 0.0;
   if(posCount > 0)
      anchor = GetExtremeEntry(type, type == POSITION_TYPE_BUY);
   else
      return;

   int nextLayer = totalLayers + 1;
   double dist = InpLayerDistance * _Point;
   double nextPrice = (type == POSITION_TYPE_BUY) ? anchor - dist : anchor + dist;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   nextPrice = NormalizeDouble(nextPrice, digits);

   if(type == POSITION_TYPE_BUY)
   {
      if(nextPrice >= SymbolInfoDouble(_Symbol, SYMBOL_BID)) return;
   }
   else
   {
      if(nextPrice <= SymbolInfoDouble(_Symbol, SYMBOL_ASK)) return;
   }

   PlaceGridLimit(type, nextLayer, nextPrice);
}

void CheckRSISignals()
{
   if(!IsNewRsiBar()) return;
   if(!IsTradingAllowed()) return;
   if(!CanStartNewCycle()) return;

   double rsi = GetRSI(1);
   if(rsi < 0.0) return;

   int buyCount  = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);

   if(InpAllowBuy && rsi <= InpRsiBuyLevel && buyCount == 0 && sellCount == 0)
   {
      if(OpenMarketLayer(POSITION_TYPE_BUY, 1))
         SendTelegram(_Symbol + " RSI BUY signal RSI=" + DoubleToString(rsi, 2));
   }

   if(InpAllowSell && rsi >= InpRsiSellLevel && sellCount == 0 && buyCount == 0)
   {
      if(OpenMarketLayer(POSITION_TYPE_SELL, 1))
         SendTelegram(_Symbol + " RSI SELL signal RSI=" + DoubleToString(rsi, 2));
   }
}

//+------------------------------------------------------------------+
//| Virtual TP / SL                                                  |
//+------------------------------------------------------------------+
void ManageVirtualExit(ENUM_POSITION_TYPE type)
{
   int count = CountPositions(type);
   if(count == 0)
   {
      ResetTrailingState(type);
      return;
   }

   if(InpTargetProfitUSD > 0.0)
   {
      double basketPL = BasketProfit(type);
      if(basketPL >= InpTargetProfitUSD)
      {
         string dir = (type == POSITION_TYPE_BUY ? "BUY" : "SELL");
         ClosePositionsByType(type, "Target Profit " + dir + " "
                              + DoubleToString(basketPL, 2) + " USD");
         return;
      }
   }

   double bep = CalculateBEP(type);
   if(bep <= 0.0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int totalLayers = CountTotalLayers(type);
   bool bepOnlyMode = (InpBepExitMinLayers > 0 && totalLayers >= InpBepExitMinLayers);

   if(type == POSITION_TYPE_BUY)
   {
      if(InpVirtualSL > 0 && bid <= bep - InpVirtualSL * _Point)
      {
         ClosePositionsByType(POSITION_TYPE_BUY, "Virtual SL BUY");
         return;
      }

      if(bepOnlyMode)
      {
         if(bid > bep)
            ClosePositionsByType(POSITION_TYPE_BUY, "BEP exit BUY (L>"
                                    + IntegerToString(totalLayers) + ")");
         return;
      }
   }
   else
   {
      if(InpVirtualSL > 0 && ask >= bep + InpVirtualSL * _Point)
      {
         ClosePositionsByType(POSITION_TYPE_SELL, "Virtual SL SELL");
         return;
      }

      if(bepOnlyMode)
      {
         if(ask < bep)
            ClosePositionsByType(POSITION_TYPE_SELL, "BEP exit SELL (L>"
                                    + IntegerToString(totalLayers) + ")");
         return;
      }
   }

   double trailStart = InpTrailingStart * _Point;
   double trailStop  = InpTrailingStop * _Point;

   if(type == POSITION_TYPE_BUY)
   {
      if(bid >= bep + trailStart)
      {
         g_buyTrailingOn = true;
         if(g_buyTrailExtreme <= 0.0 || bid > g_buyTrailExtreme)
            g_buyTrailExtreme = bid;
      }

      if(g_buyTrailingOn && g_buyTrailExtreme > 0.0)
      {
         if(bid > g_buyTrailExtreme)
            g_buyTrailExtreme = bid;

         if(bid <= g_buyTrailExtreme - trailStop)
            ClosePositionsByType(POSITION_TYPE_BUY, "Virtual TP BUY (trailing BEP)");
      }
   }
   else
   {
      if(ask <= bep - trailStart)
      {
         g_sellTrailingOn = true;
         if(g_sellTrailExtreme <= 0.0 || ask < g_sellTrailExtreme)
            g_sellTrailExtreme = ask;
      }

      if(g_sellTrailingOn && g_sellTrailExtreme > 0.0)
      {
         if(ask < g_sellTrailExtreme)
            g_sellTrailExtreme = ask;

         if(ask >= g_sellTrailExtreme + trailStop)
            ClosePositionsByType(POSITION_TYPE_SELL, "Virtual TP SELL (trailing BEP)");
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
string TfShort(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      default:         return EnumToString(tf);
   }
}

void DrawDashLabel(int row, string text, color clr, int fontSize = 9)
{
   string name = PREF + "Dash_" + IntegerToString(row);
   int y = DASH_Y + row * DASH_LINE_H;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 100);
   }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, DASH_X);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void CreateDashboardPanel()
{
   string bgName = PREF + "Dash_BG";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bgName, OBJPROP_ZORDER, 0);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }

   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, DASH_X - 4);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, DASH_Y - 6);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, DASH_W);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, DASH_H);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'16,16,20');
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, C'45,45,55');
}

void DestroyDashboard()
{
   ObjectsDeleteAll(0, PREF);
}

double BasketProfit(ENUM_POSITION_TYPE type)
{
   double pl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionMatches(ticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;
      pl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pl;
}

double TotalMatchedProfit()
{
   double pl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionMatches(ticket)) continue;
      pl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pl;
}

string FormatPL(double pl)
{
   string sign = (pl >= 0.0) ? "" : "-";
   return sign + DoubleToString(MathAbs(pl), 2);
}

bool GetNearestNews(datetime &eventTime, string &eventName, bool &isBlocking)
{
   eventTime = 0;
   eventName = "";
   isBlocking = IsNewsBlocking();

   if(!InpNewsFilter) return false;

   datetime now = TimeCurrent();
   datetime fromTime = now - 3600;
   datetime toTime   = now + 86400;

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, fromTime, toTime);
   if(total <= 0) return false;

   datetime nearest = 0;
   string nearestName = "";

   for(int i = 0; i < total; i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event)) continue;
      if(!ImportanceMatches(event.importance)) continue;

      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country)) continue;
      if(!CurrencyInNewsFilter(country.currency)) continue;

      datetime t = values[i].time;
      if(t < now - (datetime)InpNewsMinAfter * 60) continue;

      if(nearest == 0 || t < nearest)
      {
         nearest = t;
         nearestName = event.name;
      }
   }

   if(nearest > 0)
   {
      eventTime = nearest;
      eventName = nearestName;
      return true;
   }
   return false;
}

string Pad2(int v)
{
   return (v < 10 ? "0" : "") + IntegerToString(v);
}

string GetSessionLine(bool &inSession)
{
   inSession = IsWithinDailyTime() && !IsFridayBlocked();

   string sesi = Pad2(InpStartHour) + ":" + Pad2(InpStartMinute) + "-"
                 + Pad2(InpEndHour) + ":" + Pad2(InpEndMinute) + " srv";
   string jumat  = "Jum off " + Pad2(InpFridayOffHour) + ":" + Pad2(InpFridayOffMin);

   if(inSession)
      return ": DALAM sesi " + sesi + " | " + jumat;

   return ": LUAR sesi " + sesi + " | " + jumat;
}

bool IsBuyArmed()
{
   return InpAllowBuy && IsTradingAllowed() && CanStartNewCycle()
          && CountPositions(POSITION_TYPE_BUY) == 0
          && CountPositions(POSITION_TYPE_SELL) == 0;
}

bool IsSellArmed()
{
   return InpAllowSell && IsTradingAllowed() && CanStartNewCycle()
          && CountPositions(POSITION_TYPE_BUY) == 0
          && CountPositions(POSITION_TYPE_SELL) == 0;
}

int ActiveCycleNumber()
{
   int openBaskets = 0;
   if(CountPositions(POSITION_TYPE_BUY) > 0)  openBaskets++;
   if(CountPositions(POSITION_TYPE_SELL) > 0) openBaskets++;
   int active = g_completedCycles + openBaskets;
   if(active < 1 && openBaskets == 0 && g_completedCycles == 0) active = 0;
   return active;
}

void UpdateDashboard()
{
   CreateDashboardPanel();

   bool eaOn = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
               && (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   string statusTxt = eaOn ? "[ON]" : "[OFF]";

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   double rsi = GetRSI(0);
   int buyPos   = CountPositions(POSITION_TYPE_BUY);
   int sellPos  = CountPositions(POSITION_TYPE_SELL);
   int buyPnd   = CountPendingOrders(ORDER_TYPE_BUY_LIMIT);
   int sellPnd  = CountPendingOrders(ORDER_TYPE_SELL_LIMIT);
   double buyPL  = BasketProfit(POSITION_TYPE_BUY);
   double sellPL = BasketProfit(POSITION_TYPE_SELL);
   double totalPL = TotalMatchedProfit();

   bool inSession = false;
   string sessionLine = GetSessionLine(inSession);

   datetime newsTime = 0;
   string newsName = "";
   bool newsBlocking = false;
   bool hasNews = GetNearestNews(newsTime, newsName, newsBlocking);

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   int activeCycle = ActiveCycleNumber();
   if(activeCycle == 0 && (buyPos + sellPos) > 0)
      activeCycle = g_completedCycles + 1;

   // Row 0 - Header
   DrawDashLabel(0, "== RSI5 GRID EA v1.09 " + statusTxt + " ==", clrYellow);

   // Row 1 - Balance / Equity
   DrawDashLabel(1,
      "Bal: " + DoubleToString(balance, 2) + " | Eq: " + DoubleToString(equity, 2) + " " + currency,
      clrLime, 10);

   // Row 2 - RSI
   DrawDashLabel(2,
      "RSI(" + IntegerToString(InpRsiPeriod) + ") " + TfShort(InpRsiTF) + ": "
      + DoubleToString(rsi, 2) + "  arm B:" + (IsBuyArmed() ? "Y" : "N")
      + " S:" + (IsSellArmed() ? "Y" : "N"),
      clrGreen);

   // Row 3 - Server time
   DrawDashLabel(3, "Srv time: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES), clrSilver);

   // Row 4 - Session
   DrawDashLabel(4, sessionLine, inSession ? clrGreen : clrOrangeRed);

   // Row 5-6 - News
   if(!InpNewsFilter)
   {
      DrawDashLabel(5, "News: OFF", clrSilver);
      DrawDashLabel(6, "filter news nonaktif", clrGray);
   }
   else if(newsBlocking)
   {
      DrawDashLabel(5, "News: BLOCK", clrOrangeRed);
      DrawDashLabel(6, hasNews ? TimeToString(newsTime, TIME_MINUTES) + " | " + newsName : "news aktif", clrGray);
   }
   else
   {
      DrawDashLabel(5, "News: clear", clrGreen);
      if(hasNews)
      {
         string detail = TimeToString(newsTime, TIME_MINUTES) + " | " + newsName;
         if(StringLen(detail) > 42) detail = StringSubstr(detail, 0, 42) + "...";
         DrawDashLabel(6, detail, clrGray);
      }
      else
         DrawDashLabel(6, "tidak ada news terdekat", clrGray);
   }

   // Row 7 - BUY stats
   DrawDashLabel(7,
      "BUY  pos:" + IntegerToString(buyPos) + "  pnd:" + IntegerToString(buyPnd)
      + "  P/L: " + FormatPL(buyPL),
      (buyPL >= 0.0 ? clrGreen : clrOrangeRed));

   // Row 8 - SELL stats
   DrawDashLabel(8,
      "SELL pos:" + IntegerToString(sellPos) + "  pnd:" + IntegerToString(sellPnd)
      + "  P/L: " + FormatPL(sellPL),
      (sellPL >= 0.0 ? clrGreen : clrOrangeRed));

   // Row 9 - Cycle & total P/L
   string cycleExtra = "";
   if(IsCycleCapped() && InpCycleResetDaily)
      cycleExtra = " | reset 00:00 srv";
   DrawDashLabel(9,
      "Cycle aktif: " + IntegerToString(activeCycle) + " / " + CycleMaxLabel()
      + cycleExtra
      + " | Total P/L: " + FormatPL(totalPL),
      (totalPL >= 0.0 ? clrGreen : clrOrangeRed));

   // Row 10 - per-basket summary
   DrawDashLabel(10,
      "C" + IntegerToString(sellPos) + ":S" + FormatPL(sellPL)
      + "  C" + IntegerToString(buyPos) + ":B" + FormatPL(buyPL),
      clrDeepSkyBlue);

   // Row 11 - Spread & layer
   string bepMode = (InpBepExitMinLayers > 0
                     ? " | BEP>=" + IntegerToString(InpBepExitMinLayers) + "L"
                     : "");
   DrawDashLabel(11,
      "Spread: " + IntegerToString(spread) + " pt | Layer: "
      + IntegerToString(InpMaxLayers) + " x " + IntegerToString(InpLayerDistance) + " pt"
      + bepMode,
      clrSilver);

   // Row 12 - Connection & lot
   bool connected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   DrawDashLabel(12,
      "S:" + (connected ? "SAMBUNG" : "PUTUS") + " | Lot:"
      + DoubleToString(InpLotPerLayer, 2) + "+" + DoubleToString(InpLotIncrement, 2)
      + " | C:" + IntegerToString(InpCycleCooldownMin)
      + " | TG:" + (InpTgEnable ? "on" : "off"),
      clrSilver);

   // Row 13 - TP / SL / Manual
   string slTxt = (InpVirtualSL > 0 ? IntegerToString(InpVirtualSL) + " pt" : "OFF");
   string tgtTxt = (InpTargetProfitUSD > 0.0
                    ? DoubleToString(InpTargetProfitUSD, 0) + " USD"
                    : "OFF");
   DrawDashLabel(13,
      "TP " + IntegerToString(InpTrailingStart) + "/" + IntegerToString(InpTrailingStop)
      + " | Tgt:" + tgtTxt
      + " | SL " + slTxt + " | Manual:" + (InpIncludeManual ? "ON" : "OFF"),
      clrDeepSkyBlue);

   // Row 14 - License
   DrawDashLabel(14, "Lisensi s/d: " + InpLicenseExpiry, clrYellow);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   PREF = "RSIG5_" + IntegerToString(InpMagic) + "_";

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetAsyncMode(false);

   g_rsiHandle = iRSI(_Symbol, InpRsiTF, InpRsiPeriod, PRICE_CLOSE);
   if(g_rsiHandle == INVALID_HANDLE)
   {
      Print("Gagal membuat handle RSI. Error: ", GetLastError());
      return INIT_FAILED;
   }

   g_lastRsiBarTime = iTime(_Symbol, InpRsiTF, 0);
   g_cycleDayKey = ServerDayKey(TimeCurrent());
   CreateDashboardPanel();
   UpdateDashboard();

   if(!EventSetTimer(1))
      Print("Gagal mengaktifkan timer dashboard. Error: ", GetLastError());

   Print("RSI5_GridLimit_EA v1.61 initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_rsiHandle != INVALID_HANDLE)
      IndicatorRelease(g_rsiHandle);
   DestroyDashboard();
   Comment("");
}

void OnTimer()
{
   CheckDailyCycleReset();
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   static int prevBuyCount  = 0;
   static int prevSellCount = 0;

   CheckDailyCycleReset();
   CheckRSISignals();

   int buyCount  = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);

   if(buyCount > 0)
   {
      ManageGrid(POSITION_TYPE_BUY);
      ManageVirtualExit(POSITION_TYPE_BUY);
   }
   else
      ResetTrailingState(POSITION_TYPE_BUY);

   if(sellCount > 0)
   {
      ManageGrid(POSITION_TYPE_SELL);
      ManageVirtualExit(POSITION_TYPE_SELL);
   }
   else
      ResetTrailingState(POSITION_TYPE_SELL);

   if(prevBuyCount > 0 && buyCount == 0)
      OnBasketClosed(POSITION_TYPE_BUY);
   if(prevSellCount > 0 && sellCount == 0)
      OnBasketClosed(POSITION_TYPE_SELL);

   prevBuyCount  = buyCount;
   prevSellCount = sellCount;
}
