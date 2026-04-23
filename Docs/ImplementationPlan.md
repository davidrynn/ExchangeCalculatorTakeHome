# CurrencyXchangeCalc — Implementation Plan

## Context

This is a DolarApp mobile engineering code challenge: build a two-way USDc ↔ foreign-currency exchange calculator for iOS using SwiftUI. The app fetches live rates from `https://api.dolarapp.dev/v1/tickers`, handles a currencies list API that is not yet live (hardcoded fallback), and must match the Figma design. The submission must run in the simulator without modification.

Starting point: Xcode scaffold only — `ContentView.swift` and `CurrencyXchangeCalcApp.swift` contain placeholder code. Test targets exist (Swift Testing for unit tests, XCTest for UI tests) but are empty.

---

## Overall Checklist

- [x] Phase 0 — Architecture design & file scaffold
- [ ] Phase 1 — Data layer (models + service)
- [ ] Phase 2 — ViewModel (conversion logic)
- [ ] Phase 3 — Main calculator UI
- [ ] Phase 4 — Currency picker bottom sheet
- [ ] Phase 5 — Live API integration & error/loading states
- [ ] Phase 6 — Polish, edge cases & accessibility
- [ ] Phase 7 — Full test suite & public API documentation

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
- [ ] `Currency` model (`nonisolated`, `Sendable`) with `fallbackList` (MXN, ARS, BRL, COP + flag emojis)
- [ ] `ExchangeRate` Decodable model (`nonisolated`, `Sendable`, not Codable — we never encode); `currencyCode` computed from `book`
- [ ] **`ExchangeRate` custom `Decodable` / property wrapper** to decode quoted-string numbers in the API response (`"ask": "18.4105000000"`) into `Decimal` via `Decimal(string:)` — never route through `Double`, which loses precision at the 10-digit fraction
- [ ] `ConversionDirection` enum (`nonisolated`, `Sendable`)
- [ ] `ExchangeRateServiceProtocol: Sendable` with two `nonisolated async` methods
- [ ] `LiveExchangeRateService` (`nonisolated final class`) — `fetchRates` implementation
- [ ] `LiveExchangeRateService` — `fetchCurrencies` implementation (graceful fallback on 404)
- [ ] `ServiceError` enum (`nonisolated`, `Sendable`) with localized descriptions
- [ ] All types documented with `///` doc comments
- [ ] Verify no MainActor warnings when building with strict concurrency

### Unit Tests (`CurrencyXchangeCalcTests`)
- [ ] `ExchangeRateTests` — decodes valid JSON fixture correctly
- [ ] `ExchangeRateTests` — quoted-string numbers from the API (e.g. `"ask": "18.4105000000"`) decode to exact `Decimal` (no `Double` round-trip)
- [ ] `ExchangeRateTests` — `currencyCode` extraction from book string (`"usdc_mxn"` → `"MXN"`, handles uppercase)
- [ ] `ExchangeRateTests` — malformed JSON throws `DecodingError`, does not crash
- [ ] `CurrencyTests` — `fallbackList` contains exactly 4 currencies (MXN, ARS, BRL, COP)
- [ ] `CurrencyTests` — each currency has non-empty flag and displayName
- [ ] Concurrency smoke test: call `LiveExchangeRateService.fetchRates(...)` from a `nonisolated` test function — compiles and runs without MainActor hop warnings

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
- [ ] `@MainActor @Observable` ViewModel with all state properties
- [ ] `usdcAmountChanged` → updates `foreignAmount` using `rate.bid` (multiply)
- [ ] `foreignAmountChanged` → updates `usdcAmount` using `rate.ask` (divide)
- [ ] `swapCurrencies` — toggles `isSwapped` flag; values/currencies stay paired (rows move as atomic units)
- [ ] `selectCurrency` — updates selected currency, triggers in-memory re-conversion using the current mock rate
- [ ] Input guard: non-numeric / NaN / Inf ignored; empty string clears the other field
- [ ] Number formatting helper uses `Decimal.FormatStyle` (value type, inherently `Sendable`) — no shared `NumberFormatter`
- [ ] All math in `Decimal`; verify no `Double` leakage

