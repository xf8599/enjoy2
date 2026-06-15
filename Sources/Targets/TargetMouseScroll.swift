import Cocoa
import CoreGraphics

final class TargetMouseScroll: Target {
    /// howMuch 正负表方向
    var howMuch: Int = 0

    override func trigger(with jc: JoystickController) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(howMuch), wheel2: 0, wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    override func stringify() -> String {
        return "mscroll~\(howMuch)"
    }

    static func unstringifyImpl(_ comps: [String]) -> TargetMouseScroll {
        let t = TargetMouseScroll()
        t.howMuch = Int(comps[1]) ?? 0
        return t
    }
}