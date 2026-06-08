#property copyright "TTM Setup Entry v2"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#define PREFIX "TTM_SETUP_ENTRY_V2_"
#define DIR_BULL 1
#define DIR_BEAR -1

input int MaxBarsToScan = 500;
input int MaxSetupsToDisplay = 5;
input int MinFvgSizePoints = 1;
input int RectangleLengthBars = 40;
input int SwingStrength = 2;
input int MinLiquidityCandles = 2;
input bool InvalidateOnCloseInside = true;
input bool BoSByClose = false;
input bool ShowDiagnosticsPanel = true;
input bool ShowOnlyEntrySetups = false;
input bool EnableEntryAlerts = true;
input bool UsePopupAlert = true;
input bool UseSoundAlert = true;
input bool UsePushNotification = false;
input string AlertSoundFile = "alert.wav";
input color BullishFvgColor = clrLimeGreen;
input color BearishFvgColor = clrRed;
input color LiquidityColor = clrDodgerBlue;
input color BosColor = clrGold;
input color EntryColor = clrAqua;
input color TextColor = clrWhite;

struct TTMSetup
{
   int direction;
   datetime fvgStartTime;
   datetime fvgEndTime;
   datetime liquidityTime;
   datetime bosTime;
   double fvgTop;
   double fvgBottom;
   double liquidityPrice;
   double breakPrice;
   datetime entryTime;
   double entryPrice;
   bool returnedToFvg;
   bool entryTriggered;
};

TTMSetup g_setups[];
int g_fvgCandidates = 0;
int g_liquidityFound = 0;
int g_bosFound = 0;
int g_returnedToFvg = 0;
int g_entryTriggered = 0;
int g_setupsDisplayed = 0;
int g_objectsCreated = 0;
int g_objectCreateFailures = 0;
int g_lastObjectError = 0;

int IndexFromNewest(const int barsAgo, const int rates_total, const datetime &time[])
{
   bool series = time[0] > time[rates_total - 1];
   if(series)
      return MathMin(MathMax(barsAgo, 0), rates_total - 1);

   return MathMin(MathMax(rates_total - 1 - barsAgo, 0), rates_total - 1);
}

double PointValue()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

string TimeId(const datetime value)
{
   MqlDateTime dt;
   TimeToStruct(value, dt);
   return StringFormat("%04d%02d%02d%02d%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min);
}

string SetupId(const TTMSetup &setup)
{
   return PREFIX + _Symbol + "_" + IntegerToString((int)_Period) + "_" + IntegerToString(setup.direction) + "_" + TimeId(setup.fvgStartTime);
}

string EntryAlertKey(const TTMSetup &setup)
{
   return "TTM_ENTRY_" + _Symbol + "_" + IntegerToString((int)_Period) + "_" + IntegerToString(setup.direction) + "_" + TimeId(setup.fvgStartTime);
}

bool FVGSizeOk(const double top, const double bottom)
{
   return (top - bottom) >= MinFvgSizePoints * PointValue();
}

bool CloseInvalidatesFVG(const double closePrice, const double top, const double bottom, const int direction)
{
   if(InvalidateOnCloseInside && closePrice <= top && closePrice >= bottom)
      return true;

   if(direction == DIR_BULL)
      return closePrice < bottom;

   return closePrice > top;
}

bool BarTouchesFVG(const double barHigh, const double barLow, const double top, const double bottom)
{
   return barLow <= top && barHigh >= bottom;
}

bool DirectionalClose(const int direction, const double openPrice, const double closePrice)
{
   if(direction == DIR_BULL)
      return closePrice > openPrice;

   return closePrice < openPrice;
}

string DirectionText(const int direction)
{
   return direction == DIR_BULL ? "Bullish" : "Bearish";
}

bool FVGUntappedUntil(const int fvgShift, const int untilShift, const int rates_total, const datetime &time[], const double &close[], const double top, const double bottom, const int direction)
{
   for(int shift = fvgShift - 1; shift >= untilShift; shift--)
   {
      int index = IndexFromNewest(shift, rates_total, time);
      if(CloseInvalidatesFVG(close[index], top, bottom, direction))
         return false;
   }

   return true;
}

bool IsSwingLow(const int shift, const int rates_total, const datetime &time[], const double &low[])
{
   int center = IndexFromNewest(shift, rates_total, time);
   for(int offset = 1; offset <= SwingStrength; offset++)
   {
      if(shift - offset < 0 || shift + offset >= rates_total)
         return false;

      int left = IndexFromNewest(shift + offset, rates_total, time);
      int right = IndexFromNewest(shift - offset, rates_total, time);
      if(low[center] >= low[left] || low[center] >= low[right])
         return false;
   }

   return true;
}

bool IsSwingHigh(const int shift, const int rates_total, const datetime &time[], const double &high[])
{
   int center = IndexFromNewest(shift, rates_total, time);
   for(int offset = 1; offset <= SwingStrength; offset++)
   {
      if(shift - offset < 0 || shift + offset >= rates_total)
         return false;

      int left = IndexFromNewest(shift + offset, rates_total, time);
      int right = IndexFromNewest(shift - offset, rates_total, time);
      if(high[center] <= high[left] || high[center] <= high[right])
         return false;
   }

   return true;
}

void DeleteObjects()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, PREFIX) == 0)
         ObjectDelete(0, name);
   }
}

