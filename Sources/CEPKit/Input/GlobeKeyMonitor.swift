import AppKit
import CoreGraphics
import IOKit.hid
import QuartzCore

/// Watches the hardware Fn / Globe key.
///
/// Fn alone is not a normal modifier event on modern Apple keyboards: macOS
/// consumes it before it reaches a CGEventTap. The key *is* present in the HID
/// report as Usage Page 0x00FF / Usage 0x0003, so we read the keyboard's input
/// reports directly. That is event-driven (no polling) and also lets us see
/// Fn+F1 … Fn+F12 before macOS turns them into brightness/media actions.
///
/// A CGEventTap fallback is installed when no HID Fn element is found, which
/// covers keyboards that expose Fn as a normal secondary-fn flag.
final class GlobeKeyMonitor {
    var onFnDown: (() -> Void)?
    /// `usedAsModifier` is true when Fn was combined with another key
    /// (F1–F12, arrows, …). In that case the picker must not open.
    var onFnUp: ((_ usedAsModifier: Bool) -> Void)?

    private(set) var fnIsDown = false
    private var fnUsedAsModifier = false
    private var fnDownTime: CFTimeInterval = 0

    private var manager: IOHIDManager?
    private var boxes: [DeviceBox] = []
    private var fallbackTap: CFMachPort?
    private var fallbackSource: CFRunLoopSource?
    private var fallbackInstalled = false
    private var didInstallFallback = false

    private(set) var usesHID = false
    var sourceDescription: String {
        boxes.isEmpty ? (fallbackInstalled ? "EVENT TAP" : "WAITING") : "HID FN"
    }

    private final class DeviceBox {
        weak var monitor: GlobeKeyMonitor?
        let device: IOHIDDevice
        let fnElement: IOHIDElement
        let reportID: UInt32
        let vendorID: Int
        let buffer: UnsafeMutablePointer<UInt8>
        let bufferSize = 4096
        var lastFnValue = -1

        init(monitor: GlobeKeyMonitor, device: IOHIDDevice, fnElement: IOHIDElement) {
            self.monitor = monitor
            self.device = device
            self.fnElement = fnElement
            self.reportID = IOHIDElementGetReportID(fnElement)
            self.vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            self.buffer.initialize(repeating: 0, count: bufferSize)
        }

        deinit {
            buffer.deinitialize(count: bufferSize)
            buffer.deallocate()
        }

        func value() -> Int? {
            let slot = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
            defer { slot.deallocate() }
            guard IOHIDDeviceGetValue(device, fnElement, slot) == kIOReturnSuccess else { return nil }
            return Int(IOHIDValueGetIntegerValue(slot.pointee.takeUnretainedValue()))
        }

        /// Apple keyboards put the 7-bit Fn field in the last byte of report 1.
        /// Reading it directly is faster than a second IOKit round-trip and
        /// works even if the element cache lags one report behind.
        func fnFromReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) -> Int? {
            guard reportID == 1, vendorID == 0x05AC, length >= 10 else { return nil }
            return (report[length - 1] & 0x02) != 0 ? 1 : 0
        }

        func handleReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
            guard let monitor else { return }

            let parsed = fnFromReport(reportID: reportID, report: report, length: length)
            let current = parsed ?? value() ?? 0
            if current != lastFnValue {
                lastFnValue = current
                if current == 1 {
                    monitor.fnPressed()
                } else {
                    monitor.fnReleased()
                }
            }

