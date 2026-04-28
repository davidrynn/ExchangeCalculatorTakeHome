# CurrencyXchangeCalc — Implementation Plan

## Context

This is a DolarApp mobile engineering code challenge: build a two-way USDc ↔ foreign-currency exchange calculator for iOS using SwiftUI. The app fetches live rates from `https://api.dolarapp.dev/v1/tickers`, handles a currencies list API that is not yet live (hardcoded fallback), and must match the Figma design. The submission must run in the simulator without modification.

Starting point: Xcode scaffold only — `ContentView.swift` and `CurrencyXchangeCalcApp.swift` contain placeholder code. Test targets exist (Swift Testing for unit tests, XCTest for UI tests) but are empty.

---

## Spec Clarifications — Recruiter Q&A (2026-04-24)

Submitted a batch of ambiguity questions before final submission; the recruiter's response shaped the following decisions:

**Currency list (directed):**
> "The app should show whatever the endpoint returns. For this exercise, that means using a local fallback list until the endpoint is shipped, since that endpoint is intentionally missing as part of the test."

- `Currency.fallbackList` mirrors the spec's example response exactly: `["MXN", "ARS", "BRL", "COP"]`.
- No EURc, despite the Figma showing it in the picker — the Figma visual was taken as an aspirational mock, not a binding requirement for the fallback content.
- When `/tickers-currencies` ships, the VM's `loadAvailableCurrencies()` replaces the fallback with whatever the endpoint returns; metadata (flag, displayName) is merged from the fallback when codes overlap.

**Everything else — candidate's judgment:**
> "For the rest of the points (currency symbols, loading/error states, summary precision, and initial foreign currency behavior) there isn't a prescribed answer. The team is happy for you to use your own judgment there, so long as your choices are sensible and consistent."

| Area | Choice | Rationale |
|---|---|---|
| **Currency symbol** | None — amounts are symbol-less; flag + ISO code gives currency context | Avoids per-locale symbol lookup logic and the ambiguity of showing `$` on non-USD amounts |
| **Loading state** | Centered `ProgressView` with VoiceOver label "Loading exchange rates" | Live fetch is typically ~200 ms; anything heavier would visually flicker |
| **Error state** | Red dismissible banner with Retry button; cancellation errors never surfaced | Retry re-enters the `.task(id:)` load path via a bumped `retryToken` (structured concurrency, no detached `Task`) |
| **Summary-line precision** | `Decimal.FormatStyle.precision(.fractionLength(2...4))` — rate shown with 2–4 fractional digits | API returns 10; 2–4 is a compromise between readability and accuracy. Rate values are always > 1 in practice so this range is never lossy. |
| **Amount-field precision** | `Decimal.FormatStyle.precision(.fractionLength(4...8))` — amounts shown with 4–8 fractional digits | See "Round-trip precision edge case" below — 4dp minimum is what avoids the 1 MXN ↔ 0.06 USDc visible drift |
| **Input validation** | Max 2 decimal places, clamped during typing; locale-aware separator; strict parse rejects `"1.2.3"` | Matches typical currency UX; 2dp is the standard for user-typed values. (Note: this means the *displayed* output of a tiny conversion can have more digits than a user can re-type cleanly — see the round-trip note below.) |
| **Initial currency** | Hardcoded MXN on first launch; no persistence | No persistence spec; adding UserDefaults would be scope creep |
| **Keyboard dismiss** | Done button in a keyboard toolbar + tap-outside to dismiss | iOS-standard pattern; Figma's always-visible keypad is atypical for real devices |

These choices are documented alongside the code they inform (Currency.swift, loadRates/loadAvailableCurrencies, ExchangeCalculatorView, clampToTwoDecimalPlaces) and locked in by tests.

### Round-trip precision edge case

Originally the amount formatter used a fixed 2 fractional digits. A user found this:

> Type `1` in MXN. USDc shows `0.06`. Tap USDc field, type `0.06`. MXN comes back as `1.04` — not `1.00`.

**Why:** with MXN ask ≈ 17.36, `1 / 17.36 ≈ 0.05761`. The formatter rounded to `0.06`. When the user typed `0.06` back, the system computed `0.06 × bid(17.34) = 1.0404`, which rounds to `1.04`. The displayed `0.06` represents a *range* of underlying values; re-typing it picks the midpoint, not the original. There's also a small unavoidable drift from the bid/ask spread itself, but the bulk of the visible 4% error is precision loss from 2dp display rounding.

**Fix (chosen, "option A"):** widen the amount formatter's range to `.fractionLength(4...8)`. With that:
- `1 MXN → "0.0576" USDc` (4 digits — meaningful precision)
- Round-trip back: `0.0576 × 17.34 ≈ 0.9988 → "0.9988"` — within ~0.2% of the original 1 MXN. The remaining drift is just the spread.
- Tiny rates (e.g. ARS at ask ≈ 1551 → `0.000645` USDc/peso) still render their significant digits within the 8-digit upper bound.

