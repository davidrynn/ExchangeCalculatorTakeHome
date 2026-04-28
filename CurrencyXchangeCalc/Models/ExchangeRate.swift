import Foundation

/// Raw ticker from `GET /v1/tickers`.
///
/// `Sendable` so decoded values cross from the nonisolated service into
/// the `@MainActor` view model without boundary warnings.
///
/// **Quoted-decimal decoding:** The API sends numbers as JSON strings
/// (e.g. `"ask": "18.4105000000"`). A custom `Decodable` init parses them
/// via `Decimal(string:)` to avoid `Double` precision loss on 10-digit
/// fractional parts.
///
/// **Bid/ask semantics:**
/// - `ask` — price to BUY USDc (pay `ask` units of foreign per 1 USDc)
/// - `bid` — price to SELL USDc (receive `bid` units of foreign per 1 USDc)
nonisolated struct ExchangeRate: Decodable, Equatable, Sendable {
    let ask: Decimal
    let bid: Decimal
    let book: String
    let date: String

    /// Foreign currency code extracted from `book`.
    ///
    /// Book format is `"usdc_xxx"` — returns `xxx` uppercased
    /// (e.g. `"usdc_mxn"` → `"MXN"`). Returns an empty string if the book
    /// does not start with `"usdc_"`.
    var currencyCode: String {
        let prefix = "usdc_"
        guard book.lowercased().hasPrefix(prefix) else { return "" }
        return String(book.dropFirst(prefix.count)).uppercased()
    }

    /// Parsed publish time, or `nil` when the API sent an empty or
    /// unparseable timestamp. The API returns timestamps like
    /// `"2025-10-20T20:14:57.361483956"` — 9 fractional-second digits
    /// and no timezone offset — which `ISO8601DateFormatter` rejects;
    /// we strip the sub-second portion and parse as UTC per the
    /// `README.md` *Assumptions* contract.
    var publishedAt: Date? {
        guard !date.isEmpty else { return nil }
        let truncated = date.split(separator: ".", maxSplits: 1).first.map(String.init) ?? date
        return Self.timestampFormatter.date(from: truncated)
    }

    /// Configured once and reused — `DateFormatter` init is expensive,
    /// and a fixed-format formatter is thread-safe in practice.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private enum CodingKeys: String, CodingKey {
        case ask, bid, book, date
    }

    init(ask: Decimal, bid: Decimal, book: String, date: String) {
        self.ask = ask
        self.bid = bid
        self.book = book
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.book = try container.decode(String.self, forKey: .book)
        self.date = try container.decode(String.self, forKey: .date)
        self.ask = try Self.decodeDecimal(container: container, forKey: .ask)
        self.bid = try Self.decodeDecimal(container: container, forKey: .bid)
    }

    private static func decodeDecimal(
        container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Decimal {
        let stringValue = try container.decode(String.self, forKey: key)
        guard let decimal = Decimal(string: stringValue, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Expected Decimal-parseable string, got \(stringValue)"
            )
        }
        return decimal
    }
}
