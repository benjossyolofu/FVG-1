#property copyright "TTM FVG Liquidity BoS"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#define PREFIX "TTM_FLB_"
#define DIR_BULL 1
#define DIR_BEAR -1

enum ENUM_TTM_SL_MODE
{
   SL_DEEPEST_FVG_WICK = 0,
   SL_FVG_BOUNDARY = 1,
   SL_LIQUIDITY_LEVEL = 2
};

input int InpMaxBarsToScan = 1000;
input bool InpShowBullishSetups = true;
input bool InpShowBearishSetups = true;
input int InpMinFVGSizePoints = 10;
input bool InpStrictCloseInsideInvalidatesFVG = true;
input bool InpRequireImpulseCandle = true;
input double InpMinImpulseBodyPercent = 50.0;
input int InpSwingDepth = 2;
input int InpMinBarsAfterFVGForLiquidity = 2;
input int InpMaxBarsAfterFVGForLiquidity = 80;
input int InpMaxBarsAfterLiquidityForBoS = 80;
input int InpMaxBarsAfterBoSForEntry = 120;
input bool InpBoSByWick = true;
input bool InpAlertOnSetupFormed = true;
input bool InpAlertOnEntryTrigger = true;
input bool InpEnablePopupAlert = true;
input bool InpEnablePushAlert = false;
input bool InpEnableEmailAlert = false;
input bool InpEnableSoundAlert = true;
input string InpSoundFile = "alert.wav";
input bool InpShowSLTPBE = true;
input bool InpShowTradeInfoLabel = true;
input ENUM_TTM_SL_MODE InpStopLossMode = SL_DEEPEST_FVG_WICK;
input double InpRiskReward = 3.0;
input double InpBreakEvenRR = 1.5;
input int InpSLBufferPoints = 20;
input color InpBullishFVGColor = clrMediumSeaGreen;
input color InpBearishFVGColor = clrTomato;
input color InpBullishLineColor = clrDodgerBlue;
input color InpBearishLineColor = clrOrangeRed;
input color InpTextColor = clrWhite;
input bool InpShowFVGZones = true;
input bool InpShowLiquidityLines = true;
input bool InpShowBoSLabels = true;
input bool InpShowEntryMarkers = true;
input bool InpShowLatestSetupOnly = false;
input int InpMaxDisplayedSetups = 20;
input int InpMaxStoredSetups = 100;

struct TTMSetup
{
   int direction;
   datetime fvgTime;
   datetime fvgEndTime;
   double fvgTop;
   double fvgBottom;
   int fvgIndex;
   datetime liquidityTime;
   double liquidityPrice;
   double structureLevel;
   int liquidityIndex;
   datetime bosTime;
   double bosPrice;
   int bosIndex;
   datetime entryTime;
   double entryPrice;
   double slPrice;
   double bePrice;
   double tpPrice;
   bool hasLiquidity;
   bool hasBoS;
   bool hasReturned;
   bool hasEntry;
   bool invalidated;
};

TTMSetup g_setups[];
datetime g_lastClosedBarTime = 0;
string g_setupAlertIds[];
string g_entryAlertIds[];

double PointValue()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

string DirectionText(const int direction)
{
   return direction == DIR_BULL ? "BUY" : "SELL";
}

