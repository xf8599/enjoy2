import Cocoa
import IOKit.hid

/// 一个 HID 设备的封装.
final class Joystick {
    var vendorId: Int = 0
    var productId: Int = 0
    var index: Int = 0
    var productName: String = ""
    var device: IOHIDDevice!
    var children: [JSAction] = []  // populateActions() 内部填充
    var name: String = ""

    init(device: IOHIDDevice) {
        self.device = device
        // 取 product name
        if let p = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) {
            self.productName = (p as? String) ?? ""
        }
        // vendorId
        if let v = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) {
            self.vendorId = (v as? NSNumber)?.intValue ?? 0
        }
        // productId (OC 原代码此处有 bug, 实际上赋了 vendorId, 保留以保证 stringify 兼容)
        self.productId = self.vendorId
        self.name = self.productName
    }

    func setIndex(_ i: Int) {
        self.index = i
        self.name = "\(self.productName) #\(i + 1)"
    }

    func invalidate() {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        NSLog("Removed a device: \(name)")
    }

    /// 解析所有 HID Element 并构建 JSAction 树.
    func populateActions() {
        let rawElements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let elements = rawElements as? [IOHIDElement] else { return }

        var buttonIdx = 0
        var axisIdx = 0

        for element in elements {
            let type = IOHIDElementGetType(element)
            let usage = IOHIDElementGetUsage(element)
            let usagePage = IOHIDElementGetUsagePage(element)
            let physMax = IOHIDElementGetPhysicalMax(element)
            let physMin = IOHIDElementGetPhysicalMin(element)
            let elName = (IOHIDElementGetName(element) as String?) ?? ""

            // 过滤非输入元素
            // IOHIDElementType 在 Swift 中是结构体, 用 unsafeBitCast 转 UInt32
            let typeRaw = unsafeBitCast(type, to: UInt32.self)
            let miscRaw = unsafeBitCast(kIOHIDElementTypeInput_Misc, to: UInt32.self)
            let axisRaw = unsafeBitCast(kIOHIDElementTypeInput_Axis, to: UInt32.self)
            let buttonRaw = unsafeBitCast(kIOHIDElementTypeInput_Button, to: UInt32.self)
            guard typeRaw == miscRaw
                || typeRaw == axisRaw
                || typeRaw == buttonRaw else { continue }

            let action: JSAction?
            if usagePage == kHIDPage_Button || typeRaw == buttonRaw || (physMax - physMin) == 1 {
                // IOHIDElementGetName 对 Pro Controller 的 IOHIDUserDevice 返回 nil,
                // 用 "Button N" 作为 fallback 让 drawer 能显示文字
                let btnName = elName.isEmpty ? "Button \(buttonIdx + 1)" : elName
                let btn = JSActionButton(index: buttonIdx, name: btnName)
                btn.max = Int(physMax)
                buttonIdx += 1
                action = btn
            } else if usage == 0x39 {
                // Hat switch - SubAction 在 JSActionHat.init 中已创建
                let hat = JSActionHat()
                hat.setMax(Int(physMax))
                action = hat
            } else if usage >= 0x30 && usage < 0x36 {
                // 模拟轴 - SubAction 在 JSActionAnalog.init 中已创建
                let analog = JSActionAnalog(index: axisIdx, name: "Axis \(axisIdx + 1)")
                analog.min = Double(physMin)
                analog.max = Double(physMax)
                axisIdx += 1
                action = analog
            } else {
                continue
            }

            guard let a = action else { continue }
            a.base = self
            a.usage = Int(usage)
            a.cookie = IOHIDElementGetCookie(element)
            children.append(a)
        }
    }

    func stringify() -> String {
        return "\(vendorId)~\(productId)~\(index)"
    }

    func findAction(byCookie cookie: IOHIDElementCookie) -> JSAction? {
        return children.first { $0.cookie == cookie }
    }

    func action(forEvent value: IOHIDValue) -> JSAction? {
        let elt = IOHIDValueGetElement(value)
        return findAction(byCookie: IOHIDElementGetCookie(elt))
    }
}