import Cocoa

final class TargetConfig: Target {
    /// OC 原代码 `TargetConfig.m` 用 `name` 查 Config 实例.
    /// 反序列化时通过 name 在 configs 列表里查, 并持有强引用.
    var config: Config?

    override func trigger(with jc: JoystickController) {
        // OC 原方法签名是 -trigger (无参), 实际调自 active==YES 分支.
        // 这里保持 Swift 规范带 jc 参数, 调用方需传.
        guard let config = config else { return }
        let ac = NSApplication.shared.delegate as? ApplicationController
        ac?.configsController.activate(config, forApplication: String?(nil))
    }

    override func stringify() -> String {
        return "cfg~\(config?.name ?? "")"
    }

    static func unstringifyImpl(_ comps: [String], configs: [Config]) -> TargetConfig {
        let name = comps.count > 1 ? comps[1] : ""
        let t = TargetConfig()
        t.config = configs.first { $0.name == name }
        return t
    }
}