### Unit Tests (`CurrencyXchangeCalcTests`)
Using `MockExchangeRateService` (pre-seeded with fixture rates). Tests are `@MainActor` so they can read VM state directly.
- [ ] `usdcAmountChanged("1")` → `foreignAmount` equals `bid` formatted to 2dp (regression guard for bid/ask direction)
- [ ] `foreignAmountChanged("18.40")` → `usdcAmount` equals `18.40 / ask` formatted (regression guard)
- [ ] `swapCurrencies` — toggles `isSwapped`; does NOT mutate amounts
- [ ] `selectCurrency` — `selectedCurrency` updates; re-conversion uses new rate
- [ ] Empty input → other field clears to `""`
- [ ] Non-numeric input ignored (no crash, no update)
- [ ] Locale parse: accepts `,` as decimal separator when `Locale.current` is comma-locale (fixture: `es_ES`)
- [ ] Large input (e.g. `1_000_000`) does not overflow `Decimal` arithmetic

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
- [ ] `ExchangeCalculatorView` layout matches Figma (VStack, spacing 16)
- [ ] `CurrencyInputRow` — USDc row (non-tappable currency side)
- [ ] `CurrencyInputRow` — foreign row (currency side tappable, opens sheet)
- [ ] `SwapButton` styled and functional
- [ ] Rate summary line below title
- [ ] Loading state: `ProgressView` overlay while `isLoading`
- [ ] Error banner when `errorMessage != nil` (dismissible)
- [ ] `ContentView` updated — injects `ExchangeCalculatorViewModel`
- [ ] Keyboard `.numberPad` on both fields
- [ ] Background color `#F8F8F8`
- [ ] Stable `accessibilityIdentifier` on every testable element — required for UI tests:
  - `"usdcAmountField"`, `"foreignAmountField"`, `"foreignCurrencyPicker"`, `"swapButton"`, `"rateSummaryLabel"`, `"errorBanner"`

### UI Tests (`CurrencyXchangeCalcUITests`)
- [ ] `testCalculatorLoads` — app launches, both input fields visible (query by `accessibilityIdentifier`)
- [ ] `testUSDCInputUpdatesForeignField` — type "1" in `usdcAmountField`, `foreignAmountField` shows non-zero value
- [ ] `testForeignInputUpdatesUSDCField` — type amount in `foreignAmountField`, `usdcAmountField` updates
- [ ] `testSwapButtonExists` — `swapButton` is hittable
- [ ] `testSwapButtonSwapsRowPositions` — tap swap, foreign row moves above USDc row (frame.minY inverts), amounts stay attached to their currencies

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
- [ ] Tapping foreign currency side of `CurrencyInputRow` sets `showCurrencyPicker = true`
- [ ] `CurrencyPickerSheet` displayed as `.sheet`
- [ ] Lists all `viewModel.availableCurrencies`
- [ ] Selecting currency: updates ViewModel, dismisses sheet, triggers rate fetch
- [ ] Currently-selected currency shows checkmark
- [ ] `CurrencyPickerRow` shows flag, code, display name
- [ ] Accessibility identifiers: `"currencyPickerSheet"`, and each row `"currencyPickerRow.<code>"` (e.g. `currencyPickerRow.ARS`)

### UI Tests (`CurrencyXchangeCalcUITests`)
- [ ] `testCurrencyPickerOpens` — tap `foreignCurrencyPicker`, sheet appears
- [ ] `testCurrencyPickerDismisses` — swipe down closes sheet
- [ ] `testCurrencySelection` — tap `currencyPickerRow.ARS`, picker closes, code in field updates to "ARS"

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
- [ ] `CurrencyXchangeCalcApp` creates `LiveExchangeRateService` and injects into ViewModel
- [ ] `ExchangeCalculatorView` calls `viewModel.loadRates()` via `.task(id: selectedCurrency.code)`
- [ ] `fetchCurrencies` 404/unavailable → silently falls back to hardcoded list (no error shown)
- [ ] Network error on `fetchRates` → `errorMessage` set, banner shown, retry button works
- [ ] Rates refresh when currency is switched; prior in-flight task is cancelled by `.task(id:)` (stale-response protection)
- [ ] `loadRates` checks cancellation after each `await` and before mutating state
- [ ] Quoted-string `Decimal` decoding already in place from Phase 1 — verified end-to-end against live API response

