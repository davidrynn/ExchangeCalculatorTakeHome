# CurrencyXchangeCalc — Implementation Plan

## Context

This is a DolarApp mobile engineering code challenge: build a two-way USDc ↔ foreign-currency exchange calculator for iOS using SwiftUI. The app fetches live rates from `https://api.dolarapp.dev/v1/tickers`, handles a currencies list API that is not yet live (hardcoded fallback), and must match the Figma design. The submission must run in the simulator without modification.

Starting point: Xcode scaffold only — `ContentView.swift` and `CurrencyXchangeCalcApp.swift` contain placeholder code. Test targets exist (Swift Testing for unit tests, XCTest for UI tests) but are empty.

---

## Overall Checklist

- [ ] Phase 0 — Architecture design & file scaffold
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
- Open a self-review PR before merging; all tests must pass.
- Merge to `main` only after: ✅ build passes, ✅ tests pass, ✅ manual simulator smoke-test done.
- Tag `v1.0.0` on `main` before submission.
- Commit messages: `feat:`, `fix:`, `test:`, `docs:`, `polish:` prefixes.

---

## Architecture

**Pattern:** MVVM + protocol-based service layer

```
CurrencyXchangeCalc/
├── App/
│   └── CurrencyXchangeCalcApp.swift          # @main entry point (existing)
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
    ├── ContentView.swift                      # Root container (existing, to update)
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
- `bid` rate used when USDc → foreign (selling USDc); `ask` when foreign → USDc (buying USDc)
- Currency list hardcoded to `["MXN", "ARS", "BRL", "COP"]` with runtime merge if API ever responds
- No 3rd-party dependencies

---

## Phase 0 — Architecture & File Scaffold

**Branch:** `feat/phase-0-architecture`

### Spec
- Create all empty Swift files in the folder structure above
- Add them to the Xcode project target
- Write stub types with `// TODO:` markers so the project still compiles

### Checklist
- [ ] Create `Models/Currency.swift` stub
- [ ] Create `Models/ExchangeRate.swift` stub
- [ ] Create `Models/ConversionDirection.swift` stub
- [ ] Create `Services/ExchangeRateServiceProtocol.swift` stub
- [ ] Create `Services/LiveExchangeRateService.swift` stub
- [ ] Create `ViewModels/ExchangeCalculatorViewModel.swift` stub
- [ ] Create `Views/ExchangeCalculatorView.swift` stub
- [ ] Create `Views/Components/CurrencyInputRow.swift` stub
- [ ] Create `Views/Components/SwapButton.swift` stub
- [ ] Create `Views/CurrencyPicker/CurrencyPickerSheet.swift` stub
- [ ] Create `Views/CurrencyPicker/CurrencyPickerRow.swift` stub
- [ ] Add all files to Xcode target membership
- [ ] Project builds with zero errors

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

**`Currency`**
```swift
/// A supported currency for exchange against USDc.
public struct Currency: Identifiable, Hashable {
    public let code: String          // e.g. "MXN"
    public let flagEmoji: String     // e.g. "🇲🇽"
    public let displayName: String   // e.g. "Mexican Peso"
    public var id: String { code }

    /// Hardcoded fallback list used when the currencies API is unavailable.
    public static let fallbackList: [Currency]
}
```

**`ExchangeRate`**
```swift
/// Raw ticker from GET /v1/tickers.
public struct ExchangeRate: Codable, Equatable {
    public let ask: Decimal    // price to sell USDc (buy foreign)
    public let bid: Decimal    // price to buy USDc (sell foreign)
    public let book: String    // e.g. "usdc_mxn"
    public let date: String

    /// Extracts the foreign currency code from book (e.g. "usdc_mxn" → "MXN").
    public var currencyCode: String
}
```

**`ConversionDirection`**
```swift
public enum ConversionDirection {
    case usdc      // user is typing in the USDc field
    case foreign   // user is typing in the foreign currency field
}
```

**`ExchangeRateServiceProtocol`**
```swift
public protocol ExchangeRateServiceProtocol {
    /// Fetches current tickers for the given currency codes.
    func fetchRates(for currencies: [String]) async throws -> [ExchangeRate]
    /// Fetches available currency codes; throws if API is unavailable.
    func fetchCurrencies() async throws -> [String]
}
```