bool CreateObjectChecked(const string name, const ENUM_OBJECT type, const datetime t1, const double p1, const datetime t2 = 0, const double p2 = 0.0)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ResetLastError();
   bool created = ObjectCreate(0, name, type, 0, t1, p1, t2, p2);
   if(created)
      g_objectsCreated++;
   else
   {
      g_objectCreateFailures++;
      g_lastObjectError = GetLastError();
   }

   return created;
}

void SetObjectCommon(const string name)
{
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
}

void DrawRectangle(const string name, datetime t1, datetime t2, double top, double bottom, const color rectColor)
{
   if(t2 < t1)
   {
      datetime tempTime = t1;
      t1 = t2;
      t2 = tempTime;
   }

   if(bottom > top)
   {
      double tempPrice = top;
      top = bottom;
      bottom = tempPrice;
   }

   if(!CreateObjectChecked(name, OBJ_RECTANGLE, t1, top, t2, bottom))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, rectColor);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   SetObjectCommon(name);
}

void DrawLine(const string name, datetime t1, datetime t2, const double price, const color lineColor)
{
   if(t2 < t1)
   {
      datetime tempTime = t1;
      t1 = t2;
      t2 = tempTime;
   }

   if(!CreateObjectChecked(name, OBJ_TREND, t1, price, t2, price))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   SetObjectCommon(name);
}

void DrawText(const string name, const datetime textTime, const double price, const string text, const color textColor)
{
   if(!CreateObjectChecked(name, OBJ_TEXT, textTime, price))
      return;

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   SetObjectCommon(name);
}

void DrawArrow(const string name, const datetime arrowTime, const double price, const int direction, const color arrowColor)
{
   if(!CreateObjectChecked(name, OBJ_ARROW, arrowTime, price))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, arrowColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, direction == DIR_BULL ? 233 : 234);
   SetObjectCommon(name);
}

void DrawLabel(const string name, const int x, const int y, const string text, const color textColor)
{
   if(!CreateObjectChecked(name, OBJ_LABEL, 0, 0.0))
      return;

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   SetObjectCommon(name);
}

void AddSetup(const TTMSetup &setup)
{
   int total = ArraySize(g_setups);
   ArrayResize(g_setups, total + 1);
   g_setups[total] = setup;
}

void TrimSetups()
{
   int total = ArraySize(g_setups);
   if(total <= MaxSetupsToDisplay)
      return;

   int removeCount = total - MaxSetupsToDisplay;
   for(int i = 0; i < MaxSetupsToDisplay; i++)
      g_setups[i] = g_setups[i + removeCount];

   ArrayResize(g_setups, MaxSetupsToDisplay);
}

bool FindEntryAfterBoS(const int bosShift, const int direction, const double fvgTop, const double fvgBottom, const int rates_total, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], datetime &entryTime, double &entryPrice, bool &returnedToFvg)
{
   returnedToFvg = false;

   for(int shift = bosShift - 1; shift >= 1; shift--)
   {
      int index = IndexFromNewest(shift, rates_total, time);

      if(CloseInvalidatesFVG(close[index], fvgTop, fvgBottom, direction))
         return false;

      if(BarTouchesFVG(high[index], low[index], fvgTop, fvgBottom))
         returnedToFvg = true;

      if(returnedToFvg && DirectionalClose(direction, open[index], close[index]))
      {
         entryTime = time[index];
         entryPrice = close[index];
         return true;
      }
   }

   return false;
}

