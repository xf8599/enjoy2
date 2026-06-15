import Cocoa

final class Config: NSObject {
    var name: String
    /// 磁盘格式版本, 保留 "enjoy3-1.1" 兼容现有用户配置
    let format = "enjoy3-1.1"
    /// key: JSAction.stringify(),  value: Target 实例
    var entries: [String: Target] = [:]

    init(name: String) {
        self.name = name
    }

    // MARK: - Target 增删查

    func setTarget(_ target: Target?, for action: JSAction) {
        let key = action.stringify()
        if let target = target {
            entries[key] = target
        } else {
            entries.removeValue(forKey: key)
        }
    }

    func getTarget(for action: JSAction) -> Target? {
        return entries[action.stringify()]
    }

    func getTarget(forSubAction sub: SubAction) -> Target? {
        return entries[sub.stringify()]
    }

    func setTarget(_ target: Target?, forStringified key: String) {
        if let target = target {
            entries[key] = target
        } else {
            entries.removeValue(forKey: key)
        }
    }

    // MARK: - JSON 序列化

    /// 写入 ~/Library/Application Support/enjoy3/mappings/<name>.json
    func save() throws {
        let url = try Self.getMappingFilename(for: name)
        try saveJSON(to: url)
    }

    func saveJSON(to url: URL) throws {
        var dict: [String: Any] = [
            "name": name,
            "format": format
        ]
        var mappingEntries: [String: String] = [:]
        for (key, target) in entries {
            mappingEntries[key] = target.stringify()
        }
        dict["entries"] = mappingEntries
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        try data.write(to: url, options: .atomic)
    }

    // MARK: - JSON 反序列化

    /// 第一次扫描: 只读 name (用于 TargetConfig 跨引用解析)
    static func loadSkel(fromJSON url: URL) throws -> Config {
        let data = try Data(contentsOf: url)
        guard let dict = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = dict["name"] as? String else {
            throw NSError(domain: "enjoy3", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid config JSON: \(url.path)"])
        }
        return Config(name: name)
    }

    /// 第二次扫描: 解析 entries, 关联 Target 实例
    func load(fromJSON url: URL, withConfigList configs: [Config]) throws {
        let data = try Data(contentsOf: url)
        guard let dict = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entriesDict = dict["entries"] as? [String: String] else { return }
        for (key, value) in entriesDict {
            entries[key] = Target.unstringify(value, withConfigList: configs)
        }
    }

    // MARK: - 路径

    static func getMappingsDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("enjoy3/mappings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func getMappingFilename(for name: String) throws -> URL {
        let dir = try getMappingsDirectory()
        return dir.appendingPathComponent("\(name).json")
    }
}