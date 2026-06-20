import Foundation
import Carbon.HIToolbox
import PRLifeKit

/// Registers system-wide hotkeys using Carbon RegisterEventHotKey. Each chord fires
/// `onTrigger` with its CaptureContext on the main actor. No Accessibility permission needed.
final class CarbonHotKeyManager: GlobalHotKeyRegistering {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var contextByID: [UInt32: CaptureContext] = [:]
    private var onTrigger: ((CaptureContext) -> Void)?
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x50524C46 // 'PRLF'

    func register(_ bindings: [HotKeyBinding], onTrigger: @escaping (CaptureContext) -> Void) {
        unregisterAll()
        self.onTrigger = onTrigger

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<CarbonHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let context = manager.contextByID[hkID.id] {
                DispatchQueue.main.async { manager.onTrigger?(context) }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 1)
            contextByID[id] = binding.context
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: signature, id: id)
            RegisterEventHotKey(binding.keyCode, binding.modifiers, hkID,
                                GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs where ref != nil { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        contextByID.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }

    deinit { unregisterAll() }
}
