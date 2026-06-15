import Cocoa
import Carbon

@objc final class ApplicationController: NSObject, NSApplicationDelegate {
    @IBOutlet weak var jsController: JoystickController!
    @IBOutlet weak var targetController: TargetController!
    @IBOutlet weak var configsController: ConfigsController!
    @IBOutlet weak var mainWindow: NSWindow!
    @IBOutlet weak var activeButton: NSToolbarItem!
    @IBOutlet weak var activeMenuItem: NSMenuItem!
    @IBOutlet weak var dockMenuBase: NSMenu!

    /// 映射开关 (active=YES 时手柄事件触发 Target)
    var active: Bool = false
    /// 用于 ProcessInfo 后台活动资格
    private var activityToken: Any?

    // MARK: - NSApplicationDelegate / NIB 生命周期

    @objc override func awakeFromNib() {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: ProcessInfo.ActivityOptions(rawValue: 0x00FFFFFF),
            reason: "Let joystick commands fire in the background"
        )
        // ibtool 在 cell-based 模式下不序列化 NSButtonCell 的 NSTextColor,
        // 必须在运行时强制设置, 否则 dark mode 下文字是黑色看不清.
        applyDarkModeTextColorFix()
    }

    /// 强制设置主窗口 + 抽屉内所有 NSButton 的文字颜色为 controlTextColor.
    /// (ibtool 在 cell-based 模式下不保存 NSButtonCell 的 NSTextColor, NIB 修复无效;
    ///  NSTextFieldCell 在 NIB 中保留 textColor, 不需要此修复)
    private func applyDarkModeTextColorFix() {
        var visited = Set<ObjectIdentifier>()

        func fix(view: NSView) {
            let id = ObjectIdentifier(view)
            if visited.contains(id) { return }
            visited.insert(id)
            if let button = view as? NSButton, let title = button.title as String?, !title.isEmpty {
                let attr = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.controlTextColor]
                )
                button.attributedTitle = attr
                button.attributedAlternateTitle = attr
            }
            for sub in view.subviews {
                fix(view: sub)
            }
        }

        if let win = mainWindow?.contentView { fix(view: win) }
    }

    @objc func applicationDidFinishLaunching(_ note: Notification) {
        // 主动检查并引导辅助功能授权
        // ad-hoc 签名 app 在 macOS 上不会自动弹授权框, 必须在启动时主动调
        // AXIsProcessTrustedWithOptions, 系统才会显示 "enjoy3 想要控制您的电脑" 对话框
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        NSSetUncaughtExceptionHandler { e in NSLog("Uncaught: \(e.description)") }

        // 强制使用 XIB 定义的窗口尺寸 (避免 macOS state restoration 用之前的尺寸覆盖)
        // 3 栏布局: 180 (Configs) + 180 (Joysticks) + 422 (Editor) = 782
        // 高度 400 → 520 (+30%)
        if let win = mainWindow {
            win.setContentSize(NSSize(width: 782, height: 520))
            // 居中
            if let screen = win.screen {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.origin.x + (screenFrame.size.width - 782) / 2
                let y = screenFrame.origin.y + (screenFrame.size.height - 520) / 2
                win.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        jsController.setup()
        // 旧的 NSDrawer 已删除, config 列表现在在主窗口最左 panel 中, 无需 drawer.open()
        targetController.isEnabled = false
        setActive(false)
        configsController.load()

        // 安装 Carbon 应用切换事件
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassApplication),
            eventKind: UInt32(kEventAppFrontSwitched)
        )
        let ud = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            appSwitchCallback,
            1,
            &spec,
            ud,
            nil
        )
    }

    @objc func applicationWillTerminate(_ note: Notification) {
        configsController.save()
    }

    @objc func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.makeKeyAndOrderFront(self)
        return true
    }

    // MARK: - 状态切换

    func setActive(_ newActive: Bool) {
        active = newActive
        activeButton.label = newActive ? "Stop" : "Start"
        activeButton.image = NSImage(named: newActive ? "NSStopProgressFreestandingTemplate" : "NSGoRightTemplate")
        activeMenuItem.state = newActive ? .on : .off
    }

    @IBAction func toggleActivity(_ sender: Any) {
        setActive(!active)
    }

    // MARK: - Dock 菜单

    func configsListChanged() {
        while dockMenuBase.numberOfItems > 2 {
            dockMenuBase.removeItem(at: dockMenuBase.numberOfItems - 1)
        }
        for cfg in configsController.configs {
            let item = dockMenuBase.addItem(
                withTitle: cfg.name,
                action: #selector(chooseConfig(_:)),
                keyEquivalent: ""
            )
            item.target = self
        }
        configChanged()
    }

    func configChanged() {
        let current = configsController.currentConfig
        let configs = configsController.configs
        for (i, cfg) in configs.enumerated() {
            let idx = 2 + i
            // 防御: dock menu 项可能还没填充 (例如 configsListChanged 之前的早期调用)
            guard idx < dockMenuBase.numberOfItems else { break }
            (dockMenuBase.item(at: idx))?.state = (cfg === current) ? .on : .off
        }
    }

    @objc func chooseConfig(_ sender: Any) {
        guard let menuItem = sender as? NSMenuItem else { return }
        let idx = dockMenuBase.index(of: menuItem) - 2
        guard idx >= 0 && idx < configsController.configs.count else { return }
        configsController.activate(configsController.configs[idx], forApplication: nil)
    }
}

// MARK: - Carbon EventHandler 回调 (顶层 C 函数)

private let appSwitchCallback: EventHandlerUPP = { _, _, userData in
    guard let userData = userData else { return noErr }
    let ac = Unmanaged<ApplicationController>.fromOpaque(userData).takeUnretainedValue()
    let workspace = NSWorkspace.shared
    let activeApp = workspace.activeApplication
    var psn = ProcessSerialNumber()
    var appName = ""
    if let dict: [String: Any] = activeApp as? [String: Any] {
        let low = (dict["NSApplicationProcessSerialNumberLow"] as? Int) ?? 0
        let high = (dict["NSApplicationProcessSerialNumberHigh"] as? Int) ?? 0
        psn.lowLongOfPSN = UInt32(low)
        psn.highLongOfPSN = UInt32(high)
        appName = (dict["NSApplicationName"] as? String) ?? ""
    }
    ac.configsController.applicationSwitched(to: appName, psn: psn)
    return noErr
}