import Cocoa
import IOKit.hid

final class JSActionAnalog: JSAction {
    var min: Double = 0
    var max: Double = 1

    private let analogThreshold = 0.1
    private let discreteThreshold = 0.3

    private var lowActive = false
    private var highActive = false
    private var analogActive = false

    override init(index: Int, name: String) {
        super.init(index: index, name: name)
        // OC 中在 init 创建 subActions, Swift 端也按相同方式
        let low = SubAction(index: 0, name: "Low", base: self)
        let high = SubAction(index: 1, name: "High", base: self)
        let analog = SubAction(index: 2, name: "Analog", base: self)
        self.subActions = [low, high, analog]
    }

    /// 把原始整数 value 线性映射到 [-1, +1], 公式与 OC 一致.
    func getRealValue(_ raw: Int) -> Double {
        let v = Double(raw)
        if max - min < 1 { return 0 }  // 防御
        return -1.0 + 2.0 * (v - min - 0.5) / (max - min)
    }

    /// IOHIDValue 重载 (兼容)
    func getRealValue(_ raw: IOHIDValue) -> Double {
        return getRealValue(Int(IOHIDValueGetIntegerValue(raw)))
    }

    override func notifyEvent(_ value: IOHIDValue) {
        let real = getRealValue(value)

        analogActive = abs(real) > analogThreshold
        lowActive = real < -discreteThreshold
        highActive = real > discreteThreshold

        subActions[2].active = analogActive
        subActions[0].active = lowActive
        subActions[1].active = highActive
    }

    override var active: Bool {
        return lowActive || highActive || analogActive
    }

    override func findSubAction(for value: IOHIDValue) -> SubAction? {
        let parsed = getRealValue(value)

        // analog 在中位附近时返回 nil (避免抖动)
        if analogActive {
            if abs(parsed) < analogThreshold {
                return nil
            }
            return subActions[2]
        }

        if parsed < -discreteThreshold {
            return subActions[0]
        } else if parsed > discreteThreshold {
            return subActions[1]
        }
        return nil
    }

    /// 暴露给 JoystickController.inputCallback 用于 TargetMouseMove 的 inputValue
    var currentRealValue: Double = 0

    override func notifyEventValueUpdate(_ value: IOHIDValue) {
        currentRealValue = getRealValue(value)
    }
}