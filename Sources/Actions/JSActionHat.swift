import Cocoa
import IOKit.hid

/// Hat switch 动作. 4 向 (LogicalMax=3 或 4) 或 8 向 (LogicalMax=7 或 8).
final class JSActionHat: JSAction {
    private var max: Int = 0

    private var upActive = false
    private var downActive = false
    private var leftActive = false
    private var rightActive = false

    override init(index: Int, name: String) {
        super.init(index: index, name: name)
        // OC 中创建 4 个 SubAction
        let up = SubAction(index: 0, name: "Up", base: self)
        let down = SubAction(index: 1, name: "Down", base: self)
        let left = SubAction(index: 2, name: "Left", base: self)
        let right = SubAction(index: 3, name: "Right", base: self)
        self.subActions = [up, down, left, right]
    }

    convenience init() {
        self.init(index: 0, name: "Hat switch")
    }

    override func notifyEvent(_ value: IOHIDValue) {
        let parsed = Int(IOHIDValueGetIntegerValue(value))
        let size = max

        // 复刻 OC 逻辑: 当 logical max 为 7 或 3 时, parsed 自增
        var p = parsed
        var s = size
        if s == 7 || s == 3 {
            p += 1
            s += 1
        }

        let active: [Bool]
        if s == 8 {
            // 8 向查表
            active = JSActionHat.eightWayTable(p)
        } else {
            // 4 向查表 (size 应该是 4)
            active = JSActionHat.fourWayTable(p)
        }

        upActive = active[0]
        downActive = active[1]
        leftActive = active[2]
        rightActive = active[3]

        subActions[0].active = upActive
        subActions[1].active = downActive
        subActions[2].active = leftActive
        subActions[3].active = rightActive
    }

    override var active: Bool {
        return upActive || downActive || leftActive || rightActive
    }

    override func findSubAction(for value: IOHIDValue) -> SubAction? {
        let parsed = Int(IOHIDValueGetIntegerValue(value))
        let logicalMax = max
        // 复刻 OC 中 findSubActionForValue 的 switch 逻辑
        if logicalMax == 7 {
            switch parsed {
            case 0: return subActions[0]  // Up
            case 4: return subActions[1]  // Down
            case 6: return subActions[2]  // Left
            case 2: return subActions[3]  // Right
            default: return nil
            }
        } else if logicalMax == 8 {
            switch parsed {
            case 1: return subActions[0]  // Up
            case 5: return subActions[1]  // Down
            case 7: return subActions[2]  // Left
            case 3: return subActions[3]  // Right
            default: return nil
            }
        } else if logicalMax == 3 {
            switch parsed {
            case 0: return subActions[0]
            case 2: return subActions[1]
            case 3: return subActions[2]
            case 1: return subActions[3]
            default: return nil
            }
        } else if logicalMax == 4 {
            switch parsed {
            case 1: return subActions[0]
            case 3: return subActions[1]
            case 4: return subActions[2]
            case 2: return subActions[3]
            default: return nil
            }
        }
        return nil
    }

    func setMax(_ m: Int) {
        self.max = m
    }

    // MARK: - 查表 (复刻 OC 中 active_eightway / active_fourway)

    private static func eightWayTable(_ index: Int) -> [Bool] {
        // 9 个状态, 每状态 4 bit [Up, Down, Left, Right]
        let table: [[Bool]] = [
            [false, false, false, false], // center
            [true,  false, false, false], // N
            [true,  false, false, true],  // NE
            [false, false, false, true],  // E
            [false, true,  false, true],  // SE
            [false, true,  false, false], // S
            [false, true,  true,  false], // SW
            [false, false, true,  false], // W
            [true,  false, true,  false], // NW
        ]
        let safe = Swift.max(0, Swift.min(index, 8))
        return table[safe]
    }

    private static func fourWayTable(_ index: Int) -> [Bool] {
        let table: [[Bool]] = [
            [false, false, false, false], // center
            [true,  false, false, false], // N
            [false, false, false, true],  // E
            [false, true,  false, false], // S
            [false, false, true,  false], // W
        ]
        let safe = Swift.max(0, Swift.min(index, 4))
        return table[safe]
    }
}