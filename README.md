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

## Spec clarifications

The recruiter confirmed (2026-04-24) that the currency list should reflect "whatever the endpoint returns," with a local fallback standing in until the endpoint ships. The fallback therefore mirrors the spec's example response exactly (`MXN`, `ARS`, `BRL`, `COP`) — the Figma shows EURc but that was treated as aspirational mock content, not a binding requirement. All other judgment-call items (currency symbol, loading/error states, summary precision, initial currency, keyboard dismiss) are documented with rationale in `Docs/ImplementationPlan.md` under *Spec Clarifications — Recruiter Q&A*.

### Display precision (4–8 fractional digits)

Amounts use `Decimal.FormatStyle.precision(.fractionLength(4...8))` rather than fixed 2dp. The reason and the alternative considered are documented in `Docs/ImplementationPlan.md` under *Round-trip precision edge case*. Short version: at 2dp, `1 MXN → "0.06" USDc → "1.04" MXN` round-trip drift looks like a calculator bug; at 4dp, `1 MXN → "0.0576" USDc → "0.9988" MXN` — the residual drift is just the bid/ask spread. Matches how XE and Google's currency widget format.

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

### KNOWN ISSUES

1) When numbers are deleted or 0 "0.0000" or something will show in black instead of greyed-out "0.00". What is the proper handling in this case? Should it be greyed out even though there's a zero number inputted?

### RESOLVED

2) ~~If two numbers are in both fields, tapping back and forth will change the numbers, possibly because behind the hood the numbers are being truncated and changing the values — the user can see a change but the actual stored values should be Decimal to preserve accuracy.~~ — Fixed by refactoring the VM to hold `Decimal` as the source of truth (`usdcDecimal` / `foreignDecimal`) and tracking `lastEditedSide` so rate refreshes re-derive only the non-edited side from the edited side's exact `Decimal`. The input clamp was removed; user-typed strings echo back as-is. See `Docs/ImplementationPlan.md` under *Decimal source-of-truth refactor* for the full story.