**`LiveExchangeRateService`**
- Implements `ExchangeRateServiceProtocol`
- Uses `URLSession.shared` with `async/await`
- Decodes JSON with `JSONDecoder`
- Throws typed errors: `ServiceError.networkError`, `.decodingError`, `.unavailable`

### Checklist
- [ ] `Currency` model with `fallbackList: [Currency]` (MXN, ARS, BRL, COP + flag emojis)
- [ ] `ExchangeRate` Codable model; `currencyCode` computed from `book`
- [ ] `ConversionDirection` enum
- [ ] `ExchangeRateServiceProtocol` with two async methods
- [ ] `LiveExchangeRateService` — `fetchRates` implementation
- [ ] `LiveExchangeRateService` — `fetchCurrencies` implementation (graceful fallback on 404)
- [ ] `ServiceError` enum with localized descriptions
- [ ] All public types documented with `///` doc comments

### Unit Tests (`CurrencyXchangeCalcTests`)
- [ ] `ExchangeRateTests` — decodes valid JSON fixture correctly
- [ ] `ExchangeRateTests` — `currencyCode` extraction from book string
- [ ] `ExchangeRateTests` — handles malformed JSON without crash
- [ ] `CurrencyTests` — `fallbackList` contains exactly 4 currencies
- [ ] `CurrencyTests` — each currency has non-empty flag and displayName

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
@Observable
public final class ExchangeCalculatorViewModel {
    // MARK: - Published State
    public var usdcAmount: String
    public var foreignAmount: String
    public var selectedCurrency: Currency
    public var availableCurrencies: [Currency]
    public var isLoading: Bool
    public var errorMessage: String?

    // MARK: - Public Interface
    /// Called when the user edits the USDc field; recalculates foreignAmount.
    public func usdcAmountChanged(_ newValue: String)

    /// Called when the user edits the foreign field; recalculates usdcAmount.
    public func foreignAmountChanged(_ newValue: String)

    /// Swaps USDc ↔ selected currency positions (swaps displayed amounts).
    public func swapCurrencies()

    /// Sets selectedCurrency and re-fetches rates.
    public func selectCurrency(_ currency: Currency)