string TimeId(const datetime value)
{
   MqlDateTime dt;
   TimeToStruct(value, dt);
   return StringFormat("%04d%02d%02d%02d%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min);
}

string SetupId(const TTMSetup &setup)
{
   return PREFIX + _Symbol + "_" + IntegerToString((int)_Period) + "_" + IntegerToString(setup.direction) + "_" + TimeId(setup.fvgTime);
}

bool IsBullishFVG(const int i, const double &high[], const double &low[])
{
   return low[i - 2] > high[i];
}

bool IsBearishFVG(const int i, const double &high[], const double &low[])
{
   return high[i - 2] < low[i];
}

bool FVGSizeOk(const double top, const double bottom)
{
   return (top - bottom) >= InpMinFVGSizePoints * PointValue();
}

bool ImpulseCandleOk(const int direction, const int middleIndex, const double &open[], const double &high[], const double &low[], const double &close[])
{
   if(!InpRequireImpulseCandle)
      return true;

   double candleRange = high[middleIndex] - low[middleIndex];
   if(candleRange <= 0.0)
      return false;

   double bodySize = MathAbs(close[middleIndex] - open[middleIndex]);
   double bodyPercent = bodySize / candleRange * 100.0;
   if(bodyPercent < InpMinImpulseBodyPercent)
      return false;

   if(direction == DIR_BULL)
      return close[middleIndex] > open[middleIndex];

   return close[middleIndex] < open[middleIndex];
}

bool CloseInvalidatesFVG(const int direction, const double closePrice, const double top, const double bottom)
{
   if(InpStrictCloseInsideInvalidatesFVG)
      return closePrice <= top && closePrice >= bottom;

   if(direction == DIR_BULL)
      return closePrice < bottom;

   return closePrice > top;
}

bool IsFVGUntappedAfter(const int direction, const int fvgIndex, const int untilIndex, const double top, const double bottom, const double &close[])
{
   for(int j = fvgIndex - 1; j >= untilIndex; j--)
   {
      if(CloseInvalidatesFVG(direction, close[j], top, bottom))
         return false;
   }
   return true;
}

double StopLossPrice(const TTMSetup &setup, const double deepestRetrace)
{
   double buffer = InpSLBufferPoints * PointValue();

   if(setup.direction == DIR_BULL)
   {
      if(InpStopLossMode == SL_FVG_BOUNDARY)
         return setup.fvgBottom - buffer;
      if(InpStopLossMode == SL_LIQUIDITY_LEVEL)
         return setup.liquidityPrice - buffer;

      return deepestRetrace - buffer;
   }

   if(InpStopLossMode == SL_FVG_BOUNDARY)
      return setup.fvgTop + buffer;
   if(InpStopLossMode == SL_LIQUIDITY_LEVEL)
      return setup.liquidityPrice + buffer;

   return deepestRetrace + buffer;
}

bool IsSwingLow(const int i, const int depth, const double &low[], const int rates_total)
{
   if(i - depth < 1 || i + depth >= rates_total)
      return false;

   for(int k = 1; k <= depth; k++)
   {
      if(low[i] >= low[i - k] || low[i] >= low[i + k])
         return false;
   }
   return true;
}

bool IsSwingHigh(const int i, const int depth, const double &high[], const int rates_total)
{
   if(i - depth < 1 || i + depth >= rates_total)
      return false;

   for(int k = 1; k <= depth; k++)
   {
      if(high[i] <= high[i - k] || high[i] <= high[i + k])
         return false;
   }
   return true;
}

bool FindLiquidity(TTMSetup &setup, const int rates_total, const double &high[], const double &low[], const double &close[], const datetime &time[])
{
   int newestAllowed = MathMax(1 + InpSwingDepth, setup.fvgIndex - InpMaxBarsAfterFVGForLiquidity);
   int oldestAllowed = setup.fvgIndex - 2 - MathMax(0, InpMinBarsAfterFVGForLiquidity);

   for(int i = oldestAllowed; i >= newestAllowed; i--)
   {
      if(!IsFVGUntappedAfter(setup.direction, setup.fvgIndex, i, setup.fvgTop, setup.fvgBottom, close))
         return false;

      if(setup.direction == DIR_BULL)
      {
         if(IsSwingLow(i, InpSwingDepth, low, rates_total) && low[i] > setup.fvgTop)
         {
            setup.liquidityTime = time[i];
            setup.liquidityPrice = low[i];
            setup.structureLevel = high[i + 1];
            for(int k = i + 1; k <= setup.fvgIndex - 1; k++)
               setup.structureLevel = MathMax(setup.structureLevel, high[k]);
            setup.liquidityIndex = i;
            setup.hasLiquidity = true;
            return true;
         }
      }
      else
      {
         if(IsSwingHigh(i, InpSwingDepth, high, rates_total) && high[i] < setup.fvgBottom)
         {
            setup.liquidityTime = time[i];
            setup.liquidityPrice = high[i];
            setup.structureLevel = low[i + 1];
            for(int k = i + 1; k <= setup.fvgIndex - 1; k++)
               setup.structureLevel = MathMin(setup.structureLevel, low[k]);
            setup.liquidityIndex = i;
            setup.hasLiquidity = true;
            return true;
         }
      }
   }
   return false;
}

bool LiquidityInvalidatedBeforeBoS(const TTMSetup &setup, const int fromIndex, const int toIndex, const double &close[])
{
   for(int i = fromIndex; i >= toIndex; i--)
   {
      if(setup.direction == DIR_BULL && close[i] < setup.liquidityPrice)
         return true;
      if(setup.direction == DIR_BEAR && close[i] > setup.liquidityPrice)
         return true;
   }
   return false;
}

bool FindBoS(TTMSetup &setup, const double &high[], const double &low[], const double &close[], const datetime &time[])
{
   int newestAllowed = MathMax(1, setup.liquidityIndex - InpMaxBarsAfterLiquidityForBoS);

   for(int i = setup.liquidityIndex - 1; i >= newestAllowed; i--)
   {
      if(!IsFVGUntappedAfter(setup.direction, setup.fvgIndex, i, setup.fvgTop, setup.fvgBottom, close))
         return false;

      if(LiquidityInvalidatedBeforeBoS(setup, setup.liquidityIndex - 1, i, close))
         return false;

      if(setup.direction == DIR_BULL)
      {
         double breakPrice = InpBoSByWick ? high[i] : close[i];
         if(breakPrice > setup.structureLevel)
         {
            setup.bosTime = time[i];
            setup.bosPrice = breakPrice;
            setup.bosIndex = i;
            setup.hasBoS = true;
            return true;
         }
      }
      else
      {
         double breakPrice = InpBoSByWick ? low[i] : close[i];
         if(breakPrice < setup.structureLevel)
         {
            setup.bosTime = time[i];
            setup.bosPrice = breakPrice;
            setup.bosIndex = i;
            setup.hasBoS = true;
            return true;
         }
      }
   }
   return false;
}

void FindEntry(TTMSetup &setup, const double &open[], const double &high[], const double &low[], const double &close[], const datetime &time[])
{
   int newestAllowed = MathMax(1, setup.bosIndex - InpMaxBarsAfterBoSForEntry);
   double deepestRetrace = setup.direction == DIR_BULL ? DBL_MAX : -DBL_MAX;

   for(int i = setup.bosIndex - 1; i >= newestAllowed; i--)
   {
      if(CloseInvalidatesFVG(setup.direction, close[i], setup.fvgTop, setup.fvgBottom))
      {
         setup.invalidated = true;
         return;
      }

      if(setup.direction == DIR_BULL)
      {
         if(low[i] <= setup.fvgTop)
         {
            setup.hasReturned = true;
            deepestRetrace = MathMin(deepestRetrace, low[i]);
         }

         if(setup.hasReturned && close[i] > open[i])
         {
            setup.entryTime = time[i];
            setup.entryPrice = close[i];
            setup.slPrice = StopLossPrice(setup, deepestRetrace == DBL_MAX ? setup.fvgBottom : deepestRetrace);
            double risk = setup.entryPrice - setup.slPrice;
            if(risk <= 0.0)
            {
               setup.invalidated = true;
               return;
            }
            setup.bePrice = setup.entryPrice + risk * InpBreakEvenRR;
            setup.tpPrice = setup.entryPrice + risk * InpRiskReward;
            setup.hasEntry = true;
            return;
         }
      }
      else
      {
         if(high[i] >= setup.fvgBottom)
         {
            setup.hasReturned = true;
            deepestRetrace = MathMax(deepestRetrace, high[i]);
         }

         if(setup.hasReturned && close[i] < open[i])
         {
            setup.entryTime = time[i];
            setup.entryPrice = close[i];
            setup.slPrice = StopLossPrice(setup, deepestRetrace == -DBL_MAX ? setup.fvgTop : deepestRetrace);
            double risk = setup.slPrice - setup.entryPrice;
            if(risk <= 0.0)
            {
               setup.invalidated = true;
               return;
            }
            setup.bePrice = setup.entryPrice - risk * InpBreakEvenRR;
            setup.tpPrice = setup.entryPrice - risk * InpRiskReward;
            setup.hasEntry = true;
            return;
         }
      }
   }
}

bool SetupExists(const datetime fvgTime, const int direction)
{
   int total = ArraySize(g_setups);
   for(int i = 0; i < total; i++)
   {
      if(g_setups[i].fvgTime == fvgTime && g_setups[i].direction == direction)
         return true;
   }
   return false;
}

void AddSetup(const TTMSetup &setup)
{
   int total = ArraySize(g_setups);
   ArrayResize(g_setups, total + 1);
   g_setups[total] = setup;
}

void TrimStoredSetups()
{
   int total = ArraySize(g_setups);
   if(InpMaxStoredSetups <= 0 || total <= InpMaxStoredSetups)
      return;

   int removeCount = total - InpMaxStoredSetups;
   for(int i = 0; i < total - removeCount; i++)
      g_setups[i] = g_setups[i + removeCount];

   ArrayResize(g_setups, InpMaxStoredSetups);
}

void SetObjectCommon(const string name)
{
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawRectangle(const string name, const datetime t1, const datetime t2, const double top, const double bottom, const color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom);
   else
   {
      ObjectMove(0, name, 0, t1, top);
      ObjectMove(0, name, 1, t2, bottom);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, ColorToARGB(clr, 55));
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   SetObjectCommon(name);
}

void DrawTrendLine(const string name, const datetime t1, const datetime t2, const double price, const color clr, const int style = STYLE_SOLID)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
   {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
   }

   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   SetObjectCommon(name);
}

