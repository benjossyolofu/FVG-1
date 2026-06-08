#property copyright "TTM FVG Basic Visible"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#define PREFIX "TTM_FVG_VISIBLE_"
#define DIR_BULL 1
#define DIR_BEAR -1

input int MaxBarsToScan = 1000;
input int MaxFvgToDisplay = 8;
input int MinFvgSizePoints = 1;
input int RectangleLengthBars = 40;
input int MinVisualHeightPoints = 80;
input bool ExtendUntouchedToCurrentBar = false;
input bool ShowInvalidatedFvg = false;
input bool ShowStatusText = true;
input bool ShowDiagnosticsPanel = true;
input bool InvalidateOnCloseInside = true;
input color BullishFvgColor = clrLimeGreen;
input color BearishFvgColor = clrRed;
input color InvalidatedFvgColor = clrOrange;
input color TextColor = clrWhite;

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
   return (top - bottom) >= MinFvgSizePoints * PointValue();
}

bool CloseInvalidatesFVG(const double closePrice, const double top, const double bottom)
{
   if(InvalidateOnCloseInside)
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
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
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
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   SetObjectCommon(name);
}

void DisplayBounds(const double top, const double bottom, double &displayTop, double &displayBottom)
{
   displayTop = top;
   displayBottom = bottom;

   double minHeight = MinVisualHeightPoints * PointValue();
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

void DrawDiagnosticsPanel()
{
   DrawLabel(PREFIX + "DIAG_TITLE", 12, 20, "TTM FVG Basic Visible", TextColor);
   DrawLabel(PREFIX + "DIAG_CANDIDATES", 12, 38, "FVG candidates: " + IntegerToString(g_fvgCandidates), TextColor);
   DrawLabel(PREFIX + "DIAG_DISPLAYED", 12, 56, "Displayed FVGs: " + IntegerToString(g_fvgDisplayed), TextColor);
   DrawLabel(PREFIX + "DIAG_OBJECTS", 12, 74, "Objects created: " + IntegerToString(g_objectsCreated), TextColor);
   DrawLabel(PREFIX + "DIAG_FAILURES", 12, 92, "Create failures: " + IntegerToString(g_objectCreateFailures), TextColor);
   DrawLabel(PREFIX + "DIAG_ERROR", 12, 110, "Last object error: " + IntegerToString(g_lastObjectError), TextColor);
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
   if(MaxFvgToDisplay <= 0 || total <= MaxFvgToDisplay)
      return;

   int removeCount = total - MaxFvgToDisplay;
   for(int i = 0; i < total - removeCount; i++)
      g_fvgs[i] = g_fvgs[i + removeCount];

   ArrayResize(g_fvgs, MaxFvgToDisplay);
}

void ScanFVGs(const int rates_total, const datetime &time[], const double &high[], const double &low[], const double &close[])
{
   ArrayResize(g_fvgs, 0);
   g_fvgCandidates = 0;
   g_fvgDisplayed = 0;

   int maxShift = MathMin(MaxBarsToScan, rates_total - 3);
   int rectangleBars = MathMax(1, RectangleLengthBars);

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

      if(invalidated && !ShowInvalidatedFvg)
         continue;

      int endShift = MathMax(0, shift - rectangleBars);
      int labelShift = MathMax(0, shift - rectangleBars / 2);

      BasicFVG fvg;
      fvg.direction = direction;
      fvg.startTime = time[leftIndex];
      fvg.endTime = ExtendUntouchedToCurrentBar && !invalidated ? time[IndexFromNewest(0, rates_total, time)] : time[IndexFromNewest(endShift, rates_total, time)];
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
   color rectColor = fvg.invalidated ? InvalidatedFvgColor : (fvg.direction == DIR_BULL ? BullishFvgColor : BearishFvgColor);
   string directionText = fvg.direction == DIR_BULL ? "Bullish" : "Bearish";
   string statusText = fvg.invalidated ? "Invalidated" : "Untouched";
   double labelPrice = (fvg.displayTop + fvg.displayBottom) / 2.0;

   DrawRectangle(id + "_RECT", fvg.startTime, fvg.endTime, fvg.displayTop, fvg.displayBottom, rectColor);
   DrawLine(id + "_TOP", fvg.startTime, fvg.endTime, fvg.top, rectColor);
   DrawLine(id + "_BOTTOM", fvg.startTime, fvg.endTime, fvg.bottom, rectColor);
   DrawMarker(id + "_MARKER", fvg.labelTime, labelPrice, rectColor);

   if(ShowStatusText)
      DrawText(id + "_TEXT", fvg.labelTime, labelPrice, directionText + " FVG - " + statusText, TextColor);
}

void DrawAllFVGs()
{
   DeleteObjects();
   g_objectsCreated = 0;
   g_objectCreateFailures = 0;
   g_lastObjectError = 0;

   for(int i = 0; i < ArraySize(g_fvgs); i++)
      DrawFVG(g_fvgs[i]);

   if(ShowDiagnosticsPanel)
      DrawDiagnosticsPanel();

   ChartRedraw(0);
}

int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "TTM FVG Basic Visible");
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
   DrawAllFVGs();

   return rates_total;
}
