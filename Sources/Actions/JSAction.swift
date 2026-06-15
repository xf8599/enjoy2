import Cocoa
import IOKit.hid

/// 手柄动作的抽象基类. 区分按钮 / 轴 / 帽开关.
class JSAction: NSObject {
    var usage: Int = 0
    var cookie: IOHIDElementCookie = 0
    let index: Int
    var subActions: [SubAction] = []
    /// 所属 Joystick 设备 (用于 stringify 串接设备 ID)
    weak var base: Joystick?
    let name: String

    init(index: Int, name: String) {
        self.index = index
        self.name = name
    }

    /// 由事件 value 更新 active 状态
    func notifyEvent(_ value: IOHIDValue) {
        fatalError("JSAction.notifyEvent(_:) must be overridden in subclass")
    }

    /// 当前是否激活 (用于触发 Target)
    var active: Bool {
        fatalError("JSAction.active must be overridden in subclass")
    }

    /// 根据 value 找到对应的 SubAction, 若无 SubAction 则返回 self.
    func findSubAction(for value: IOHIDValue) -> SubAction? {
        return nil
    }

    /// 序列化为 "vid~pid~idx~cookie"
    func stringify() -> String {
        let baseStr = base?.stringify() ?? "?"
        return "\(baseStr)~\(cookie)"
    }
}

/// 缺省实现: 仅供 JSActionAnalog 实际使用 (供 JoystickController 记录最新值)
extension JSAction {
    @objc func notifyEventValueUpdate(_ value: IOHIDValue) {
        // 基类空实现
    }
}

/// 子动作. JSActionButton 通常无 SubAction; JSActionAnalog 有 Low/High/Analog 三个.
final class SubAction {
    weak var base: JSAction?
    let name: String
    let index: Int
    var active = false

    init(index: Int, name: String, base: JSAction) {
        self.index = index
        self.name = name
        self.base = base
    }

    /// 序列化为 "vid~pid~idx~cookie~subIndex"
    func stringify() -> String {
        return "\(base!.stringify())~\(index)"
    }
}