    /// Initiates API fetch; falls back to hardcoded currencies on error.
    public func loadRates() async
}
```

**Conversion math:**
- USDc → foreign: `foreignAmount = usdcAmount * rate.ask`
- Foreign → USDc: `usdcAmount = foreignAmount / rate.bid`
- Format output to 2 decimal places, locale-aware

### Checklist
- [ ] `@Observable` ViewModel with all state properties
- [ ] `usdcAmountChanged` → updates `foreignAmount` using `ask`
- [ ] `foreignAmountChanged` → updates `usdcAmount` using `bid`
- [ ] `swapCurrencies` — swaps displayed amounts and positions flag
- [ ] `selectCurrency` — updates selected currency, triggers `loadRates`
- [ ] `loadRates` — fetches rates, sets `isLoading`, catches errors to `errorMessage`
- [ ] Input guard: ignores changes that produce NaN/Inf
- [ ] Number formatting utility (2 dp, locale decimal separator)

### Unit Tests (`CurrencyXchangeCalcTests`)
Using `MockExchangeRateService` (pre-seeded with fixture rates):
- [ ] `usdcAmountChanged("1")` → `foreignAmount` equals `ask` formatted to 2dp
- [ ] `foreignAmountChanged("18.40")` → `usdcAmount` equals `18.40 / bid` formatted
- [ ] `swapCurrencies` — amounts swap correctly
- [ ] `selectCurrency` — `selectedCurrency` updates, `loadRates` called
- [ ] Empty input → other field clears to `""`
- [ ] Non-numeric input ignored (no crash, no update)
- [ ] `loadRates` error → `errorMessage` is non-nil, `availableCurrencies` falls back

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

### UI Tests (`CurrencyXchangeCalcUITests`)
- [ ] `testCalculatorLoads` — app launches, two input fields visible
- [ ] `testUSDCInputUpdatesForeinField` — type "1" in USDc field, foreign field shows non-zero value
- [ ] `testForeignInputUpdatesUSDCField` — type amount in foreign field, USDc field updates
- [ ] `testSwapButtonExists` — swap button is hittable
- [ ] `testSwapButtonSwapsValues` — tap swap, field positions invert

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

### UI Tests (`CurrencyXchangeCalcUITests`)
- [ ] `testCurrencyPickerOpens` — tap foreign currency label, sheet appears
- [ ] `testCurrencyPickerDismisses` — swipe down closes sheet
- [ ] `testCurrencySelection` — select a different currency, picker closes, code in field updates

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
- Wire `LiveExchangeRateService` into ViewModel (injected at app startup via `ContentView`)
- Call `loadRates()` on `.task` modifier when view appears
- Currencies fallback: try `fetchCurrencies()`; on error/404 use `Currency.fallbackList`
- Error UI: non-blocking banner with retry button
- Loading UI: skeleton or `ProgressView` during initial fetch

### Checklist
- [ ] `CurrencyXchangeCalcApp` creates `LiveExchangeRateService` and injects into ViewModel
- [ ] `ExchangeCalculatorView` calls `viewModel.loadRates()` via `.task`
- [ ] `fetchCurrencies` 404/unavailable → silently falls back to hardcoded list (no error shown)
- [ ] Network error on `fetchRates` → `errorMessage` set, banner shown, retry button works
- [ ] Rates refresh when currency is switched (`selectCurrency` triggers `loadRates`)
- [ ] Cancels in-flight task on view disappear (`.task` cancellation is automatic)

### Unit Tests
- [ ] `MockExchangeRateService` with configurable failure mode
- [ ] `loadRates` with service throwing → `errorMessage != nil`, `isLoading == false`
- [ ] `loadRates` success → `isLoading == false`, rates available

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
- [ ] Input guard: max 2 decimal places enforced in `TextField`
- [ ] Input guard: no leading zeros (e.g. "007" → "7")
- [ ] Input guard: empty field clears the other field to `""`
- [ ] Decimal separator localized (`.` vs `,`) using `Locale.current`
- [ ] Numeric keyboard dismiss on tap outside (`.toolbar { ToolbarItemGroup(placement: .keyboard) }`)
- [ ] Zero input ("0") → other field shows "0.00"
- [ ] Very large numbers don't overflow layout (truncation or compact formatting)
- [ ] Accessibility: all interactive elements have `accessibilityLabel`
- [ ] `CurrencyInputRow` USDc side has `accessibilityLabel("USDc amount")`
- [ ] `SwapButton` has `accessibilityLabel("Swap currencies")`
- [ ] Figma colors confirmed: background `#F8F8F8`, card `#FFFFFF`, green `#22D081`, text `#2C2C2E`

### Unit Tests
- [ ] `formatAmount("0.12345")` → `"0.12"`
- [ ] `formatAmount("")` → `""`
- [ ] `formatAmount("007")` → `"7"`
- [ ] `formatAmount("1.2.3")` → ignores second decimal point

### Commit
```
polish: input validation, number formatting, accessibility labels, UX edge cases
```

### User Input Gate
- Final visual review in simulator against Figma screenshots

---

## Phase 7 — Full Test Suite & Public API Documentation

**Branch:** `feat/phase-7-tests-docs`

### Spec & Checklist

**Unit tests — complete coverage targets:**
- [ ] `ExchangeRate` — decoding, `currencyCode` extraction, edge cases
- [ ] `Currency` — fallback list integrity
- [ ] `ExchangeCalculatorViewModel` — all public methods covered
- [ ] Number formatting utility — boundary cases

**UI tests — golden path:**
- [ ] App launch → fields visible, rate shown
- [ ] Type in USDc → foreign updates
- [ ] Type in foreign → USDc updates
- [ ] Tap swap → values and positions exchange
- [ ] Tap currency → picker opens → select currency → picker closes → code updated
- [ ] Network error scenario (mock offline) → error banner appears

**Documentation:**
- [ ] All `public` types and functions have `///` doc comment (`Summary`, `Parameters`, `Returns`, `Throws`)
- [ ] `README.md` updated: project overview, how to build & run, architecture summary
- [ ] CLAUDE.md Architecture section updated to reflect actual file structure

**Final pre-submission checks:**
- [ ] `xcodebuild ... test` passes with zero failures
- [ ] Clean build from scratch passes
- [ ] App runs on iPhone 16 simulator without modification
- [ ] No hardcoded simulator UDIDs or developer team IDs in project
- [ ] Git history is clean; no secrets in commits

### Commit
```
test: full unit and UI test suite
docs: public API documentation, updated README and CLAUDE.md
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
