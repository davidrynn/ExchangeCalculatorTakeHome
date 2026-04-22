# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A SwiftUI iOS currency exchange calculator app (code challenge). Converts between USDc and other currencies using live exchange rates from `https://api.dolarapp.dev/v1/tickers`.

- iOS deployment target: 26.4
- No external dependencies (pure Swift/SwiftUI/Foundation)
- Uses Swift Testing for unit tests, XCTest for UI tests
- Use native Apple SwiftUI UI frameworks where possible

## Build & Test Commands

Use the `xcodebuildmcp` skill for all build/run/test operations. Alternatively:

```bash
# Build
xcodebuild -project CurrencyXchangeCalc.xcodeproj -scheme CurrencyXchangeCalc -configuration Debug build

# Run all tests
xcodebuild -project CurrencyXchangeCalc.xcodeproj -scheme CurrencyXchangeCalc test

# Run only unit tests
xcodebuild -project CurrencyXchangeCalc.xcodeproj -scheme CurrencyXchangeCalc test -only-testing:CurrencyXchangeCalcTests

# Run only UI tests
xcodebuild -project CurrencyXchangeCalc.xcodeproj -scheme CurrencyXchangeCalc test -only-testing:CurrencyXchangeCalcUITests
```

## Architecture

MVVM + protocol-based service layer. Full design and phase plan lives in `Docs/ImplementationPlan.md`.

- **`CurrencyXchangeCalcApp.swift`** — `@main` entry point
- **`ContentView.swift`** — Root container (hosts `ExchangeCalculatorView`)
- **`Models/`** — `Currency`, `ExchangeRate`, `ConversionDirection` (all `nonisolated`, `Sendable`)
- **`Services/`** — `ExchangeRateServiceProtocol` (`Sendable`, `nonisolated` methods) + `LiveExchangeRateService` (`nonisolated final class`)
- **`ViewModels/ExchangeCalculatorViewModel`** — `@MainActor @Observable`
- **`Views/`** — `ExchangeCalculatorView`, `CurrencyInputRow`, `SwapButton`, `CurrencyPickerSheet`, `CurrencyPickerRow`

### Concurrency

Xcode project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Every unannotated type is implicitly `@MainActor`. When adding new code:
- Value-type data models: `nonisolated` + `Sendable`
- Network/service types: `nonisolated final class … Sendable`
- UI-owning types (view models): explicit `@MainActor`
- Network work must not pin to main — use `nonisolated async` on protocol requirements
- SwiftUI cancellation is driven by `.task(id:)`; do NOT wrap VM async calls in another `Task { }`

### Core Features to Implement

1. **Two-way currency input** — USDc field + selected-currency field; editing either auto-calculates the other
2. **Currency selection bottom sheet** — tapping the non-USDc field opens a sheet to pick a currency
3. **Swap button** — swaps the two currency positions
4. **Exchange rate API** — `GET https://api.dolarapp.dev/v1/tickers?currencies=MXN,ARS,...`
   - Response: array of `{ ask, bid, book, date }` where `book` is `"usdc_mxn"` etc.
   - Book format `usdc_xxx` — USDc is base, foreign is quote.
   - **USDc → foreign:** multiply by `bid` (user sells USDc, receives bid in foreign)
   - **Foreign → USDc:** divide by `ask` (user buys USDc, pays ask in foreign)
   - Decode quoted-string decimals (e.g. `"18.4105000000"`) into `Decimal` via `Decimal(string:)` — never `Double`.
5. **Currency list API** — `GET https://api.dolarapp.dev/v1/tickers-currencies` returns `["MXN","ARS","BRL","COP"]`
   - **This API is not yet live.** The app must work without it — hardcode a fallback currency list.

## Large Reference Files

  - `Docs/DesignCSS.css` — Raw 13k-line Figma CSS export. Do NOT read unless explicitly asked. Use grep for
  specific values instead.  

### Figma Reference

Design: `https://www.figma.com/design/xX7gSbMEIzybCrG9Wwk9Wx/-EXT--Exchange-Home-Task` (password: `DolarApp!123`)
