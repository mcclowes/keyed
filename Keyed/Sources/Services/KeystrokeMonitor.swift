import Carbon
import Cocoa
import Foundation

enum KeystrokeEvent {
    case character(String)
    case backspace
    case boundaryKey // arrow, tab, escape, mouse click — resets buffer
    case modifiedKey // cmd/ctrl/option combo — ignored
}

protocol KeystrokeMonitoring: AnyObject, Sendable {
    var onKeystroke: (@Sendable (KeystrokeEvent) -> Void)? { get set }
    func start()
    func stop()
}

final class CGEventTapMonitor: KeystrokeMonitoring, @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var monitorQueue: DispatchQueue?
    private var runLoop: CFRunLoop?
    private let lock = NSLock()

    var onKeystroke: (@Sendable (KeystrokeEvent) -> Void)?

    func start() {
        let queue = DispatchQueue(label: "com.mcclowes.keyed.eventtap", qos: .userInteractive)
        monitorQueue = queue

        queue.async { [weak self] in
            guard let self else { return }

            let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

            let unmanagedSelf = Unmanaged.passUnretained(self)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
                    guard let userInfo else { return Unmanaged.passRetained(event) }
                    let monitor = Unmanaged<CGEventTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                    monitor.handleEvent(event)
                    return Unmanaged.passRetained(event)
                },
                userInfo: unmanagedSelf.toOpaque()
            ) else {
                return
            }

            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                return
            }

            lock.lock()
            eventTap = tap
            runLoopSource = source
            runLoop = CFRunLoopGetCurrent()
            lock.unlock()

            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
    }

    func stop() {
        lock.lock()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource, let runLoop {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
            CFRunLoopStop(runLoop)
        }
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        lock.unlock()
    }

    private func handleEvent(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Ignore if modifier keys (Cmd, Ctrl, Option) are held — these are shortcuts
        let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        if !flags.intersection(modifierMask).isEmpty {
            onKeystroke?(.modifiedKey)
            return
        }

        // Backspace
        if keyCode == kVK_Delete {
            onKeystroke?(.backspace)
            return
        }

        // Boundary keys — reset the buffer
        let boundaryKeys: Set<Int64> = [
            Int64(kVK_Return), Int64(kVK_Tab), Int64(kVK_Escape),
            Int64(kVK_LeftArrow), Int64(kVK_RightArrow),
            Int64(kVK_UpArrow), Int64(kVK_DownArrow),
            Int64(kVK_Home), Int64(kVK_End),
            Int64(kVK_PageUp), Int64(kVK_PageDown),
        ]
        if boundaryKeys.contains(keyCode) {
            onKeystroke?(.boundaryKey)
            return
        }

        // Extract the unicode character
        var unicodeLength = 1
        var unicodeChar: [UniChar] = [0]
        event.keyboardGetUnicodeString(
            maxStringLength: 1,
            actualStringLength: &unicodeLength,
            unicodeString: &unicodeChar
        )

        guard unicodeLength > 0 else { return }

        let character = String(utf16CodeUnits: unicodeChar, count: Int(unicodeLength))
        guard !character.isEmpty else { return }

        onKeystroke?(.character(character))
    }

    deinit {
        stop()
    }
}
