#property copyright "TTM FVG Draw Test 2"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#define PREFIX "TTM_FVG_DRAW_TEST_2_"
#define DIR_BULL 1
#define DIR_BEAR -1

input int InpMaxBarsToScan = 1000;
input int InpMaxFVGsToDisplay = 15;
input int InpMinFVGSizePoints = 1;
input int InpRectangleLengthBars = 40;
input int InpMinVisualHeightPoints = 80;
input bool InpExtendUntouchedToCurrentBar = false;
input bool InpShowInvalidatedFVGs = true;
input bool InpShowStatusText = true;
input bool InpShowDiagnosticsPanel = true;
input bool InpDrawTestBox = true;
input bool InpInvalidateOnCloseInside = true;
input color InpBullishFVGColor = clrDeepSkyBlue;
input color InpBearishFVGColor = clrMagenta;
input color InpInvalidatedFVGColor = clrOrange;
input color InpTestBoxColor = clrYellow;
input color InpTextColor = clrWhite;

struct BasicFVG
{
   int direction;
   datetime startTime;
   datetime endTime;
   datetime labelTime;
   double top;
   double bottom;
   double displayTop;
   double displayBottom;
   bool invalidated;
};

BasicFVG g_fvgs[];
int g_fvgCandidates = 0;
int g_fvgDisplayed = 0;
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

string FVGId(const BasicFVG &fvg)
{
   return PREFIX + _Symbol + "_" + IntegerToString((int)_Period) + "_" + IntegerToString(fvg.direction) + "_" + TimeId(fvg.startTime);
}

bool FVGSizeOk(const double top, const double bottom)
{
   return (top - bottom) >= InpMinFVGSizePoints * PointValue();
}

bool CloseInvalidatesFVG(const double closePrice, const double top, const double bottom)
{
   if(InpInvalidateOnCloseInside)
      return closePrice <= top && closePrice >= bottom;

   return false;
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

void SetObjectCommon(const string name)
{
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 100);
}

bool CreateObjectChecked(const string name, const ENUM_OBJECT type, const datetime t1, const double p1, const datetime t2 = 0, const double p2 = 0.0)
{
   ResetLastError();
   bool created = false;

   if(type == OBJ_RECTANGLE || type == OBJ_TREND)
      created = ObjectCreate(0, name, type, 0, t1, p1, t2, p2);
   else
      created = ObjectCreate(0, name, type, 0, t1, p1);

   if(created)
   {
      g_objectsCreated++;
      return true;
   }

   g_objectCreateFailures++;
   g_lastObjectError = GetLastError();
   return false;
}

void DrawRectangle(const string name, const datetime t1, const datetime t2, const double top, const double bottom, const color clr)
{
   datetime leftTime = t1 < t2 ? t1 : t2;
   datetime rightTime = t1 < t2 ? t2 : t1;
   double highPrice = top > bottom ? top : bottom;
   double lowPrice = top > bottom ? bottom : top;

   if(ObjectFind(0, name) < 0)
      CreateObjectChecked(name, OBJ_RECTANGLE, leftTime, highPrice, rightTime, lowPrice);
   else
   {
      ObjectMove(0, name, 0, leftTime, highPrice);
      ObjectMove(0, name, 1, rightTime, lowPrice);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   SetObjectCommon(name);
}

void DrawLine(const string name, const datetime t1, const datetime t2, const double price, const color clr)
{
   datetime leftTime = t1 < t2 ? t1 : t2;
   datetime rightTime = t1 < t2 ? t2 : t1;

   if(ObjectFind(0, name) < 0)
      CreateObjectChecked(name, OBJ_TREND, leftTime, price, rightTime, price);
   else
   {
      ObjectMove(0, name, 0, leftTime, price);
      ObjectMove(0, name, 1, rightTime, price);
   }

   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   SetObjectCommon(name);
}

void DrawMarker(const string name, const datetime t, const double price, const color clr)
{
   if(ObjectFind(0, name) < 0)
      CreateObjectChecked(name, OBJ_ARROW, t, price);
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 4);
   SetObjectCommon(name);
}