            guard monitor.fnIsDown, reportID == self.reportID, length > 2 else { return }
            let start = reportID != 0 ? 1 : 0
            guard length > start + 2 else { return }
            let modifiers = Int(report[start])
            // Ctrl / Alt / Cmd held with Fn means a system shortcut, not a tap.
            if modifiers & 0x0D != 0 {
                monitor.noteModifierDuringFn()
            }
            let keyStart = start + 2
            let keyEnd = min(Int(length), keyStart + 6)
            if keyStart < keyEnd {
                for index in keyStart..<keyEnd {
                    let usage = Int(report[index])
                    if usage != 0 {
                        monitor.noteKeyDuringFn(usage: usage)
                    }
                }
            }
        }
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() {
        guard manager == nil else { return }
        Self.requestInputMonitoringIfNeeded()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [[
            kIOHIDDeviceUsagePageKey as String: 0x01,
            kIOHIDDeviceUsageKey as String: 0x06
        ]]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatched, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        Log.debug("GlobeKeyMonitor open=\(status)")

        // The Fn device may not be present yet (Bluetooth reconnect). Give the
        // manager a moment before falling back to a CGEventTap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.boxes.isEmpty, !self.didInstallFallback else { return }
            self.didInstallFallback = true
            self.installFallbackTap()
        }
    }

    func stop() {
        if let fallbackTap {
            CGEvent.tapEnable(tap: fallbackTap, enable: false)
        }
        if let fallbackSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), fallbackSource, .commonModes)
        }
        fallbackTap = nil
        fallbackSource = nil
        fallbackInstalled = false

        for box in boxes {
            IOHIDDeviceUnscheduleFromRunLoop(box.device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(box.device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        boxes.removeAll()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        usesHID = false
    }

    // MARK: - Fn state

    fileprivate func fnPressed() {
        guard !fnIsDown else { return }
        fnIsDown = true
        fnUsedAsModifier = false
        fnDownTime = CACurrentMediaTime()
        onFnDown?()
    }

    fileprivate func fnReleased() {
        guard fnIsDown else { return }
        let held = CACurrentMediaTime() - fnDownTime
        let used = fnUsedAsModifier
        fnIsDown = false
        fnUsedAsModifier = false
        // 20 ms guards against a one-report glitch, not against fast taps.
        guard held >= 0.02 else { return }
        onFnUp?(used)
    }

    fileprivate func noteKeyDuringFn(usage: Int) {
        guard fnIsDown else { return }
        fnUsedAsModifier = true
        Log.debug("Fn used with HID usage \(String(format: "0x%02X", usage))")
    }

    fileprivate func noteModifierDuringFn() {
        guard fnIsDown else { return }
        fnUsedAsModifier = true
    }

    // MARK: - HID callbacks

    private static let deviceMatched: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context else { return }
        let monitor = Unmanaged<GlobeKeyMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.attach(device: device)
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context else { return }
        let monitor = Unmanaged<GlobeKeyMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.detach(device: device)
    }

    private static let reportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, length in
        guard let context else { return }
        let box = Unmanaged<DeviceBox>.fromOpaque(context).takeUnretainedValue()
        box.handleReport(reportID: reportID, report: report, length: length)
    }

    private func attach(device: IOHIDDevice) {
        guard !boxes.contains(where: { CFEqual($0.device, device) }) else { return }
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        // The Touch Bar exposes a look-alike Fn usage on an output element.
        guard !productName.localizedCaseInsensitiveContains("TouchBar") else { return }
        let elements = IOHIDDeviceCopyMatchingElements(
            device,
            nil,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] ?? []
        guard let fnElement = elements.first(where: {
            Int(IOHIDElementGetUsagePage($0)) == 0x00FF &&
                Int(IOHIDElementGetUsage($0)) == 0x03 &&
                (IOHIDElementGetType($0) == kIOHIDElementTypeInput_Button ||
                 IOHIDElementGetType($0) == kIOHIDElementTypeInput_Misc)
        }) else {
            return
        }

        let openStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else {
            Log.debug("Fn keyboard open failed: \(openStatus)")
            return
        }

        let box = DeviceBox(monitor: self, device: device, fnElement: fnElement)
        box.lastFnValue = box.value() ?? 0
        boxes.append(box)
        usesHID = true
        removeFallbackTap()

        IOHIDDeviceRegisterInputReportCallback(
            device,
            box.buffer,
            box.bufferSize,
            Self.reportCallback,
            Unmanaged.passUnretained(box).toOpaque()
        )
        IOHIDDeviceScheduleWithRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "keyboard"
        Log.debug("Fn keyboard attached: \(product), report \(IOHIDElementGetReportID(fnElement))")
    }

    private func detach(device: IOHIDDevice) {
        guard let index = boxes.firstIndex(where: { CFEqual($0.device, device) }) else { return }
        let box = boxes.remove(at: index)
        IOHIDDeviceUnscheduleFromRunLoop(box.device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(box.device, IOOptionBits(kIOHIDOptionsTypeNone))
        usesHID = !boxes.isEmpty
    }

    // MARK: - CGEventTap fallback

    private func installFallbackTap() {
        guard fallbackTap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: GlobeKeyMonitor.fallbackCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.debug("fallback Fn event tap unavailable")
            return
        }

        fallbackTap = tap
        fallbackInstalled = true
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        fallbackSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.debug("fallback Fn event tap installed")
    }

    private func removeFallbackTap() {
        guard fallbackInstalled else { return }
        if let fallbackTap {
            CGEvent.tapEnable(tap: fallbackTap, enable: false)
        }
        if let fallbackSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), fallbackSource, .commonModes)
        }
        fallbackTap = nil
        fallbackSource = nil
        fallbackInstalled = false
    }

    private static let fallbackCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<GlobeKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.fallbackTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        let fnDown = event.flags.contains(.maskSecondaryFn)
        if type == .flagsChanged || type == .keyDown || type == .keyUp {
            if fnDown && !monitor.fnIsDown {
                monitor.fnPressed()
            } else if !fnDown && monitor.fnIsDown {
                monitor.fnReleased()
            }
        }
        if type == .keyDown, monitor.fnIsDown {
            monitor.noteKeyDuringFn(usage: Int(event.getIntegerValueField(.keyboardEventKeycode)))
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Permissions

    static func inputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestInputMonitoringIfNeeded() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }
}
