# CreditClock Implementation Plan for Claude (Based on Stitch Design)

## Goal
Implement the macOS-first CreditClock UI and data flow from Stitch mockups, with WidgetKit parity for glanceable usage status.

## Scope
- In scope: macOS app UI, widget UI, provider abstraction, persistence, refresh pipeline, status system
- Out of scope (first phase): account billing management, cross-device sync, full analytics backend

## Milestones

### M1. Design Token Foundation
Deliverables:
- Create centralized visual tokens for colors, spacing, radius, typography scale
- Mirror Stitch palette and semantic states (`active/trial/paused/expired/warning`)
- Add utility styles for card, status pill, progress, metric emphasis

Acceptance:
- All app screens consume shared tokens; no hard-coded random colors

### M2. Dashboard Layout (macOS)
Deliverables:
- Header toolbar (app name, sync info, Refresh, Add Provider)
- Sidebar filters (All/Active/Trial/Expired/Paused)
- Summary strip (total remaining, next refill, warning count)
- Responsive card grid for provider snapshots

Acceptance:
- Layout visually matches Stitch structure at common desktop widths
- Keyboard navigation works between sidebar and cards

### M3. Provider Card & Status Logic
Deliverables:
- Provider card component with usage bar, remaining credits, refill countdown, status pill
- Status thresholds:
  - `warning` when utilization >= 0.80
  - `critical` when utilization >= 0.95
- Relative time formatting and last-sync display

Acceptance:
- Cards render accurate states from mock and real data
- Warning/critical styling consistent in app + widget

### M4. Provider Detail Screen
Deliverables:
- Detail route/view with cycle stats, trend chart placeholder, diagnostics panel
- Segmented range selector (7d/30d)
- Alert rule controls + test connection action

Acceptance:
- Detail view opens from dashboard card
- Data placeholders are wired to model contracts

### M5. Widget Parity
Deliverables:
- Medium and large widget variants matching Stitch board
- Shared store synchronization via App Group
- Timeline refresh policy and fallback snapshot handling

Acceptance:
- Widget values align with in-app snapshot data
- Visual parity with design for typography/status chips

### M6. Data Integration Layer
Deliverables:
- Replace mock providers with concrete providers incrementally
- Introduce normalized mapping to `ServiceSnapshot`
- Retry/backoff, stale cache fallback, error telemetry hooks

Acceptance:
- At least one live provider integrated end-to-end
- API failure does not break UI rendering

## Claude Task Breakdown (Suggested Sequence)
1. Build `DesignTokens.swift` + semantic color/state map.
2. Refactor current `ContentView` into feature-based views:
   - `DashboardView`
   - `SidebarFilterView`
   - `SummaryStripView`
   - `ProviderCardView`
3. Implement stateful filtering and sorting in `ServiceStore`.
4. Add provider detail navigation + placeholder chart module.
5. Align widget UI components with shared status style helpers.
6. Integrate first real provider behind `ServiceProvider` protocol.
7. Add snapshot/UI tests for core states.

## Engineering Constraints
- Keep SwiftUI views small and composable.
- Preserve `Shared/` model contracts for app/widget compatibility.
- Never hard-code API tokens in source; use Keychain.
- Maintain minimum deployment target currently set in project config.

## Test Plan
- Unit tests:
  - Utilization and threshold calculation
  - Refill countdown formatting
  - Store filtering/sorting behavior
- Snapshot/UI tests:
  - Dashboard default/empty/error/warning states
  - Widget medium/large visual state checks
- Integration tests:
  - Provider mapping from raw JSON to `ServiceSnapshot`

## Definition of Done
- macOS dashboard matches Stitch key structure and hierarchy.
- Widget reflects the same source-of-truth data.
- One live provider integrated with resilient failure handling.
- Tests for status logic and store behavior are green.
