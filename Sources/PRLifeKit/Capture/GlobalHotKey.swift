import Foundation

/// A global hotkey chord mapped to a capture context. `keyCode`/`modifiers` are raw
/// Carbon values so the macOS concrete can register them directly; defined here
/// (platform-free) so they are unit-testable and shared.
public struct HotKeyBinding: Equatable, Sendable {
    public let context: CaptureContext
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(context: CaptureContext, keyCode: UInt32, modifiers: UInt32) {
        self.context = context; self.keyCode = keyCode; self.modifiers = modifiers
    }

    /// Carbon `controlKey | optionKey`.
    public static let ctrlOption: UInt32 = 0x1000 | 0x0800

    /// ⌃⌥Space / ⌃⌥W / ⌃⌥J / ⌃⌥I — matches the Devices-tab spec.
    public static let defaults: [HotKeyBinding] = [
        HotKeyBinding(context: .quick,   keyCode: 49, modifiers: ctrlOption), // Space
        HotKeyBinding(context: .work,    keyCode: 13, modifiers: ctrlOption), // W
        HotKeyBinding(context: .journal, keyCode: 38, modifiers: ctrlOption), // J
        HotKeyBinding(context: .ideas,   keyCode: 34, modifiers: ctrlOption), // I
    ]
}

/// Registers global hotkeys. The macOS concrete wraps Carbon `RegisterEventHotKey`;
/// tests use a fake. `onTrigger` is called on the main actor by the concrete.
public protocol GlobalHotKeyRegistering: AnyObject {
    func register(_ bindings: [HotKeyBinding], onTrigger: @escaping (CaptureContext) -> Void)
    func unregisterAll()
}