**Why this approach over the alternative ("option B"):** the alternative was to keep 2dp display but track a precise underlying `Decimal` per field, using the precise value for round-trip math. That works but adds parallel state (the displayed value no longer reflects what the VM actually holds), invariants to maintain (when does the precise value get invalidated by user typing?), and complexity for a marginal UX gain. The "show more digits" approach matches what XE, Google's currency widget, and other exchange calculators do — simpler, cleaner, conventional.

### `Decimal` source-of-truth refactor

Follow-up bug user reported after the precision fix:

> If two numbers are in both fields, tapping back and forth will change the numbers, possibly because behind the hood the numbers are being truncated and changing the values — the user can see a change but the actual stored values should be Decimal to preserve accuracy.

User instinct was right. The original VM stored both `usdcAmount` and `foreignAmount` as `String`, with the input handler running a 2dp clamp on the typed value before parsing. Two leak paths:

1. **Rate refresh re-clamping a computed display string.** The old `recalculateAfterRateUpdate()` re-invoked `usdcAmountChanged(usdcAmount)`, which sent a previously-formatted display value (e.g. `"0.0576"`) through the clamp → `"0.05"` → recomputed foreign. The user would see the foreign side jump.
2. **The clamp itself, applied to user input at all.** Even with no rate refresh, any re-entry into the input handler with a previously-formatted string (e.g. one of the field's own display values being passed back through SwiftUI binding mechanics) would clamp away precision.

**Fix:** make the `Decimal` the authoritative numeric value, not the display string. The VM now holds:

- `usdcDecimal: Decimal?` and `foreignDecimal: Decimal?` — `private(set)`, the source of truth.
- `usdcAmount: String` and `foreignAmount: String` — what the field shows. For the *user-edited* side it's the raw typed text (no clamp, no re-format). For the *derived* side it's `format(decimal)`.
- `lastEditedSide: EditedSide?` — `.usdc` or `.foreign`. On rate refresh, only the *non-edited* side is re-derived from the edited side's `Decimal`. The user-edited side never goes through the parser/formatter again.

**Removed:** the 2dp input clamp. Users can now type any precision they want; the underlying `Decimal` records exactly what they typed. The display formatter (4–8dp) still applies to the *derived* side.

**Tests** locking this in:
- `usdcChangedPreservesUserInputAsTyped` — `"1.2345"` stays `"1.2345"`, no clamp.
- `rateRefreshDoesNotMutateUserTypedSide` — type `"1"` in foreign, refresh rate, foreign stays `"1"`.

---

## Overall Checklist

- [x] Phase 0 — Architecture design & file scaffold
- [x] Phase 1 — Data layer (models + service)
- [x] Phase 2 — ViewModel (conversion logic)
- [x] Phase 3 — Main calculator UI
- [x] Phase 4 — Currency picker bottom sheet
- [x] Phase 5 — Live API integration & error/loading states
- [x] Phase 6 — Polish, edge cases & accessibility (some sub-items intentionally walked back — see *Decimal source-of-truth refactor*)
- [x] Phase 7 — Full test suite & public API documentation

---

## Git Flow

```
main  ──────────────────────────────────────────────── (always builds & runs)
         │
         ├── feat/phase-0-architecture
         ├── feat/phase-1-data-layer
         ├── feat/phase-2-viewmodel
         ├── feat/phase-3-calculator-ui
         ├── feat/phase-4-currency-picker
         ├── feat/phase-5-api-integration
         ├── feat/phase-6-polish
         └── feat/phase-7-tests-docs
```

**Rules:**
- Each phase lives on its own branch off `main`.
- Before opening the phase PR: rebase or merge latest `main` into the branch so PRs diff cleanly and avoid pile-up conflicts across phases.
- Open a self-review PR before merging; all tests must pass.
- Merge to `main` only after: ✅ build passes, ✅ tests pass, ✅ manual simulator smoke-test done, ✅ codex review completed (see below).
- Tag `v1.0.0` on `main` before submission.
- Commit messages: `feat:`, `fix:`, `test:`, `docs:`, `polish:` prefixes.

### Per-phase workflow (mandatory)

Every phase follows this exact sequence. Do not skip the codex review step:

1. Branch off latest `main` → implement → tests green → commit.
2. **Codex review** of the phase commit(s). Resume the existing codex review thread if one is already running; otherwise start a new review, pointing at the phase commit hash(es) and the relevant plan section. Default settings: a reasoning-capable Codex model, high reasoning effort, read-only sandbox — adjust as needed.
3. Evaluate critiques directly. For each: agree/disagree with reasoning. Apply fixes as new commits, rerun tests.
4. Summarize the review outcome (table of severity / issue / fix) to the user.
5. Ask for sign-off to merge to `main`.
6. Merge (`--no-ff`) and move to next phase.

The codex review has caught real bugs that local tests didn't: inverted bid/ask formulas, `Decimal(string:)` silently parsing `"1.2.3"` as `1.2`, a no-op binding setter causing TextField/VM divergence after swap, and an accessibility identifier attached to the wrong element. Treat it as a required gate, not an optional polish step.

---

## Architecture

**Pattern:** MVVM + protocol-based service layer

```
CurrencyXchangeCalc/
├── CurrencyXchangeCalcApp.swift              # @main entry point (root of target group)
├── ContentView.swift                          # Root container (existing, to update)
├── Models/
│   ├── Currency.swift                         # Currency code, flag, display name
│   ├── ExchangeRate.swift                     # API ticker model (ask/bid/book/date)
│   └── ConversionDirection.swift             # Enum: .usdc / .foreign
├── Services/
│   ├── ExchangeRateServiceProtocol.swift     # Protocol (enables mocking)
│   └── LiveExchangeRateService.swift         # URLSession implementation
├── ViewModels/
│   └── ExchangeCalculatorViewModel.swift     # @Observable — all business logic
└── Views/
    ├── ExchangeCalculatorView.swift           # Main screen
    ├── Components/
    │   ├── CurrencyInputRow.swift            # Flag + code + amount field row
    │   └── SwapButton.swift                  # Green circular swap button
    └── CurrencyPicker/
        ├── CurrencyPickerSheet.swift         # Bottom sheet container
        └── CurrencyPickerRow.swift           # Single row in picker list

CurrencyXchangeCalcTests/
├── Models/
│   ├── ExchangeRateTests.swift              # JSON decoding, model logic
│   └── CurrencyTests.swift                  # Fallback list, flag mapping
├── Services/
│   └── MockExchangeRateService.swift        # Test double
└── ViewModels/
    └── ExchangeCalculatorViewModelTests.swift  # Conversion, swap, bid/ask

CurrencyXchangeCalcUITests/
├── CalculatorUITests.swift                   # Two-way input, swap button
└── CurrencyPickerUITests.swift               # Sheet open/close, currency selection
```

**Key design decisions:**
- `@Observable` ViewModel (iOS 17+ / 26.4 target allows this)
- Service protocol with `async throws` — swap in `MockExchangeRateService` in tests
- **Bid/ask semantics (single source of truth):** API book `usdc_xxx` means USDc is base, foreign is quote.
  - **USDc → foreign:** multiply by `bid` (user sells USDc, receives bid price in foreign)
  - **Foreign → USDc:** divide by `ask` (user buys USDc, pays ask price in foreign)
  - All formulas, tests, and docs in this plan must match this convention.
- Currency list hardcoded to `["MXN", "ARS", "BRL", "COP"]` with runtime merge if API ever responds
- No 3rd-party dependencies

### Concurrency & Actor Isolation

The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`, so every unannotated type is implicitly `@MainActor`. Explicit isolation annotations are required wherever work should run off the main thread.

| Layer | Isolation | Rationale |
|---|---|---|
| Models (`Currency`, `ExchangeRate`, `ConversionDirection`) | `Sendable`, nonisolated | Pure value types; must cross isolation boundaries |
| `ExchangeRateServiceProtocol` | `Sendable` | Held by MainActor VM; must be safe to share |
| `LiveExchangeRateService` | `final class … Sendable`, `nonisolated` methods | Stateless URLSession wrapper; network work off main |
| `MockExchangeRateService` (tests) | `@MainActor` | Sequential test code with mutable stubs |
| `ExchangeCalculatorViewModel` | explicit `@MainActor` | Owns UI state |
| All Views | `@MainActor` (SwiftUI default) | — |

**Structured concurrency rules:**
- Views kick off fetches via `.task(id: viewModel.selectedCurrency.code) { await viewModel.loadRates() }` — SwiftUI cancels and restarts the task whenever the id changes (e.g. user picks a different currency), and cancels on view disappear.
- `.task(id:)` owns cancellation end-to-end; the VM does **not** store its own `Task` reference. `loadRates()` is a plain `async` function and relies on `Task.isCancelled` / `try Task.checkCancellation()` to drop stale responses.
- ViewModel methods that call the service use plain `await` (inherits MainActor); the service methods are `nonisolated async`, so the actual network I/O runs off main.
- Long-running / retryable loops call `try Task.checkCancellation()` cooperatively.
- Parallel fan-out (if we later prefetch multiple currencies): `async let` inside `loadRates`.
- No raw `Task.detached` unless we explicitly need to escape inheritance — prefer letting `.task(id:)` scope manage lifetime.

---

## Phase 0 — Architecture & File Scaffold

**Branch:** `feat/phase-0-architecture`

### Spec
- Create all empty Swift files in the folder structure above
- Add them to the Xcode project target
- Write stub types with `// TODO:` markers so the project still compiles

### Checklist
- [x] Create `Models/Currency.swift` stub
- [x] Create `Models/ExchangeRate.swift` stub
- [x] Create `Models/ConversionDirection.swift` stub
- [x] Create `Services/ExchangeRateServiceProtocol.swift` stub
- [x] Create `Services/LiveExchangeRateService.swift` stub
- [x] Create `ViewModels/ExchangeCalculatorViewModel.swift` stub
- [x] Create `Views/ExchangeCalculatorView.swift` stub
- [x] Create `Views/Components/CurrencyInputRow.swift` stub
- [x] Create `Views/Components/SwapButton.swift` stub
- [x] Create `Views/CurrencyPicker/CurrencyPickerSheet.swift` stub
- [x] Create `Views/CurrencyPicker/CurrencyPickerRow.swift` stub
- [x] Add all files to Xcode target membership — N/A, project uses `PBXFileSystemSynchronizedRootGroup` (auto-discovery)
- [x] Project builds with zero errors
- [x] Concurrency/isolation annotations applied (see Concurrency & Actor Isolation section)

### Testing
- Build check: `xcodebuild -scheme CurrencyXchangeCalc -configuration Debug build`

### Commit
```
feat: scaffold architecture — models, services, viewmodel, view stubs
```

### User Input Gate
- Review folder structure and architecture decisions before proceeding

---

## Phase 1 — Data Layer (Models & Service)

**Branch:** `feat/phase-1-data-layer`

### Spec

Single-target app uses internal access (no `public`). Annotations below reflect the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting.

**`Currency`**
```swift
/// A supported currency for exchange against USDc.
nonisolated struct Currency: Identifiable, Hashable, Sendable {
    let code: String          // e.g. "MXN"
    let flagEmoji: String     // e.g. "🇲🇽"
    let displayName: String   // e.g. "Mexican Peso"
    var id: String { code }

    /// Hardcoded fallback list used when the currencies API is unavailable.
    static let fallbackList: [Currency]
}
```

**`ExchangeRate`**
```swift
/// Raw ticker from GET /v1/tickers.
/// Decodable only — we never encode these back to JSON.
nonisolated struct ExchangeRate: Decodable, Equatable, Sendable {
    let ask: Decimal    // price to BUY USDc (pay `ask` units of foreign per 1 USDc)
    let bid: Decimal    // price to SELL USDc (receive `bid` units of foreign per 1 USDc)
    let book: String    // e.g. "usdc_mxn"
    let date: String

    /// Extracts the foreign currency code from book (e.g. "usdc_mxn" → "MXN").
    var currencyCode: String
}
```

**`ConversionDirection`**
```swift
nonisolated enum ConversionDirection: Sendable {
    case usdc      // user is typing in the USDc field
    case foreign   // user is typing in the foreign currency field
}
```

**`ExchangeRateServiceProtocol`**
```swift
protocol ExchangeRateServiceProtocol: Sendable {
    /// Fetches current tickers for the given currency codes.
    /// Explicitly `nonisolated` so conformers cannot accidentally inherit the
    /// module's MainActor default and pin network I/O to the main thread.
    nonisolated func fetchRates(for currencies: [String]) async throws -> [ExchangeRate]

    /// Fetches available currency codes; throws if API is unavailable.
    nonisolated func fetchCurrencies() async throws -> [String]
}
```

**`LiveExchangeRateService`**
```swift
nonisolated final class LiveExchangeRateService: ExchangeRateServiceProtocol {
    // URLSession-backed implementation — runs off the main thread.
}
```
- Uses `URLSession.shared` with `async/await`
- Decodes JSON with `JSONDecoder`
- Throws typed errors: `ServiceError.networkError`, `.decodingError`, `.unavailable`
- Honors cooperative cancellation — `URLSession.data(...)` is cancellation-aware

### Checklist
- [x] `Currency` model (`nonisolated`, `Sendable`) with `fallbackList` (MXN, ARS, BRL, COP + flag emojis)
- [x] `ExchangeRate` Decodable model (`nonisolated`, `Sendable`, not Codable — we never encode); `currencyCode` computed from `book`
- [x] **`ExchangeRate` custom `Decodable` / property wrapper** to decode quoted-string numbers in the API response (`"ask": "18.4105000000"`) into `Decimal` via `Decimal(string:)` — never route through `Double`, which loses precision at the 10-digit fraction
- [x] `ConversionDirection` enum (`nonisolated`, `Sendable`)
- [x] `ExchangeRateServiceProtocol: Sendable` with two `nonisolated async` methods
- [x] `LiveExchangeRateService` (`nonisolated final class`) — `fetchRates` implementation
- [x] `LiveExchangeRateService` — `fetchCurrencies` implementation (graceful fallback on 404)
- [x] `ServiceError` enum (`nonisolated`, `Sendable`) with localized descriptions
- [x] All types documented with `///` doc comments
- [x] Verify no MainActor warnings when building with strict concurrency

### Unit Tests (`CurrencyXchangeCalcTests`)
- [x] `ExchangeRateTests` — decodes valid JSON fixture correctly
- [x] `ExchangeRateTests` — quoted-string numbers from the API (e.g. `"ask": "18.4105000000"`) decode to exact `Decimal` (no `Double` round-trip)
- [x] `ExchangeRateTests` — `currencyCode` extraction from book string (`"usdc_mxn"` → `"MXN"`, handles uppercase)
- [x] `ExchangeRateTests` — malformed JSON throws `DecodingError`, does not crash
- [x] `CurrencyTests` — `fallbackList` contains exactly 4 currencies (MXN, ARS, BRL, COP)
- [x] `CurrencyTests` — each currency has non-empty flag and displayName
- [x] Concurrency smoke test: call `LiveExchangeRateService.fetchRates(...)` from a `nonisolated` test function — compiles and runs without MainActor hop warnings

### Testing Command
```bash
xcodebuild -scheme CurrencyXchangeCalc test -only-testing:CurrencyXchangeCalcTests
```

### Commit
```
feat: data layer — ExchangeRate model, Currency fallback list, service protocol + live impl
```

### User Input Gate
- Confirm bid/ask direction semantics before Phase 2

---

## Phase 2 — ViewModel (Conversion Logic)

**Branch:** `feat/phase-2-viewmodel`

### Spec

**`ExchangeCalculatorViewModel`**
```swift
@MainActor
@Observable
final class ExchangeCalculatorViewModel {
    // MARK: - Published State (MainActor-isolated)
    var usdcAmount: String
    var foreignAmount: String
    var selectedCurrency: Currency
    var availableCurrencies: [Currency]
    var isLoading: Bool
    var errorMessage: String?

    private let service: ExchangeRateServiceProtocol  // Sendable, nonisolated

    // MARK: - Public Interface
    /// Called when the user edits the USDc field; recalculates foreignAmount.
    func usdcAmountChanged(_ newValue: String)

    /// Called when the user edits the foreign field; recalculates usdcAmount.
    func foreignAmountChanged(_ newValue: String)

    /// Toggles `isSwapped`, flipping which row the view renders on top.
    /// Does not touch amounts or currency assignments — rows move as
    /// atomic units, carrying their values with them.
    func swapCurrencies()

    /// Sets selectedCurrency and re-converts using the currently held rate.
    /// Does not trigger network fetches — rate loading is driven by the view's
    /// `.task(id: selectedCurrency.code)` modifier in Phase 5.
    func selectCurrency(_ currency: Currency)

    /// Fetches rates for the selected currency via the injected service.
    /// In Phase 2 this is exercised only via `MockExchangeRateService`.
    /// Honors structured cancellation — caller is typically SwiftUI `.task(id:)`.
    func loadRates() async
}
```

**Conversion math (matches the Bid/Ask Semantics source-of-truth in Architecture):**
- USDc → foreign: `foreignAmount = usdcAmount * rate.bid`
- Foreign → USDc: `usdcAmount = foreignAmount / rate.ask`
- All math uses `Decimal` — never `Double` — to avoid binary-float rounding.
- Format output with `Decimal.FormatStyle` (value-type, `Sendable`-safe); do **not** use shared `NumberFormatter` instances.
- 2 decimal places for display, locale-aware decimal separator via `Decimal.FormatStyle.locale(.current)`.

### Checklist
**Phase 2 uses `MockExchangeRateService` only — no live URLSession work. That lands in Phase 5.**
- [x] `@MainActor @Observable` ViewModel with all state properties
- [x] `usdcAmountChanged` → updates `foreignAmount` using `rate.bid` (multiply)
- [x] `foreignAmountChanged` → updates `usdcAmount` using `rate.ask` (divide)
- [x] `swapCurrencies` — toggles `isSwapped` flag; values/currencies stay paired (rows move as atomic units)
- [x] `selectCurrency` — updates selected currency, triggers in-memory re-conversion using the current mock rate
- [x] Input guard: non-numeric / NaN / Inf ignored; empty string clears the other field
- [x] Number formatting helper uses `Decimal.FormatStyle` (value type, inherently `Sendable`) — no shared `NumberFormatter` (now lives in `Extensions/Decimal+Formatting.swift`)
- [x] All math in `Decimal`; verify no `Double` leakage

### Unit Tests (`CurrencyXchangeCalcTests`)
Using `MockExchangeRateService` (pre-seeded with fixture rates). Tests are `@MainActor` so they can read VM state directly.
- [x] `usdcAmountChanged("1")` → `foreignAmount` equals `bid` formatted (regression guard for bid/ask direction; precision is now 4–8dp per the round-trip refactor below)
- [x] `foreignAmountChanged("18.40")` → `usdcAmount` equals `18.40 / ask` formatted (regression guard)
- [x] `swapCurrencies` — toggles `isSwapped`; does NOT mutate amounts
- [x] `selectCurrency` — `selectedCurrency` updates; re-conversion uses new rate
- [x] Empty input → other field clears to `""` (only when a `currentRate` exists; without a rate the two fields are independent)
- [x] Non-numeric input ignored (no crash, no update)
- [x] Locale parse: accepts `,` as decimal separator when `Locale.current` is comma-locale (fixture: `es_ES`)
- [x] Large input (e.g. `1_000_000`) does not overflow `Decimal` arithmetic

> Note: live-fetch error paths, cancellation ordering, and fallback-list wiring are tested in Phase 5, where live networking is introduced.

### Testing Command
```bash
xcodebuild -scheme CurrencyXchangeCalc test -only-testing:CurrencyXchangeCalcTests
```

### Commit
```
feat: viewmodel — two-way conversion, swap logic, bid/ask math, error handling
```

### User Input Gate
- Confirm number formatting rules (locale decimal separator? max digits?)

---

## Phase 3 — Main Calculator UI

**Branch:** `feat/phase-3-calculator-ui`

### Spec

**`ExchangeCalculatorView`** — root calculator screen:
- Navigation title "Exchange"
- Rate summary line: `"1 USDc = {rate} {code}"` in green (`#22D081`)
- Stacked `CurrencyInputRow` (USDc on top, foreign below)
- `SwapButton` overlaid between the two rows
- Connects to `ExchangeCalculatorViewModel` via `@State` or environment

**`CurrencyInputRow`** — single input row:
- Flag emoji + currency code on the left (tappable on foreign row)
- Right-aligned `TextField` for amount (numeric keyboard)
- White card background, `cornerRadius(16)`, padding 12/16

**`SwapButton`** — circular green button:
- Background `#22D081`, 24×24, border 6pt `#F4F4F4`
- SF Symbol `arrow.up.arrow.down` (white)
- Triggers `viewModel.swapCurrencies()`

**`ContentView`** — updated to host `ExchangeCalculatorView` and inject ViewModel.

### Checklist
- [x] `ExchangeCalculatorView` layout matches Figma (VStack, spacing 16)
- [x] `CurrencyInputRow` — USDc row (non-tappable currency side)
- [x] `CurrencyInputRow` — foreign row (currency side tappable, opens sheet)
- [x] `SwapButton` styled and functional (later replaced by `CircleIconStyle` applied to a plain `Button`)
- [x] Rate summary line below title
- [x] Loading state: `ProgressView` overlay while `isLoading`
- [x] Error banner when `errorMessage != nil` (dismissible)
- [x] `ContentView` updated — injects `ExchangeCalculatorViewModel`
- [x] Keyboard `.numberPad` on both fields (uses `.decimalPad` for locale-correct decimal entry)
- [x] Background color `#F8F8F8`
- [x] Stable `accessibilityIdentifier` on every testable element — required for UI tests:
  - `"usdcAmountField"`, `"foreignAmountField"`, `"foreignCurrencyPicker"`, `"swapButton"`, `"rateSummaryLabel"`, `"errorBanner"`

### UI Tests (`CurrencyXchangeCalcUITests`)
- [x] `testCalculatorLoads` — app launches, both input fields visible (query by `accessibilityIdentifier`)
- [x] `testUSDCInputUpdatesForeignField` — type "1" in `usdcAmountField`, `foreignAmountField` shows non-zero value
- [x] `testForeignInputUpdatesUSDCField` — type amount in `foreignAmountField`, `usdcAmountField` updates
- [x] `testSwapButtonExists` — `swapButton` is hittable
- [x] `testSwapButtonSwapsRowPositions` — tap swap, foreign row moves above USDc row (frame.minY inverts), amounts stay attached to their currencies

### Testing Commands
```bash
xcodebuild -scheme CurrencyXchangeCalc test -only-testing:CurrencyXchangeCalcUITests
xcodebuild -scheme CurrencyXchangeCalc test -only-testing:CurrencyXchangeCalcTests
```

### Commit
```
feat: main calculator UI — input rows, swap button, rate summary, loading/error states
```

### User Input Gate
- Visual review in simulator before building the picker

---

## Phase 4 — Currency Picker Bottom Sheet

**Branch:** `feat/phase-4-currency-picker`

### Spec

**`CurrencyPickerSheet`** — `.sheet` presented when user taps the foreign currency row:
- Search field (optional enhancement)
- `List` of `CurrencyPickerRow` items
- Selecting a row calls `viewModel.selectCurrency(_:)` and dismisses sheet

**`CurrencyPickerRow`** — one currency in the list:
- Flag emoji + currency code + display name
- Checkmark if currently selected

### Checklist
- [x] Tapping foreign currency side of `CurrencyInputRow` sets `showCurrencyPicker = true`
- [x] `CurrencyPickerSheet` displayed as `.sheet`
- [x] Lists all `viewModel.availableCurrencies`, sorted A→Z by ISO code
- [x] Selecting currency: updates ViewModel, dismisses sheet, triggers rate fetch
- [x] Currently-selected currency shows checkmark
- [x] `CurrencyPickerRow` shows flag + code (display name was originally rendered then removed — see post-Phase changes)
- [x] Accessibility identifiers: `"currencyPickerSheet"`, and each row `"currencyPickerRow.<code>"` (e.g. `currencyPickerRow.ARS`)

### UI Tests (`CurrencyXchangeCalcUITests`)
- [x] `testCurrencyPickerOpens` — tap `foreignCurrencyPicker`, sheet appears
- [x] `testCurrencyPickerDismisses` — swipe down closes sheet (covered by `testPickerDismissesViaCancel`)
- [x] `testCurrencySelection` — tap `currencyPickerRow.ARS`, picker closes, code in field updates to "ARS"

### Testing Command
```bash
xcodebuild -scheme CurrencyXchangeCalc test -only-testing:CurrencyXchangeCalcUITests
```

### Commit
```
feat: currency picker bottom sheet — list, selection, dismiss
```

### User Input Gate
- Demo the picker flow in simulator before moving to API wiring

---

## Phase 5 — Live API Integration & Error States

**Branch:** `feat/phase-5-api-integration`

### Spec
- Wire `LiveExchangeRateService` into ViewModel (injected at app startup via `CurrencyXchangeCalcApp`).
- Call `loadRates()` via `.task(id: viewModel.selectedCurrency.code) { await viewModel.loadRates() }`. SwiftUI owns the task lifecycle: changing the id cancels the old task and starts a new one; leaving the view cancels too.
- Currencies fallback: try `fetchCurrencies()`; on error/404 use `Currency.fallbackList` silently (no error surfaced).
- **Stale-response protection (single model — SwiftUI-driven):** `.task(id:)` cancels any prior in-flight call when the id changes. `loadRates()` stays a plain `async` function with no stored `Task` — after every `await`, it calls `try Task.checkCancellation()` (or checks `Task.isCancelled`) before mutating state, so a stale response that finishes after cancellation cannot overwrite newer state. Do **not** wrap the call in another `Task { }` inside the VM; that would create double-task orchestration and defeat SwiftUI's cancellation.
- Error UI: non-blocking banner with retry button.
- Loading UI: `ProgressView` during initial fetch.

### Checklist
- [x] `CurrencyXchangeCalcApp` creates `LiveExchangeRateService` and injects into ViewModel
- [x] `ExchangeCalculatorView` calls `viewModel.loadRates()` via `.task(id: …)` — composite id `"<code>#<retry>"` so Retry / refresh also re-fire through the same boundary
- [x] `fetchCurrencies` 404/unavailable → silently falls back to hardcoded list (no error shown)
- [x] Network error on `fetchRates` → `errorMessage` set, banner shown, retry button works
- [x] Rates refresh when currency is switched; prior in-flight task is cancelled by `.task(id:)` (stale-response protection)
- [x] `loadRates` checks cancellation after each `await` and before mutating state
- [x] Quoted-string `Decimal` decoding already in place from Phase 1 — verified end-to-end against live API response

### Unit Tests
- [x] `MockExchangeRateService` with configurable failure mode
- [x] `loadRates` with service throwing → `errorMessage != nil`, `isLoading == false`
- [x] `loadRates` success → `isLoading == false`, rates available
- [x] Deterministic cancellation: issue two `loadRates` back-to-back; only the later one commits state (`overlappingLoadRatesDoesNotCommitOlderResult`)
- [x] `fetchCurrencies` throwing `.unavailable` → `availableCurrencies` equals `Currency.fallbackList` and `errorMessage` is `nil`

### Testing Command
```bash
xcodebuild -scheme CurrencyXchangeCalc test
```

### Commit
```
feat: live API integration — URLSession, fallback currencies, error/retry UI
```

### User Input Gate
- Test with real device/sim network; confirm fallback list behavior

---

## Phase 6 — Polish, Edge Cases & Accessibility

**Branch:** `feat/phase-6-polish`

### Spec & Checklist
- [ ] ~~Input guard: max 2 decimal places enforced in `TextField`~~ — **deliberately removed** in the *Decimal source-of-truth refactor* (above) so user-typed precision survives unchanged. Display formatting now uses 4–8dp; underlying `Decimal` is exact.
- [ ] Input guard: no leading zeros (e.g. "007" → "7") — not implemented; input is accepted as-typed and parses cleanly via `Decimal(string:)`
- [x] Input guard: empty field clears the other field to `""` (gated on having a `currentRate` — see *Edge cases* in README)
- [x] Decimal separator localized (`.` vs `,`) using `Decimal.FormatStyle` / `Decimal.ParseStrategy` with `Locale.current` — no shared `NumberFormatter` (not `Sendable`, race-prone)
- [x] Numeric keyboard dismiss on tap outside (`.toolbar { ToolbarItemGroup(placement: .keyboard) }`) + Done toolbar button
- [ ] Zero input ("0") → other field shows "0.00" — currently shows `"0.0000"` because of the 4–8dp display change. Visual treatment is an open question (see README *KNOWN ISSUES*).
- [ ] Very large numbers don't overflow layout — current layout grows the field leftward via `fixedSize`; explicit overflow handling (truncation / scaling) is not in place.
- [x] Accessibility: all interactive elements have `accessibilityLabel`
- [x] `CurrencyInputRow` USDc side has `accessibilityLabel("USDc amount")`
- [x] `SwapButton` has `accessibilityLabel("Swap currencies")`
- [x] Figma colors confirmed: background `#F8F8F8`, card `#FFFFFF`, green `#22D081`, text `#2C2C2E`

### Unit Tests
- [x] `formatAmount` boundary tests (precision moved to 4–8dp; equivalent tests: `formatZeroPadsToFourDp`, `formatTruncatesAtMaxEightDp`)
- [x] `formatAmount(Decimal.zero)` → `"0.0000"` (was `"0.00"` before the precision change)
- [x] Parse `"007"` → `Decimal(7)` (`parseLeadingZerosAcceptedAsDecimalValue`)
- [x] Parse `"1.2.3"` rejected (returns `nil`) (`parseRejectsMultipleDecimalPoints`)
- [x] `es_ES` locale: parse `"1,23"` → `Decimal(string: "1.23")`; format → `"1,23"`
- [x] `en_US` locale: parse `"1.23"` → `Decimal(string: "1.23")`; format → `"1.23"`

### Commit
```
polish: input validation, number formatting, accessibility labels, UX edge cases
```

### User Input Gate
- Final visual review in simulator against Figma screenshots

---

## Phase 7 — Full Test Suite & API Documentation

**Branch:** `feat/phase-7-tests-docs`

### Spec & Checklist

**Unit tests — complete coverage targets:**
- [x] `ExchangeRate` — decoding, `currencyCode` extraction, edge cases (plus `publishedAt` parsing variants)
- [x] `Currency` — fallback list integrity (plus `symbol` rendering, narrow form, USD-stablecoin fallback)
- [x] `ExchangeCalculatorViewModel` — every externally-callable method covered
- [x] Number formatting utility — boundary cases (zero, tiny, negative, max precision, locale)

**UI tests — golden path:**
- [x] App launch → fields visible, rate shown
- [x] Type in USDc → foreign updates
- [x] Type in foreign → USDc updates
- [x] Tap swap → row positions flip; amounts stay attached to their currencies
- [x] Tap currency → picker opens → select currency → picker closes → code updated
- [x] Network error scenario (mock offline) → error banner appears
- [x] Rate-freshness label renders when timestamp present; refresh button actually re-runs the load (proven via `-UITEST_INCREMENT_RATE`)
- [x] Picker rows render alphabetically by ISO code

**Documentation:**
- [x] Every type, method, and non-trivial property in the app target (all `internal` — single-target app has no `public` surface) has a `///` doc comment covering Summary, Parameters, Returns, Throws where applicable
- [x] `README.md` updated: project overview, how to build & run, architecture summary, edge cases, beyond-spec improvements, and the AI + manual workflow notes
- [x] CLAUDE.md Architecture section updated to reflect actual file structure

**Final pre-submission checks:**
- [x] `xcodebuild ... test` passes with zero failures
- [x] Clean build from scratch passes
- [x] App runs on iPhone 17 simulator without modification (iPhone 16 is not available on the dev machine; iPhone 17 is the closest supported sim for iOS 26.4)
- [x] No hardcoded simulator UDIDs or developer team IDs in project
- [x] Git history is clean; no secrets in commits

### Commit
```
test: full unit and UI test suite
docs: internal API documentation, updated README and CLAUDE.md
```

### Git Tag & Submission
```bash
git tag v1.0.0
git push origin main --tags
```

---

## Files to Create/Modify (Summary)

| File | Action |
|------|--------|
| `CurrencyXchangeCalc/Models/Currency.swift` | Create |
| `CurrencyXchangeCalc/Models/ExchangeRate.swift` | Create |
| `CurrencyXchangeCalc/Models/ConversionDirection.swift` | Create |
| `CurrencyXchangeCalc/Services/ExchangeRateServiceProtocol.swift` | Create |
| `CurrencyXchangeCalc/Services/LiveExchangeRateService.swift` | Create |
| `CurrencyXchangeCalc/ViewModels/ExchangeCalculatorViewModel.swift` | Create |
| `CurrencyXchangeCalc/Views/ExchangeCalculatorView.swift` | Create |
| `CurrencyXchangeCalc/Views/Components/CurrencyInputRow.swift` | Create |
| `CurrencyXchangeCalc/Views/Components/SwapButton.swift` | Create |
| `CurrencyXchangeCalc/Views/CurrencyPicker/CurrencyPickerSheet.swift` | Create |
| `CurrencyXchangeCalc/Views/CurrencyPicker/CurrencyPickerRow.swift` | Create |
| `CurrencyXchangeCalc/ContentView.swift` | Modify (host ExchangeCalculatorView) |
| `CurrencyXchangeCalcTests/CurrencyXchangeCalcTests.swift` | Modify (expand) |
| `CurrencyXchangeCalcUITests/CurrencyXchangeCalcUITests.swift` | Modify (expand) |
| `README.md` | Modify |

---

## Verification Per Phase

Each phase ends with:
1. `xcodebuild -scheme CurrencyXchangeCalc build` → zero errors
2. `xcodebuild -scheme CurrencyXchangeCalc test` → zero failures
3. Manual simulator smoke-test of the feature just built
4. User sign-off before merging to `main`
