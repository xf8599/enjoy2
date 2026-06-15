import Cocoa
import Carbon

final class ConfigsController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var removeButton: NSButton!
    @IBOutlet weak var targetController: TargetController!
    @IBOutlet weak var appController: ApplicationController!

    private(set) var configs: [Config] = []
    private(set) var currentConfig: Config?
    private var neutralConfig: Config?
    private var attachedApplication = ProcessSerialNumber()
    private var hasAttachedApplication = false

    override func awakeFromNib() {
        super.awakeFromNib()
        applyDarkModeAppearance()
    }

    /// 配置列表 NSTableView 在 cell-based 模式下, dark mode 下交替行底色会变成白色.
    /// 这里在运行时强制使用统一的 dark 背景 + 不交替, 并精确处理 scrollView / clipView / 列头 / drawer 容器.
    private func applyDarkModeAppearance() {
        guard let tv = tableView else { return }
        let dark = NSColor(calibratedWhite: 0.10, alpha: 1.0)

        tv.usesAlternatingRowBackgroundColors = false
        tv.backgroundColor = dark
        tv.gridColor = NSColor(calibratedWhite: 0.20, alpha: 1.0)
        // 恢复 .regular 高亮 — 之前设 .none 导致用户看不到选中状态.
        // 主窗口已强制 darkAqua 外观, 系统 highlight 在 dark mode 下会自适应深色.
        tv.selectionHighlightStyle = .regular
        // cell-based 模式下, 直接置 nil 仍会绘制列头 — 用自定义的 DarkTableHeaderView 替代.
        tv.headerView = DarkTableHeaderView(frame: NSRect(x: 0, y: 0, width: tv.bounds.width, height: 22))
        tv.cornerView = nil
        // 让列头的 cell 自身背景透明, 避免列头 cell 自己也画一个白底
        for column in tv.tableColumns {
            column.headerCell.backgroundColor = dark
            // dataCell 是 Any? (XIB 中实际是 NSTextFieldCell).
            // 注意: drawsBackground 必须设 false, 否则 NSTextFieldCell 会自己画深色背景,
            // 把系统 selection highlight 盖住, 用户就看不到选中.
            if let dataCell = column.dataCell as? NSTextFieldCell {
                dataCell.drawsBackground = false
            }
        }

        if let sv = tv.enclosingScrollView {
            sv.backgroundColor = dark
            sv.drawsBackground = true
        }
        if let clip = tv.enclosingScrollView?.contentView {
            clip.backgroundColor = dark
            clip.drawsBackground = true
        }

        // 向上遍历: 一直走到 drawer 容器, 把每一层 customView 都设成深色.
        // NSDrawer 的 chrome (那个细灰边) 改不了, 但容器本身可以.
        var v: NSView? = tv.superview
        while let cur = v {
            cur.wantsLayer = true
            cur.layer?.backgroundColor = dark.cgColor
            // 到达 NSVisualEffectView 或 NSWindow 时停止 (不要再往上染色)
            if cur is NSVisualEffectView || cur is NSWindow { break }
            v = cur.superview
        }

        // 主窗口强制使用 darkAqua, 让 drawer chrome 跟随 (否则 NSDrawer 在 light 系统主题下用白底)
        if let win = tv.window {
            win.appearance = NSAppearance(named: .darkAqua)
        }

        // 主窗口的 splitView 现在是 3 栏, drawer 已删除, 整个主窗口用 darkAqua 即可
        if let win = tv.window {
            win.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - 加载与保存

    func load() {
        // 阶段一: 只读 name (用于 TargetConfig 跨引用解析)
        do {
            let dir = try Config.getMappingsDirectory()
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for url in files where url.pathExtension == "json" {
                if let cfg = try? Config.loadSkel(fromJSON: url) {
                    configs.append(cfg)
                }
            }
            // 阶段二: 解析 entries, 关联 Target 实例
            for cfg in configs {
                if let url = try? Config.getMappingFilename(for: cfg.name) {
                    try? cfg.load(fromJSON: url, withConfigList: configs)
                }
            }
        } catch {
            NSLog("enjoy3: load failed: \(error)")
        }

        // 恢复上次选中的 Config
        let savedName = UserDefaults.standard.string(forKey: "selectedMapping")
        if let savedName = savedName, let cfg = configs.first(where: { $0.name == savedName }) {
            activate(cfg, forApplication: nil)
        }
        if currentConfig == nil, !configs.isEmpty {
            currentConfig = configs.first
        }
        tableView.reloadData()
    }

    func save() {
        do {
            // 清理过期文件
            let dir = try Config.getMappingsDirectory()
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for url in files where url.pathExtension == "json" {
                let name = url.deletingPathExtension().lastPathComponent
                if !configs.contains(where: { $0.name == name }) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            // 写所有 Config
            for cfg in configs {
                try cfg.save()
            }

            // 持久化当前 Config 名
            if let neutral = currentNeutralConfig(), let n = neutral.name as String? {
                UserDefaults.standard.set(n, forKey: "selectedMapping")
            }
            UserDefaults.standard.synchronize()
        } catch {
            NSLog("enjoy3: save failed: \(error)")
        }
    }

    // MARK: - 激活

    func activate(_ config: Config, forApplication appName: String?) {
        if let appName = appName, currentConfig != nil {
            // 保存当前作为 neutral
            neutralConfig = currentConfig
            attachedApplication = ProcessSerialNumber()
            hasAttachedApplication = true
            _ = appName  // 简化: 不实际存 appName, 由 OC 行为决定
        } else if appName == nil {
            // 手动激活, 清除 neutral
            neutralConfig = nil
            hasAttachedApplication = false
        }
        if currentConfig != nil {
            targetController?.reset()
        }
        currentConfig = config
        removeButton?.isEnabled = !configs.isEmpty
        targetController?.load()
        appController?.configChanged()
        if let idx = configs.firstIndex(where: { $0 === config }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
    }

    func restoreNeutralConfig() {
        guard let neutral = neutralConfig else { return }
        if !configs.contains(where: { $0 === neutral }) {
            neutralConfig = nil
            return
        }
        activate(neutral, forApplication: nil)
    }

    /// Carbon EventHandler 回调
    func applicationSwitched(to appName: String, psn: ProcessSerialNumber) {
        if let match = configs.first(where: { $0.name == appName }) {
            if currentConfig !== match {
                activate(match, forApplication: appName)
            }
        } else {
            restoreNeutralConfig()
        }
    }

    func currentNeutralConfig() -> Config? {
        if let n = neutralConfig { return n }
        return currentConfig
    }

    // MARK: - UI 操作

    @IBAction func addPressed(_ sender: Any) {
        let new = Config(name: "untitled")
        configs.append(new)
        appController?.configsListChanged()
        tableView.reloadData()
        let row = configs.count - 1
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.editColumn(0, row: row, with: nil, select: true)
        save()
    }

    @IBAction func removePressed(_ sender: Any) {
        let row = tableView.selectedRow
        guard row >= 0, row < configs.count else { return }
        let removed = configs[row]
        // 清理所有 TargetConfig 引用
        for cfg in configs {
            for (key, target) in cfg.entries {
                if let tc = target as? TargetConfig, tc.config === removed {
                    cfg.entries.removeValue(forKey: key)
                }
            }
        }
        configs.remove(at: row)
        if currentConfig === removed {
            currentConfig = configs.first
        }
        if neutralConfig === removed {
            neutralConfig = nil
        }
        appController?.configsListChanged()
        tableView.reloadData()
        save()
    }

    // MARK: - NSTableViewDataSource

    @objc func numberOfRows(in tableView: NSTableView) -> Int {
        return configs.count
    }

    @objc func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0, row < configs.count else { return nil }
        return configs[row].name
    }

    @objc func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard let newName = object as? String, row >= 0, row < configs.count else { return }
        // 唯一性检查
        if configs.contains(where: { $0.name == newName }) {
            let alert = NSAlert()
            alert.messageText = "请为这个映射取一个唯一的名称"
            alert.runModal()
            tableView.editColumn(0, row: row, with: nil, select: true)
            return
        }
        let oldName = configs[row].name
        configs[row].name = newName
        // 旧 JSON 文件需要删除
        if let oldURL = try? Config.getMappingFilename(for: oldName) {
            try? FileManager.default.removeItem(at: oldURL)
        }
        targetController?.refreshConfigsPreservingSelection(true)
        tableView.reloadData()
        appController?.configsListChanged()
        save()
    }

    @objc func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < configs.count else { return }
        activate(configs[row], forApplication: nil)
    }

    // Swift 5.9 把 shouldEditTableColumn 重命名为 shouldEdit. 用 @objc 显式锁定 Objective-C 选择子
    // 使 NSTableView 能调用到原始协议方法 tableView:shouldEditTableColumn:row:
    @objc(tableView:shouldEditTableColumn:row:)
    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return true
    }
}