#property copyright "TTM FVG HTF v6"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#define PREFIX "TTM_FVG_HTF_V6_"
#define DIR_BULL 1
#define DIR_BEAR -1
#define GRADE_C 1
#define GRADE_B 2
#define GRADE_A 3

input int MaxBarsToScan = 1000;
input int MaxFvgToDisplay = 8;
input int MinFvgSizePoints = 1;
input int MinGradeToShow = 1;
input int GradeA_MinPoints = 150;
input int GradeB_MinPoints = 60;
input bool UseAtrGrading = true;
input int AtrPeriod = 14;
input double GradeA_AtrMultiple = 0.25;
input double GradeB_AtrMultiple = 0.10;
input bool UseFreshnessDecay = true;
input int FreshBars = 30;
input int StaleBars = 80;
input bool HideStaleFvg = false;
input bool ShowFvgAge = true;
input bool UseClusterBoost = true;
input int ClusterLookbackBars = 40;
input int MinClusterCount = 2;
input int ClusterMaxDistancePoints = 120;
input bool ShowClusterTag = true;
input int RectangleLengthBars = 40;
input int MinVisualHeightPoints = 80;
input bool ExtendUntouchedToCurrentBar = false;
input bool ShowInvalidatedFvg = false;
input bool ShowStatusText = true;
input bool ShowFvgGrade = true;
input bool ShowDiagnosticsPanel = true;
input bool InvalidateOnCloseInside = true;
input bool EnableTouchAlerts = true;
input int MinAlertGrade = 2;
input bool AlertOnCurrentBar = true;
input bool AlertOnStaleFvg = false;
input bool AlertInvalidatedFvg = false;
input bool UsePopupAlert = true;
input bool UseSoundAlert = true;
input bool UsePushNotification = false;
input string AlertSoundFile = "alert.wav";
input bool ShowHtfFvgPanel = true;
input bool ScanM30Fvg = true;
input bool ScanH1Fvg = true;
input bool ScanH4Fvg = true;
input int HtfMaxBarsToScan = 300;
input int HtfMinGradeToShow = 2;
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
   double sizePoints;
   int grade;
   int originalGrade;
   int ageBars;
   int clusterCount;
   bool clustered;
   bool stale;
   bool invalidated;
};

BasicFVG g_fvgs[];
int g_fvgCandidates = 0;
int g_fvgDisplayed = 0;
int g_objectsCreated = 0;
int g_objectCreateFailures = 0;
int g_lastObjectError = 0;
int g_gradeA = 0;
int g_gradeB = 0;
int g_gradeC = 0;
int g_staleFvgs = 0;
int g_clusteredFvgs = 0;
int g_touchAlerts = 0;
string g_htfM30Text = "M30 FVG: scanning";
string g_htfH1Text = "H1 FVG: scanning";
string g_htfH4Text = "H4 FVG: scanning";

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

string AlertKey(const BasicFVG &fvg)
{
   return "TTM_ALERT_" + _Symbol + "_" + IntegerToString((int)_Period) + "_" + IntegerToString(fvg.direction) + "_" + TimeId(fvg.startTime);
}

bool FVGSizeOk(const double top, const double bottom)
{
   return (top - bottom) >= MinFvgSizePoints * PointValue();
}

double CalculateATRAtShift(const int shift, const int rates_total, const datetime &time[], const double &high[], const double &low[], const double &close[])
{
   if(AtrPeriod <= 0 || rates_total < AtrPeriod + shift + 2)
      return 0.0;

   double totalRange = 0.0;
   for(int offset = shift; offset < shift + AtrPeriod; offset++)
   {
      int index = IndexFromNewest(offset, rates_total, time);
      int previousIndex = IndexFromNewest(offset + 1, rates_total, time);
      double rangeHighLow = high[index] - low[index];
      double rangeHighClose = MathAbs(high[index] - close[previousIndex]);
      double rangeLowClose = MathAbs(low[index] - close[previousIndex]);
      totalRange += MathMax(rangeHighLow, MathMax(rangeHighClose, rangeLowClose));
   }

   return totalRange / AtrPeriod;
}

int CalculateFVGGrade(const double top, const double bottom, const double atrValue)
{
   double sizePoints = (top - bottom) / PointValue();

   if(UseAtrGrading && atrValue > 0.0)
   {
      double size = top - bottom;

      if(size >= atrValue * GradeA_AtrMultiple)
         return GRADE_A;

      if(size >= atrValue * GradeB_AtrMultiple)
         return GRADE_B;

      return GRADE_C;
   }

   if(sizePoints >= GradeA_MinPoints)
      return GRADE_A;

   if(sizePoints >= GradeB_MinPoints)
      return GRADE_B;

   return GRADE_C;
}

