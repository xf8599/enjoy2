import Cocoa

/// 主窗口的 3 栏布局容器.
/// - 左: Configs 列表 (sidebar 风格)
/// - 中: Joysticks 列表
/// - 右: Target 编辑面板
/// 替代原先的 NSDrawer + 内嵌 NSSplitView 方案.
final class MainSplitViewController: NSSplitViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // 启用 sidebar 折叠/展开行为
        splitView.autosaveName = "MainSplitView"
        splitView.identifier = NSUserInterfaceItemIdentifier("MainSplitView")
    }
}
