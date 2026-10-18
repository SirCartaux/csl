import AppKit
import Carbon.HIToolbox

/// Global hotkeys via the Carbon hotkey API. This needs no Accessibility
/// permission and delivers the event without polling.
///
/// Primary: ⌘Space (must be freed from Spotlight once – see README).
/// Fallback: ⌥Space, so the launcher is usable before that.
final class HotkeyManager {
    private(set) var activeBindings: [String] = []
    var onTrigger: (() -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private let signature: OSType = 0x4353_4C31 // 'CSL1'

    func install() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onTrigger?()
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            Log.debug("InstallEventHandler failed: \(status)")
        }

        register(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey), label: "CMD+SPACE", id: 1)
        register(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "OPT+SPACE", id: 2)

        Log.debug("hotkeys active: \(activeBindings.joined(separator: ", "))")
    }

    private func register(keyCode: UInt32, modifiers: UInt32, label: String, id: UInt32) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            Log.debug("hotkey \(label) registration failed: \(status)")
            return
        }

        hotKeyRefs.append(reference)
        activeBindings.append(label)
    }

    deinit {
        for reference in hotKeyRefs {
            UnregisterEventHotKey(reference)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }
}
