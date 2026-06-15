import Cocoa

/// Configs 列表 sidebar 视图控制器.
/// 视图来自 NIB (MainMenu.xib 中 splitView 最左 panel).
final class ConfigsSidebarViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // dark mode 适配由 ConfigsController.applyDarkModeAppearance() 在 awakeFromNib 中处理
    }
}
