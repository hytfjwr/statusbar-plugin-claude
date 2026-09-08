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
    let fiveHour: RateLimitWindow
    let sevenDay: RateLimitWindow
    let modelScoped: [ModelScopedWindow]
    let fetchedAt: Date

    static let empty = RateLimitData(
        fiveHour: RateLimitWindow(usedPercentage: 0, resetsAt: nil),
        sevenDay: RateLimitWindow(usedPercentage: 0, resetsAt: nil),
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
        return parse(data)
    }

    static func parse(_ data: Data) -> RateLimitData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = json["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        let fiveHour = parseWindow(rateLimits["five_hour"])
        let sevenDay = parseWindow(rateLimits["seven_day"])
        let modelScoped = parseModelScoped(rateLimits["model_scoped"])

        return RateLimitData(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            modelScoped: modelScoped,
            fetchedAt: Date()
        )
    }

    private static func parseWindow(_ value: Any?) -> RateLimitWindow {
        guard let dict = value as? [String: Any] else {
            return RateLimitWindow(usedPercentage: 0, resetsAt: nil)
        }

        return RateLimitWindow(
            usedPercentage: (dict["used_percentage"] as? Double) ?? 0,
            resetsAt: parseDate(dict["resets_at"] as? String)
        )
    }

    /// Per-model weekly windows. Additive — absent for accounts the server emits none for.
    private static func parseModelScoped(_ value: Any?) -> [ModelScopedWindow] {
        guard let entries = value as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { entry in
            guard let displayName = entry["display_name"] as? String, !displayName.isEmpty else {
                return nil
            }
            return ModelScopedWindow(
                displayName: displayName,
                usedPercentage: (entry["used_percentage"] as? Double) ?? 0,
                resetsAt: parseDate(entry["resets_at"] as? String)
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
