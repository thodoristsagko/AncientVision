# UI Simplification Design

**Date:** 2026-03-06
**Branch:** docker-experiment-flutter
**Goal:** Simplify the Safety/Monitor tab for competition demos — unclutter the header and remove the confusing Simple/Detail mode split.

---

## Problem

The Safety tab has two issues:
1. **Header overload** — 8 items crammed into one row (mode toggle, language, calibration icon, history, info, dev mode, settings, calibrate, scan button). Overflows on smaller screens, scan button gets clipped.
2. **Simple/Detail mode split** — two different views of the same data, with a toggle that judges don't understand and that adds cognitive load.

---

## Design

### Header

**Before:** 8 controls in one row, overflows.

**After:** 2 visible controls only.

```
[ ⋮ ]  ·····························  [ SCAN ]
```

- `⋮` is a `PopupMenuButton` containing: History, Calibrate (only when connected), Settings, Language (EN/EL toggle), Info, Diagnostics
- SCAN / DISCONNECT pill stays always visible — most-used control
- Title row above unchanged: title + LiveChip + RSSI chip + BatteryIndicator

### Main Content

**Before:** `_simpleMode` bool controlling two completely different widget trees.

**After:** Single unified view, always shown.

```
┌─────────────────────────────────┐
│  SAFE          0.023 mm/s       │   ← status card (colour-coded bg)
│  ████████░░░░░░░░░░░░░░░░░░░░  │     PPV bar inside card
└─────────────────────────────────┘

  PPV trend chart (60s rolling)       ← always visible

  ▸ Advanced                          ← collapsed by default
    · Spectrogram
    · Sensor history graph
    · Standards / metrics detail
```

- **Status card** = current Simple mode's coloured block (SAFE/CAUTION/DANGER + PPV + bar). Uses `_getSimpleSafetyLevel()` and `_getAlertColour()`.
- **PPV trend chart** = `PpvTrendChart` widget, always below status card.
- **Advanced section** = `ExpansionTile` wrapping: current alert banner, spectrogram card, sensor history graph card, standards/metrics detail. Collapsed by default, state not persisted (resets to collapsed on reconnect).
- `_simpleMode` state variable and `_buildSimpleModeToggle()` are removed entirely.

---

## Files Changed

- `lib/screens/safety/safety_view.dart` — header row + mode split removal + unified layout