void DrawText(const string name, const datetime t, const double price, const string text, const color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   SetObjectCommon(name);
}

void DrawArrow(const string name, const datetime t, const double price, const int direction)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, direction == DIR_BULL ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, direction == DIR_BULL ? clrLime : clrRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   SetObjectCommon(name);
}

string TradeInfoText(const TTMSetup &setup)
{
   double riskPoints = MathAbs(setup.entryPrice - setup.slPrice) / PointValue();
   return DirectionText(setup.direction) +
          " Entry: " + DoubleToString(setup.entryPrice, _Digits) +
          " | SL: " + DoubleToString(setup.slPrice, _Digits) +
          " | BE: " + DoubleToString(setup.bePrice, _Digits) +
          " | TP: " + DoubleToString(setup.tpPrice, _Digits) +
          " | Risk: " + DoubleToString(riskPoints, 1) + " pts";
}

void SendTTMAlert(const string message)
{
   if(InpEnablePopupAlert)
      Alert(message);
   if(InpEnablePushAlert)
      SendNotification(message);
   if(InpEnableEmailAlert)
      SendMail("TTM Indicator Alert", message);
   if(InpEnableSoundAlert)
      PlaySound(InpSoundFile);
}

bool HasAlerted(const string &ids[], const string id)
{
   int total = ArraySize(ids);
   for(int i = 0; i < total; i++)
   {
      if(ids[i] == id)
         return true;
   }
   return false;
}

