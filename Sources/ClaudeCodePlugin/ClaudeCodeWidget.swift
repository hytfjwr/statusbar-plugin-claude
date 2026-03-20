import Combine
import StatusBarKit
import SwiftUI

@MainActor
@Observable
public final class ClaudeCodeWidget: StatusBarWidget {
    public let id = "claude-code-usage"
    public let position: WidgetPosition = .right
    public let updateInterval: TimeInterval? = nil
    public let sfSymbolName = "sparkle"
    public let preferredSettingsSize: CGSize? = CGSize(width: 420, height: 680)

    private var data: RateLimitData = .empty
    private var popupPanel: PopupPanel?
    private var timer: AnyCancellable?

    private var settings: ClaudeCodeSettings { ClaudeCodeSettings.shared }

    public func start() {
        refresh()
        restartTimer()
        observeSettings()
    }

    public func stop() {
        timer?.cancel()
        popupPanel?.hidePopup()
    }

    public func settingsBody() -> some View {
        ClaudeCodeWidgetSettings()
    }

    public func body() -> some View {
        Image(systemName: "sparkle")
            .font(Theme.sfIconFont)
            .foregroundStyle(barIconColor)
            .contentShape(Rectangle())
            .onTapGesture { [weak self] in
                self?.togglePopup()
            }
    }

    // MARK: - Private

    private func refresh() {
        if let newData = RateLimitReader.read(from: settings.resolvedDataFilePath) {
            data = newData
        }
        if popupPanel?.isVisible == true {
            popupPanel?.updateContent(makePopupContent())
        }
    }

    private func restartTimer() {
        timer?.cancel()
        let interval = settings.updateInterval
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.warningThreshold
            _ = settings.criticalThreshold
            _ = settings.warningColorHex
            _ = settings.criticalColorHex
            _ = settings.dataFilePath
            _ = settings.updateInterval
            _ = settings.staleThreshold
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.restartTimer()
                self?.refresh()
                self?.observeSettings()
            }
        }
    }

    private var barIconColor: Color {
        let isStale = data.isStale(threshold: settings.staleThreshold)
        return isStale ? Theme.secondary : colorForPercentage(data.fiveHour.usedPercentage)
    }

    private func colorForPercentage(_ percentage: Double) -> Color {
        if percentage < settings.warningThreshold {
            return Theme.green
        } else if percentage < settings.criticalThreshold {
            return settings.warningColor
        } else {
            return settings.criticalColor
        }
    }

    private func togglePopup() {
        if popupPanel?.isVisible == true {
            popupPanel?.hidePopup()
        } else {
            showPopup()
        }
    }

    private func showPopup() {
        refresh()

        if popupPanel == nil {
            popupPanel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 220))
        }

        guard let (barFrame, screen) = PopupPanel.barTriggerFrame() else { return }
        popupPanel?.showPopup(relativeTo: barFrame, on: screen, content: makePopupContent())
    }

    private func makePopupContent() -> some View {
        ClaudeCodePopupContent(
            data: data,
            warningThreshold: settings.warningThreshold,
            criticalThreshold: settings.criticalThreshold,
            warningColor: settings.warningColor,
            criticalColor: settings.criticalColor,
            staleThreshold: settings.staleThreshold
        )
    }
}

// MARK: - Popup Content