bool FindLiquidityAndBoS(const int fvgShift, const int direction, const double fvgTop, const double fvgBottom, const int rates_total, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], datetime &liquidityTime, double &liquidityPrice, double &breakPrice, datetime &bosTime, datetime &entryTime, double &entryPrice, bool &returnedToFvg, bool &entryTriggered)
{
   int minLiquidityCandles = MathMax(1, MinLiquidityCandles);
   for(int liqShift = fvgShift - minLiquidityCandles; liqShift >= SwingStrength + 1; liqShift--)
   {
      int liqIndex = IndexFromNewest(liqShift, rates_total, time);
      bool liquidityOk = false;

      if(direction == DIR_BULL && IsSwingLow(liqShift, rates_total, time, low) && low[liqIndex] > fvgTop)
      {
         liquidityOk = true;
         liquidityPrice = low[liqIndex];
         int breakIndex = IndexFromNewest(liqShift + 1, rates_total, time);
         breakPrice = high[breakIndex];
      }
      else if(direction == DIR_BEAR && IsSwingHigh(liqShift, rates_total, time, high) && high[liqIndex] < fvgBottom)
      {
         liquidityOk = true;
         liquidityPrice = high[liqIndex];
         int breakIndex = IndexFromNewest(liqShift + 1, rates_total, time);
         breakPrice = low[breakIndex];
      }

      if(!liquidityOk)
         continue;

      if(!FVGUntappedUntil(fvgShift, liqShift, rates_total, time, close, fvgTop, fvgBottom, direction))
         continue;

      g_liquidityFound++;
      liquidityTime = time[liqIndex];

      for(int bosShift = liqShift - 1; bosShift >= 1; bosShift--)
      {
         int bosIndex = IndexFromNewest(bosShift, rates_total, time);
         if(CloseInvalidatesFVG(close[bosIndex], fvgTop, fvgBottom, direction))
            return false;

         bool bosOk = false;
         if(direction == DIR_BULL)
            bosOk = BoSByClose ? close[bosIndex] > breakPrice : high[bosIndex] > breakPrice;
         else
            bosOk = BoSByClose ? close[bosIndex] < breakPrice : low[bosIndex] < breakPrice;

         if(bosOk)
         {
            bosTime = time[bosIndex];
            g_bosFound++;
            entryTriggered = FindEntryAfterBoS(bosShift, direction, fvgTop, fvgBottom, rates_total, time, open, high, low, close, entryTime, entryPrice, returnedToFvg);
            if(returnedToFvg)
               g_returnedToFvg++;
            if(entryTriggered)
               g_entryTriggered++;
            return true;
         }
      }
   }

   return false;
}

void ScanSetups(const int rates_total, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[])
{
   ArrayResize(g_setups, 0);
   g_fvgCandidates = 0;
   g_liquidityFound = 0;
   g_bosFound = 0;
   g_returnedToFvg = 0;
   g_entryTriggered = 0;
   g_setupsDisplayed = 0;

   int maxShift = MathMin(MaxBarsToScan, rates_total - 3);
   int rectangleBars = MathMax(1, RectangleLengthBars);

   for(int shift = maxShift; shift >= SwingStrength + MinLiquidityCandles + 2; shift--)
   {
      int leftIndex = IndexFromNewest(shift + 2, rates_total, time);
      int rightIndex = IndexFromNewest(shift, rates_total, time);
      int direction = 0;
      double top = 0.0;
      double bottom = 0.0;

      if(low[rightIndex] > high[leftIndex])
      {
         direction = DIR_BULL;
         top = low[rightIndex];
         bottom = high[leftIndex];
      }
      else if(high[rightIndex] < low[leftIndex])
      {
         direction = DIR_BEAR;
         top = low[leftIndex];
         bottom = high[rightIndex];
      }

      if(direction == 0 || !FVGSizeOk(top, bottom))
         continue;

      g_fvgCandidates++;

      datetime liquidityTime = 0;
      double liquidityPrice = 0.0;
      double breakPrice = 0.0;
      datetime bosTime = 0;
      datetime entryTime = 0;
      double entryPrice = 0.0;
      bool returnedToFvg = false;
      bool entryTriggered = false;

      if(!FindLiquidityAndBoS(shift, direction, top, bottom, rates_total, time, open, high, low, close, liquidityTime, liquidityPrice, breakPrice, bosTime, entryTime, entryPrice, returnedToFvg, entryTriggered))
         continue;

      if(ShowOnlyEntrySetups && !entryTriggered)
         continue;

      int endShift = MathMax(0, shift - rectangleBars);

      TTMSetup setup;
      setup.direction = direction;
      setup.fvgStartTime = time[leftIndex];
      setup.fvgEndTime = time[IndexFromNewest(endShift, rates_total, time)];
      setup.liquidityTime = liquidityTime;
      setup.bosTime = bosTime;
      setup.fvgTop = top;
      setup.fvgBottom = bottom;
      setup.liquidityPrice = liquidityPrice;
      setup.breakPrice = breakPrice;
      setup.entryTime = entryTime;
      setup.entryPrice = entryPrice;
      setup.returnedToFvg = returnedToFvg;
      setup.entryTriggered = entryTriggered;

      AddSetup(setup);
      TrimSetups();
      g_setupsDisplayed = ArraySize(g_setups);
   }
}

