import Cocoa
import Carbon
import CoreGraphics

final class TargetMouseMove: Target {
    /// dir 0 = X (horizontal), 1 = Y (vertical)
    var dir: Int = 0

    override var isContinuous: Bool { true }

    override func update(with jc: JoystickController) {
        // 根据 inputValue 计算 delta
        // OC 原逻辑: 1.0 inputValue = 12.0 pixels/frame (80Hz)
        // frontWindowOnly 时: 4.0 pixels/frame
        let speed = jc.frontWindowOnly ? 4.0 : 12.0
        let v = jc.mouseLoc
        var newLoc = v

        if dir == 0 {
            // X 方向
            newLoc.x += CGFloat(inputValue) * CGFloat(speed)
        } else {
            // Y 方向 (Cocoa NSScreen 原点在左下, CGEvent 在左上, 需翻转)
            newLoc.y -= CGFloat(inputValue) * CGFloat(speed)
        }

        jc.mouseLoc = newLoc

        // 合成鼠标移动事件
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newLoc, mouseButton: .left) else { return }
        event.setIntegerValueField(CGEventField.mouseEventDeltaX, value: Int64(inputValue * Double(speed)))
        event.setIntegerValueField(CGEventField.mouseEventDeltaY, value: Int64(-inputValue * Double(speed)))

        if jc.frontWindowOnly {
            var psn = ProcessSerialNumber()
            // GetFrontProcess 已在 macOS 10.9 弃用, 但 OC 原代码仍使用以兼容旧应用
            // 使用 @_silgen_name 直接调用 C 符号绕过 Swift 的 unavailable 标记
            _getFrontProcess(&psn)
            event.postToPSN(processSerialNumber: &psn)
        } else {
            event.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    override func stringify() -> String {
        return "mmove~\(dir)"
    }

    static func unstringifyImpl(_ comps: [String]) -> TargetMouseMove {
        let t = TargetMouseMove()
        t.dir = Int(comps[1]) ?? 0
        return t
    }
}

// 直接调用 C 符号, 绕过 Swift unavailable 标记
@_silgen_name("GetFrontProcess")
private func _getFrontProcess(_ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus