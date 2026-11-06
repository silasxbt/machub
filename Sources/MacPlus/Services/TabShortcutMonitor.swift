import Carbon
import Foundation

final class TabShortcutMonitor {
    var actionHandler: ((String) -> Void)?
    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tabDown = false
    private var deadline: DispatchTime?

    func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<TabShortcutMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        guard let eventTap else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        eventTap = nil
        tabDown = false
        deadline = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }; return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty == false { return }
        if type == .keyDown, keyCode == 48 {
            tabDown = true
            deadline = DispatchTime.now() + .milliseconds(500)
            return
        }
        if type == .keyUp, keyCode == 48 { tabDown = false; deadline = nil; return }
        guard type == .keyDown, tabDown, let deadline, DispatchTime.now() <= deadline, let key = Self.letter(for: keyCode) else { return }
        tabDown = false
        self.deadline = nil
        // The event tap is attached to the main run loop, so dispatching again
        // would only introduce an avoidable actor hop.
        actionHandler?(key)
    }

    private static func letter(for code: Int64) -> String? {
        let map: [Int64: String] = [0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z"]
        return map[code]
    }
}
