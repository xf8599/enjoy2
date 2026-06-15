import Cocoa

/// NSOutlineView 行视图 (view-based 模式).
/// XIB 中 column 的 dataCell 内嵌此 customClass, 由 outlineView(_:viewFor:row:) 通过 makeView 复用.
@objc final class JoystickCellView: NSTableCellView {
}
