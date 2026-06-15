# enjoy3 Objective-C → Swift 迁移 · 详细执行手册

> **使用说明**: 本文件是完整的、可独立执行的迁移手册. 任意新会话只需读此文件即可继续推进, 无需依赖之前的上下文. 完成后建议把此文件复制到项目目录 `/Users/xufei/Documents/claudecode/enjoy3/MIGRATION_PLAN.md`.

---

## 目录

1. [项目背景与目标](#1-项目背景与目标)
2. [已确认的关键决策](#2-已确认的关键决策)
3. [前置工作:环境与工具](#3-前置工作环境与工具)
4. [目录与文件组织](#4-目录与文件组织)
5. [整体执行流程(7 个阶段)](#5-整体执行流程7-个阶段)
6. [阶段 1:工程骨架](#6-阶段-1工程骨架)
7. [阶段 2:核心数据模型](#7-阶段-2核心数据模型)
8. [阶段 3:手柄层](#8-阶段-3手柄层)
9. [阶段 4:输出层](#9-阶段-4输出层)
10. [阶段 5:UI 控制器](#10-阶段-5ui-控制器)
11. [阶段 6:XIB 类名更新](#11-阶段-6xib-类名更新)
12. [阶段 7:编译验证与 bug 修复](#12-阶段-7编译验证与-bug-修复)
13. [关键技术细节参考](#13-关键技术细节参考)
14. [OC 文件 → Swift 文件映射表](#14-oc-文件--swift-文件映射表)
15. [常见 bug 与修复手册](#15-常见-bug-与修复手册)
16. [端到端验证清单](#16-端到端验证清单)

---

## 1. 项目背景与目标

**enjoy3** 是 macOS Cocoa 应用, 把 USB/蓝牙手柄 (Joystick/GamePad/MultiAxisController) 的按钮、摇杆、十字键事件实时映射为键盘/鼠标事件.

**功能清单** (必须完整保留):
- IOKit HID 订阅手柄插拔 + 按键/轴/帽开关事件
- 6 种 Target 输出: 键盘按键 / 切换配置 / 鼠标移动 (连续) / 鼠标左右键 / 滚轮 / 切换鼠标作用域
- JSON 配置文件, 存于 `~/Library/Application Support/enjoy3/mappings/`, `format="enjoy3-1.1"`
- 多个 Config (mapping), 可在 Dock 菜单切换, 可按应用自动切换
- 80Hz CFRunLoopTimer 驱动连续型 Target (鼠标移动)
- 中英文本地化 (英文 + 简体中文)
- Sparkle 1.x 自动更新 (appcast S3 + DSA 验签)
- 工具栏 Start/Stop 开关

**目标**: 把全部业务代码从 Objective-C (MRC) 改写为 Swift, 工程从老 pbxproj 升级为 XcodeGen, 清理死代码 (JSONKit + v1.1 兼容), 同时功能 100% 保持.

---

## 2. 已确认的关键决策

| 项 | 决策 |
|---|---|
| UI 层 | 保留 4 个 XIB, 仅把 OC 类引用改为 Swift 类 (customModule="enjoy3") |
| 部署目标 | macOS 12 (Monterey) |
| 工程生成 | XcodeGen (`project.yml`) 替换旧 `.xcodeproj` |
| 清理范围 | 删除 `JSONKit/` 目录 + `ver11LoadConfigsFrom:` 旧版兼容 + `enjoy3_Prefix.pch` |
| 代码签名 | ad-hoc (`CODE_SIGN_IDENTITY = "-"`) |
| Bundle ID | `net.tunah.enjoy3` (与 Info.plist 保持一致) |
| 架构 | arm64 单架构 (沿用 build.sh 的 `ONLY_ACTIVE_ARCH=YES`) |
| 协议 | 抽象基类保留 class 继承, 不改 enum (因为需要 NSObject 子类化和对象引用) |
| JSON | 仍用 `JSONSerialization` 保留原 `format="enjoy3-1.1"` 格式, 不用 Codable |
| 内存管理 | MRC → ARC 自动 |

---

## 3. 前置工作:环境与工具

### 3.1 检查工具链
```bash
# Xcode 命令行工具
xcode-select --install

# 检查 xcodebuild 版本
xcodebuild -version
# 期望输出: Xcode 14.0+ (含 macOS 12 SDK)

# 安装 xcodegen (如未安装)
brew install xcodegen
xcodegen --version  # 应 >= 2.38
```

### 3.2 备份原始项目
```bash
cd /Users/xufei/Documents/claudecode/enjoy3
# 把整个 .xcodeproj 备份到 .backup 目录(便于回退对比)
cp -R Enjoy2.xcodeproj Enjoy2.xcodeproj.backup
```

### 3.3 当前项目结构速查
```
/Users/xufei/Documents/claudecode/enjoy3/
├── Enjoy2.xcodeproj/           # 旧工程 (待删除)
├── JSONKit/                    # 死代码 (待删除)
├── English.lproj/MainMenu.xib  # 需改 customClass
├── zh-Hans.lproj/MainMenu.xib  # 需改 customClass
├── English.lproj/TranslationWindow.xib  # 无 customClass
├── zh-Hans.lproj/TranslationWindow.xib  # 无 customClass
├── Sparkle.framework/          # 嵌入
├── Updates/                    # appcast + changelog
├── JoystickImages/dualshock.png  # 资源
├── Info.plist                  # 保留
├── enjoy3_Prefix.pch           # 待删除
├── icon.icns, Credits.rtf, dsa_pub.pem, README.md, license.txt  # 资源
├── build.sh                    # 需更新
└── *.h / *.m (20+ 业务文件)    # 翻译为 Swift
```

---

## 4. 目录与文件组织

### 4.1 新建目录
```bash
cd /Users/xufei/Documents/claudecode/enjoy3
mkdir -p Sources/{App,Targets,Actions,Devices,Config,UI}
```

### 4.2 最终文件结构
```
/Users/xufei/Documents/claudecode/enjoy3/
├── project.yml                 # NEW: XcodeGen 配置
├── Sources/
│   ├── enjoy3-Bridging-Header.h    # NEW: 暴露 C/OC 框架给 Swift
│   ├── App/
│   │   └── main.swift              # NEW: 入口
│   ├── Targets/
│   │   ├── Target.swift            # NEW: 基类 + 工厂
│   │   ├── TargetKeyboard.swift
│   │   ├── TargetConfig.swift
│   │   ├── TargetMouseMove.swift
│   │   ├── TargetMouseBtn.swift
│   │   ├── TargetMouseScroll.swift
│   │   └── TargetToggleMouseScope.swift
│   ├── Actions/
│   │   ├── JSAction.swift          # 含 SubAction
│   │   ├── JSActionButton.swift
│   │   ├── JSActionAnalog.swift
│   │   └── JSActionHat.swift
│   ├── Devices/
│   │   ├── Joystick.swift
│   │   └── JoystickController.swift
│   ├── Config/
│   │   ├── Config.swift
│   │   └── ConfigsController.swift
│   ├── UI/
│   │   ├── ApplicationController.swift
│   │   ├── TargetController.swift
│   │   └── KeyInputTextView.swift
│   └── CKeys.swift
├── (保留) Info.plist, English.lproj/, zh-Hans.lproj/, icon.icns, Credits.rtf,
│        dsa_pub.pem, Sparkle.framework/, JoystickImages/, Updates/, README.md, license.txt
├── (删除) Enjoy2.xcodeproj/, JSONKit/, enjoy3_Prefix.pch, *.h, *.m, main.m
└── (修改) build.sh
```

---

## 5. 整体执行流程(7 个阶段)

| 阶段 | 任务 | 预计工时 | 验证标志 |
|---|---|---|---|
| 1 | 工程骨架: xcodegen + 最小 main.swift | 0.5 d | 空 Swift 壳可编译 |
| 2 | 核心数据模型: Target + JSAction + Config | 0.5 d | 6 种 Target 字符串往返与 OC 一致 |
| 3 | 手柄层: Joystick + JoystickController | 0.5-1 d | 插入手柄能识别 |
| 4 | 输出层: 各 Target trigger/untrigger | 含于阶段 2 | 键盘/鼠标事件能合成 |
| 5 | UI 控制器: 3 个 Controller + KeyInputTextView | 1 d | UI 控件能交互 |
| 6 | XIB 类名更新 (sed 批量) | 10 min | NIB 能找到 Swift 类 |
| 7 | 编译验证 + bug 修复 + 端到端测试 | 0.5-1 d | 16 节验证清单全过 |

**总预计**: 3-4 d

**每阶段完成时**:
1. `xcodegen generate` + `xcodebuild -arch arm64 -configuration Release build` 必须通过
2. 提交一个 git commit (如已初始化 git), 方便回退
3. 记录此阶段遇到的坑到第 15 节

---

## 6. 阶段 1:工程骨架

### 6.1 删除旧文件
```bash
cd /Users/xufei/Documents/claudecode/enjoy3

# 删除旧工程
rm -rf Enjoy2.xcodeproj

# 删除 JSONKit 死代码
rm -rf JSONKit

# 删除 PCH
rm -f enjoy3_Prefix.pch

# 删除所有旧 .h 和 .m
rm -f *.h *.m

# 验证: 当前目录应只剩目录 + 资源文件
ls -la
```

### 6.2 创建新目录
```bash
mkdir -p Sources/{App,Targets,Actions,Devices,Config,UI}
```

### 6.3 写 `project.yml` (XcodeGen 配置)
文件路径: `/Users/xufei/Documents/claudecode/enjoy3/project.yml`

```yaml
name: enjoy3
options:
  bundleIdPrefix: net.tunah
  deploymentTarget:
    macOS: "12.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "12.0"
    PRODUCT_MODULE_NAME: enjoy3
    PRODUCT_BUNDLE_IDENTIFIER: net.tunah.enjoy3
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""
    SWIFT_OBJC_BRIDGING_HEADER: Sources/enjoy3-Bridging-Header.h
    GCC_PRECOMPILE_PREFIX_HEADER: NO
    CLANG_ENABLE_OBJC_ARC: YES
    SWIFT_OPTIMIZATION_LEVEL: "-O"
    ARCHS: "$(ARCHS_STANDARD)"
    ONLY_ACTIVE_ARCH: YES
    ENABLE_HARDENED_RUNTIME: YES
    LD_RUNPATH_SEARCH_PATHS:
      - "@executable_path/../Frameworks"
    INFOPLIST_FILE: Info.plist
    GENERATE_INFOPLIST_FILE: NO
    ASSETCATALOG_COMPILER_APPICON_NAME: ""
    COMBINE_HIDPI_IMAGES: YES
    ENABLE_USER_SCRIPT_SANDBOXING: NO

targets:
  enjoy3:
    type: application
    platform: macOS
    sources:
      - path: Sources
      - path: English.lproj
        type: folder
      - path: zh-Hans.lproj
        type: folder
      - path: JoystickImages
        type: folder
      - path: icon.icns
      - path: Credits.rtf
      - path: dsa_pub.pem
      - path: Sparkle.framework
        type: folder
        buildPhase: copyFiles
        copyFiles:
          destination: frameworks
    dependencies:
      - sdk: Cocoa.framework
      - sdk: IOKit.framework
      - sdk: Carbon.framework
      - sdk: CoreGraphics.framework
      - sdk: ApplicationServices.framework

schemes:
  enjoy3:
    build:
      targets:
        enjoy3: all
    run:
      config: Release
    archive:
      config: Release
```

### 6.4 写 Bridging Header
文件路径: `/Users/xufei/Documents/claudecode/enjoy3/Sources/enjoy3-Bridging-Header.h`

```c
#ifndef enjoy3_Bridging_Header_h
#define enjoy3_Bridging_Header_h

#import <Cocoa/Cocoa.h>
#import <IOKit/hid/IOHIDLib.h>
#import <Carbon/Carbon.h>

// Sparkle 1.x 是 OC 框架, 直接 import 主头即可被 Swift 调用
#import <Sparkle/Sparkle.h>

#endif
```

### 6.5 写最小 `main.swift`
文件路径: `/Users/xufei/Documents/claudecode/enjoy3/Sources/App/main.swift`

```swift
import Cocoa

// 等价于 Objective-C 的 NSApplicationMain(argc, argv)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
```

### 6.6 临时移除 .lproj 以避免 XIB 找不到 owner
阶段 1 暂时不需要 XIB, 先编译空壳. 把 .lproj 临时挪到别处:
```bash
mv English.lproj English.lproj.stage1
mv zh-Hans.lproj zh-Hans.lproj.stage1
```

### 6.7 编译验证
```bash
cd /Users/xufei/Documents/claudecode/enjoy3
xcodegen generate
xcodebuild -project enjoy3.xcodeproj -configuration Release -arch arm64 ONLY_ACTIVE_ARCH=YES build 2>&1 | tail -30
```

**期望**: `BUILD SUCCEEDED`. 产物 `build/Release/enjoy3.app/Contents/MacOS/enjoy3` 存在.

### 6.8 把 .lproj 移回
```bash
mv English.lproj.stage1 English.lproj
mv zh-Hans.lproj.stage1 zh-Hans.lproj
```

### 6.9 阶段 1 完成标志
- [ ] `Enjoy2.xcodeproj` 已删除
- [ ] `JSONKit/` 已删除
- [ ] `enjoy3_Prefix.pch` 已删除
- [ ] 所有旧 `*.h` / `*.m` 已删除
- [ ] `project.yml` 已创建
- [ ] `Sources/enjoy3-Bridging-Header.h` 已创建
- [ ] `Sources/App/main.swift` 已创建
- [ ] `xcodebuild` 编译通过, 生成空 Swift .app

---

## 7. 阶段 2:核心数据模型

### 7.1 写 `Target.swift` (基类 + 工厂)
文件路径: `/Users/xufei/Documents/claudecode/enjoy3/Sources/Targets/Target.swift`

**参考源文件**: `/Users/xufei/Documents/claudecode/enjoy3.backup/Target.h`, `Target.m`

```swift
import Cocoa
import Carbon

/// 所有输出目标的协议.
protocol TargetBehavior: AnyObject {
    var running: Bool { get set }
    var isContinuous: Bool { get }
    var inputValue: Double { get set }
    func trigger(with jc: JoystickController)
    func untrigger(with jc: JoystickController)
    func update(with jc: JoystickController)
    func stringify() -> String
}

/// 抽象基类. 子类必须重写 trigger / update / stringify.
class Target: NSObject, TargetBehavior {
    var running = false
    var isContinuous: Bool { false }
    var inputValue: Double = 0

    func trigger(with jc: JoystickController) {
        fatalError("Target.trigger(with:) must be overridden in subclass")
    }

    func untrigger(with jc: JoystickController) {
        // 默认空实现 (一些 Target 仅在 trigger 时做事情)
    }

    func update(with jc: JoystickController) {
        // 默认空实现 (仅连续型 Target 需要)
    }

    func stringify() -> String {
        fatalError("Target.stringify() must be overridden in subclass")
    }

    /// 工厂方法: 根据 stringified 格式还原 Target.
    /// - Parameter str: 形如 "key~13~W" / "cfg~myConfig" / "mmove~1" 等
    /// - Parameter configs: 已加载的配置列表 (用于 cfg 类型反查 Config 实例)
    static func unstringify(_ str: String, withConfigList configs: [Config]) -> Target? {
        let comps = str.components(separatedBy: "~")
        guard let tag = comps.first else { return nil }
        switch tag {
        case "key":     return TargetKeyboard.unstringifyImpl(comps)
        case "cfg":     return TargetConfig.unstringifyImpl(comps, configs: configs)
        case "mmove":   return TargetMouseMove.unstringifyImpl(comps)
        case "mbtn":    return TargetMouseBtn.unstringifyImpl(comps)
        case "mscroll": return TargetMouseScroll.unstringifyImpl(comps)
        case "mtoggle": return TargetToggleMouseScope.unstringifyImpl(comps)
        default:        return nil
        }
    }
}
```

**OC 源对照** (`/Users/xufei/Documents/claudecode/enjoy3.backup/Target.m:1-30`):
- 6 个 tag (key/cfg/mmove/mbtn/mscroll/mtoggle) 必须保持
- `doesNotRecognizeSelector:` 改 `fatalError` (Swift 编译期就强制 override)
- `unstringify:` 接受 `configs` 参数用于 cfg 类型反查

### 7.2 写 6 个 Target 子类

#### 7.2.1 `TargetKeyboard.swift`
**参考源**: `TargetKeyboard.h` + `TargetKeyboard.m`

```swift
import Cocoa
import CoreGraphics

final class TargetKeyboard: Target {
    var vk: CGKeyCode = 0
    var descr: String = ""

    override func trigger(with jc: JoystickController) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: true) else { return }
        event.post(tap: .cghidEventTap)
    }

    override func untrigger(with jc: JoystickController) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: false) else { return }
        event.post(tap: .cghidEventTap)
    }

    override func stringify() -> String {
        return "key~\(Int(vk))~\(descr)"
    }

    static func unstringifyImpl(_ comps: [String]) -> TargetKeyboard {
        assert(comps.count == 3, "TargetKeyboard expects 3 components, got \(comps.count)")
        let t = TargetKeyboard()
        t.vk = CGKeyCode(Int(comps[1]) ?? 0)
        t.descr = comps[2]
        return t
    }
}
```

**OC 行为对照** (`TargetKeyboard.m:21-33`): `CGEventCreateKeyboardEvent(NULL, vk, true/false)` + `CGEventPost(kCGHIDEventTap, ...)`.

#### 7.2.2 `TargetConfig.swift`
```swift
import Cocoa

final class TargetConfig: Target {
    /// 注意: OC 原代码 `TargetConfig.m` 用 `name` 查 Config 实例.
    /// 反序列化时通过 name 在 configs 列表里查, 并持有强引用.
    weak var config: Config?

    override func trigger(with jc: JoystickController) {
        // OC 原方法签名是 -trigger (无参), 实际调自 active==YES 分支.
        // 这里保持 Swift 规范带 jc 参数, 调用方需传.
        guard let config = config else { return }
        let ac = NSApplication.shared.delegate as? ApplicationController
        ac?.configsController.activate(config, forApplication: nil)
    }

    override func stringify() -> String {
        return "cfg~\(config?.name ?? "")"
    }

    static func unstringifyImpl(_ comps: [String], configs: [Config]) -> TargetConfig {
        let name = comps.count > 1 ? comps[1] : ""
        let t = TargetConfig()
        t.config = configs.first { $0.name == name }
        return t
    }
}
```

**注意**: `TargetConfig.m` 原 OC 中 trigger 写法如下, 需对应改写:
```objc
- (void)trigger {
    ConfigsController *cc = [[[NSApplication sharedApplication] delegate] configsController];
    [cc activateConfig:config forApplication:NULL];
}
```

#### 7.2.3 `TargetMouseMove.swift`
```swift
import Cocoa
import Carbon

final class TargetMouseMove: Target {
    /// dir 0 = X (horizontal), 1 = Y (vertical)
    var dir: Int = 0

    override var isContinuous: Bool { true }

    override func update(with jc: JoystickController) {
        // 根据 inputValue 计算 delta
        // OC 原逻辑: 1.0 inputValue = 12.0 pixels/frame (80Hz)
        // frontWindowOnly 时: 4.0 pixels/frame
        let speed = jc.frontWindowOnly ? 4.0 : 12.0
        let v = jc.mouseLoc
        var newLoc = v

        if dir == 0 {
            // X 方向
            newLoc.x += CGFloat(inputValue) * CGFloat(speed)
        } else {
            // Y 方向 (Cocoa NSScreen 原点在左下, CGEvent 在左上, 需翻转)
            newLoc.y -= CGFloat(inputValue) * CGFloat(speed)
        }

        jc.mouseLoc = newLoc

        // 合成鼠标移动事件
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newLoc, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(inputValue * Double(speed)))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(-inputValue * Double(speed)))

        if jc.frontWindowOnly {
            var psn = ProcessSerialNumber()
            GetFrontProcess(&psn)
            event.postToPSN(&psn)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    override func stringify() -> String {
        return "mmove~\(dir)"
    }

    static func unstringifyImpl(_ comps: [String]) -> TargetMouseMove {
        let t = TargetMouseMove()
        t.dir = Int(comps[1]) ?? 0
        return t
    }
}
```

**OC 行为对照** (`TargetMouseMove.m:38-78`): 注意 80Hz Timer 持续触发; `frontWindowOnly` 模式用 PSN 路径.

#### 7.2.4 `TargetMouseBtn.swift`
```swift
import Cocoa
import CoreGraphics

final class TargetMouseBtn: Target {
    /// which 0 = left, 1 = right
    var which: Int = 0

    override func trigger(with jc: JoystickController) {
        let pos = NSEvent.mouseLocation
        let cgPos = CGPoint(x: pos.x, y: NSScreen.main?.frame.height ?? 0 - pos.y)
        // Cocoa NSScreen 原点在左下, CGEvent 在左上, 需翻转 Y
        let actualPos = CGPoint(x: pos.x, y: (NSScreen.main?.frame.height ?? 0) - pos.y)

        let mouseType: CGEventType = (which == 0) ? .leftMouseDown : .rightMouseDown
        let button: CGMouseButton = (which == 0) ? .left : .right

        guard let down = CGEvent(mouseEventSource: nil, mouseType: mouseType, mouseCursorPosition: actualPos, mouseButton: button) else { return }
        down.post(tap: .cghidEventTap)

        let upType: CGEventType = (which == 0) ? .leftMouseUp : .rightMouseUp
        guard let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: actualPos, mouseButton: button) else { return }
        up.post(tap: .cghidEventTap)
    }

    override func stringify() -> String {
        return "mbtn~\(which)"
    }

    static func unstringifyImpl(_ comps: [String]) -> TargetMouseBtn {
        let t = TargetMouseBtn()
        t.which = Int(comps[1]) ?? 0
        return t
    }
}
```

**OC 行为对照** (`TargetMouseBtn.m:25-49`): 单次 click (down + up).

#### 7.2.5 `TargetMouseScroll.swift`
```swift
import Cocoa
import CoreGraphics

final class TargetMouseScroll: Target {
    /// howMuch 正负表方向
    var howMuch: Int = 0

    override func trigger(with jc: JoystickController) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(howMuch), wheel2: 0, wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    override func stringify() -> String {
        return "mscroll~\(howMuch)"
    }

    static func unstringifyImpl(_ comps: [String]) -> TargetMouseScroll {
        let t = TargetMouseScroll()
        t.howMuch = Int(comps[1]) ?? 0
        return t
    }
}
```

**OC 行为对照** (`TargetMouseScroll.m:24-33`): `CGEventCreateScrollWheelEvent2(NULL, kCGScrollEventUnitLine, 1, howMuch)`.

#### 7.2.6 `TargetToggleMouseScope.swift`
```swift
import Cocoa

final class TargetToggleMouseScope: Target {
    override func trigger(with jc: JoystickController) {
        jc.frontWindowOnly.toggle()
    }

    override func stringify() -> String {
        return "mtoggle"
    }

    static func unstringifyImpl(_ comps: [String]) -> TargetToggleMouseScope {
        return TargetToggleMouseScope()
    }
}
```

**OC 行为对照** (`TargetToggleMouseScope.m:24-29`): 翻转 `JoystickController.frontWindowOnly` 标志.

### 7.3 写 `Config.swift`
**参考源**: `Config.h` + `Config.m`

```swift
import Cocoa

final class Config: NSObject {
    var name: String
    /// 磁盘格式版本, 保留 "enjoy3-1.1" 兼容现有用户配置
    let format = "enjoy3-1.1"
    /// key: JSAction.stringify(),  value: Target 实例
    private(set) var entries: [String: Target] = [:]

    init(name: String) {
        self.name = name
    }

    // MARK: - Target 增删查

    func setTarget(_ target: Target?, for action: JSAction) {
        let key = action.stringify()
        if let target = target {
            entries[key] = target
        } else {
            entries.removeValue(forKey: key)
        }
    }

    func getTarget(for action: JSAction) -> Target? {
        return entries[action.stringify()]
    }

    // MARK: - JSON 序列化

    /// 写入 ~/Library/Application Support/enjoy3/mappings/<name>.json
    func save() throws {
        let url = try Self.getMappingFilename(for: name)
        try saveJSON(to: url)
    }

    func saveJSON(to url: URL) throws {
        var dict: [String: Any] = [
            "name": name,
            "format": format
        ]
        var mappingEntries: [String: String] = [:]
        for (key, target) in entries {
            mappingEntries[key] = target.stringify()
        }
        dict["entries"] = mappingEntries
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        try data.write(to: url, options: .atomic)
    }

    // MARK: - JSON 反序列化

    /// 第一次扫描: 只读 name (用于 TargetConfig 跨引用解析)
    static func loadSkel(fromJSON url: URL) throws -> Config {
        let data = try Data(contentsOf: url)
        guard let dict = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = dict["name"] as? String else {
            throw NSError(domain: "enjoy3", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid config JSON: \(url.path)"])
        }
        return Config(name: name)
    }

    /// 第二次扫描: 解析 entries, 关联 Target 实例
    func load(fromJSON url: URL, withConfigList configs: [Config]) throws {
        let data = try Data(contentsOf: url)
        guard let dict = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entriesDict = dict["entries"] as? [String: String] else { return }
        for (key, value) in entriesDict {
            entries[key] = Target.unstringify(value, withConfigList: configs)
        }
    }

    // MARK: - 路径

    static func getMappingsDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("enjoy3/mappings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func getMappingFilename(for name: String) throws -> URL {
        let dir = try getMappingsDirectory()
        return dir.appendingPathComponent("\(name).json")
    }
}
```

**OC 行为对照** (`Config.m:1-100`):
- `name`, `format`, `entries` 三个字段名严格保留 (JSON 兼容性)
- `format` 写死 `"enjoy3-1.1"`, 不接受外部传入
- 两阶段加载: `loadSkel` (只读 name) + `load` (读 entries), 原因: TargetConfig 引用别的 Config, 必须先建好所有 Config 列表

### 7.4 写 `JSAction.swift` (含 SubAction)
**参考源**: `JSAction.h` + `JSAction.m` + `SubAction.h` + `SubAction.m`

```swift
import Cocoa
import IOKit.hid

/// 手柄动作的抽象基类. 区分按钮 / 轴 / 帽开关.
class JSAction: NSObject {
    var usage: Int = 0
    var cookie: IOHIDElementCookie = 0
    let index: Int
    var subActions: [SubAction] = []
    /// 所属 Joystick 设备 (用于 stringify 串接设备 ID)
    weak var base: Joystick?
    let name: String

    init(index: Int, name: String) {
        self.index = index
        self.name = name
    }

    /// 由事件 value 更新 active 状态
    func notifyEvent(_ value: IOHIDValue) {
        fatalError("JSAction.notifyEvent(_:) must be overridden in subclass")
    }

    /// 当前是否激活 (用于触发 Target)
    var active: Bool {
        fatalError("JSAction.active must be overridden in subclass")
    }

    /// 根据 value 找到对应的 SubAction, 若无 SubAction 则返回 self.
    func findSubAction(for value: IOHIDValue) -> JSAction? {
        return nil
    }

    /// 序列化为 "vid~pid~idx~cookie"
    func stringify() -> String {
        let baseStr = base?.stringify() ?? "?"
        return "\(baseStr)~\(cookie)"
    }
}

/// 子动作. JSActionButton 通常无 SubAction; JSActionAnalog 有 Low/High/Analog 三个.
final class SubAction {
    weak var base: JSAction?
    let name: String
    let index: Int
    var active = false

    init(index: Int, name: String, base: JSAction) {
        self.index = index
        self.name = name
        self.base = base
    }

    /// 序列化为 "vid~pid~idx~cookie~subIndex"
    func stringify() -> String {
        return "\(base!.stringify())~\(index)"
    }
}
```

### 7.5 写 3 个 JSAction 子类

#### 7.5.1 `JSActionButton.swift`
**参考源**: `JSActionButton.h` + `JSActionButton.m:1-25`

```swift
import Cocoa
import IOKit.hid

final class JSActionButton: JSAction {
    var max: Int = 1

    override func notifyEvent(_ value: IOHIDValue) {
        let v = Int(IOHIDValueGetIntegerValue(value))
        active_internal = (v == max)
    }

    override var active: Bool {
        return active_internal
    }

    override func findSubAction(for value: IOHIDValue) -> JSAction? {
        return active ? self : nil
    }

    private var active_internal: Bool = false
}
```

#### 7.5.2 `JSActionAnalog.swift`
**参考源**: `JSActionAnalog.h` + `JSActionAnalog.m:1-50`

```swift
import Cocoa
import IOKit.hid

final class JSActionAnalog: JSAction {
    var min: Double = 0
    var max: Double = 1

    private let analogThreshold = 0.1
    private let discreteThreshold = 0.3

    private var lowActive = false
    private var highActive = false
    private var analogActive = false

    /// 把原始整数 value 线性映射到 [-1, +1], 公式与 OC 一致.
    func getRealValue(_ raw: IOHIDValue) -> Double {
        let v = Double(IOHIDValueGetIntegerValue(raw))
        if max - min < 1 { return 0 }  // 防御
        return -1.0 + 2.0 * (v - min - 0.5) / (max - min)
    }

    override func notifyEvent(_ value: IOHIDValue) {
        let real = getRealValue(value)

        lowActive = real < -discreteThreshold
        highActive = real > discreteThreshold
        analogActive = abs(real) > analogThreshold
    }

    override var active: Bool {
        return lowActive || highActive || analogActive
    }

    override func findSubAction(for value: IOHIDValue) -> JSAction? {
        if analogActive {
            return subActions.first { $0.name == "Analog" }
        }
        if highActive {
            return subActions.first { $0.name == "High" }
        }
        if lowActive {
            return subActions.first { $0.name == "Low" }
        }
        return nil
    }

    /// 暴露给 JoystickController.inputCallback 用于 TargetMouseMove 的 inputValue
    var currentRealValue: Double = 0

    /// 重写 notifyEvent 末尾记录最新值
    override func notifyEventValueUpdate(_ value: IOHIDValue) {
        currentRealValue = getRealValue(value)
    }
}

// 扩展方法 (便于在 JoystickController 中调用)
extension JSAction {
    /// 缺省实现: 仅供 JSActionAnalog 实际使用
    func notifyEventValueUpdate(_ value: IOHIDValue) {
        // 基类空实现
    }
}
```

**注意**: OC 中 JSActionAnalog 的 subActions 创建在 `Joystick.populateActions` 中, 不在子类内. Swift 端在 Joystick 内创建.

#### 7.5.3 `JSActionHat.swift`
**参考源**: `JSActionHat.h` + `JSActionHat.m:1-90`

```swift
import Cocoa
import IOKit.hid

final class JSActionHat: JSAction {
    private var max: Int = 0

    /// 4 向: 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW
    /// OC 中用查表法. 简化版本: 直接判断 value.
    private var upActive = false
    private var downActive = false
    private var leftActive = false
    private var rightActive = false

    override func notifyEvent(_ value: IOHIDValue) {
        let v = Int(IOHIDValueGetIntegerValue(value))
        // 8 向: value 0-7, 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW
        // 4 向: value 0-3, 0=N, 1=E, 2=S, 3=W
        if max >= 7 {
            // 8 向
            upActive = (v == 0 || v == 1 || v == 7)
            rightActive = (v == 1 || v == 2 || v == 3)
            downActive = (v == 3 || v == 4 || v == 5)
            leftActive = (v == 5 || v == 6 || v == 7)
        } else {
            // 4 向
            upActive = (v == 0)
            rightActive = (v == 1)
            downActive = (v == 2)
            leftActive = (v == 3)
        }
    }

    override var active: Bool {
        return upActive || downActive || leftActive || rightActive
    }

    override func findSubAction(for value: IOHIDValue) -> JSAction? {
        if upActive { return subActions.first { $0.name == "Up" } }
        if downActive { return subActions.first { $0.name == "Down" } }
        if leftActive { return subActions.first { $0.name == "Left" } }
        if rightActive { return subActions.first { $0.name == "Right" } }
        return nil
    }

    func setMax(_ m: Int) {
        self.max = m
    }
}
```

**OC 行为对照** (`JSActionHat.m`): 用 `active_eightway[36]` 与 `active_fourway[20]` 查表. Swift 改 if-else 更易读, 行为等价.

### 7.6 阶段 2 编译验证
```bash
xcodegen generate
xcodebuild -project enjoy3.xcodeproj -configuration Release -arch arm64 ONLY_ACTIVE_ARCH=YES build 2>&1 | tail -30
```

**期望**: 编译通过 (会报 `JoystickController` / `ApplicationController` 等未定义的错, 因为阶段 3/5 还未写, 这正常).

**临时验证 (可选)**: 写一个单元测试, 跑 6 种 Target 的 stringify 往返:
```bash
# 临时创建一个 test 文件
cat > /tmp/test_target.swift << 'EOF'
let configs: [Config] = []
let t1 = TargetKeyboard()
t1.vk = 13
t1.descr = "W"
let s1 = t1.stringify()  // "key~13~W"
let t1b = Target.unstringify(s1, withConfigList: configs)!
assert(t1b.stringify() == s1)
EOF
```

### 7.7 阶段 2 完成标志
- [ ] `Sources/Targets/` 7 个 .swift 文件已创建
- [ ] `Sources/Actions/JSAction.swift` 含 SubAction
- [ ] `Sources/Actions/` 3 个子类 .swift 已创建
- [ ] `Sources/Config/Config.swift` 已创建
- [ ] 编译错误仅限 "JoystickController / ApplicationController 未找到"

---

## 8. 阶段 3:手柄层

### 8.1 写 `Joystick.swift`
**参考源**: `Joystick.h` + `Joystick.m`

```swift
import Cocoa
import IOKit.hid

/// 一个 HID 设备的封装.
final class Joystick {
    var vendorId: Int = 0
    var productId: Int = 0
    var index: Int = 0
    var productName: String = ""
    var device: IOHIDDevice!
    private(set) var children: [JSAction] = []
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
            guard type == IOHIDElementType.inputMisc
                || type == IOHIDElementType.inputAxis
                || type == IOHIDElementType.inputButton else { continue }

            let action: JSAction?
            if usagePage == kHIDPage_Button || type == IOHIDElementType.inputButton || (physMax - physMin) == 1 {
                let btn = JSActionButton(index: buttonIdx, name: elName)
                btn.max = Int(physMax)
                buttonIdx += 1
                action = btn
            } else if usage == 0x39 {
                // Hat switch
                let hat = JSActionHat()
                hat.setMax(Int(physMax))
                action = hat
            } else if usage >= 0x30 && usage < 0x36 {
                // 模拟轴
                let analog = JSActionAnalog(index: axisIdx, name: elName)
                analog.min = Double(physMin)
                analog.max = Double(physMax)
                axisIdx += 1
                action = analog

                // 给 Analog 创建 3 个 SubAction
                let low = SubAction(index: 0, name: "Low", base: analog)
                let high = SubAction(index: 1, name: "High", base: analog)
                let ana = SubAction(index: 2, name: "Analog", base: analog)
                analog.subActions = [low, high, ana]
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
```

**OC 行为对照** (`Joystick.m:1-130`):
- 注意 `productId = vendorId` 的原 bug 保留 (stringify 兼容性)
- `populateActions` 内创建 SubAction, Hat 不创建 SubAction (OC 中 Hat 的 SubAction 也在此处创建)

### 8.2 写 `JoystickController.swift`
**参考源**: `JoystickController.h` + `JoystickController.m`

```swift
import Cocoa
import IOKit.hid

/// 手柄集合管理器 + 事件分发器.
final class JoystickController: NSObject {
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var targetController: TargetController!
    @IBOutlet weak var configsController: ConfigsController!

    /// 已知手柄设备
    private(set) var joysticks: [Joystick] = []
    /// 连续型 Target (鼠标移动) 列表, 由 80Hz Timer 驱动
    private(set) var runningTargets: [Target] = []
    /// 鼠标移动时是否仅作用于前台窗口
    var frontWindowOnly = false
    /// 当前鼠标位置 (NSEvent.mouseLocation)
    var mouseLoc: NSPoint = .zero
    /// 在 C 回调中标记 outlineView 选中是否由程序触发 (避免选中事件递归)
    private var programmaticallySelecting = false

    private var hidManager: IOHIDManager?
    private var timer: Timer?

    // MARK: - 初始化与销毁

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
        IOHIDManagerRegisterDeviceMatchingCallback(manager, JoystickController.addCallback, ud)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, JoystickController.removeCallback, ud)

        // 80Hz 定时器驱动连续型 Target
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/80.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.mouseLoc = NSEvent.mouseLocation
            for target in self.runningTargets {
                target.update(with: self)
            }
        }
        if let t = timer {
            RunLoop.current.add(t, forMode: .common)
        }
    }

    deinit {
        timer?.invalidate()
        if let m = hidManager {
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    // MARK: - 工具

    func findAvailableIndex(for joystick: Joystick) -> Int {
        // 找到第一个未被占用的 index
        var i = 0
        while joysticks.contains(where: { $0.index == i }) { i += 1 }
        return i
    }

    func findJoystick(byRef device: IOHIDDevice) -> Joystick? {
        return joysticks.first { $0.device == device }
    }

    /// 展开 outlineView 中指定 item 的所有父节点并选中它.
    func expandRecursive(_ item: Any) {
        var row = outlineView.row(forItem: item)
        while row >= 0, let parent = outlineView.parent(forItem: item) {
            if !outlineView.isItemExpanded(parent) {
                outlineView.expandItem(parent, expandChildren: true)
            }
            row = outlineView.row(forItem: parent)
        }
    }

    /// 选中 handler (SubAction 或 JSAction) 时, 通知 targetController 加载 UI.
    func selectHandler(_ handler: Any) {
        programmaticallySelecting = true
        let row = outlineView.row(forItem: handler)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    // MARK: - NSOutlineView DataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return joysticks.count
        }
        if let js = item as? Joystick {
            return js.children.count
        }
        if let action = item as? JSAction {
            return action.subActions.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
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

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if item is Joystick { return true }
        if let action = item as? JSAction, !action.subActions.isEmpty { return true }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        if let js = item as? Joystick { return js.name }
        if let action = item as? JSAction { return action.name }
        if let sub = item as? SubAction { return sub.name }
        return ""
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if programmaticallySelecting {
            programmaticallySelecting = false
            return
        }
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? JSAction else { return }
        targetController?.load(action: item)
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
        let subActions: [JSAction] = mainAction.subActions.isEmpty ? [mainAction] : mainAction.subActions
        for sub in subActions {
            guard let target = jc.configsController?.currentConfig?.getTarget(for: sub) else { continue }
            if target.running != sub.active {
                if sub.active {
                    target.trigger(with: jc)
                } else {
                    target.untrigger(with: jc)
                }
                target.running = sub.active
            }
            // 连续型 Target 注册
            if target.isContinuous, target.running, !jc.runningTargets.contains(where: { $0 === target }) {
                jc.runningTargets.append(target)
            }
        }
        // 清理不活动的 continuous target
        jc.runningTargets.removeAll { !$0.running }
    } else if NSApplication.shared.isActive, NSApplication.shared.mainWindow?.isVisible == true {
        // UI 导航模式
        guard let handler = js.action(forEvent: value) else { return }
        jc.expandRecursive(handler)
        jc.selectHandler(handler)
    }
}
```

**OC 行为对照** (`JoystickController.m:1-200`):
- 三个 C 回调 (`add_callback` / `remove_callback` / `input_callback`) 改为顶层 `@convention(c)` 闭包
- 80Hz Timer 用 `Timer.scheduledTimer` + `[weak self]`
- `IOHIDManagerScheduleWithRunLoop` 第三个参数: OC 是 `kCFRunLoopDefaultMode`, Swift 写 `CFRunLoopMode.defaultMode.rawValue` (避免命名冲突)

### 8.3 阶段 3 完成标志
- [ ] `Sources/Devices/Joystick.swift` 已创建
- [ ] `Sources/Devices/JoystickController.swift` 已创建
- [ ] 编译时除 ApplicationController/ConfigsController/TargetController 未找到外, 应无错

---

## 9. 阶段 4:输出层

**已完成于阶段 2**. 验证所有 6 个 Target 子类可正确 trigger / untrigger.

### 9.1 验证 checklist
- [ ] `TargetKeyboard.trigger` 发送 `CGEvent(keyboardEventSource:virtualKey:keyDown: true)` + post
- [ ] `TargetKeyboard.untrigger` 发送 keyDown: false
- [ ] `TargetMouseBtn.trigger` 发送 leftMouseDown/Up 或 rightMouseDown/Up
- [ ] `TargetMouseScroll.trigger` 发送 scrollWheelEvent
- [ ] `TargetMouseMove.update` 由 80Hz Timer 触发, 计算 delta 并 post
- [ ] `TargetToggleMouseScope.trigger` 翻转 `jc.frontWindowOnly`
- [ ] `TargetConfig.trigger` 调 `cc.activate(config, forApplication: nil)`

### 9.2 CGEvent 在 macOS 12 Swift 5.9 的已知问题

| 现象 | 解决 |
|---|---|
| `CGEvent.postToPSN` 编译失败 | 需 `import Carbon` (Bridging Header 已 import, Swift 端再写一次) |
| `CGEventSetIntegerValueField` 改名 | Swift API 是 `event.setIntegerValueField(.mouseEventDeltaX, value:)` |
| `CGEventCreateScrollWheelEvent2` 改名 | Swift API 是 `CGEvent(scrollWheelEvent2Source:units:wheelCount:wheel1:wheel2:wheel3:)` |
| 编译错误 "Cannot find 'kCGScrollEventUnitLine' in scope" | 用 `CGScrollEventUnit.line` (Swift enum 化) |

---

## 10. 阶段 5:UI 控制器

### 10.1 写 `ApplicationController.swift`
**参考源**: `ApplicationController.h` + `ApplicationController.m`

```swift
import Cocoa
import Carbon

@objc final class ApplicationController: NSObject {
    @IBOutlet weak var jsController: JoystickController!
    @IBOutlet weak var targetController: TargetController!
    @IBOutlet weak var configsController: ConfigsController!
    @IBOutlet weak var drawer: NSDrawer!
    @IBOutlet weak var mainWindow: NSWindow!
    @IBOutlet weak var activeButton: NSToolbarItem!
    @IBOutlet weak var activeMenuItem: NSMenuItem!
    @IBOutlet weak var dockMenuBase: NSMenu!

    /// 映射开关 (active=YES 时手柄事件触发 Target)
    var active: Bool = false
    /// 用于 ProcessInfo 后台活动资格
    private var activityToken: Any?

    // MARK: - NSApplicationDelegate / NIB 生命周期

    @objc func awakeFromNib() {
        if #available(macOS 10.9, *) {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: ProcessInfo.ActivityOptions(rawValue: 0x00FFFFFF),
                reason: "Let joystick commands fire in the background"
            )
        }
    }

    @objc func applicationDidFinishLaunching(_ note: Notification) {
        NSSetUncaughtExceptionHandler { e in NSLog("Uncaught: \(e.description)") }

        jsController.setup()
        drawer.open()
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
        if dockMenuBase.numberOfItems - 2 != configs.count {
            NSLog("dockMenuBase has wrong number of items!")
        }
        for (i, cfg) in configs.enumerated() {
            (dockMenuBase.item(at: 2 + i))?.state = (cfg === current) ? .on : .off
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

private let appSwitchCallback: @convention(c) (
    EventHandlerCallRef,
    EventRef,
    UnsafeMutableRawPointer?
) -> OSStatus = { _, _, userData in
    guard let userData = userData,
          let dict = NSWorkspace.shared.activeApplication else { return noErr }
    let ac = Unmanaged<ApplicationController>.fromOpaque(userData).takeUnretainedValue()
    var psn = ProcessSerialNumber()
    psn.lowLongOfPSN = Int32((dict["NSApplicationProcessSerialNumberLow"] as? Int) ?? 0)
    psn.highLongOfPSN = Int32((dict["NSApplicationProcessSerialNumberHigh"] as? Int) ?? 0)
    let appName = (dict["NSApplicationName"] as? String) ?? ""
    ac.configsController.applicationSwitched(to: appName, psn: psn)
    return noErr
}
```

**OC 行为对照** (`ApplicationController.m:1-160`):
- `appSwitch` 用 `@convention(c)` 顶层闭包
- `InstallEventHandler` 第三个参数是 `&spec` 指针
- `NSWorkspace.activeApplication` 返回 `[String: Any]`, 取出 PSN low/high long

### 10.2 写 `ConfigsController.swift`
**参考源**: `ConfigsController.h` + `ConfigsController.m`

```swift
import Cocoa
import Carbon

final class ConfigsController: NSObject {
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var removeButton: NSButton!
    @IBOutlet weak var targetController: TargetController!
    @IBOutlet weak var appController: ApplicationController!

    private(set) var configs: [Config] = []
    private(set) var currentConfig: Config?
    private var neutralConfig: Config?
    private var attachedApplication: String?

    // MARK: - 加载与保存

    func load() {
        do {
            let dir = try Config.getMappingsDirectory()
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            // 阶段一: 只读 name
            for url in files where url.pathExtension == "json" {
                if let cfg = try? Config.loadSkel(fromJSON: url) {
                    configs.append(cfg)
                }
            }
            // 阶段二: 解析 entries
            for cfg in configs {
                let url = try? Config.getMappingFilename(for: cfg.name)
                if let url = url {
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
        } else {
            currentConfig = configs.first
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
        } catch {
            NSLog("enjoy3: save failed: \(error)")
        }
    }

    // MARK: - 激活

    func activate(_ config: Config, forApplication appName: String?) {
        if let appName = appName, currentConfig != nil {
            // 保存当前作为 neutral
            neutralConfig = currentConfig
            attachedApplication = appName
        } else if appName == nil {
            // 手动激活, 清除 neutral
            neutralConfig = nil
            attachedApplication = nil
        }
        currentConfig = config
        UserDefaults.standard.set(config.name, forKey: "selectedMapping")
        targetController?.load(action: targetController?.currentJSAction)
        appController?.configChanged()
        tableView.reloadData()
    }

    func restoreNeutralConfig() {
        if let neutral = neutralConfig {
            currentConfig = neutral
            attachedApplication = nil
            neutralConfig = nil
            appController?.configChanged()
            tableView.reloadData()
        }
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

    // MARK: - UI 操作

    @IBAction func addPressed(_ sender: Any) {
        let new = Config(name: "untitled")
        configs.append(new)
        appController?.configsListChanged()
        tableView.reloadData()
        save()
        // 立即进入编辑模式让用户改名
        let row = configs.count - 1
        tableView.editColumn(0, row: row, with: nil, select: true)
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

    func numberOfRows(in tableView: NSTableView) -> Int {
        return configs.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return configs[row].name
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard let newName = object as? String, row < configs.count else { return }
        // 唯一性检查
        if configs.contains(where: { $0.name == newName }) {
            let alert = NSAlert()
            alert.messageText = "请为这个映射取一个唯一的名称"
            alert.runModal()
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
            return
        }
        let oldName = configs[row].name
        configs[row].name = newName
        // 旧 JSON 文件需要删除
        if let oldURL = try? Config.getMappingFilename(for: oldName) {
            try? FileManager.default.removeItem(at: oldURL)
        }
        save()
        appController?.configsListChanged()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < configs.count else { return }
        activate(configs[row], forApplication: nil)
    }
}
```

**OC 行为对照** (`ConfigsController.m:1-300`):
- `load` 阶段一 + 阶段二
- `save` 删除已不存在的 Config 文件, 写所有 Config
- `addPressed` / `removePressed` / `tableViewSelectionDidChange` 保持相同行为
- `applicationSwitched` 处理 Carbon 事件

### 10.3 写 `TargetController.swift`
**参考源**: `TargetController.h` + `TargetController.m`

```swift
import Cocoa

final class TargetController: NSObject {
    @IBOutlet weak var title: NSTextField!
    @IBOutlet weak var keyInput: KeyInputTextView!
    @IBOutlet weak var radioButtons: NSMatrix!
    @IBOutlet weak var radioNoAction: NSButtonCell!
    @IBOutlet weak var radioKey: NSButtonCell!
    @IBOutlet weak var radioConfig: NSButtonCell!
    @IBOutlet weak var mouseDirSelect: NSSegmentedControl!
    @IBOutlet weak var mouseBtnSelect: NSSegmentedControl!
    @IBOutlet weak var scrollDirSelect: NSSegmentedControl!
    @IBOutlet weak var configPopup: NSPopUpButton!
    @IBOutlet weak var configsController: ConfigsController!
    @IBOutlet weak var joystickController: JoystickController!

    /// 当前编辑的 JSAction
    private(set) var currentJSAction: JSAction?
    private var radioAction: ((Int) -> Void)?

    var isEnabled: Bool = false {
        didSet {
            radioButtons.isEnabled = isEnabled
            keyInput.isEnabled = isEnabled
            mouseDirSelect?.isEnabled = isEnabled
            mouseBtnSelect?.isEnabled = isEnabled
            scrollDirSelect?.isEnabled = isEnabled
            configPopup?.isEnabled = isEnabled
        }
    }

    // MARK: - 加载

    func load(action: JSAction?) {
        currentJSAction = action
        guard let action = action,
              let config = configsController?.currentConfig else {
            // 清空 UI
            title.stringValue = ""
            keyInput.clear()
            return
        }

        let target = config.getTarget(for: action)
        title.stringValue = "\(config.name) > \(action.name)"

        // 根据 target 类型设置 UI
        if target == nil {
            radioButtons.selectCell(atRow: 0, column: 0)  // No Action
        } else if let t = target as? TargetKeyboard {
            radioButtons.selectCell(atRow: 1, column: 0)
            keyInput.vk = Int(t.vk)
        } else if let t = target as? TargetConfig {
            radioButtons.selectCell(atRow: 2, column: 0)
            // 选中 configPopup 中对应的 config
            for (i, c) in configsController.configs.enumerated() {
                if c === t.config {
                    configPopup.selectItem(at: i)
                    break
                }
            }
        } else if let t = target as? TargetMouseMove {
            radioButtons.selectCell(atRow: 3, column: 0)
            mouseDirSelect.selectSegment(withTag: t.dir)
        } else if let t = target as? TargetMouseBtn {
            radioButtons.selectCell(atRow: 4, column: 0)
            mouseBtnSelect.selectSegment(withTag: t.which)
        } else if let t = target as? TargetMouseScroll {
            radioButtons.selectCell(atRow: 5, column: 0)
            scrollDirSelect.selectSegment(withTag: t.howMuch > 0 ? 0 : 1)
        } else if target is TargetToggleMouseScope {
            radioButtons.selectCell(atRow: 6, column: 0)
        }
    }

    // MARK: - 提交 (任意 UI 变化都调)

    private func commit() {
        guard let action = currentJSAction,
              let config = configsController?.currentConfig else { return }
        let row = radioButtons.selectedRow
        let target: Target?
        switch row {
        case 0:
            target = nil
        case 1:
            let t = TargetKeyboard()
            t.vk = CGKeyCode(keyInput.vk)
            t.descr = keyInput.descr
            target = t
        case 2:
            let t = TargetConfig()
            let idx = configPopup.indexOfSelectedItem
            t.config = configsController.configs[idx]
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
            t.howMuch = scrollDirSelect.selectedSegment == 0 ? 1 : -1
            target = t
        case 6:
            target = TargetToggleMouseScope()
        default:
            target = nil
        }
        config.setTarget(target, for: action)
        configsController.save()
    }

    // MARK: - IBAction

    @IBAction func radioChanged(_ sender: Any) {
        commit()
    }

    @IBAction func mdirChanged(_ sender: Any) {
        commit()
    }

    @IBAction func mbtnChanged(_ sender: Any) {
        commit()
    }

    @IBAction func sdirChanged(_ sender: Any) {
        commit()
    }

    @IBAction func configChosen(_ sender: Any) {
        commit()
    }

    /// KeyInputTextView 捕获到键时调
    func keyChanged() {
        radioButtons.selectCell(atRow: 1, column: 0)
        commit()
    }
}
```

**OC 行为对照** (`TargetController.m:1-200`):
- 7 行单选: 0=None, 1=Key, 2=Config, 3=MouseMove, 4=MouseBtn, 5=Scroll, 6=Toggle
- `keyChanged` 自动切到 Key 行
- 任何 UI 变化立即 commit + save

### 10.4 写 `KeyInputTextView.swift`
**参考源**: `KeyInputTextView.h` + `KeyInputTextView.m`

```swift
import Cocoa

@objc final class KeyInputTextView: NSTextView {
    @IBOutlet weak var window: NSWindow?
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
            pressed(event.keyCode)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        pressed(event.keyCode)
    }
}
```

### 10.5 写 `CKeys.swift`
**参考源**: `KeyInputTextView.m:18-90` (内含的 switch 大法)

```swift
import Cocoa

/// CGKeyCode → 显示名查表.
enum CKeys {
    private static let table: [Int: String] = [
        // F1-F19
        0x7a: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6d: "F10", 0x67: "F11", 0x6f: "F12",
        0x69: "F13", 0x6b: "F14", 0x71: "F15", 0x6a: "F16",
        0x40: "F17", 0x4f: "F18", 0x50: "F19",
        // 字母 (按 macOS keycode 顺序)
        0x00: "A", 0x0b: "B", 0x08: "C", 0x02: "D", 0x0e: "E",
        0x03: "F", 0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J",
        0x28: "K", 0x25: "L", 0x2e: "M", 0x2d: "N", 0x1f: "O",
        0x23: "P", 0x0c: "Q", 0x0f: "R", 0x01: "S", 0x11: "T",
        0x20: "U", 0x09: "V", 0x0d: "W", 0x07: "X", 0x10: "Y",
        0x06: "Z",
        // 数字
        0x1d: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
        0x17: "5", 0x16: "6", 0x1a: "7", 0x1c: "8", 0x19: "9",
        // 修饰键
        0x35: "Esc", 0x31: "Space", 0x24: "Return", 0x30: "Tab",
        0x33: "Delete", 0x75: "Delete Forward",
        0x7b: "Left Arrow", 0x7c: "Right Arrow",
        0x7d: "Down Arrow", 0x7e: "Up Arrow",
        // 符号键
        0x18: "=", 0x21: "[", 0x1e: "]", 0x2a: "\\",
        0x29: ";", 0x27: "'", 0x32: "`", 0x2b: ",",
        0x2f: ".", 0x2c: "/", 0x41: ".",
        // 小键盘
        0x52: "Numpad 0", 0x53: "Numpad 1", 0x54: "Numpad 2",
        0x55: "Numpad 3", 0x56: "Numpad 4", 0x57: "Numpad 5",
        0x58: "Numpad 6", 0x59: "Numpad 7", 0x5a: "Numpad 8",
        0x5b: "Numpad 9",
        0x43: "Numpad *", 0x45: "Numpad +", 0x4e: "Numpad -",
        0x41: "Numpad .", 0x4b: "Numpad /", 0x4c: "Numpad Enter",
        // 其他
        0x39: "Caps Lock", 0x36: "Command", 0x37: "Command",
        0x38: "Shift", 0x3a: "Option", 0x3b: "Control",
        0x72: "Help", 0x73: "Home", 0x74: "Page Up",
        0x79: "Page Down", 0x77: "End",
    ]

    static func name(for keyCode: Int) -> String {
        return table[keyCode] ?? String(format: "0x%x", keyCode)
    }
}
```

**OC 行为对照** (`KeyInputTextView.m:stringForKeyCode:`): 原代码是一大段 switch-case, 改为字典查表. 完整键码与原 OC 保持一致.

### 10.6 阶段 5 完成标志
- [ ] 5 个 .swift 文件已创建 (ApplicationController / ConfigsController / TargetController / KeyInputTextView / CKeys)
- [ ] 编译错误仅剩 XIB 中找不到 Swift 类的错误 (阶段 6 修复)

---

## 11. 阶段 6:XIB 类名更新

### 11.1 备份 XIB
```bash
cp English.lproj/MainMenu.xib English.lproj/MainMenu.xib.bak
cp zh-Hans.lproj/MainMenu.xib zh-Hans.lproj/MainMenu.xib.bak
```

### 11.2 批量替换 customClass
```bash
cd /Users/xufei/Documents/claudecode/enjoy3

# 替换: customClass="Xxx"  →  customClass="Xxx" customModule="enjoy3" customModuleProvider="target"
sed -i '' 's/customClass="\(ApplicationController\|ConfigsController\|JoystickController\|TargetController\|KeyInputTextView\)"/customClass="\1" customModule="enjoy3" customModuleProvider="target"/g' \
    English.lproj/MainMenu.xib \
    zh-Hans.lproj/MainMenu.xib
```

### 11.3 验证
```bash
# 应该看到所有 5 个 customClass 都有 customModule
grep -E 'customClass="(Application|Configs|Joystick|Target|KeyInput)' English.lproj/MainMenu.xib
```

**期望输出** (示例):
```xml
<customObject id="482" userLabel="ApplicationController" customClass="ApplicationController" customModule="enjoy3" customModuleProvider="target">
<customObject id="514" userLabel="ConfigsController" customClass="ConfigsController" customModule="enjoy3" customModuleProvider="target">
<customObject id="624" userLabel="JoystickController" customClass="JoystickController" customModule="enjoy3" customModuleProvider="target">
<customObject id="686" userLabel="TargetController" customClass="TargetController" customModule="enjoy3" customModuleProvider="target">
<customObject id="683" userLabel="KeyInputTextView" customClass="KeyInputTextView" customModule="enjoy3" customModuleProvider="target">
```

### 11.4 阶段 6 完成标志
- [ ] 2 个 MainMenu.xib 中 5 个 customClass 全部带 customModule

---

## 12. 阶段 7:编译验证与 bug 修复

### 12.1 完整编译
```bash
cd /Users/xufei/Documents/claudecode/enjoy3
xcodegen generate
xcodebuild -project enjoy3.xcodeproj -configuration Release -arch arm64 ONLY_ACTIVE_ARCH=YES build 2>&1 | tee /tmp/build.log
```

### 12.2 启动验证
```bash
# 重置辅助功能授权 (用 build.sh 中的命令)
tccutil reset Accessibility net.tunah.enjoy3

# 启动
open build/Release/enjoy3.app
```

**期望**: Dock 图标出现, 菜单栏有 "enjoy3" 项, 主窗口出现, 抽屉打开.

### 12.3 典型错误与修复 (参见第 15 节)

### 12.4 更新 `build.sh`
文件路径: `/Users/xufei/Documents/claudecode/enjoy3/build.sh`

```bash
#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/project.yml"
XCODEPROJ="$PROJECT_DIR/enjoy3.xcodeproj"
APP="$PROJECT_DIR/build/Release/enjoy3.app"
BUNDLE_ID="net.tunah.enjoy3"

# 参数解析
RESET=1
OPEN=1
CLEAN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-reset) RESET=0 ;;
        --no-open)  OPEN=0 ;;
        --clean)    CLEAN=1 ;;
        -h|--help)
            echo "Usage: ./build.sh [--no-reset] [--no-open] [--clean]"
            exit 0
            ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
    shift
done

# 关闭旧实例
pkill -x enjoy3 2>/dev/null || true

# 清理
if [ "$CLEAN" = "1" ]; then
    rm -rf "$PROJECT_DIR/build"
fi

# 生成 Xcode 工程
xcodegen generate

# 编译
xcodebuild -project "$XCODEPROJ" -configuration Release -arch arm64 ONLY_ACTIVE_ARCH=YES build 2>&1 | tail -20

# 重置辅助功能授权
if [ "$RESET" = "1" ]; then
    tccutil reset Accessibility "$BUNDLE_ID"
fi

# 启动
if [ "$OPEN" = "1" ]; then
    open "$APP"
fi
```

### 12.5 阶段 7 完成标志
- [ ] 编译通过
- [ ] 启动不崩
- [ ] 第 16 节所有验证清单全部通过

---

## 13. 关键技术细节参考

### 13.1 IOHID C API 在 Swift 中的常见模式

| C 写法 | Swift 等价 |
|---|---|
| `IOHIDManagerRef mgr = IOHIDManagerCreate(...)` | `let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))` |
| `IOHIDManagerOpen(mgr, 0)` | `IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))` |
| `IOHIDManagerClose(mgr, 0)` | `IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))` |
| `IOHIDValueGetIntegerValue(value)` | `IOHIDValueGetIntegerValue(value)` (直接调用) |
| `IOHIDElementGetCookie(elt)` | `IOHIDElementGetCookie(elt)` (直接调用) |
| `kHIDPage_Button` | `kHIDPage_Button` (Bridging Header 已暴露) |
| `kIOHIDDeviceUsagePageKey` | `kIOHIDDeviceUsagePageKey as CFString` (强转) |

### 13.2 C 回调签名对照

| C 签名 | Swift 闭包签名 |
|---|---|
| `void add_cb(void* ctx, IOReturn r, void* sender, IOHIDDeviceRef device)` | `IOHIDDeviceCallback = @convention(c) (UnsafeMutableRawPointer?, IOReturn, UnsafeMutableRawPointer?, IOHIDDevice) -> Void` |
| `void input_cb(void* ctx, IOReturn r, void* sender, IOHIDValueRef value)` | `IOHIDValueCallback = @convention(c) (UnsafeMutableRawPointer?, IOReturn, UnsafeMutableRawPointer?, IOHIDValue) -> Void` |
| `OSStatus appSwitch(EventHandlerCallRef, EventRef, void*)` | `@convention(c) (EventHandlerCallRef, EventRef, UnsafeMutableRawPointer?) -> OSStatus` |

### 13.3 Unmanaged 模式速记

```swift
// 把 self 转成 ctx
let ud = Unmanaged.passUnretained(self).toOpaque()

// 在 C 回调中取回 self
let jc = Unmanaged<JoystickController>.fromOpaque(ctx).takeUnretainedValue()
```

- 用 `passUnretained` / `takeUnretainedValue`: 不增加引用计数, 等价 OC 中 ctx 不 retain self
- 用 `passRetained` / `takeRetainedValue`: 增加引用计数, 需要在某个时机 `release()`, 容易泄漏, 不推荐

### 13.4 Swift 中常见的 IOKit 隐式转换陷阱

**问题**: `IOHIDValueGetElement(value)` 返回 `IOHIDElement`, 但在 `value` 为 `IOHIDValue`(不透明类型)时, Swift 隐式转换有时不工作.

**解决**:
```swift
let elt = IOHIDValueGetElement(value)
let cookie = IOHIDElementGetCookie(elt)
```

如果编译报 "Cannot convert value of type 'IOHIDElement' to expected...", 显式 `as IOHIDElement` 或重新查表.

### 13.5 CGEvent 内存管理

Swift 中 `CGEvent` 是值类型 (bridged), ARC 自动管理, 不需要 `CFRelease`. 在 Objective-C 中要写:
```objc
CGEventRef e = CGEventCreateKeyboardEvent(NULL, vk, true);
CGEventPost(kCGHIDEventTap, e);
CFRelease(e);
```

Swift 直接:
```swift
let e = CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: true)
e.post(tap: .cghidEventTap)
```

### 13.6 NSTimer vs CFRunLoopTimer

| 特性 | NSTimer | CFRunLoopTimer |
|---|---|---|
| 引用循环 | 需 `[weak self]` | 不需要 (C API) |
| Mode 切换 | 需手动 add to mode | 需手动 add to mode |
| deinit 停止 | `invalidate()` | `CFRunLoopTimerInvalidate()` |
| 80Hz 精度 | 足够 | 更精确 |

**推荐**: 用 `Timer.scheduledTimer` 即可, 与 OC 行为一致.

### 13.7 NIB 加载 Swift 类的要求

- Swift 类必须继承 `NSObject`
- 必须标记 `@objc`
- XIB 中 `customClass` 必须匹配类名, `customModule` 匹配 PRODUCT_MODULE_NAME
- @IBOutlet 必须用 `weak` (避免循环引用) 或 `@IBOutlet var` (强引用, 仅当需要持有)

---

## 14. OC 文件 → Swift 文件映射表

| OC 文件 | Swift 文件 | 行数估算 (OC 行 → Swift 行) |
|---|---|---|
| `main.m` (8 行) | `Sources/App/main.swift` | 8 → 3 |
| `ApplicationController.h/.m` (160 行) | `Sources/UI/ApplicationController.swift` | 160 → 150 |
| `Config.h/.m` (100 行) | `Sources/Config/Config.swift` | 100 → 110 |
| `ConfigsController.h/.m` (300 行) | `Sources/Config/ConfigsController.swift` | 300 → 200 |
| `JSAction.h/.m` + `SubAction.h/.m` (60 行) | `Sources/Actions/JSAction.swift` | 60 → 70 |
| `JSActionButton.h/.m` (30 行) | `Sources/Actions/JSActionButton.swift` | 30 → 25 |
| `JSActionAnalog.h/.m` (60 行) | `Sources/Actions/JSActionAnalog.swift` | 60 → 60 |
| `JSActionHat.h/.m` (90 行) | `Sources/Actions/JSActionHat.swift` | 90 → 60 |
| `Joystick.h/.m` (130 行) | `Sources/Devices/Joystick.swift` | 130 → 120 |
| `JoystickController.h/.m` (250 行) | `Sources/Devices/JoystickController.swift` | 250 → 220 |
| `KeyInputTextView.h/.m` (200 行, 含 100 行键码表) | `Sources/UI/KeyInputTextView.swift` + `Sources/CKeys.swift` | 200 → 60 + 60 |
| `Target.h/.m` (60 行) | `Sources/Targets/Target.swift` | 60 → 60 |
| `TargetConfig.h/.m` (40 行) | `Sources/Targets/TargetConfig.swift` | 40 → 30 |
| `TargetController.h/.m` (200 行) | `Sources/UI/TargetController.swift` | 200 → 150 |
| `TargetKeyboard.h/.m` (50 行) | `Sources/Targets/TargetKeyboard.swift` | 50 → 30 |
| `TargetMouseBtn.h/.m` (50 行) | `Sources/Targets/TargetMouseBtn.swift` | 50 → 30 |
| `TargetMouseMove.h/.m` (90 行) | `Sources/Targets/TargetMouseMove.swift` | 90 → 50 |
| `TargetMouseScroll.h/.m` (30 行) | `Sources/Targets/TargetMouseScroll.swift` | 30 → 20 |
| `TargetToggleMouseScope.h/.m` (30 行) | `Sources/Targets/TargetToggleMouseScope.swift` | 30 → 15 |
| (项目) `enjoy3_Prefix.pch` | `Sources/enjoy3-Bridging-Header.h` | 30 → 15 |
| (项目) `Enjoy2.xcodeproj` | `project.yml` | 1500 → 60 |

**总 OC 行数** (估算): 1968 行
**总 Swift 行数** (估算): 1500 行 (代码更紧凑, 加上文件头和注释)

---

## 15. 常见 bug 与修复手册

### Bug 1: "Cannot find 'Xxx' in scope"

**症状**: 编译报 "Cannot find type 'Xxx' in scope"
**原因**: Swift 类未声明 `import` 或类名拼写错误
**修复**:
- 检查同模块文件是否都创建了
- 检查是否漏写 `class Xxx: NSObject`
- 检查 XIB 类名是否与 Swift 类名完全一致 (大小写敏感)

### Bug 2: "@convention(c) closure cannot capture context"

**症状**: 编译报 "@convention(c) closure cannot capture..."
**原因**: `@convention(c)` 闭包试图捕获 Swift 局部变量
**修复**: 把闭包改为顶层 (`let` 在文件全局), 通过 `Unmanaged` 传 self 指针, 在闭包内 `takeUnretainedValue()` 取回

### Bug 3: 启动后立刻崩, 控制台报 "Unknown class Xxx in Interface Builder file"

**症状**: 启动后立即崩, Console 报 "Could not load NIB in bundle..." 或 "Unknown class ApplicationController in Interface Builder file"
**原因**: XIB 中 `customClass="Xxx"` 找不到对应 Swift 类
**修复**:
- 确认 XIB 中添加了 `customModule="enjoy3" customModuleProvider="target"`
- 确认 Swift 类继承 NSObject + @objc
- 确认 PRODUCT_MODULE_NAME = enjoy3
- 重新 `xcodegen generate` 让 NIB 重新编译

### Bug 4: IOHIDValueGetIntegerValue 编译错误

**症状**: "Cannot find 'IOHIDValueGetIntegerValue' in scope"
**原因**: Bridging Header 缺失或 IOKit 框架未引入
**修复**:
- 检查 `Sources/enjoy3-Bridging-Header.h` 中 `#import <IOKit/hid/IOHIDLib.h>`
- 检查 `project.yml` 中 `SWIFT_OBJC_BRIDGING_HEADER` 路径正确
- 检查 `dependencies` 中 `IOKit.framework` 已加入

### Bug 5: CGEvent 编译报 "Type 'CGEvent' has no member 'postToPSN'"

**症状**: `event.postToPSN(&psn)` 报 "no member"
**原因**: macOS 12 Swift API 中 `postToPSN` 存在但需要 `import Carbon`
**修复**: Swift 文件顶部加 `import Carbon` (Bridging Header 已 import, Swift 端需再写一次)

### Bug 6: 80Hz 定时器在滚动窗口时不触发

**症状**: 鼠标移动在拖动滚动条时卡顿
**原因**: Timer 默认在 `.default` mode, 滚动时 RunLoop 处于 `.eventTracking` mode
**修复**: `RunLoop.current.add(timer!, forMode: .common)`

### Bug 7: 切到后台后手柄事件丢失

**症状**: 切换到非 enjoy3 应用, 手柄事件不触发
**原因**: App 进入后台后 IOHID 事件被挂起
**修复**: 在 `awakeFromNib` 中 `ProcessInfo.processInfo.beginActivity(options: 0x00FFFFFF, reason: ...)` (Swift 5 用 `ProcessInfo.ActivityOptions(rawValue: 0x00FFFFFF)`)

### Bug 8: C 回调中访问 NSOutlineView 崩

**症状**: 插拔手柄时崩
**原因**: IOHID 回调在内部线程触发, 但 NSOutlineView 必须在主线程访问
**修复**: `DispatchQueue.main.async { jc.outlineView.reloadData() }`

### Bug 9: 旧用户配置文件加载崩溃

**症状**: 加载时崩或 nil deref
**原因**: JSON 格式不匹配或 `TargetConfig.config` 找不到对应 Config
**修复**:
- `Config.loadSkel(fromJSON:)` 阶段一解析失败时跳过该文件, 不崩溃
- `Config.load(fromJSON:)` 阶段二对 `Target.unstringify` 返回 nil 时跳过该 entry
- 在 `ConfigsController.load` 中 `if currentConfig == nil, !configs.isEmpty { currentConfig = configs.first }`

### Bug 10: Sparkle 自动更新失效

**症状**: 菜单中 "Check for Updates" 不响应
**原因**: Sparkle.framework 未嵌入或 Info.plist 中 SUFeedURL 丢失
**修复**:
- 检查 `build/Release/enjoy3.app/Contents/Frameworks/Sparkle.framework` 存在
- 检查 Info.plist 中 `SUFeedURL` 和 `SUPublicDSAKeyFile` 字段存在
- 检查 `dsa_pub.pem` 在 `Contents/Resources/`

### Bug 11: `productId = vendorId` 原 OC bug 保留与否

**症状**: 不确定是否修复
**决策**:
- 如果保留, 用户已有配置的 actionKey 保持不变
- 如果修复, 用户需重新创建 mapping
- **建议保留** (避免用户数据迁移), 在代码注释中说明

### Bug 12: `ConfigsController removePressed:` 不删磁盘文件

**症状**: 删除 Config 后磁盘 JSON 还在
**决策**: `save()` 中已加入清理逻辑, 会删除已不存在的 Config 文件. 行为改进

---

## 16. 端到端验证清单

执行顺序:

1. [ ] **编译通过**: `xcodegen generate && xcodebuild ... build` 无错
2. [ ] **启动**: `open build/Release/enjoy3.app`, Dock 图标出现
3. [ ] **菜单**: 菜单栏 "enjoy3" 项可见, File 菜单 "Joysticks active" 可点
4. [ ] **主窗口**: 主窗口出现, NSDrawer 打开 (左侧抽屉)
5. [ ] **本地化**: 切到英文系统 → 英文菜单; 切到中文 → 中文菜单 (如系统是中文, 验证 zh-Hans 资源)
6. [ ] **空手柄列表**: 左侧 NSOutlineView 为空
7. [ ] **插入手柄**: 插入手柄 → 树形视图出现设备, 展开后看到 Button/Analog/Hat
8. [ ] **选中按钮**: 选中某个 Button → 右侧面板显示标题 "<Config> > <ActionName>"
9. [ ] **配置 Key**: 选 "Key" 单选, 按下键盘 → 输入框显示按键名, JSON 文件落盘到 `~/Library/Application Support/enjoy3/mappings/`
10. [ ] **JSON 内容正确**: `cat <file>.json` 显示 `{"name": "untitled", "format": "enjoy3-1.1", "entries": {...}}`
11. [ ] **触发键盘事件**: Start 工具栏按钮 → 按下手柄按钮 → 对应键盘事件被合成到前台应用 (如 Terminal)
12. [ ] **配置 MouseBtn**: 选 "Mouse Button" → 选 Left → 按手柄 → 点击事件
13. [ ] **配置 MouseMove**: 选 "Mouse Move" → 选 X → 摇动摇杆 → 鼠标水平移动
14. [ ] **配置 Scroll**: 选 "Scroll" → 选 Up → 按手柄 → 滚轮上滚
15. [ ] **配置 ToggleScope**: 选 "Toggle" → 按手柄 → 切换 frontWindowOnly
16. [ ] **应用切换自动激活**: 创建一个名为 "Terminal" 的 Config, 切到 Terminal → 自动激活该 Config
17. [ ] **恢复 neutral**: 切回 enjoy3 或非匹配 App → 恢复上一次手动激活的 Config
18. [ ] **拔手柄**: 拔掉手柄 → 树形视图移除设备
19. [ ] **保存退出**: Cmd+Q → JSON 配置正常落盘
20. [ ] **重启数据保留**: 重启 enjoy3 → 上次选中的 Config 自动激活

**全部通过即视为迁移成功**.

---

## 附录 A: 备份策略

迁移前:
```bash
cd /Users/xufei/Documents/claudecode
cp -R enjoy3 enjoy3.backup.before-swift-migration
```

迁移中: 不要删除 `enjoy3.backup/`, 每个阶段完成后可在两个目录间 diff.

迁移成功后:
```bash
rm -rf enjoy3.backup enjoy3.backup.before-swift-migration enjoy3/Enjoy2.xcodeproj.backup
```

---

## 附录 B: Git 提交策略 (如启用 git)

每个阶段完成后提交一次:
```bash
cd /Users/xufei/Documents/claudecode/enjoy3
git add -A
git commit -m "阶段 1: 工程骨架 (xcodegen + Bridging Header + main.swift)"
```

便于回退与 review.

---

## 附录 C: 阶段间依赖图

```
阶段 1 (工程骨架)
  ↓
阶段 2 (Target + JSAction + Config) ─── 可与阶段 3 并行
  ↓                                   ↓
阶段 4 (输出层验证)              阶段 3 (手柄层)
  ↓                                   ↓
  └──────────┬────────────────────────┘
             ↓
        阶段 5 (UI 控制器)
             ↓
        阶段 6 (XIB 类名)
             ↓
        阶段 7 (验证)
```

**最小可运行**: 阶段 1 + 阶段 2 + 阶段 3 + 阶段 5 + 阶段 6 = 可启动, 基础功能可用.
阶段 4 已在阶段 2 中完成, 阶段 7 是端到端测试.

---

**本计划完成时间**: 2026-06-14
**预计实施时间**: 3-4 个工作日
**关键文件**: 见第 4.2 节与第 7-10 阶段
