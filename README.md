# CurrencyXchangeCalc

A SwiftUI iOS currency exchange calculator. Converts between USDc and foreign currencies using live exchange rates from the dolarapp.dev API.

Built for the DolarApp Mobile Engineering Home Task.

## Requirements

- Xcode 26.4+
- iOS 26.4 simulator (iPhone 17 recommended on the dev machine)
- Swift 6.2 strict concurrency enabled

## Running the app

```bash
# Build and launch on the default iPhone 17 simulator
xcodebuild -project CurrencyXchangeCalc.xcodeproj \
           -scheme CurrencyXchangeCalc \
           -configuration Debug \
           -destination 'platform=iOS Simulator,name=iPhone 17' \
           build
```

Or open the project in Xcode and `⌘R`. No additional configuration, signing, or credentials are needed — the app calls a public endpoint.

## Running the tests

```bash
# Full test suite (unit + UI)
xcodebuild -project CurrencyXchangeCalc.xcodeproj \
           -scheme CurrencyXchangeCalc \
           -destination 'platform=iOS Simulator,name=iPhone 17' \
           test

# Unit only
xcodebuild -project CurrencyXchangeCalc.xcodeproj \
           -scheme CurrencyXchangeCalc \
           -destination 'platform=iOS Simulator,name=iPhone 17' \
           test -only-testing:CurrencyXchangeCalcTests

# UI only
xcodebuild -project CurrencyXchangeCalc.xcodeproj \
           -scheme CurrencyXchangeCalc \
           -destination 'platform=iOS Simulator,name=iPhone 17' \
           test -only-testing:CurrencyXchangeCalcUITests
```

## Features

- Two-way currency input: editing either field auto-calculates the other using the live bid (USDc → foreign) / ask (foreign → USDc) rate.
- Swap button flips the two rows' layout positions (values stay attached to their currencies).
- Currency picker bottom sheet with flag, ISO code, and display name; picks from a fallback list (MXN, ARS, BRL, COP) that merges with the `/tickers-currencies` API when available.
- Loading indicator + dismissible error banner with retry.
- Locale-aware input (accepts `.` or `,` as decimal separator) and output (formatted per `Locale.current`).
- Keyboard dismiss via `Done` toolbar button or tap outside.

## Architecture

MVVM with a protocol-based service layer.

```
CurrencyXchangeCalc/
├── CurrencyXchangeCalcApp.swift   # composition root, injects LiveExchangeRateService
├── ContentView.swift              # root container
├── Models/                        # nonisolated, Sendable value types
│   ├── Currency.swift
│   ├── ExchangeRate.swift
│   └── ConversionDirection.swift
├── Services/
│   ├── ExchangeRateServiceProtocol.swift   # Sendable, nonisolated async methods
│   └── LiveExchangeRateService.swift       # URLSession-backed
├── ViewModels/
│   └── ExchangeCalculatorViewModel.swift   # @MainActor @Observable
└── Views/
    ├── ExchangeCalculatorView.swift
    ├── Components/
    │   ├── CurrencyInputRow.swift
    │   └── SwapButton.swift
    └── CurrencyPicker/
        ├── CurrencyPickerSheet.swift
        └── CurrencyPickerRow.swift
```

### Concurrency

The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every unannotated type is implicitly `@MainActor`. To keep network I/O off the main thread, the service layer is explicitly `nonisolated`:

- Models are `nonisolated` + `Sendable` value types.
- `ExchangeRateServiceProtocol` is `Sendable` with `nonisolated async` requirements.
- `LiveExchangeRateService` is a `nonisolated final class` — URLSession work runs off main.
- `ExchangeCalculatorViewModel` is explicit `@MainActor @Observable`.
- `.task(id: "<code>#<retry>")` is the sole rate-load cancellation boundary: changing the currency or tapping Retry bumps the id, and SwiftUI cancels the old task and starts a new one. No unstructured `Task { }` wrappers.

### Bid/ask convention

API book `usdc_xxx` means USDc is base, foreign is quote.
- **USDc → foreign:** multiply by `bid` (user sells USDc, receives bid in foreign).
- **Foreign → USDc:** divide by `ask` (user buys USDc, pays ask in foreign).
- Quoted-string decimals (e.g. `"18.4105000000"`) decode directly to `Decimal` via `Decimal(string:)` — never through `Double`.

## APIs

- `GET https://api.dolarapp.dev/v1/tickers?currencies=MXN,ARS` — live rates (used).
- `GET https://api.dolarapp.dev/v1/tickers-currencies` — currency list (not yet deployed; the app falls back silently to a hardcoded list when it 404s).

## Testing

66 tests total (53 unit + 10 UI + 3 launch):
- **Models** — JSON decoding, quoted-decimal precision, `currencyCode` extraction, fallback list integrity.
- **Service** — URL construction, HTTP status mapping, decoding error paths, fetchCurrencies fallback, concurrency smoke test (non-MainActor callable).
- **ViewModel** — bid/ask regression guards, swap semantics, selectCurrency invalidation, input parsing/clamping, locale handling, cancellation safety, overlap safety, error surfacing.
- **UI** — calculator loads, input reflection, swap row-position flip, picker open/select/dismiss, network error banner.

UI tests use launch arguments for deterministic scenarios:
- `-UITEST_DISABLE_NETWORK` — no-op service, empty state.
- `-UITEST_SEED_RATE` — fixed bid=10/ask=20 for predictable math.
- `-UITEST_FAIL_RATES` — service throws on fetchRates, error banner appears.

## Implementation notes

The full phased implementation plan and per-phase codex code reviews live in `Docs/ImplementationPlan.md`. Every phase was reviewed by a second AI (codex) before merge; findings and fixes are in the git history.
