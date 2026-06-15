import Cocoa
import Carbon

/// 所有输出目标的协议.
protocol TargetBehavior: AnyObject {
    var running: Bool { get set }
    var isContinuous: Bool { get }
    var inputValue: Double { get set }
    func trigger(with jc: JoystickController)
    func untrigger(with jc: JoystickController)
    func update(with jc: JoystickController)
    func stringify() -> String
}

/// 抽象基类. 子类必须重写 trigger / update / stringify.
class Target: NSObject, TargetBehavior {
    var running = false
    var isContinuous: Bool { false }
    var inputValue: Double = 0

    func trigger(with jc: JoystickController) {
        fatalError("Target.trigger(with:) must be overridden in subclass")
    }

    func untrigger(with jc: JoystickController) {
        // 默认空实现 (一些 Target 仅在 trigger 时做事情)
    }

    func update(with jc: JoystickController) {
        // 默认空实现 (仅连续型 Target 需要)
    }

    func stringify() -> String {
        fatalError("Target.stringify() must be overridden in subclass")
    }

    /// 工厂方法: 根据 stringified 格式还原 Target.
    /// - Parameter str: 形如 "key~13~W" / "cfg~myConfig" / "mmove~1" 等
    /// - Parameter configs: 已加载的配置列表 (用于 cfg 类型反查 Config 实例)
    static func unstringify(_ str: String, withConfigList configs: [Config]) -> Target? {
        let comps = str.components(separatedBy: "~")
        guard let tag = comps.first else { return nil }
        switch tag {
        case "key":     return TargetKeyboard.unstringifyImpl(comps)
        case "cfg":     return TargetConfig.unstringifyImpl(comps, configs: configs)
        case "mmove":   return TargetMouseMove.unstringifyImpl(comps)
        case "mbtn":    return TargetMouseBtn.unstringifyImpl(comps)
        case "mscroll": return TargetMouseScroll.unstringifyImpl(comps)
        case "mtoggle": return TargetToggleMouseScope.unstringifyImpl(comps)
        default:        return nil
        }
    }
}