### Unit Tests
- [ ] `MockExchangeRateService` with configurable failure mode
- [ ] `loadRates` with service throwing → `errorMessage != nil`, `isLoading == false`
- [ ] `loadRates` success → `isLoading == false`, rates available
- [ ] Deterministic cancellation: issue two `loadRates` back-to-back; only the later one commits state
- [ ] `fetchCurrencies` throwing `.unavailable` → `availableCurrencies` equals `Currency.fallbackList` and `errorMessage` is `nil`

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
- [ ] Input guard: max 2 decimal places enforced in `TextField` (parse → `Decimal`, reject extras)
- [ ] Input guard: no leading zeros (e.g. "007" → "7")
- [ ] Input guard: empty field clears the other field to `""`
- [ ] Decimal separator localized (`.` vs `,`) using `Decimal.FormatStyle` / `Decimal.ParseStrategy` with `Locale.current` — no shared `NumberFormatter` (not `Sendable`, race-prone)
- [ ] Numeric keyboard dismiss on tap outside (`.toolbar { ToolbarItemGroup(placement: .keyboard) }`)
- [ ] Zero input ("0") → other field shows "0.00"
- [ ] Very large numbers don't overflow layout (truncation or compact formatting)
- [ ] Accessibility: all interactive elements have `accessibilityLabel`
- [ ] `CurrencyInputRow` USDc side has `accessibilityLabel("USDc amount")`
- [ ] `SwapButton` has `accessibilityLabel("Swap currencies")`
- [ ] Figma colors confirmed: background `#F8F8F8`, card `#FFFFFF`, green `#22D081`, text `#2C2C2E`

### Unit Tests
- [ ] `formatAmount(Decimal(string: "0.12345")!)` → `"0.12"`
- [ ] `formatAmount(Decimal.zero)` → `"0.00"`
- [ ] Parse `"007"` → `Decimal(7)`
- [ ] Parse `"1.2.3"` rejected (returns `nil`)
- [ ] `es_ES` locale: parse `"1,23"` → `Decimal(string: "1.23")`; format `Decimal(string: "1.23")` → `"1,23"`
- [ ] `en_US` locale: parse `"1.23"` → `Decimal(string: "1.23")`; format → `"1.23"`

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
- [ ] `ExchangeRate` — decoding, `currencyCode` extraction, edge cases
- [ ] `Currency` — fallback list integrity
- [ ] `ExchangeCalculatorViewModel` — every externally-callable method covered
- [ ] Number formatting utility — boundary cases

**UI tests — golden path:**
- [ ] App launch → fields visible, rate shown
- [ ] Type in USDc → foreign updates
- [ ] Type in foreign → USDc updates
- [ ] Tap swap → row positions flip; amounts stay attached to their currencies
- [ ] Tap currency → picker opens → select currency → picker closes → code updated
- [ ] Network error scenario (mock offline) → error banner appears

**Documentation:**
- [ ] Every type, method, and non-trivial property in the app target (all `internal` — single-target app has no `public` surface) has a `///` doc comment covering Summary, Parameters, Returns, Throws where applicable
- [ ] `README.md` updated: project overview, how to build & run, architecture summary
- [ ] CLAUDE.md Architecture section updated to reflect actual file structure

**Final pre-submission checks:**
- [ ] `xcodebuild ... test` passes with zero failures
- [ ] Clean build from scratch passes
- [ ] App runs on iPhone 17 simulator without modification (iPhone 16 is not available on the dev machine; iPhone 17 is the closest supported sim for iOS 26.4)
- [ ] No hardcoded simulator UDIDs or developer team IDs in project
- [ ] Git history is clean; no secrets in commits

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
