import Cocoa
import IOKit.hid
import Carbon

/// 手柄集合管理器 + 事件分发器.
final class JoystickController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var targetController: TargetController!
    @IBOutlet weak var configsController: ConfigsController!

    /// 已知手柄设备
    var joysticks: [Joystick] = []
    /// 连续型 Target (鼠标移动) 列表, 由 80Hz Timer 驱动
    var runningTargets: [Target] = []
    /// 鼠标移动时是否仅作用于前台窗口
    var frontWindowOnly = false
    /// 当前鼠标位置 (NSEvent.mouseLocation)
    var mouseLoc: NSPoint = .zero
    /// 当前选中的 JSAction (供 TargetController 加载)
    var selectedAction: Any?
    /// 在 C 回调中标记 outlineView 选中是否由程序触发 (避免选中事件递归)
    private var programmaticallySelecting = false

    private var hidManager: IOHIDManager?
    private var timer: Timer?

    // MARK: - 初始化与销毁

    override init() {
        super.init()
        programmaticallySelecting = false
        mouseLoc.x = 0
        mouseLoc.y = 0
    }

    deinit {
        timer?.invalidate()
        if let m = hidManager {
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    func setup() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        let criteria: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: NSNumber(value: kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: NSNumber(value: kHIDUsage_GD_Joystick)
            ],
            [
                kIOHIDDeviceUsagePageKey as String: NSNumber(value: kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: NSNumber(value: kHIDUsage_GD_GamePad)
            ],
            [
                kIOHIDDeviceUsagePageKey as String: NSNumber(value: kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: NSNumber(value: kHIDUsage_GD_MultiAxisController)
            ],
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, criteria as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        let ud = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, addCallback, ud)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removeCallback, ud)

        // 80Hz 定时器驱动连续型 Target
        let timer = Timer(timeInterval: 1.0/80.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.mouseLoc = NSEvent.mouseLocation
            for target in self.runningTargets {
                target.update(with: self)
            }
        }
        self.timer = timer
        RunLoop.current.add(timer, forMode: .common)

        // dark mode 修复: XIB 中 NSOutlineView 是 cell-based 模式, NSTextFieldCell 在
        // dark mode 下文字默认黑色不可见. cell-based 是 Apple 已废弃的模式, 但 XIB
        // 无法用 UI 转 view-based (Xcode 14+ 已移除 Convert 菜单).
        // 运行时重建一个 view-based NSOutlineView 替换 XIB 加载的实例.
        DispatchQueue.main.async { [weak self] in
            self?.replaceOutlineViewWithViewBased()
        }
    }

    /// 运行时把 XIB 加载的 cell-based NSOutlineView 替换为代码创建的 view-based 版本.
    /// 新版本由 outlineView(_:viewFor:row:) 提供 NSTableCellView (含 NSTextField,
    /// dynamic textColor 自动适配 dark/light mode).
    private func replaceOutlineViewWithViewBased() {
        guard let old = self.outlineView, let superview = old.superview else { return }

        let frame = old.frame
        let autoresizingMask = old.autoresizingMask

        // 移除旧 column (NSOutlineView 要求先 setOutlineTableColumn: 指向其他 column 再 remove)
        // Swift 暴露的 outlineTableColumn 是 readonly, 用 performSelector 调 OC setter.
        // 注意: 不能传 nil, 必须传一个非 nil 的临时 column, 否则 NSOutlineView 仍会拒绝 remove.
        let tempCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("__e3_temp__"))
        let sel = NSSelectorFromString("setOutlineTableColumn:")
        if old.responds(to: sel) {
            _ = old.perform(sel, with: tempCol)
        }
        for col in old.tableColumns where col !== tempCol {
            old.removeTableColumn(col)
        }

        // 移除旧 outlineView, 准备替换
        old.removeFromSuperview()

        // 创建 view-based NSOutlineView
        let new = NSOutlineView(frame: frame)
        new.autoresizingMask = autoresizingMask
        // column 宽度必须 ≤ outlineView frame.width - scroller 宽, 否则横向溢出且 scrollView 检测不到
        // frame.width=180, scroller=16, clipView border=1, 可视 ≈ 163
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        col.width = 160
        col.minWidth = 16
        col.maxWidth = 1000
        col.isEditable = false
        new.addTableColumn(col)
        new.outlineTableColumn = col
        new.autoresizesOutlineColumn = true
        new.indentationPerLevel = 13
        new.allowsMultipleSelection = false
        new.allowsExpansionToolTips = true
        new.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        new.backgroundColor = NSColor.controlBackgroundColor
        new.gridColor = NSColor.separatorColor
        // 隐藏 column header — 否则 view-based outlineView 会显示 "Field" 标题行,
        // 占去顶部 17 像素, 既多余又难看 (我们只需要显示设备/动作层级树, 不需要表头)
        new.headerView = nil

        // 把 new 装到 clipView. **必须用 documentView = new, 不能仅 addSubview**.
        // NSClipView 的 contentSize 由 documentView.frame 决定, scrollView 的可滚动
        // 区域也是基于 documentView. 如果只用 addSubview, clipView.documentView 仍指向
        // 已被 removeFromSuperview 的 old, 即使 new 加了几百行, scrollView 也不知道
        // 需要滚动 -> verticalScroller 不显示, mouseWheel 也不响应. (PageDown 能用
        // 是因为它走 responder chain 的 moveDown, 跟 scrollView 无关)
        if let clip = superview as? NSClipView {
            clip.documentView = new
        } else {
            superview.addSubview(new)
        }

        // 转移 dataSource / delegate 引用
        new.dataSource = self
        new.delegate = self

        // 替换 outlineView 引用 (weak var 可重新赋值)
        self.outlineView = new

        // 强制让 enclosing scrollView 显示 vertical scroller, 避免 XIB 设置在运行时被覆盖
        if let sv = new.enclosingScrollView {
            sv.hasVerticalScroller = true
            sv.autohidesScrollers = false
            // scroller 宽度 + autoresizing 重新设置
            if let vs = sv.verticalScroller {
                vs.autoresizingMask = [.minXMargin, .height]
            }
            if let hs = sv.horizontalScroller {
                hs.autoresizingMask = [.width, .maxYMargin]
            }
        }

        // 重新加载数据并展开
        new.reloadData()
        // 通知 tableView 重新计算 row 数量, 触发 scrollView 更新 contentSize
        new.noteNumberOfRowsChanged()
        new.layoutSubtreeIfNeeded()

        // 强制 scrollView 重新计算 contentSize 和重新布局 scroller.
        // noteNumberOfRowsChanged 改变了 outlineView.frame, 但 scrollView 不会自动
        // 调 reflectScrolledClipView, 需要手动调一次让 scroller 出现.
        if let sv = new.enclosingScrollView {
            sv.reflectScrolledClipView(sv.contentView)
            sv.tile()
        }

        // 让新 outlineView 接管 firstResponder. 旧 outlineView 已经被 removeFromSuperview,
        // 之前如果它是 firstResponder, 现在 firstResponder 状态已经失效. 必须在
        // 下一个 runloop 等 layout 完成后再设置, 否则 setMakeFirstResponder 会失败.
        if let win = new.window {
            DispatchQueue.main.async { [weak new] in
                guard let new = new else { return }
                win.makeFirstResponder(new)
            }
        }
    }

    // MARK: - 工具

    func findAvailableIndex(for joystick: Joystick) -> Int {
        // OC 原逻辑: 同时检查 vendorId, productId, index
        for index in 0..<Int.max {
            var available = true
            for js2 in joysticks {
                if js2.vendorId == joystick.vendorId
                    && js2.productId == joystick.productId
                    && js2.index == index {
                    available = false
                    break
                }
            }
            if available { return index }
        }
        return 0
    }

    func findJoystick(byRef device: IOHIDDevice) -> Joystick? {
        return joysticks.first { $0.device == device }
    }

    /// 展开 outlineView 中指定 item 的所有父节点并选中它.
    /// SubAction 自身没有 children, 必须先展开父 JSAction 才能让 SubAction row 可见.
    func expandRecursive(_ item: Any) {
        if let sub = item as? SubAction, let base = sub.base {
            expandRecursive(base)
        } else if let action = item as? JSAction, let base = action.base {
            expandRecursive(base)
        }
        outlineView.expandItem(item)
    }

    /// 选中 handler (SubAction 或 JSAction) 时, 通知 targetController 加载 UI.
    /// 兜底: 如果 handler 是 SubAction 但父 JSAction 未展开导致 row = -1, 回退到父 JSAction.
    func selectHandler(_ handler: Any) {
        programmaticallySelecting = true
        var target: Any = handler
        var row = outlineView.row(forItem: target)
        if row < 0, let sub = target as? SubAction, let base = sub.base {
            target = base
            row = outlineView.row(forItem: target)
        }
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        }
    }

    /// 决定当前 outlineView 选中项对应的 action, 用于 TargetController.load().
    func determineSelectedAction() -> Any? {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return nil }
        if let action = item as? JSAction, !action.subActions.isEmpty {
            return nil
        }
        if item is Joystick { return nil }
        return item
    }

    // MARK: - NSOutlineView DataSource

    @objc func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let n: Int
        if item == nil {
            n = joysticks.count
        } else if let js = item as? Joystick {
            n = js.children.count
        } else if let action = item as? JSAction {
            n = action.subActions.count
        } else {
            n = 0
        }
        return n
    }

    @objc func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return joysticks[index]
        }
        if let js = item as? Joystick {
            return js.children[index]
        }
        if let action = item as? JSAction {
            return action.subActions[index]
        }
        return ""
    }

    @objc func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if item is Joystick { return true }
        if let action = item as? JSAction, !action.subActions.isEmpty { return true }
        return false
    }

    /// view-based 模式下由系统调用, 返回每行的视图.
    /// NSTextField 自带 dynamic textColor, 在 dark/light mode 都能正确显示, 避免 cell-based
    /// 下 NSTextFieldCell 在 dark mode 文字变黑不可见的问题.
    @objc(outlineView:viewForTableColumn:item:)
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("JoystickCellView")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 17))
            cell.identifier = identifier
            let tf = NSTextField(frame: cell.bounds)
            tf.autoresizingMask = [.width]
            tf.isBezeled = false
            tf.drawsBackground = false
            tf.isEditable = false
            tf.isSelectable = false
            tf.lineBreakMode = .byTruncatingTail
            cell.addSubview(tf)
            cell.textField = tf
        }

        let s: String
        if let js = item as? Joystick { s = js.name }
        else if let action = item as? JSAction { s = action.name }
        else if let sub = item as? SubAction { s = sub.name }
        else { s = "" }
        cell.textField?.stringValue = s
        return cell
    }

    @objc func outlineViewSelectionDidChange(_ notification: Notification) {
        targetController?.reset()
        selectedAction = determineSelectedAction()
        targetController?.load()
        if programmaticallySelecting {
            targetController?.focusKey()
        }
        programmaticallySelecting = false
    }
}

