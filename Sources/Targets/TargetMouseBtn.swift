import Cocoa
import CoreGraphics

final class TargetMouseBtn: Target {
    /// which 0 = left, 1 = right
    var which: Int = 0

    override func trigger(with jc: JoystickController) {
        let pos = NSEvent.mouseLocation
        // Cocoa NSScreen 原点在左下, CGEvent 在左上, 需翻转 Y
        let actualPos = CGPoint(x: pos.x, y: (NSScreen.main?.frame.height ?? 0) - pos.y)

        let mouseType: CGEventType = (which == 0) ? .leftMouseDown : .rightMouseDown
        let button: CGMouseButton = (which == 0) ? .left : .right

        guard let down = CGEvent(mouseEventSource: nil, mouseType: mouseType, mouseCursorPosition: actualPos, mouseButton: button) else { return }
        down.post(tap: .cghidEventTap)

        let upType: CGEventType = (which == 0) ? .leftMouseUp : .rightMouseUp
        guard let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: actualPos, mouseButton: button) else { return }
        up.post(tap: .cghidEventTap)
    }

    override func stringify() -> String {
        return "mbtn~\(which)"
    }

    static func unstringifyImpl(_ comps: [String]) -> TargetMouseBtn {
        let t = TargetMouseBtn()
        t.which = Int(comps[1]) ?? 0
        return t
    }
}