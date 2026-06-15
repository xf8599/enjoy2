import Cocoa

/// dark mode 下 NSTableView 的列头强制使用深色背景 + 深色边框.
final class DarkTableHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        // 深色背景
        NSColor(calibratedWhite: 0.10, alpha: 1.0).setFill()
        dirtyRect.fill()

        // 底部分割线
        NSColor(calibratedWhite: 0.20, alpha: 1.0).setFill()
        NSRect(x: 0, y: 0, width: dirtyRect.width, height: 1).fill()
    }
}