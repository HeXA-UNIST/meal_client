# Spec: KST Timezone Cache Bugfix

**File:** `lib/features/meal/meal_data_source.dart`
**Function:** `_getKstWeekNumber(DateTime time)` → renamed to `_kstWeekId`
**Status:** Ready for implementation
**Date:** 2026-05-10
**Reviewed by:** Claude (analysis) + Gemini gemini-3.1-pro-preview (validation)

---

## 1. Bug Description

### Root Cause

`_getKstWeekNumber` extracts `time.year` from the **local timezone** `DateTime`,
but computes the diff using `time.toUtc().add(Duration(hours: 9))` (**KST**).
When local year ≠ KST year, `theFirstDay` is anchored to the wrong year, producing
a week number off by ~52 weeks.

```dart
// BUGGY: time.year is local, but diff is KST
int _getKstWeekNumber(DateTime time) {
  final DateTime start;
  {
    final theFirstDay = DateTime.utc(time.year, 1, 1, 0);   // ← local year
    start = theFirstDay.subtract(Duration(days: theFirstDay.weekday - 1));
  }
  final diff = time.toUtc().add(Duration(hours: 9)).difference(start); // ← KST
  return (diff.inDays / 7).toInt() + 1;
}
```

### Concrete Example (Gemini-verified)

| | Value |
|---|---|
| User timezone | EST (UTC-5) |
| Local `time` | Dec 31, 2025 11:00 EST |
| `time.year` | **2025** → `theFirstDay` = Jan 1, 2025 |
| KST equivalent | **Jan 1, 2026** 01:00 KST |
| `diff` computed against | 2025's first week start |
| Resulting week number | ~Week 53 (wrong year baseline) |
| Cache file week number | Matches 2025 baseline |
| Outcome | Mismatch → unnecessary network fetch |

### Additional Edge Case (Gemini)

Even with the year-extraction fix applied, a second edge case exists: when Jan 1
falls on a **Sunday** (e.g., Jan 1, 2023), the year-relative week calculation
causes a mid-week cache invalidation.

- Dec 31, 2022 (Saturday KST) → Week **53** (relative to 2022)
- Jan 1, 2023 (Sunday KST) → Week **1** (relative to 2023)

`fileWeekNum (53) ≠ nowWeekNum (1)` → cache invalidated on Sunday, one day
before the actual menu week boundary (Monday).

### Scope

- **Not a data integrity bug.** App always shows correct data.
- No security impact.
- Primary audience (UNIST students in KST) unaffected in practice.
- Year-boundary issue: ~9 hours/year for UTC+10..+12 users.
- Sunday-boundary issue: ~24 hours/year when Jan 1 is a Sunday.

---

## 2. Fix Specification

### Preferred: Monotonic Epoch Week ID (Gemini-recommended)

Replace the year-relative week number with a monotonically increasing week ID
anchored to **January 5, 1970 (a known Monday)**. This eliminates both the
year-extraction bug and the ISO week 53 edge case simultaneously.

```dart
// 반환값은 주 번호가 아닌 단조 증가 주 ID — 절댓값이 아닌 동등 비교에만 사용.
int _kstWeekId(DateTime time) {
  final kstTime = time.toUtc().add(const Duration(hours: 9));
  // 1970년 1월 5일은 월요일 — 안정적인 에포크 기준점으로 사용.
  final epoch = DateTime.utc(1970, 1, 5);
  return kstTime.difference(epoch).inDays ~/ 7;
}
```

This returns an opaque week ID (e.g., 2938) that increments exactly once per
Monday 00:00 KST, with no year resets. Only equality between two IDs is
meaningful — the absolute value carries no semantic information.

### Alternative: Minimal Year-Extraction Fix (Claude)

If the monotonic approach is too large a change for the current commit scope,
a minimal fix that addresses only the year-extraction bug:

```dart
int _kstWeekId(DateTime time) {
  final kstTime = time.toUtc().add(const Duration(hours: 9));
  final theFirstDay = DateTime.utc(kstTime.year, 1, 1, 0);
  final start = theFirstDay.subtract(Duration(days: theFirstDay.weekday - 1));
  final diff = kstTime.difference(start);
  return (diff.inDays / 7).toInt() + 1;
}
```

This fixes the year mismatch but leaves the Sunday/ISO-week-53 edge case open.

### Recommendation

Use the **monotonic epoch approach**. It is simpler, shorter, and provably
correct across all timezone and year-boundary scenarios. No behavioral
regression for existing KST users.

---

## 3. Behavioral Contract

`_kstWeekId(DateTime time)` MUST:

1. Convert `time` to KST (UTC+9) before any date arithmetic.
2. Return a value that increments exactly once per KST week boundary (Monday 00:00 KST).
3. Return identical values for two `DateTime` inputs in the same KST calendar week, regardless of caller's local timezone.
4. Not depend on the local timezone of the device.

---

## 4. Test Plan

These tests verify the **monotonic epoch implementation** is correct — they are not
regression tests for the original `.year` bug. (The buggy implementation would
also pass tests 1–3 in most timezones because `DateTime.utc(...)` already has
UTC `.year`, not local `.year`.) Test 4 is the only one the buggy implementation
fails reliably.