string GradeText(const int grade)
{
   if(grade >= GRADE_A)
      return "A";

   if(grade == GRADE_B)
      return "B";

   return "C";
}

string DirectionText(const int direction)
{
   return direction == DIR_BULL ? "Bullish" : "Bearish";
}

int ApplyFreshnessDecay(const int grade, const int ageBars)
{
   if(!UseFreshnessDecay)
      return grade;

   if(ageBars >= StaleBars)
      return MathMax(GRADE_C, grade - 2);

   if(ageBars > FreshBars)
      return MathMax(GRADE_C, grade - 1);

   return grade;
}

bool PriceZonesNear(const double topA, const double bottomA, const double topB, const double bottomB)
{
   double distance = 0.0;

   if(bottomA > topB)
      distance = bottomA - topB;
   else if(bottomB > topA)
      distance = bottomB - topA;

   return distance <= ClusterMaxDistancePoints * PointValue();
}

int CountNearbyClusterFVGs(const int currentShift, const int direction, const double top, const double bottom, const int rates_total, const datetime &time[], const double &high[], const double &low[])
{
   if(!UseClusterBoost)
      return 1;

   int clusterCount = 1;
   int maxClusterShift = MathMin(rates_total - 3, currentShift + MathMax(1, ClusterLookbackBars));

   for(int shift = currentShift + 1; shift <= maxClusterShift; shift++)
   {
      int leftIndex = IndexFromNewest(shift + 2, rates_total, time);
      int rightIndex = IndexFromNewest(shift, rates_total, time);
      int nearbyDirection = 0;
      double nearbyTop = 0.0;
      double nearbyBottom = 0.0;

      if(low[rightIndex] > high[leftIndex])
      {
         nearbyDirection = DIR_BULL;
         nearbyTop = low[rightIndex];
         nearbyBottom = high[leftIndex];
      }
      else if(high[rightIndex] < low[leftIndex])
      {
         nearbyDirection = DIR_BEAR;
         nearbyTop = low[leftIndex];
         nearbyBottom = high[rightIndex];
      }

      if(nearbyDirection == direction && FVGSizeOk(nearbyTop, nearbyBottom) && PriceZonesNear(top, bottom, nearbyTop, nearbyBottom))
         clusterCount++;
   }

   return clusterCount;
}