// MARK: - 顶层 C 回调 (顶层 @convention(c) 闭包)

private let addCallback: IOHIDDeviceCallback = { ctx, _, _, device in
    guard let ctx = ctx else { return }
    let jc = Unmanaged<JoystickController>.fromOpaque(ctx).takeUnretainedValue()

    IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDDeviceRegisterInputValueCallback(device, inputCallback, ctx)

    let js = Joystick(device: device)
    js.setIndex(jc.findAvailableIndex(for: js))
    js.populateActions()
    jc.joysticks.append(js)

    DispatchQueue.main.async {
        jc.outlineView.reloadData()
    }
}

private let removeCallback: IOHIDDeviceCallback = { ctx, _, _, device in
    guard let ctx = ctx else { return }
    let jc = Unmanaged<JoystickController>.fromOpaque(ctx).takeUnretainedValue()
    guard let match = jc.findJoystick(byRef: device) else { return }

    // OC 中是 removeObject:, 这里用引用相等
    jc.joysticks.removeAll { $0 === match }
    match.invalidate()

    DispatchQueue.main.async {
        jc.outlineView.reloadData()
    }
}

private let inputCallback: IOHIDValueCallback = { ctx, _, sender, value in
    guard let ctx = ctx else { return }
    let jc = Unmanaged<JoystickController>.fromOpaque(ctx).takeUnretainedValue()

    let device = unsafeBitCast(sender, to: IOHIDDevice.self)
    guard let js = jc.findJoystick(byRef: device) else { return }

    let ac = NSApplication.shared.delegate as? ApplicationController
    if ac?.active == true {
        // 映射模式
        guard let mainAction = js.action(forEvent: value) else { return }
        mainAction.notifyEvent(value)
        if let analog = mainAction as? JSActionAnalog {
            analog.notifyEventValueUpdate(value)
        }

        // 遍历 subActions (Button 无 subAction, 则用 mainAction 自己)
        let actions: [Any] = mainAction.subActions.isEmpty ? [mainAction] : mainAction.subActions
        for sub in actions {
            // 解析 target (支持 JSAction 和 SubAction 两种 key)
            let target: Target?
            if let subAction = sub as? SubAction {
                target = jc.configsController?.currentConfig?.getTarget(forSubAction: subAction)
            } else if let action = sub as? JSAction {
                target = jc.configsController?.currentConfig?.getTarget(for: action)
            } else {
                target = nil
            }
            guard let target = target else { continue }

            // 判断 subAction 的 active 状态
            let isActive: Bool
            if let subAction = sub as? SubAction {
                isActive = subAction.active
            } else if let action = sub as? JSAction {
                isActive = action.active
            } else {
                isActive = false
            }

            if target.running != isActive {
                if isActive {
                    target.trigger(with: jc)
                } else {
                    target.untrigger(with: jc)
                }
                target.running = isActive
            }

            // 连续型 Target (鼠标移动) 需要 inputValue
            if let analog = mainAction as? JSActionAnalog {
                target.inputValue = analog.currentRealValue

                if target.isContinuous && target.running {
                    if !jc.runningTargets.contains(where: { $0 === target }) {
                        jc.runningTargets.append(target)
                    }
                }
            }
        }
        // 清理不活动的 continuous target
        jc.runningTargets.removeAll { !$0.running }
    } else if NSApplication.shared.isActive, NSApplication.shared.mainWindow?.isVisible == true {
        // UI 导航模式.
        // 区分"按钮同 report 里的 stale axis"和"用户主动摇杆":
        // - 先调 mainAction.notifyEvent 更新 active 状态
        // - axis: 仅在 value 超出死区 (findSubAction 返回 Low/High/Analog subAction) 时响应.
        //   死区内 (stale value, 静止) findSubAction 返回 nil, 不响应.
        //   这样按 B 按钮时, 同 report 里的 axis value 接近 0 (死区内) 被自然过滤, 不会二次跳转.
        //   真正摇动摇杆时 value 超出死区, 正常选中 subAction.
        // - button/hat: 保留原行为, findSubAction 返回 self 或方向 subAction, 选中.
        guard let mainAction = js.action(forEvent: value) else { return }
        mainAction.notifyEvent(value)
        if let analog = mainAction as? JSActionAnalog {
            analog.notifyEventValueUpdate(value)
        }
        if mainAction is JSActionAnalog {
            // axis: 只在 dead zone 外响应
            guard let sub = mainAction.findSubAction(for: value) else { return }
            let handler: Any = sub
            DispatchQueue.main.async {
                jc.expandRecursive(handler)
                jc.selectHandler(handler)
            }
        } else {
            let handler: Any = mainAction.findSubAction(for: value) ?? mainAction
            DispatchQueue.main.async {
                jc.expandRecursive(handler)
                jc.selectHandler(handler)
            }
        }
    }
}