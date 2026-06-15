import Cocoa
import Carbon

final class TargetController: NSObject {
    @IBOutlet weak var title: NSTextField!
    @IBOutlet weak var keyInput: KeyInputTextView!
    @IBOutlet weak var radioButtons: NSMatrix!
    @IBOutlet weak var mouseDirSelect: NSSegmentedControl!
    @IBOutlet weak var mouseBtnSelect: NSSegmentedControl!
    @IBOutlet weak var scrollDirSelect: NSSegmentedControl!
    @IBOutlet weak var configPopup: NSPopUpButton!
    @IBOutlet weak var configsController: ConfigsController!
    @IBOutlet weak var joystickController: JoystickController!

    /// 当前编辑的 JSAction / SubAction (供 commit 使用)
    private(set) var currentJSAction: Any?
    /// 兼容 OC 中 currentJsaction 拼写
    var selectedAction: Any? {
        return currentJSAction
    }

    var isEnabled: Bool {
        get { radioButtons.isEnabled }
        set {
            radioButtons.isEnabled = newValue
            keyInput?.enabled = newValue
            mouseDirSelect?.isEnabled = newValue
            mouseBtnSelect?.isEnabled = newValue
            scrollDirSelect?.isEnabled = newValue
            configPopup?.isEnabled = newValue
        }
    }

    // MARK: - 加载

    func load() {
        let jsaction = joystickController?.selectedAction
        currentJSAction = jsaction
        guard let action = jsaction else {
            isEnabled = false
            title.stringValue = ""
            return
        }
        isEnabled = true

        let target: Target? = lookupTarget(for: action)

        // 构建 actFullName (沿 base 链向上)
        var actFullName = actionName(of: action)
        var current: Any? = action
        while let base = (current as? JSAction)?.base {
            actFullName = "\(actionName(of: base)) > \(actFullName)"
            current = base
        }
        title.stringValue = "\(configsController?.currentConfig?.name ?? "") > \(actFullName)"

        // 根据 target 类型设置 UI
        if target == nil {
            resetRadios()
        } else if let t = target as? TargetKeyboard {
            selectRadio(at: 1)
            keyInput.vk = Int(t.vk)
        } else if let t = target as? TargetConfig {
            selectRadio(at: 2)
            for (i, c) in configsController.configs.enumerated() {
                if c === t.config {
                    configPopup.selectItem(at: i)
                    break
                }
            }
        } else if let t = target as? TargetMouseMove {
            selectRadio(at: 3)
            mouseDirSelect.selectedSegment = t.dir
        } else if let t = target as? TargetMouseBtn {
            selectRadio(at: 4)
            mouseBtnSelect.selectedSegment = t.which
        } else if let t = target as? TargetMouseScroll {
            selectRadio(at: 5)
            scrollDirSelect.selectedSegment = t.howMuch < 0 ? 0 : 1
        } else if target is TargetToggleMouseScope {
            selectRadio(at: 6)
        }
    }

    private func lookupTarget(for action: Any) -> Target? {
        guard let config = configsController?.currentConfig else { return nil }
        if let sub = action as? SubAction {
            return config.getTarget(forSubAction: sub)
        }
        if let act = action as? JSAction {
            return config.getTarget(for: act)
        }
        return nil
    }

    private func actionName(of action: Any) -> String {
        if let act = action as? JSAction { return act.name }
        if let sub = action as? SubAction { return sub.name }
        return ""
    }

    private func resetRadios() {
        radioButtons.selectCell(atRow: 0, column: 0)
        mouseDirSelect.selectedSegment = 0
        mouseBtnSelect.selectedSegment = 0
        scrollDirSelect.selectedSegment = 0
    }

    private func selectRadio(at row: Int) {
        radioButtons.selectCell(atRow: row, column: 0)
    }

    // MARK: - 提交 (任意 UI 变化都调)

    func commit() {
        guard let action = currentJSAction,
              let config = configsController?.currentConfig else { return }
        let row = radioButtons.selectedRow
        let target: Target?
        switch row {
        case 0:
            target = nil
        case 1:
            // Key
            if keyInput.hasKey {
                let t = TargetKeyboard()
                t.vk = CGKeyCode(keyInput.vk)
                t.descr = keyInput.descr
                target = t
            } else {
                target = nil
            }
        case 2:
            let t = TargetConfig()
            let idx = configPopup.indexOfSelectedItem
            if idx >= 0 && idx < configsController.configs.count {
                t.config = configsController.configs[idx]
            }
            target = t
        case 3:
            let t = TargetMouseMove()
            t.dir = mouseDirSelect.selectedSegment
            target = t
        case 4:
            let t = TargetMouseBtn()
            t.which = mouseBtnSelect.selectedSegment
            target = t
        case 5:
            let t = TargetMouseScroll()
            t.howMuch = scrollDirSelect.selectedSegment == 0 ? -1 : 1
            target = t
        case 6:
            target = TargetToggleMouseScope()
        default:
            target = nil
        }

        if let sub = action as? SubAction {
            config.setTarget(target, forStringified: sub.stringify())
        } else if let act = action as? JSAction {
            if let target = target {
                config.entries[act.stringify()] = target
            } else {
                config.entries.removeValue(forKey: act.stringify())
            }
        }

        configsController.save()
    }

    // MARK: - IBAction

    @IBAction func radioChanged(_ sender: Any) {
        if let resp = sender as? NSResponder {
            NSApp.mainWindow?.makeFirstResponder(resp)
        }
        commit()
    }

    @IBAction func mdirChanged(_ sender: Any) {
        selectRadio(at: 3)
        if let resp = sender as? NSResponder {
            NSApp.mainWindow?.makeFirstResponder(resp)
        }
        commit()
    }

    @IBAction func mbtnChanged(_ sender: Any) {
        selectRadio(at: 4)
        if let resp = sender as? NSResponder {
            NSApp.mainWindow?.makeFirstResponder(resp)
        }
        commit()
    }

    @IBAction func sdirChanged(_ sender: Any) {
        selectRadio(at: 5)
        if let resp = sender as? NSResponder {
            NSApp.mainWindow?.makeFirstResponder(resp)
        }
        commit()
    }

    @IBAction func configChosen(_ sender: Any) {
        selectRadio(at: 2)
        commit()
    }

    /// KeyInputTextView 捕获到键时调
    func keyChanged() {
        selectRadio(at: 1)
        commit()
    }

    func reset() {
        keyInput.clear()
        resetRadios()
        refreshConfigsPreservingSelection(false)
    }

    func focusKey() {
        NSApp.mainWindow?.makeFirstResponder(keyInput)
    }

    func refreshConfigsPreservingSelection(_ preserve: Bool) {
        let initialIndex = configPopup.indexOfSelectedItem
        configPopup.removeAllItems()
        for cfg in configsController.configs {
            configPopup.addItem(withTitle: cfg.name)
        }
        if preserve {
            configPopup.selectItem(at: initialIndex)
        }
    }
}