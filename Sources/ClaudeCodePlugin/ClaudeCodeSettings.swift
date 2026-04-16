import Foundation
import StatusBarKit
import SwiftUI

@MainActor
@Observable
final class ClaudeCodeSettings: WidgetConfigProvider {
    static let shared = ClaudeCodeSettings()

    let configID = "claude-code"
    private var suppressWrite = false

    var warningThreshold: Double {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var criticalThreshold: Double {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var warningColorHex: String {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var criticalColorHex: String {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var dataFilePath: String {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var updateInterval: Double {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var staleThreshold: Double {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var toastOnWarning: Bool {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    var toastOnCritical: Bool {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    /// Bar display mode: "icon", "5h", "7d", or "both"
    var barDisplayMode: String {
        didSet { if !suppressWrite { WidgetConfigRegistry.shared.notifySettingsChanged() } }
    }

    private init() {
        let cfg = WidgetConfigRegistry.shared.values(for: "claude-code")
        warningThreshold = cfg?["warningThreshold"]?.doubleValue ?? 50.0
        criticalThreshold = cfg?["criticalThreshold"]?.doubleValue ?? 80.0
        warningColorHex = cfg?["warningColorHex"]?.stringValue ?? "FFD60A"
        criticalColorHex = cfg?["criticalColorHex"]?.stringValue ?? "FF453A"
        dataFilePath = cfg?["dataFilePath"]?.stringValue ?? "~/.claude/rate_limits.json"
        updateInterval = cfg?["updateInterval"]?.doubleValue ?? 10.0
        staleThreshold = cfg?["staleThreshold"]?.doubleValue ?? 120.0
        toastOnWarning = cfg?["toastOnWarning"]?.boolValue ?? true
        toastOnCritical = cfg?["toastOnCritical"]?.boolValue ?? true
        barDisplayMode = cfg?["barDisplayMode"]?.stringValue ?? "icon"
        WidgetConfigRegistry.shared.register(self)
    }

    func exportConfig() -> [String: ConfigValue] {
        [
            "warningThreshold": .double(warningThreshold),
            "criticalThreshold": .double(criticalThreshold),
            "warningColorHex": .string(warningColorHex),
            "criticalColorHex": .string(criticalColorHex),
            "dataFilePath": .string(dataFilePath),
            "updateInterval": .double(updateInterval),
            "staleThreshold": .double(staleThreshold),
            "toastOnWarning": .bool(toastOnWarning),
            "toastOnCritical": .bool(toastOnCritical),
            "barDisplayMode": .string(barDisplayMode),
        ]
    }

    func applyConfig(_ values: [String: ConfigValue]) {
        suppressWrite = true
        defer { suppressWrite = false }
        if let v = values["warningThreshold"]?.doubleValue { warningThreshold = v }
        if let v = values["criticalThreshold"]?.doubleValue { criticalThreshold = v }
        if let v = values["warningColorHex"]?.stringValue { warningColorHex = v }
        if let v = values["criticalColorHex"]?.stringValue { criticalColorHex = v }
        if let v = values["dataFilePath"]?.stringValue { dataFilePath = v }
        if let v = values["updateInterval"]?.doubleValue { updateInterval = v }
        if let v = values["staleThreshold"]?.doubleValue { staleThreshold = v }
        if let v = values["toastOnWarning"]?.boolValue { toastOnWarning = v }
        if let v = values["toastOnCritical"]?.boolValue { toastOnCritical = v }
        if let v = values["barDisplayMode"]?.stringValue { barDisplayMode = v }
    }

    /// Resolve the data file path, expanding `~` to the user's home directory.
    var resolvedDataFilePath: String {
        (dataFilePath as NSString).expandingTildeInPath
    }

    var warningColor: Color {
        Color(hex: UInt32(warningColorHex, radix: 16) ?? 0xFFD60A)
    }

    var criticalColor: Color {
        Color(hex: UInt32(criticalColorHex, radix: 16) ?? 0xFF453A)
    }
}