private struct ClaudeCodePopupContent: View {
    let data: RateLimitData
    let warningThreshold: Double
    let criticalThreshold: Double
    let warningColor: Color
    let criticalColor: Color
    let staleThreshold: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("CLAUDE CODE")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if data.isStale(threshold: staleThreshold) {
                    PopupStatusBadge("Stale", color: .orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if data.fetchedAt == .distantPast {
                PopupEmptyState(
                    icon: "exclamationmark.triangle",
                    message: "No rate limit data found.\nConfigure Claude Code statusline."
                )
                .padding(.bottom, 12)
            } else {
                VStack(spacing: 12) {
                    UsageCard(
                        title: "Session (5h)",
                        icon: "bolt.fill",
                        percentage: data.fiveHour.usedPercentage,
                        resetsAt: data.fiveHour.resetsAt,
                        warningThreshold: warningThreshold,
                        criticalThreshold: criticalThreshold,
                        warningColor: warningColor,
                        criticalColor: criticalColor
                    )

                    UsageCard(
                        title: "Weekly (7d)",
                        icon: "calendar",
                        percentage: data.sevenDay.usedPercentage,
                        resetsAt: data.sevenDay.resetsAt,
                        warningThreshold: warningThreshold,
                        criticalThreshold: criticalThreshold,
                        warningColor: warningColor,
                        criticalColor: criticalColor
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 280)
    }
}

// MARK: - Usage Card

private struct UsageCard: View {
    let title: String
    let icon: String
    let percentage: Double
    let resetsAt: Date?
    let warningThreshold: Double
    let criticalThreshold: Double
    let warningColor: Color
    let criticalColor: Color

    private var color: Color {
        colorForPercentage(
            percentage,
            warning: warningThreshold,
            critical: criticalThreshold,
            warningColor: warningColor,
            criticalColor: criticalColor
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Spacer()
                Text("\(formattedPercentage)%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }

            UsageProgressBar(percentage: percentage, color: color)

            if let resetsAt {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                    Text("Reset: \(formattedResetTime(resetsAt))")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Theme.secondary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(color.opacity(0.15), lineWidth: 1)
                }
        }
    }

    private var formattedPercentage: String {
        if percentage == percentage.rounded() {
            return "\(Int(percentage))"
        }
        return String(format: "%.1f", percentage)
    }

    private func formattedResetTime(_ date: Date) -> String {
        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval <= 0 {
            return "now"
        }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Progress Bar

private struct UsageProgressBar: View {
    let percentage: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.08))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geometry.size.width * min(percentage, 100) / 100))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Helpers

@MainActor
private func colorForPercentage(
    _ percentage: Double,
    warning: Double,
    critical: Double,
    warningColor: Color,
    criticalColor: Color
) -> Color {
    if percentage < warning {
        return Theme.green
    } else if percentage < critical {
        return warningColor
    } else {
        return criticalColor
    }
}

// MARK: - Settings View

struct ClaudeCodeWidgetSettings: View {
    @State private var warningThreshold: Double
    @State private var criticalThreshold: Double
    @State private var warningColor: Color
    @State private var criticalColor: Color
    @State private var dataFilePath: String
    @State private var updateInterval: Double
    @State private var staleThreshold: Double

    init() {
        let s = ClaudeCodeSettings.shared
        _warningThreshold = State(initialValue: s.warningThreshold)
        _criticalThreshold = State(initialValue: s.criticalThreshold)
        _warningColor = State(initialValue: s.warningColor)
        _criticalColor = State(initialValue: s.criticalColor)
        _dataFilePath = State(initialValue: s.dataFilePath)
        _updateInterval = State(initialValue: s.updateInterval)
        _staleThreshold = State(initialValue: s.staleThreshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Live Preview
            settingsPreview

            Divider()

            // Thresholds
            VStack(alignment: .leading, spacing: 10) {
                Text("Thresholds")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                // Warning
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ColorPicker("", selection: $warningColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 24, height: 24)
                            .onChange(of: warningColor) { _, newValue in
                                ClaudeCodeSettings.shared.warningColorHex = newValue.hexString
                            }

                        Text("Warning")
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        Text("\(Int(warningThreshold))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(warningColor)
                            .frame(width: 40, alignment: .trailing)
                    }

                    Slider(value: $warningThreshold, in: 10...90, step: 5)
                        .tint(warningColor)
                        .onChange(of: warningThreshold) { _, newValue in
                            ClaudeCodeSettings.shared.warningThreshold = newValue
                            if criticalThreshold <= newValue {
                                criticalThreshold = min(newValue + 5, 95)
                                ClaudeCodeSettings.shared.criticalThreshold = criticalThreshold
                            }
                        }
                }

                // Critical
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ColorPicker("", selection: $criticalColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 24, height: 24)
                            .onChange(of: criticalColor) { _, newValue in
                                ClaudeCodeSettings.shared.criticalColorHex = newValue.hexString
                            }

                        Text("Critical")
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        Text("\(Int(criticalThreshold))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(criticalColor)
                            .frame(width: 40, alignment: .trailing)
                    }

                    Slider(value: $criticalThreshold, in: 15...95, step: 5)
                        .tint(criticalColor)
                        .onChange(of: criticalThreshold) { _, newValue in
                            ClaudeCodeSettings.shared.criticalThreshold = newValue
                            if warningThreshold >= newValue {
                                warningThreshold = max(newValue - 5, 10)
                                ClaudeCodeSettings.shared.warningThreshold = warningThreshold
                            }
                        }
                }
            }

            Divider()

            // Update Interval
            VStack(alignment: .leading, spacing: 8) {
                Text("Update Interval")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("Update Interval", selection: $updateInterval) {
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: updateInterval) { _, newValue in
                    ClaudeCodeSettings.shared.updateInterval = newValue
                }
            }

            Divider()

            // Stale Threshold
            VStack(alignment: .leading, spacing: 8) {
                Text("Stale Data Threshold")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("Stale Threshold", selection: $staleThreshold) {
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("10 minutes").tag(600.0)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: staleThreshold) { _, newValue in
                    ClaudeCodeSettings.shared.staleThreshold = newValue
                }
            }

            Divider()

            // Data Source
            VStack(alignment: .leading, spacing: 8) {
                Text("Data Source")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("File path", text: $dataFilePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: dataFilePath) { _, newValue in
                            ClaudeCodeSettings.shared.dataFilePath = newValue
                        }

                    Button("Reset") {
                        dataFilePath = "~/.claude/rate_limits.json"
                    }
                    .controlSize(.small)
                }

                Text("Path to the JSON file written by Claude Code's statusline script.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Live Preview

    @MainActor
    private var settingsPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                previewBar(percentage: warningThreshold - 10, label: "Normal")
                previewBar(percentage: warningThreshold + 5, label: "Warning")
                previewBar(percentage: criticalThreshold + 5, label: "Critical")
            }
            .frame(maxWidth: .infinity)

            // Threshold scale
            ThresholdScaleView(
                warningThreshold: warningThreshold,
                criticalThreshold: criticalThreshold,
                warningColor: warningColor,
                criticalColor: criticalColor
            )
        }
    }

    @MainActor
    private func previewBar(percentage: Double, label: String) -> some View {
        let color = previewColor(for: percentage)
        return VStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.1))
                }

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
    }

    @MainActor
    private func previewColor(for percentage: Double) -> Color {
        if percentage < warningThreshold {
            return Theme.green
        } else if percentage < criticalThreshold {
            return warningColor
        } else {
            return criticalColor
        }
    }
}

// MARK: - Threshold Scale

private struct ThresholdScaleView: View {
    let warningThreshold: Double
    let criticalThreshold: Double
    let warningColor: Color
    let criticalColor: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                // Track segments
                HStack(spacing: 0) {
                    Theme.green.opacity(0.3)
                        .frame(width: width * warningThreshold / 100)
                    warningColor.opacity(0.3)
                        .frame(width: width * (criticalThreshold - warningThreshold) / 100)
                    criticalColor.opacity(0.3)
                        .frame(width: width * (100 - criticalThreshold) / 100)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                // Warning marker
                thresholdMarker(at: warningThreshold, width: width, color: warningColor)
                // Critical marker
                thresholdMarker(at: criticalThreshold, width: width, color: criticalColor)
            }
        }
        .frame(height: 12)
    }

    private func thresholdMarker(at percentage: Double, width: CGFloat, color: Color) -> some View {
        let x = width * percentage / 100
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
            }
            .offset(x: x - 4)
    }
}

// MARK: - Color Hex Helper

extension Color {
    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else {
            return "FFFFFF"
        }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