```dart
// 같은 KST 주 내 두 시각은 동일한 주 ID를 반환한다
test('같은 KST 주의 월요일과 일요일은 동일한 주 ID이다', () {
  final monday = DateTime.utc(2026, 5, 4, 1, 0); // Mon May 4 10:00 KST
  final sunday = DateTime.utc(2026, 5, 10, 1, 0); // Sun May 10 10:00 KST
  expect(_kstWeekId(monday), equals(_kstWeekId(sunday)));
});

// KST 월요일 00:00 직전/직후 경계에서 주 ID가 정확히 1 증가한다
test('KST 월요일 00:00에 주 ID가 1 증가한다', () {
  final beforeMidnight = DateTime.utc(2026, 5, 10, 14, 59); // Sun 23:59 KST
  final afterMidnight  = DateTime.utc(2026, 5, 10, 15, 0);  // Mon 00:00 KST
  expect(_kstWeekId(afterMidnight),
         equals(_kstWeekId(beforeMidnight) + 1));
});

// 연도 경계: UTC+10 사용자가 Jan 1 00:30 로컬 (= Dec 31 KST)
test('KST 기준 연도 말일 23:30은 같은 날 10:00 KST와 동일한 주 ID이다', () {
  // Jan 1 2026 00:30 UTC+10 = Dec 31 2025 23:30 KST = UTC Dec 31 2025 14:30
  final utcPlus10Jan1 = DateTime.utc(2025, 12, 31, 14, 30);
  final kstDec31Ref   = DateTime.utc(2025, 12, 31, 1, 0); // Dec 31 10:00 KST
  expect(_kstWeekId(utcPlus10Jan1),
         equals(_kstWeekId(kstDec31Ref)));
});

// ISO week 53 경계: 2023-01-01은 일요일 (monotonic 방식에서만 통과)
test('Jan 1이 일요일일 때 토요일과 같은 주 ID이다', () {
  final satDec31 = DateTime.utc(2022, 12, 31, 1, 0); // Dec 31 10:00 KST
  final sunJan1  = DateTime.utc(2023, 1, 1, 1, 0);   // Jan 1 10:00 KST
  expect(_kstWeekId(sunJan1),
         equals(_kstWeekId(satDec31)));
});
```

> **Note:** `_kstWeekId` is private. Either annotate with `@visibleForTesting`
> (requires `package:meta`) or move to `lib/core/constants.dart` as a package-visible
> function alongside `MealTimeConfig`.

---

## 5. Implementation Plan

### Step 1 — Apply fix (5 min)

Replace `_getKstWeekNumber` in `lib/features/meal/meal_data_source.dart` with
the monotonic epoch implementation from §2, renamed to `_kstWeekId`. Update the
two call sites in `getCachedMealData` accordingly.

### Step 2 — Add tests (15 min)

Add the four test cases from §4. If keeping the function private, expose it for
testing:

```dart
// meal_data_source.dart
@visibleForTesting
int kstWeekIdForTest(DateTime time) => _kstWeekId(time);
```

Or move `_kstWeekId` to `lib/core/constants.dart` (remove `_` prefix),
consistent with where `MealTimeConfig` lives.

### Step 3 — Static analysis and tests

```bash
flutter analyze
flutter test
```

### Step 4 — Commit

```
fix: KST 주 번호 계산에서 epoch 기반 단조 증가 방식으로 전환

시간대가 KST가 아닌 기기에서 time.year가 로컬 연도를 반환해
KST 주 번호 계산이 잘못될 수 있는 버그를 수정한다.
또한 1월 1일이 일요일인 경우 주 경계가 월요일 대신 일요일에
발생하던 ISO week 53 엣지 케이스도 함께 해결한다.
```

---

## 6. Out of Scope

- `getCachedMealData` and `fetchAndCacheMealData` call sites — no changes.
- `getLastModifiedOfFile` return type — no changes.
- API or backend changes.
- Week navigation feature (separate TODO).

---

## 7. Codex Review Findings (2026-05-10)

The bug is real, but the practical impact is narrower than a data correctness
issue.

- `_getKstWeekNumber()` (pre-fix) currently reads `time.year` before converting the input
  to KST, while the diff is calculated from `time.toUtc().add(9h)`. This can
  classify two timestamps in the same KST week as different cache weeks when the
  local calendar year and KST calendar year differ.
- The Jan 1 Sunday case is also real. With the current year-relative week
  calculation, Dec 31, 2022 (Saturday KST) and Jan 1, 2023 (Sunday KST) produce
  different week numbers even though the app's visible week boundary is Monday
  KST.
- The app still attempts `fetchAndCacheMealData()` after cache resolution in
  `HomePage`, so the main user-visible impact is avoidable cache misses,
  spinners, and unnecessary network dependency. If the network is unavailable,
  a still-valid cache may fail to display.
- The EST example demonstrates the wrong year baseline for a single timestamp,
  but a cache mismatch requires comparing two timestamps that should be in the
  same KST week and end up using different local-year baselines.
- The timezone scope is broader than UTC+10..+12. Any device timezone can be
  affected during the interval where local calendar year and KST calendar year
  differ around New Year.

The monotonic epoch-week implementation remains the preferred fix. Moving the
helper into `core/constants.dart` or another small testable utility is cleaner
than exposing a data-source-only `kstWeekIdForTest()` wrapper.
