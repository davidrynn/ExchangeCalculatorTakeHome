# CurrencyXchangeCalc

A SwiftUI iOS currency exchange calculator. Converts between USDc and foreign currencies using live exchange rates from the dolarapp.dev API.

Built for the DolarApp Mobile Engineering Home Task.

## Requirements

- Xcode 26.4+
- iOS 26.4 simulator (iPhone 17 recommended on the dev machine)
- Swift 6.2 strict concurrency enabled

### Assumptions

- Currency codes follow ISO 4217.
- Rate timestamps are UTC, formatted as ISO 8601 / RFC 3339.
- The currency picker list is sorted alphabetically by ISO code (inferred from the Figma).
- The numeric keyboard is dismissed after the user finishes entering an amount (Done toolbar button or tap outside).

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
- Currency picker bottom sheet with flag, ISO code, and display name; rows sorted A→Z by ISO code. Picks from a fallback list (MXN, ARS, BRL, COP) that merges with the `/tickers-currencies` API when available.
- Rate freshness caption ("Updated X ago") under the rate summary, with a small refresh button next to it that re-fetches the current rate.
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
    │   ├── CircleIconStyle.swift     # circular ButtonStyle for the swap button
    │   ├── Color+Hex.swift           # Color(hex:) initializer
    │   └── CurrencyInputRow.swift
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

## Edge cases

- **Tiny round-trip values** — Output uses 4–8 fractional digits so `1 MXN ↔ 0.0576 USDc` round-trips cleanly instead of collapsing to `0.06`. See *Display precision* above.
- **Rate refresh mid-input** — The VM holds `Decimal` as source-of-truth (`usdcDecimal` / `foreignDecimal`) and tracks the last-edited side. A fresh rate re-derives only the *other* side from the user's exact `Decimal`, so values don't drift on every refresh.
- **Idempotent setters** — Field bindings no-op when the value is unchanged. SwiftUI re-fires setters on focus/rebind; without this guard, every focus tap would flip `lastEditedSide` and recompute through the bid/ask spread.
- **Empty field with no rate** — Clearing one field only wipes the other when a `currentRate` exists. Independent fields stay independent until a rate links them.
- **Currency switch** — Selecting a new foreign currency invalidates the stale rate and clears the foreign field; the USDc amount stays sticky so the user's intent survives.
- **Locale-aware input** — Accepts both `.` and the locale separator (e.g. `,` in `es_ES`). The strict parser rejects `"1.2.3"`, `"1e5"`, and `"1,000.00"`; `Decimal(string:)` would otherwise parse a prefix and silently truncate.
- **Quoted-string API decimals** — `"18.4105000000"` decodes via `Decimal(string:)`, never `Double`. Full precision preserved.
- **Case-insensitive currency match** — API code `EURC` resolves to fallback metadata stored as `EURc`, and vice versa, so display names and flags survive casing differences.
- **`/tickers-currencies` 404** — Falls back silently to the hardcoded list (`MXN`, `ARS`, `BRL`, `COP`). Transport errors fall back silently too; decoding errors *do* surface, since those indicate a real schema mismatch rather than a missing endpoint.
- **Cancelled or overlapping fetches** — `.task(id:)` cancels prior in-flight rate calls when the currency or retry token changes. `loadRates()` checks `Task.isCancelled` after every `await` before mutating state, and a monotonic `loadGeneration` token guards against direct callers (tests, future flows) that bypass `.task(id:)`. `CancellationError` never surfaces as a user-facing error.
- **Division-by-zero guard** — `recomputeUsdcFromForeign()` skips the divide when `rate.ask == 0`, so a malformed rate response can't crash the VM.

## Testing

