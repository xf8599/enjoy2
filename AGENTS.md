# enjoy3 — 项目上下文

macOS 手柄映射工具(前身 Enjoy2,Objective-C)。本工程已完成 OC → Swift 5.9 迁移,
用 XcodeGen 管理,arm64 原生构建,面向 Apple Silicon。

## 构建

```bash
./build.sh              # 编译 + 重置辅助功能授权 + 启动
./build.sh --no-open    # 只编译和重置授权,不启动
./build.sh --no-reset   # 不重置辅助功能授权
./build.sh --clean      # 先清理再编译
```

或手动两步:

```bash
xcodegen generate       # project.yml → enjoy3.xcodeproj (勿手改 .xcodeproj)
xcodebuild -project enjoy3.xcodeproj -scheme enjoy3 -configuration Release -arch arm64 build
```

**产物路径**:`.build/Build/Products/enjoy3.app`

`project.yml` 通过 `CONFIGURATION_BUILD_DIR` / `OBJROOT` / `SYMROOT` 把产物锁在项目内
`.build/`,不污染 `~/Library/Developer/Xcode/DerivedData/`。**改构建配置时,`build.sh`
里的 `APP_PATH` 必须同步改**,否则脚本在编译成功后误报"编译失败"。

- 部署目标:macOS 12.0
- 架构:arm64(`build.sh` 硬编码 `-arch arm64`,不含 Intel 通用二进制)
- Bundle ID:`net.tunah.enjoy3`
- `enjoy3.xcodeproj/` 在 .gitignore 中,**所有工程改动都改 `project.yml`**

## 目录结构

```
Sources/
  App/main.swift              入口
  Config/                     Config.swift(mapping 解析) + ConfigsController.swift(切换/增删)
  Devices/                    Joystick.swift(设备读写) + JoystickController.swift(手柄列表)
  Actions/                    JSAction 家族: 把手柄事件翻译成动作
  Targets/                    Target 家族: 动作的输出目标(键盘/鼠标移动/点击/滚轮/切换)
  UI/                         ViewController + Cell,菜单栏与主窗口
  CKeys.swift                 键码常量表
  enjoy3-Bridging-Header.h    OC 头文件桥接(Cocoa/IOKit/Carbon/ApplicationServices)
English.lproj/ zh-Hans.lproj/ MainMenu.xib + 各窗口 XIB(英文/简体中文)
JoystickImages/  icon.icns  Credits.rtf  license.txt
```

配置数据在 `~/Library/Application Support/enjoy3/mappings/`,JSON 格式
`format="enjoy3-1.1"`。改 Config 解析时注意向后兼容,用户本地已有旧数据。

## 约定

- **UI 用 XIB 而非纯代码**:新增界面先加 XIB,再在 `ApplicationController.swift` 里
  `NSNib` 加载。改 XIB 后务必确认没有引用已删除的 Objective-C 类名。
- **删除文件用 `/usr/bin/trash`**,不用 `rm`。
- 搜索默认限定在本仓库内。
- 不主动做代码简化/重构,除非明确要求。
- 未经要求不截图验证。

## 已移除的依赖

- **Sparkle 1.8.0 自动更新**(2026-09-30 移除)。原链路是死代码:无任何调用、
  appcast 指向 2014 年的失效安装包、Autoupdate.app 打包时被排除、框架仅 x86_64。
  移除时同步清理了 `Info.plist` 的 SU 键、bridging header 的 import、EN/ZH `MainMenu.xib`
  的 "Check for Updates" 菜单项及 `customClass="SUUpdater"` 的 customObject。
  **如果以后要重新接自动更新,直接上 Sparkle 2.x,不要恢复 1.x。**
- **JSONKit**,已换成系统 `NSJSONSerialization`。

## 权限

App 需要**辅助功能权限**操作键鼠事件。`build.sh` 用 `tccutil reset Accessibility`
重置,方便调试时重新授权。菜单栏会主动弹出授权提示。
