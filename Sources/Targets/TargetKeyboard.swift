import Cocoa
import CoreGraphics

final class TargetKeyboard: Target {
    var vk: CGKeyCode = 0
    var descr: String = ""

    override func trigger(with jc: JoystickController) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: true) else { return }
        event.post(tap: .cghidEventTap)
    }

    override func untrigger(with jc: JoystickController) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: false) else { return }
        event.post(tap: .cghidEventTap)
    }

    override func stringify() -> String {
        return "key~\(Int(vk))~\(descr)"
    }

    static func unstringifyImpl(_ comps: [String]) -> TargetKeyboard {
        assert(comps.count == 3, "TargetKeyboard expects 3 components, got \(comps.count)")
        let t = TargetKeyboard()
        t.vk = CGKeyCode(Int(comps[1]) ?? 0)
        t.descr = comps[2]
        return t
    }
}