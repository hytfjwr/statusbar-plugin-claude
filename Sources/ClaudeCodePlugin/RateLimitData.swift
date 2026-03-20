import Foundation

struct RateLimitWindow: Sendable {
    let usedPercentage: Double
    let resetsAt: Date?
}

struct RateLimitData: Sendable {
    let fiveHour: RateLimitWindow
    let sevenDay: RateLimitWindow
    let fetchedAt: Date

    static let empty = RateLimitData(
        fiveHour: RateLimitWindow(usedPercentage: 0, resetsAt: nil),
        sevenDay: RateLimitWindow(usedPercentage: 0, resetsAt: nil),
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

        return RateLimitData(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            fetchedAt: Date()
        )
    }

    private static func parseWindow(_ value: Any?) -> RateLimitWindow {
        guard let dict = value as? [String: Any] else {
            return RateLimitWindow(usedPercentage: 0, resetsAt: nil)
        }

        let percentage = (dict["used_percentage"] as? Double) ?? 0
        var resetDate: Date?
        if let resetStr = dict["resets_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetDate = formatter.date(from: resetStr)
            if resetDate == nil {
                formatter.formatOptions = [.withInternetDateTime]
                resetDate = formatter.date(from: resetStr)
            }
        }

        return RateLimitWindow(usedPercentage: percentage, resetsAt: resetDate)
    }
}