int ApplyClusterBoost(const int grade, const int clusterCount)
{
   if(!UseClusterBoost || clusterCount < MinClusterCount)
      return grade;

   return MathMin(GRADE_A, grade + 1);
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

string HtfFvgSummary(const ENUM_TIMEFRAMES timeframe, const string timeframeName)
{
   int bars = Bars(_Symbol, timeframe);
   if(bars < 10)
      return timeframeName + " FVG: no data";

   int maxShift = MathMin(HtfMaxBarsToScan, bars - 3);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double nearestDistance = DBL_MAX;
   int nearestDirection = 0;
   int nearestGrade = 0;
   int nearestAge = 0;
   bool found = false;

   for(int shift = 1; shift <= maxShift; shift++)
   {
      double leftHigh = iHigh(_Symbol, timeframe, shift + 2);
      double leftLow = iLow(_Symbol, timeframe, shift + 2);
      double rightHigh = iHigh(_Symbol, timeframe, shift);
      double rightLow = iLow(_Symbol, timeframe, shift);
      int direction = 0;
      double top = 0.0;
      double bottom = 0.0;

      if(rightLow > leftHigh)
      {
         direction = DIR_BULL;
         top = rightLow;
         bottom = leftHigh;
      }
      else if(rightHigh < leftLow)
      {
         direction = DIR_BEAR;
         top = leftLow;
         bottom = rightHigh;
      }

      if(direction == 0 || !FVGSizeOk(top, bottom))
         continue;

      int grade = CalculateFVGGrade(top, bottom, 0.0);
      if(grade < HtfMinGradeToShow)
         continue;

      double distance = 0.0;
      if(currentPrice > top)
         distance = currentPrice - top;
      else if(currentPrice < bottom)
         distance = bottom - currentPrice;

      if(distance < nearestDistance)
      {
         nearestDistance = distance;
         nearestDirection = direction;
         nearestGrade = grade;
         nearestAge = shift;
         found = true;
      }
   }

   if(!found)
      return timeframeName + " FVG: none";

   return timeframeName + " FVG: " + DirectionText(nearestDirection) + " " + GradeText(nearestGrade) + " | " + IntegerToString(nearestAge) + " bars";
}

void UpdateHtfFvgSummaries()
{
   g_htfM30Text = ScanM30Fvg ? HtfFvgSummary(PERIOD_M30, "M30") : "M30 FVG: off";
   g_htfH1Text = ScanH1Fvg ? HtfFvgSummary(PERIOD_H1, "H1") : "H1 FVG: off";
   g_htfH4Text = ScanH4Fvg ? HtfFvgSummary(PERIOD_H4, "H4") : "H4 FVG: off";
}

void DrawDiagnosticsPanel()
{
   DrawLabel(PREFIX + "DIAG_TITLE", 12, 20, "TTM FVG HTF v6", TextColor);
   DrawLabel(PREFIX + "DIAG_CANDIDATES", 12, 38, "FVG candidates: " + IntegerToString(g_fvgCandidates), TextColor);
   DrawLabel(PREFIX + "DIAG_DISPLAYED", 12, 56, "Displayed FVGs: " + IntegerToString(g_fvgDisplayed), TextColor);
   DrawLabel(PREFIX + "DIAG_GRADES", 12, 74, "Grades A/B/C: " + IntegerToString(g_gradeA) + "/" + IntegerToString(g_gradeB) + "/" + IntegerToString(g_gradeC), TextColor);
   DrawLabel(PREFIX + "DIAG_ATR", 12, 92, "ATR grading: " + (UseAtrGrading ? "ON" : "OFF"), TextColor);
   DrawLabel(PREFIX + "DIAG_FRESHNESS", 12, 110, "Freshness decay: " + (UseFreshnessDecay ? "ON" : "OFF") + " | Stale: " + IntegerToString(g_staleFvgs), TextColor);
   DrawLabel(PREFIX + "DIAG_CLUSTER", 12, 128, "Cluster boost: " + (UseClusterBoost ? "ON" : "OFF") + " | Clustered: " + IntegerToString(g_clusteredFvgs), TextColor);
   DrawLabel(PREFIX + "DIAG_ALERTS", 12, 146, "Touch alerts: " + (EnableTouchAlerts ? "ON" : "OFF") + " | Sent: " + IntegerToString(g_touchAlerts), TextColor);
   if(ShowHtfFvgPanel)
   {
      DrawLabel(PREFIX + "DIAG_HTF_TITLE", 12, 164, "Higher TF FVGs:", TextColor);
      DrawLabel(PREFIX + "DIAG_HTF_M30", 12, 182, g_htfM30Text, TextColor);
      DrawLabel(PREFIX + "DIAG_HTF_H1", 12, 200, g_htfH1Text, TextColor);
      DrawLabel(PREFIX + "DIAG_HTF_H4", 12, 218, g_htfH4Text, TextColor);
   }
   DrawLabel(PREFIX + "DIAG_OBJECTS", 12, ShowHtfFvgPanel ? 236 : 164, "Objects created: " + IntegerToString(g_objectsCreated), TextColor);
   DrawLabel(PREFIX + "DIAG_FAILURES", 12, ShowHtfFvgPanel ? 254 : 182, "Create failures: " + IntegerToString(g_objectCreateFailures), TextColor);
   DrawLabel(PREFIX + "DIAG_ERROR", 12, ShowHtfFvgPanel ? 272 : 200, "Last object error: " + IntegerToString(g_lastObjectError), TextColor);
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
   g_gradeA = 0;
   g_gradeB = 0;
   g_gradeC = 0;
   g_staleFvgs = 0;
   g_clusteredFvgs = 0;

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
      double atrValue = CalculateATRAtShift(shift, rates_total, time, high, low, close);
      int originalGrade = CalculateFVGGrade(top, bottom, atrValue);
      int ageBars = shift;
      bool stale = UseFreshnessDecay && ageBars >= StaleBars;

      if(stale)
         g_staleFvgs++;

      if(stale && HideStaleFvg)
         continue;

      int clusterCount = CountNearbyClusterFVGs(shift, direction, top, bottom, rates_total, time, high, low);
      bool clustered = UseClusterBoost && clusterCount >= MinClusterCount;
      int grade = ApplyClusterBoost(ApplyFreshnessDecay(originalGrade, ageBars), clusterCount);

      if(clustered)
         g_clusteredFvgs++;

      if(grade < MinGradeToShow)
         continue;

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
      fvg.sizePoints = (top - bottom) / PointValue();
      fvg.grade = grade;
      fvg.originalGrade = originalGrade;
      fvg.ageBars = ageBars;
      fvg.clusterCount = clusterCount;
      fvg.clustered = clustered;
      fvg.stale = stale;
      fvg.invalidated = invalidated;

      AddFVG(fvg);
      TrimFVGs();
      g_fvgDisplayed = ArraySize(g_fvgs);

      if(grade >= GRADE_A)
         g_gradeA++;
      else if(grade == GRADE_B)
         g_gradeB++;
      else
         g_gradeC++;
   }
}