void MarkAlerted(string &ids[], const string id)
{
   int total = ArraySize(ids);
   ArrayResize(ids, total + 1);
   ids[total] = id;
}

void SendOneTimeAlert(string &ids[], const string id, const string message)
{
   if(HasAlerted(ids, id))
      return;

   SendTTMAlert(message);
   MarkAlerted(ids, id);
}

void DrawSetup(const TTMSetup &setup, const datetime lastTime)
{
   string id = SetupId(setup);
   color zoneColor = setup.direction == DIR_BULL ? InpBullishFVGColor : InpBearishFVGColor;
   color lineColor = setup.direction == DIR_BULL ? InpBullishLineColor : InpBearishLineColor;
   datetime endTime = setup.hasEntry ? setup.entryTime : lastTime;

   if(InpShowFVGZones)
      DrawRectangle(id + "_FVG", setup.fvgTime, endTime, setup.fvgTop, setup.fvgBottom, zoneColor);

   if(InpShowLiquidityLines)
   {
      DrawTrendLine(id + "_LIQ", setup.liquidityTime, endTime, setup.liquidityPrice, lineColor);
      DrawText(id + "_LIQ_TXT", setup.liquidityTime, setup.liquidityPrice, "Liquidity", InpTextColor);
   }

   if(InpShowBoSLabels)
      DrawText(id + "_BOS", setup.bosTime, setup.bosPrice, "BoS", InpTextColor);

   if(setup.hasEntry && InpShowEntryMarkers)
   {
      DrawArrow(id + "_ENTRY", setup.entryTime, setup.entryPrice, setup.direction);
      DrawText(id + "_ENTRY_TXT", setup.entryTime, setup.entryPrice, DirectionText(setup.direction), InpTextColor);

      if(InpShowSLTPBE)
      {
         DrawTrendLine(id + "_SL", setup.entryTime, endTime, setup.slPrice, clrRed, STYLE_DOT);
         DrawTrendLine(id + "_BE", setup.entryTime, endTime, setup.bePrice, clrGold, STYLE_DASH);
         DrawTrendLine(id + "_TP", setup.entryTime, endTime, setup.tpPrice, clrLime, STYLE_DOT);
         DrawText(id + "_SL_TXT", setup.entryTime, setup.slPrice, "SL", clrRed);
         DrawText(id + "_BE_TXT", setup.entryTime, setup.bePrice, "BE", clrGold);
         DrawText(id + "_TP_TXT", setup.entryTime, setup.tpPrice, "TP 1:" + DoubleToString(InpRiskReward, 1), clrLime);
      }

      if(InpShowTradeInfoLabel)
         DrawText(id + "_INFO", setup.entryTime, setup.entryPrice, TradeInfoText(setup), InpTextColor);
   }
}