void DisplayBounds(const double top, const double bottom, double &displayTop, double &displayBottom)
{
   displayTop = top;
   displayBottom = bottom;

   double minHeight = InpMinVisualHeightPoints * PointValue();
   if(minHeight <= 0.0 || top - bottom >= minHeight)
      return;

   double middle = (top + bottom) / 2.0;
   displayTop = middle + minHeight / 2.0;
   displayBottom = middle - minHeight / 2.0;
}

void DrawText(const string name, const datetime t, const double price, const string text, const color clr)
{
   if(ObjectFind(0, name) < 0)
      CreateObjectChecked(name, OBJ_TEXT, t, price);
   else
      ObjectMove(0, name, 0, t, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   SetObjectCommon(name);
}

void DrawLabel(const string name, const int x, const int y, const string text, const color clr)
{
   if(ObjectFind(0, name) < 0)
      CreateObjectChecked(name, OBJ_LABEL, 0, 0.0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   SetObjectCommon(name);
}

void DrawScreenTestBox()
{
   string boxName = PREFIX + "SCREEN_TEST_BOX";
   if(ObjectFind(0, boxName) < 0)
      CreateObjectChecked(boxName, OBJ_RECTANGLE_LABEL, 0, 0.0);

   ObjectSetInteger(0, boxName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, boxName, OBJPROP_XDISTANCE, 260);
   ObjectSetInteger(0, boxName, OBJPROP_YDISTANCE, 35);
   ObjectSetInteger(0, boxName, OBJPROP_XSIZE, 220);
   ObjectSetInteger(0, boxName, OBJPROP_YSIZE, 80);
   ObjectSetInteger(0, boxName, OBJPROP_BGCOLOR, clrYellow);
   ObjectSetInteger(0, boxName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, boxName, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, boxName, OBJPROP_WIDTH, 3);
   SetObjectCommon(boxName);

   DrawLabel(PREFIX + "SCREEN_TEST_TEXT", 285, 62, "SCREEN TEST BOX", clrRed);
}

void DrawDiagnosticsPanel()
{
   string orientation = "Array order: ";
   DrawLabel(PREFIX + "DIAG_TITLE", 12, 20, "TTM FVG Draw Test 2", InpTextColor);
   DrawLabel(PREFIX + "DIAG_CANDIDATES", 12, 38, "FVG candidates: " + IntegerToString(g_fvgCandidates), InpTextColor);
   DrawLabel(PREFIX + "DIAG_DISPLAYED", 12, 56, "Displayed FVGs: " + IntegerToString(g_fvgDisplayed), InpTextColor);
   DrawLabel(PREFIX + "DIAG_OBJECTS", 12, 74, "Objects created: " + IntegerToString(g_objectsCreated), InpTextColor);
   DrawLabel(PREFIX + "DIAG_FAILURES", 12, 92, "Create failures: " + IntegerToString(g_objectCreateFailures), InpTextColor);
   DrawLabel(PREFIX + "DIAG_ERROR", 12, 110, "Last object error: " + IntegerToString(g_lastObjectError), InpTextColor);
}

void DrawTestBox(const datetime &time[], const double &high[], const double &low[], const int rates_total)
{
   if(!InpDrawTestBox || rates_total < 25)
      return;

   int firstIndex = IndexFromNewest(1, rates_total, time);
   double visibleHigh = high[firstIndex];
   double visibleLow = low[firstIndex];
   for(int barsAgo = 2; barsAgo <= 24 && barsAgo < rates_total; barsAgo++)
   {
      int index = IndexFromNewest(barsAgo, rates_total, time);
      visibleHigh = MathMax(visibleHigh, high[index]);
      visibleLow = MathMin(visibleLow, low[index]);
   }

   double boxHeight = MathMax((visibleHigh - visibleLow) * 0.12, InpMinVisualHeightPoints * PointValue());
   double middle = (visibleHigh + visibleLow) / 2.0;
   datetime leftTime = time[IndexFromNewest(20, rates_total, time)];
   datetime rightTime = time[IndexFromNewest(1, rates_total, time)];

   DrawRectangle(PREFIX + "TEST_RECT", leftTime, rightTime, middle + boxHeight, middle, InpTestBoxColor);
   DrawText(PREFIX + "TEST_TEXT", leftTime, middle + boxHeight, "PRICE TEST BOX", InpTextColor);
}

void AddFVG(const BasicFVG &fvg)
{
   int total = ArraySize(g_fvgs);
   ArrayResize(g_fvgs, total + 1);
   g_fvgs[total] = fvg;
}

void TrimFVGs()
{
   int total = ArraySize(g_fvgs);
   if(InpMaxFVGsToDisplay <= 0 || total <= InpMaxFVGsToDisplay)
      return;

   int removeCount = total - InpMaxFVGsToDisplay;
   for(int i = 0; i < total - removeCount; i++)
      g_fvgs[i] = g_fvgs[i + removeCount];

   ArrayResize(g_fvgs, InpMaxFVGsToDisplay);
}

void ScanFVGs(const int rates_total, const datetime &time[], const double &high[], const double &low[], const double &close[])
{
   ArrayResize(g_fvgs, 0);
   g_fvgCandidates = 0;
   g_fvgDisplayed = 0;

   int maxShift = MathMin(InpMaxBarsToScan, rates_total - 3);
   int rectangleBars = MathMax(1, InpRectangleLengthBars);

   for(int shift = maxShift; shift >= 1; shift--)
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

      bool invalidated = false;
      for(int newerShift = shift - 1; newerShift >= 1; newerShift--)
      {
         int newerIndex = IndexFromNewest(newerShift, rates_total, time);
         if(CloseInvalidatesFVG(close[newerIndex], top, bottom))
         {
            invalidated = true;
            break;
         }
      }

      if(invalidated && !InpShowInvalidatedFVGs)
         continue;

      int endShift = MathMax(0, shift - rectangleBars);
      int labelShift = MathMax(0, shift - rectangleBars / 2);

      BasicFVG fvg;
      fvg.direction = direction;
      fvg.startTime = time[leftIndex];
      fvg.endTime = InpExtendUntouchedToCurrentBar && !invalidated ? time[IndexFromNewest(0, rates_total, time)] : time[IndexFromNewest(endShift, rates_total, time)];
      fvg.labelTime = time[IndexFromNewest(labelShift, rates_total, time)];
      fvg.top = top;
      fvg.bottom = bottom;
      DisplayBounds(top, bottom, fvg.displayTop, fvg.displayBottom);
      fvg.invalidated = invalidated;

      AddFVG(fvg);
      TrimFVGs();
      g_fvgDisplayed = ArraySize(g_fvgs);
   }
}

void DrawFVG(const BasicFVG &fvg)
{
   string id = FVGId(fvg);
   color rectColor = fvg.invalidated ? InpInvalidatedFVGColor : (fvg.direction == DIR_BULL ? InpBullishFVGColor : InpBearishFVGColor);
   string directionText = fvg.direction == DIR_BULL ? "Bullish" : "Bearish";
   string statusText = fvg.invalidated ? "Invalidated" : "Untouched";
   double labelPrice = (fvg.displayTop + fvg.displayBottom) / 2.0;

   DrawRectangle(id + "_RECT", fvg.startTime, fvg.endTime, fvg.displayTop, fvg.displayBottom, rectColor);
   DrawLine(id + "_TOP", fvg.startTime, fvg.endTime, fvg.top, rectColor);
   DrawLine(id + "_BOTTOM", fvg.startTime, fvg.endTime, fvg.bottom, rectColor);
   DrawMarker(id + "_MARKER", fvg.labelTime, labelPrice, rectColor);

   if(InpShowStatusText)
      DrawText(id + "_TEXT", fvg.labelTime, labelPrice, directionText + " FVG - " + statusText, InpTextColor);
}

void DrawAllFVGs(const datetime &time[], const double &high[], const double &low[], const int rates_total)
{
   DeleteObjects();
   g_objectsCreated = 0;
   g_objectCreateFailures = 0;
   g_lastObjectError = 0;

   for(int i = 0; i < ArraySize(g_fvgs); i++)
      DrawFVG(g_fvgs[i]);

   DrawTestBox(time, high, low, rates_total);
   DrawScreenTestBox();

   if(InpShowDiagnosticsPanel)
      DrawDiagnosticsPanel();

   ChartRedraw(0);
}

int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "TTM FVG Draw Test 2");
   ChartSetInteger(0, CHART_FOREGROUND, false);
   ArrayResize(g_fvgs, 0);
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
   if(rates_total < 25)
      return 0;

   ScanFVGs(rates_total, time, high, low, close);
   DrawAllFVGs(time, high, low, rates_total);

   return rates_total;
}