void DrawFVG(const BasicFVG &fvg)
{
   string id = FVGId(fvg);
   color rectColor = fvg.invalidated ? InvalidatedFvgColor : (fvg.direction == DIR_BULL ? BullishFvgColor : BearishFvgColor);
   string directionText = fvg.direction == DIR_BULL ? "Bullish" : "Bearish";
   string statusText = fvg.invalidated ? "Invalidated" : "Untouched";
   string gradeText = ShowFvgGrade ? " Grade " + GradeText(fvg.grade) : "";
   string ageText = ShowFvgAge ? " | " + IntegerToString(fvg.ageBars) + " bars" : "";
   string clusterText = ShowClusterTag && fvg.clustered ? " | Cluster x" + IntegerToString(fvg.clusterCount) : "";
   double labelPrice = (fvg.displayTop + fvg.displayBottom) / 2.0;

   DrawRectangle(id + "_RECT", fvg.startTime, fvg.endTime, fvg.displayTop, fvg.displayBottom, rectColor);
   DrawLine(id + "_TOP", fvg.startTime, fvg.endTime, fvg.top, rectColor);
   DrawLine(id + "_BOTTOM", fvg.startTime, fvg.endTime, fvg.bottom, rectColor);
   DrawMarker(id + "_MARKER", fvg.labelTime, labelPrice, rectColor);

   if(ShowStatusText)
      DrawText(id + "_TEXT", fvg.labelTime, labelPrice, directionText + " FVG" + gradeText + " - " + statusText + ageText + clusterText, TextColor);
}

bool CurrentBarTouchesFVG(const BasicFVG &fvg, const double barHigh, const double barLow)
{
   return barLow <= fvg.top && barHigh >= fvg.bottom;
}

string TouchAlertMessage(const BasicFVG &fvg)
{
   string directionText = fvg.direction == DIR_BULL ? "Bullish" : "Bearish";
   string message = "TTM FVG touch: " + directionText + " Grade " + GradeText(fvg.grade) + " FVG touched on " + _Symbol + " " + EnumToString(_Period);
   message += " | Age " + IntegerToString(fvg.ageBars) + " bars";

   if(fvg.clustered)
      message += " | Cluster x" + IntegerToString(fvg.clusterCount);

   return message;
}

void SendTouchAlert(const string message)
{
   if(UsePopupAlert)
      Alert(message);

   if(UseSoundAlert)
      PlaySound(AlertSoundFile);

   if(UsePushNotification)
      SendNotification(message);
}

void CheckTouchAlerts(const int rates_total, const datetime &time[], const double &high[], const double &low[])
{
   if(!EnableTouchAlerts || ArraySize(g_fvgs) == 0)
      return;

   int barIndex = IndexFromNewest(AlertOnCurrentBar ? 0 : 1, rates_total, time);
   double barHigh = high[barIndex];
   double barLow = low[barIndex];

   for(int i = 0; i < ArraySize(g_fvgs); i++)
   {
      BasicFVG fvg = g_fvgs[i];

      if(fvg.grade < MinAlertGrade)
         continue;

      if(fvg.stale && !AlertOnStaleFvg)
         continue;

      if(fvg.invalidated && !AlertInvalidatedFvg)
         continue;

      if(!CurrentBarTouchesFVG(fvg, barHigh, barLow))
         continue;

      string key = AlertKey(fvg);

      if(GlobalVariableCheck(key))
         continue;

      SendTouchAlert(TouchAlertMessage(fvg));
      GlobalVariableSet(key, TimeCurrent());
      g_touchAlerts++;
   }
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
   IndicatorSetString(INDICATOR_SHORTNAME, "TTM FVG HTF v6");
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
   UpdateHtfFvgSummaries();
   CheckTouchAlerts(rates_total, time, high, low);
   DrawAllFVGs();

   return rates_total;
}
