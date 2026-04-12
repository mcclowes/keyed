import Carbon
import Cocoa
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "KeystrokeMonitor")

enum KeystrokeEvent {
    case character(String)
    case backspace
    case boundaryKey // arrow, tab, escape — resets buffer
    case modifiedKey // cmd/ctrl combo — ignored
    /// Signalled when the event tap has been re-enabled after the system disabled it
    /// (timeout or user-input blackout). The engine must treat its buffer as stale because
    /// any characters typed during the blackout were never observed.
    case tapReset
}

protocol KeystrokeMonitoring: AnyObject, Sendable {
    var onKeystroke: (@Sendable (KeystrokeEvent) -> Void)? { get set }
    /// Invoked asynchronously on the main queue when tap creation fails — almost always because
    /// Accessibility permission is not (yet) in force for this process. Lets the caller retry
    /// once trust changes rather than silently remaining dead.
    var onTapCreationFailed: (@Sendable () -> Void)? { get set }
    /// True when a live CGEventTap is currently installed.
    var isRunning: Bool { get }
    func start()
    func stop()
    /// Temporarily disables the tap so injected synthetic events cannot feed back into
    /// the buffer. Calls are not reference-counted — a single `resume()` undoes any
    /// number of `pause()` calls. Safe to call from any thread.
    func pause()
    func resume()
}

/// CGEventTap-based system keystroke capture.
///
/// Lifetime management: when `start()` succeeds, this object retains itself via an `Unmanaged`
/// passed to the C callback. `stop()` releases that retain after tearing down the tap.
final class CGEventTapMonitor: KeystrokeMonitoring, @unchecked Sendable {
    private let stateLock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var monitorQueue: DispatchQueue?
    private var runLoop: CFRunLoop?
    private var retainedSelf: Unmanaged<CGEventTapMonitor>?

    private var _onKeystroke: (@Sendable (KeystrokeEvent) -> Void)?
    var onKeystroke: (@Sendable (KeystrokeEvent) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _onKeystroke
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _onKeystroke = newValue
        }
    }

    private var _onTapCreationFailed: (@Sendable () -> Void)?
    var onTapCreationFailed: (@Sendable () -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _onTapCreationFailed
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _onTapCreationFailed = newValue
        }
    }

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return eventTap != nil
    }

    func start() {
        stateLock.lock()
        if eventTap != nil {
            stateLock.unlock()
            return
        }
        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained
        stateLock.unlock()

        let queue = DispatchQueue(label: "com.mcclowes.keyed.eventtap", qos: .userInteractive)

        stateLock.lock()
        monitorQueue = queue
        stateLock.unlock()

        queue.async {
            let eventMask: CGEventMask =
                (1 << CGEventType.keyDown.rawValue) |
                (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                (1 << CGEventType.tapDisabledByUserInput.rawValue)

            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                    guard let userInfo else { return Unmanaged.passRetained(event) }
                    let monitor = Unmanaged<CGEventTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                    monitor.handleCallback(type: type, event: event)
                    return Unmanaged.passRetained(event)
                },
                userInfo: retained.toOpaque()
            ) else {
                logger.error("Failed to create event tap — accessibility permission likely missing")
                self.stateLock.lock()
                self.retainedSelf = nil
                self.monitorQueue = nil
                let failureHandler = self._onTapCreationFailed
                self.stateLock.unlock()
                retained.release()
                if let failureHandler {
                    DispatchQueue.main.async { failureHandler() }
                }
                return
            }

            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                CGEvent.tapEnable(tap: tap, enable: false)
                self.stateLock.lock()
                self.retainedSelf = nil
                self.monitorQueue = nil
                self.stateLock.unlock()
                retained.release()
                return
            }

            self.stateLock.lock()
            self.eventTap = tap
            self.runLoopSource = source
            self.runLoop = CFRunLoopGetCurrent()
            self.stateLock.unlock()

            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
    }

    func stop() {
        stateLock.lock()
        let tap = eventTap
        let source = runLoopSource
        let loop = runLoop
        let retained = retainedSelf
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        monitorQueue = nil
        retainedSelf = nil
        stateLock.unlock()

        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source, let loop {
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFRunLoopStop(loop)
        }
        retained?.release()
    }

    func pause() {
        stateLock.lock()
        let tap = eventTap
        stateLock.unlock()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    func resume() {
        stateLock.lock()
        let tap = eventTap
        stateLock.unlock()
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func handleCallback(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            logger.notice("Event tap disabled (type=\(type.rawValue)) — re-enabling")
            stateLock.lock()
            let tap = eventTap
            stateLock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Anything typed during the blackout is lost — tell the engine to discard its
            // buffer so a stale prefix cannot combine with new input to trigger an expansion.
            onKeystroke?(.tapReset)
            return
        case .keyDown:
            handleKeyDown(event)
        default:
            break
        }
    }

    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Only treat Command and Control as "this is a shortcut, ignore it."
        // Option is legitimately used for character composition on many layouts.
        let shortcutMask: CGEventFlags = [.maskCommand, .maskControl]
        if !flags.isDisjoint(with: shortcutMask) {
            onKeystroke?(.modifiedKey)
            return
        }

        if keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            onKeystroke?(.backspace)
            return
        }

        let boundaryKeys: Set<Int64> = [
            Int64(kVK_Return), Int64(kVK_ANSI_KeypadEnter),
            Int64(kVK_Tab), Int64(kVK_Escape),
            Int64(kVK_LeftArrow), Int64(kVK_RightArrow),
            Int64(kVK_UpArrow), Int64(kVK_DownArrow),
            Int64(kVK_Home), Int64(kVK_End),
            Int64(kVK_PageUp), Int64(kVK_PageDown),
        ]
        if boundaryKeys.contains(keyCode) {
            onKeystroke?(.boundaryKey)
            return
        }

        // Read up to 4 UTF-16 code units so we pick up surrogate pairs for non-BMP characters.
        var unicodeLength = 0
        var unicodeChars: [UniChar] = [0, 0, 0, 0]
        event.keyboardGetUnicodeString(
            maxStringLength: 4,
            actualStringLength: &unicodeLength,
            unicodeString: &unicodeChars
        )

        guard unicodeLength > 0 else { return }

        let character = String(utf16CodeUnits: unicodeChars, count: Int(unicodeLength))
        guard !character.isEmpty else { return }

        onKeystroke?(.character(character))
    }

    deinit {
        stop()
    }
}