void DrawSetup(const TTMSetup &setup)
{
   string id = SetupId(setup);
   color fvgColor = setup.direction == DIR_BULL ? BullishFvgColor : BearishFvgColor;
   string directionText = DirectionText(setup.direction);

   DrawRectangle(id + "_FVG", setup.fvgStartTime, setup.fvgEndTime, setup.fvgTop, setup.fvgBottom, fvgColor);
   DrawLine(id + "_LIQ", setup.liquidityTime, setup.bosTime, setup.liquidityPrice, LiquidityColor);
   DrawLine(id + "_BOS_LEVEL", setup.liquidityTime, setup.bosTime, setup.breakPrice, BosColor);
   DrawText(id + "_LIQ_TEXT", setup.liquidityTime, setup.liquidityPrice, "Liquidity", LiquidityColor);
   DrawText(id + "_BOS_TEXT", setup.bosTime, setup.breakPrice, directionText + " BoS", BosColor);
   DrawText(id + "_SETUP_TEXT", setup.bosTime, (setup.fvgTop + setup.fvgBottom) / 2.0, directionText + " TTM Setup", TextColor);

   if(setup.entryTriggered)
   {
      DrawArrow(id + "_ENTRY_ARROW", setup.entryTime, setup.entryPrice, setup.direction, EntryColor);
      DrawText(id + "_ENTRY_TEXT", setup.entryTime, setup.entryPrice, directionText + " Entry", EntryColor);
   }
}

string EntryAlertMessage(const TTMSetup &setup)
{
   return "TTM Entry Trigger: " + DirectionText(setup.direction) + " setup on " + _Symbol + " " + EnumToString(_Period);
}

void SendEntryAlert(const string message)
{
   if(UsePopupAlert)
      Alert(message);

   if(UseSoundAlert)
      PlaySound(AlertSoundFile);

   if(UsePushNotification)
      SendNotification(message);
}

void CheckEntryAlerts()
{
   if(!EnableEntryAlerts)
      return;

   for(int i = 0; i < ArraySize(g_setups); i++)
   {
      if(!g_setups[i].entryTriggered)
         continue;

      string key = EntryAlertKey(g_setups[i]);
      if(GlobalVariableCheck(key))
         continue;

      SendEntryAlert(EntryAlertMessage(g_setups[i]));
      GlobalVariableSet(key, TimeCurrent());
   }
}

void DrawDiagnosticsPanel()
{
   DrawLabel(PREFIX + "DIAG_TITLE", 12, 20, "TTM Setup Entry v2", TextColor);
   DrawLabel(PREFIX + "DIAG_FVG", 12, 38, "FVG candidates: " + IntegerToString(g_fvgCandidates), TextColor);
   DrawLabel(PREFIX + "DIAG_LIQ", 12, 56, "Liquidity found: " + IntegerToString(g_liquidityFound), TextColor);
   DrawLabel(PREFIX + "DIAG_BOS", 12, 74, "BoS found: " + IntegerToString(g_bosFound), TextColor);
   DrawLabel(PREFIX + "DIAG_RETURN", 12, 92, "Returned to FVG: " + IntegerToString(g_returnedToFvg), TextColor);
   DrawLabel(PREFIX + "DIAG_ENTRY", 12, 110, "Entry triggers: " + IntegerToString(g_entryTriggered), TextColor);
   DrawLabel(PREFIX + "DIAG_SETUPS", 12, 128, "Displayed setups: " + IntegerToString(g_setupsDisplayed), TextColor);
   DrawLabel(PREFIX + "DIAG_OBJECTS", 12, 146, "Objects created: " + IntegerToString(g_objectsCreated), TextColor);
   DrawLabel(PREFIX + "DIAG_FAILURES", 12, 164, "Create failures: " + IntegerToString(g_objectCreateFailures), TextColor);
   DrawLabel(PREFIX + "DIAG_ERROR", 12, 182, "Last object error: " + IntegerToString(g_lastObjectError), TextColor);
}

void DrawAllSetups()
{
   DeleteObjects();
   g_objectsCreated = 0;
   g_objectCreateFailures = 0;
   g_lastObjectError = 0;

   for(int i = 0; i < ArraySize(g_setups); i++)
      DrawSetup(g_setups[i]);

   if(ShowDiagnosticsPanel)
      DrawDiagnosticsPanel();

   ChartRedraw(0);
}

int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "TTM Setup Entry v2");
   ChartSetInteger(0, CHART_FOREGROUND, false);
   ArrayResize(g_setups, 0);
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
   if(rates_total < 50)
      return 0;

   ScanSetups(rates_total, time, open, high, low, close);
   CheckEntryAlerts();
   DrawAllSetups();

   return rates_total;
}
