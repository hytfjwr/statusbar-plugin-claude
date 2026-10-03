import Foundation

struct RateLimitWindow: Sendable {
    let usedPercentage: Double
    let resetsAt: Date?
}

/// A weekly window scoped to one model bucket (e.g. Fable), labelled by the server.
struct ModelScopedWindow: Sendable, Identifiable {
    let displayName: String
    let usedPercentage: Double
    let resetsAt: Date?

    var id: String { displayName }
}

struct RateLimitData: Sendable {
    /// nil when the source reported no such window, or its reset time has already passed —
    /// both mean "unknown", which must not read as 0%.
    let fiveHour: RateLimitWindow?
    let sevenDay: RateLimitWindow?
    let modelScoped: [ModelScopedWindow]
    /// When the source observed these numbers: `rate_limits.fetched_at` when present,
    /// otherwise the data file's modification time.
    let fetchedAt: Date

    static let empty = RateLimitData(
        fiveHour: nil,
        sevenDay: nil,
        modelScoped: [],
        fetchedAt: .distantPast
    )

    func isStale(threshold: Double) -> Bool {
        guard fetchedAt != .distantPast else { return false }
        return Date().timeIntervalSince(fetchedAt) > threshold
    }
}

enum RateLimitReader {
    static func read(from path: String) -> RateLimitData? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return parse(data, fallbackFetchedAt: modifiedAt ?? Date())
    }

    static func parse(_ data: Data, fallbackFetchedAt: Date, now: Date = Date()) -> RateLimitData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = json["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        return RateLimitData(
            fiveHour: parseWindow(rateLimits["five_hour"], now: now),
            sevenDay: parseWindow(rateLimits["seven_day"], now: now),
            modelScoped: parseModelScoped(rateLimits["model_scoped"], now: now),
            fetchedAt: parseDate(rateLimits["fetched_at"] as? String) ?? fallbackFetchedAt
        )
    }

    /// nil for a missing or null window, one without a usage figure, or one whose reset time
    /// has passed: the figure belongs to a window that is already over.
    private static func parseWindow(_ value: Any?, now: Date) -> RateLimitWindow? {
        guard let dict = value as? [String: Any],
              let usedPercentage = dict["used_percentage"] as? Double
        else {
            return nil
        }
        let resetsAt = parseDate(dict["resets_at"] as? String)
        if let resetsAt, resetsAt <= now {
            return nil
        }
        return RateLimitWindow(usedPercentage: usedPercentage, resetsAt: resetsAt)
    }

    /// Per-model weekly windows. Additive — absent for accounts the server emits none for.
    /// Entries without a usage figure, or whose reset time has passed, are dropped.
    private static func parseModelScoped(_ value: Any?, now: Date) -> [ModelScopedWindow] {
        guard let entries = value as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { entry in
            guard let displayName = entry["display_name"] as? String, !displayName.isEmpty,
                  let usedPercentage = entry["used_percentage"] as? Double
            else {
                return nil
            }
            let resetsAt = parseDate(entry["resets_at"] as? String)
            if let resetsAt, resetsAt <= now {
                return nil
            }
            return ModelScopedWindow(
                displayName: displayName,
                usedPercentage: usedPercentage,
                resetsAt: resetsAt
            )
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        // The usage endpoint emits microsecond precision, which ISO8601DateFormatter
        // rejects; drop the fractional part and retry.
        guard let dot = value.firstIndex(of: "."),
              let fractionEnd = value[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
        else {
            return nil
        }
        return formatter.date(from: value.replacingCharacters(in: dot..<fractionEnd, with: ""))
    }
}
