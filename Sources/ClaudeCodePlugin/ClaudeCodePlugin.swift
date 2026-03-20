import StatusBarKit

@MainActor
public struct ClaudeCodePlugin: StatusBarPlugin {
    public let manifest = PluginManifest(
        id: "com.hytfjwr.claudecode",
        name: "Claude Code"
    )
    public let widgets: [any StatusBarWidget]

    public init() {
        widgets = [ClaudeCodeWidget()]
    }
}

@_cdecl("createStatusBarPlugin")
public func createStatusBarPlugin() -> UnsafeMutableRawPointer {
    let box = PluginBox { ClaudeCodePlugin() }
    return Unmanaged.passRetained(box).toOpaque()
}