88 tests total (70 unit + 17 UI + 1 launch):
- **Models** — JSON decoding, quoted-decimal precision, `currencyCode` extraction, fallback list integrity, `publishedAt` timestamp parsing (UTC contract, fractional-seconds variants, malformed input).
- **Service** — URL construction, HTTP status mapping, decoding error paths, fetchCurrencies fallback, concurrency smoke test (non-MainActor callable).
- **ViewModel** — bid/ask regression guards, swap semantics, selectCurrency invalidation, input parsing/clamping, locale handling, cancellation safety, overlap safety, error surfacing.
- **UI** — calculator loads, input reflection, swap row-position flip, picker open/select/dismiss + alphabetical sort, network error banner + Retry, rate freshness label, refresh button presence + actually-retriggers-load proof.

UI tests use launch arguments for deterministic scenarios:
- `-UITEST_DISABLE_NETWORK` — no-op service, empty state.
- `-UITEST_SEED_RATE` — fixed bid=10/ask=20 with a real timestamp for predictable math + freshness/refresh rendering.
- `-UITEST_FAIL_RATES` — service throws on fetchRates, error banner appears.
- `-UITEST_INCREMENT_RATE` — service returns a different rate on each call (bid/ask bump per call number) so the refresh-button test can assert the rate label *changed* after tap.

## Implementation notes

The codebase was built with a hybrid AI + manual workflow. Each phase started from a written plan, was implemented with agent assistance, then reviewed manually on the diff (often with a second-AI codex pass) before merging.

The AI side was constrained by two checked-in artifacts:
- `Docs/ImplementationPlan.md` — full phased scope, test gates, and recruiter Q&A. Every phase has a codex review documented in the git history.
- `Docs/Code_Challenge_Instructions.md` plus the recruiter Q&A inside the plan — the binding spec the AI worked against, separate from the Figma reference.

Two custom Claude Code skills support the workflow:
- `.claude/skills/codex/` — runs the Codex CLI for an independent second-AI review on uncommitted changes (model + reasoning effort selectable per run).
- `.claude/skills/button-style/` — scaffolds reusable SwiftUI `ButtonStyle` types (used to factor out `CircleIconStyle`).

Manual decisions and verification covered layout/UX iteration in the simulator, the Decimal source-of-truth refactor (triggered by observed drift in the running app), accessibility tap-target sizing, and final cleanup.

## Improvements

- **Rate freshness display** — Below the "1 USDc = X" rate summary the app shows "Updated X ago", parsed from each rate's `date` field via `ExchangeRate.publishedAt`. The parser handles the API's non-standard timestamp shape (9 fractional-second digits, no timezone offset) and treats it as UTC per the documented contract. Hidden when the timestamp is empty or unparseable so users never see a guess.

- **Manual rate refresh** — A small refresh button beside the "Updated X ago" caption lets the user pull a fresh rate without changing currency or relying on the error-banner Retry. Implemented by reusing the `retryToken` already wired into the rate-load `.task(id:)` key, so the new affordance shares the same structured-cancellation guarantees as every other rate-load entry point.

## Known limitations

- **Dynamic Type at the largest accessibility sizes.** The screen now scrolls (top-level `ScrollView`) and the title uses semantic `.largeTitle` so it scales with Dynamic Type. **Not yet handled:** the input rows are still single-line — at the largest accessibility text sizes a long value's symbol + digits cluster can grow wider than the row's available trailing region and clip at the edge. Full fix would change the `TextField` to `axis: .vertical` with `.lineLimit(1...3)` so the cluster wraps, relax `.frame(height: 66)` to a `minHeight`, and add `.layoutPriority(1)` to the currency-side label so it never gets compressed; estimated 2–3 hours including UI-test layout updates (the swap test asserts row Y positions, which would change once rows can grow). Not blocking for the default-size experience or for typical accessibility sizes.

- **Very long input values overflow the row.** Same root cause: the cluster (`.fixedSize`'d for the symbol-glued layout) grows leftward as the user types and at extreme lengths (≈ 14+ digits at default Dynamic Type) eventually bumps the currency-side label or clips. Acceptable for typical currency amounts; a `minimumScaleFactor(0.6)` + capped `.frame(maxWidth:)` strategy was tried and rejected because it scaled too eagerly at default sizes. The honest fix is the same multi-line input above.

