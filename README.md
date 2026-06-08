# TTM FVG Liquidity BoS MT5 Indicator

A MetaTrader 5 custom indicator for detecting TTM-style setups using three required concepts:

- Untapped Fair Value Gap (FVG)
- Liquidity level
- Break of Structure (BoS)

The indicator is designed for the 15-minute timeframe but can be attached to any MT5 chart timeframe.

## Current Status

This is a development build that has been committed through Phase 7 packaging. The source still needs to be compiled and validated in MetaEditor/MT5 before being considered production-ready.

## File

```text
TTM_FVG_Liquidity_BoS.mq5
```

## Installation

1. Open MetaTrader 5.
2. Go to `File > Open Data Folder`.
3. Open `MQL5 > Indicators`.
4. Copy `TTM_FVG_Liquidity_BoS.mq5` into the `Indicators` folder.
5. Open MetaEditor with `Tools > MetaQuotes Language Editor` or press `F4`.
6. Open `TTM_FVG_Liquidity_BoS.mq5`.
7. Press `Compile`.
8. Return to MT5.
9. In Navigator, right-click `Indicators` and select `Refresh`.
10. Attach `TTM FVG Liquidity BoS` to a chart.

## Recommended First Test

Use a 15-minute chart first:

```text
EURUSD M15
GBPUSD M15
XAUUSD M15
NAS100 M15
```

## Core Logic

### Bullish Setup

1. Detect bullish FVG from a 3-candle displacement.
2. Confirm the FVG remains untapped.
3. Detect a swing low liquidity level above the FVG.
4. Confirm BoS above the structure high.
5. Wait for price to return to the FVG.
6. Trigger entry on bullish directional close.

### Bearish Setup

1. Detect bearish FVG from a 3-candle displacement.
2. Confirm the FVG remains untapped.
3. Detect a swing high liquidity level below the FVG.
4. Confirm BoS below the structure low.
5. Wait for price to return to the FVG.
6. Trigger entry on bearish directional close.

## Main Inputs

### Detection

- `InpMaxBarsToScan`
- `InpShowBullishSetups`
- `InpShowBearishSetups`
- `InpMinFVGSizePoints`
- `InpStrictCloseInsideInvalidatesFVG`
- `InpRequireImpulseCandle`
- `InpMinImpulseBodyPercent`
- `InpSwingDepth`
- `InpMinBarsAfterFVGForLiquidity`
- `InpMaxBarsAfterFVGForLiquidity`
- `InpMaxBarsAfterLiquidityForBoS`
- `InpMaxBarsAfterBoSForEntry`
- `InpBoSByWick`

### Alerts

- `InpAlertOnSetupFormed`
- `InpAlertOnEntryTrigger`
- `InpEnablePopupAlert`
- `InpEnablePushAlert`
- `InpEnableEmailAlert`
- `InpEnableSoundAlert`
- `InpSoundFile`

### Risk Tools

- `InpShowSLTPBE`
- `InpShowTradeInfoLabel`
- `InpStopLossMode`
- `InpRiskReward`
- `InpBreakEvenRR`
- `InpSLBufferPoints`

### Visuals

- `InpBullishFVGColor`
- `InpBearishFVGColor`
- `InpBullishLineColor`
- `InpBearishLineColor`
- `InpTextColor`
- `InpShowFVGZones`
- `InpShowLiquidityLines`
- `InpShowBoSLabels`
- `InpShowEntryMarkers`
- `InpShowLatestSetupOnly`
- `InpMaxDisplayedSetups`
- `InpMaxStoredSetups`

## Testing Checklist

After compiling in MetaEditor, test the following:

- FVG rectangles appear at correct candle gaps.
- Wick taps do not invalidate an FVG.
- Candle closes inside the FVG invalidate the setup when strict mode is enabled.
- Liquidity line forms only above bullish FVG or below bearish FVG.
- BoS label appears only after the structure level is broken.
- Entry arrow appears only after return to FVG and directional close.
- SL, BE, and TP lines calculate correctly.
- Alerts fire once per setup/entry.
- Chart objects are removed when the indicator is removed.
- Display remains clean with `InpMaxDisplayedSetups` and `InpShowLatestSetupOnly`.

## Important Note

This is an indicator, not an Expert Advisor. It does not place or manage trades automatically.

## Next Development Steps

- Compile in MetaEditor and fix any errors or warnings.
- Validate on MT5 charts.
- Refine FVG and liquidity selection based on real examples.
- Consider ATR-based FVG filtering after chart validation.
