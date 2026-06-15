import Cocoa

@objc final class KeyInputTextView: NSTextView {
    @IBOutlet weak var targetController: TargetController?

    private(set) var hasKey = false
    var vk: Int = -1 {
        didSet {
            hasKey = (vk >= 0)
            descr = CKeys.name(for: vk)
            self.string = descr
        }
    }
    private(set) var descr: String = ""

    var enabled: Bool = false {
        didSet {
            if !enabled, window?.firstResponder === self {
                window?.makeFirstResponder(nil)
            }
            updateBackground()
        }
    }

    func clear() {
        vk = -1
        hasKey = false
        descr = ""
        string = ""
    }

    override var acceptsFirstResponder: Bool { enabled }

    private func updateBackground() {
        let isFirstResponder = (window?.firstResponder === self)
        backgroundColor = (enabled && isFirstResponder)
            ? NSColor.selectedTextBackgroundColor
            : NSColor.textBackgroundColor
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        updateBackground()
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        updateBackground()
        return ok
    }

    private func pressed(_ keyCode: Int) {
        vk = keyCode
        window?.makeFirstResponder(nil)
        targetController?.keyChanged()
    }

    override func keyDown(with event: NSEvent) {
        if !event.isARepeat {
            pressed(Int(event.keyCode))
        }
    }

    override func flagsChanged(with event: NSEvent) {
        pressed(Int(event.keyCode))
    }
}