int FirstDisplayedSetupIndex()
{
   int total = ArraySize(g_setups);
   if(InpShowLatestSetupOnly && total > 0)
      return total - 1;

   if(InpMaxDisplayedSetups <= 0 || total <= InpMaxDisplayedSetups)
      return 0;

   return total - InpMaxDisplayedSetups;
}

void DeleteObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PREFIX) == 0)
         ObjectDelete(0, name);
   }
}

void RedrawVisibleSetups(const datetime lastTime, const bool cleanFirst)
{
   if(cleanFirst)
      DeleteObjects();

   for(int i = FirstDisplayedSetupIndex(); i < ArraySize(g_setups); i++)
      DrawSetup(g_setups[i], lastTime);
}

void ScanSetups(const int rates_total, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[])
{
   int maxBars = MathMin(InpMaxBarsToScan, rates_total - InpSwingDepth - 5);
   if(maxBars < InpSwingDepth + 5)
      return;

   int oldest = maxBars;

   for(int i = oldest; i >= 3; i--)
   {
      int direction = 0;
      double top = 0.0;
      double bottom = 0.0;

      if(InpShowBullishSetups && IsBullishFVG(i, high, low))
      {
         direction = DIR_BULL;
         top = low[i - 2];
         bottom = high[i];
      }
      else if(InpShowBearishSetups && IsBearishFVG(i, high, low))
      {
         direction = DIR_BEAR;
         top = low[i];
         bottom = high[i - 2];
      }

      if(direction == 0 || !FVGSizeOk(top, bottom) || !ImpulseCandleOk(direction, i - 1, open, high, low, close) || SetupExists(time[i], direction))
         continue;

      TTMSetup setup;
      ZeroMemory(setup);
      setup.direction = direction;
      setup.fvgTime = time[i];
      setup.fvgEndTime = time[i - 2];
      setup.fvgTop = top;
      setup.fvgBottom = bottom;
      setup.fvgIndex = i;

      if(!FindLiquidity(setup, rates_total, high, low, close, time))
         continue;

      if(!FindBoS(setup, high, low, close, time))
         continue;

      FindEntry(setup, open, high, low, close, time);

      if(!setup.invalidated)
      {
         AddSetup(setup);
         TrimStoredSetups();

         string setupMessage = _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period) + " TTM A+ " + DirectionText(direction) + " setup formed";
         if(InpAlertOnSetupFormed && setup.bosIndex == 1)
            SendOneTimeAlert(g_setupAlertIds, SetupId(setup) + "_SETUP", setupMessage);

         string entryMessage = _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period) + " TTM " + DirectionText(direction) + " entry trigger";
         if(InpAlertOnEntryTrigger && setup.hasEntry && setup.entryTime == time[1])
            SendOneTimeAlert(g_entryAlertIds, SetupId(setup) + "_ENTRY", entryMessage);
      }
   }
}

int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "TTM FVG Liquidity BoS");
   ArrayResize(g_setups, 0);
   ArrayResize(g_setupAlertIds, 0);
   ArrayResize(g_entryAlertIds, 0);
   DeleteObjects();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteObjects();
}

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
   if(rates_total < InpSwingDepth * 2 + 10)
      return 0;

   if(prev_calculated == 0)
   {
      ArrayResize(g_setups, 0);
      ArrayResize(g_setupAlertIds, 0);
      ArrayResize(g_entryAlertIds, 0);
      DeleteObjects();
      ScanSetups(rates_total, time, open, high, low, close);
      g_lastClosedBarTime = time[1];
      RedrawVisibleSetups(time[1], false);
      return rates_total;
   }

   if(time[1] != g_lastClosedBarTime)
   {
      ScanSetups(rates_total, time, open, high, low, close);
      g_lastClosedBarTime = time[1];
      RedrawVisibleSetups(time[1], true);
      return rates_total;
   }

   RedrawVisibleSetups(time[1], false);

   return rates_total;
}
