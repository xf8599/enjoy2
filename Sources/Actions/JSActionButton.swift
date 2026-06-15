import Cocoa
import IOKit.hid

final class JSActionButton: JSAction {
    var max: Int = 1

    private var active_internal: Bool = false

    override func notifyEvent(_ value: IOHIDValue) {
        let v = Int(IOHIDValueGetIntegerValue(value))
        active_internal = (v == max)
    }

    override var active: Bool {
        return active_internal
    }

    override func findSubAction(for value: IOHIDValue) -> SubAction? {
        // Button 没有 SubAction, 调用方应直接用 self.stringify() 查 target
        return nil
    }
}