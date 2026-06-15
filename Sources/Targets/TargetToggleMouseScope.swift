import Cocoa

final class TargetToggleMouseScope: Target {
    override func trigger(with jc: JoystickController) {
        jc.frontWindowOnly.toggle()
    }

    override func stringify() -> String {
        return "mtoggle"
    }

    static func unstringifyImpl(_ comps: [String]) -> TargetToggleMouseScope {
        return TargetToggleMouseScope()
    }
}