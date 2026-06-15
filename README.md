# enjoy3

一款简洁的 macOS 应用，可以将游戏手柄 / 摇杆的输入转换为键盘或鼠标事件。

如果你玩过某些只支持键鼠操作的游戏，但想用手柄或摇杆来玩，那么 enjoy3 就是为你准备的。enjoy3 可以将手柄输入映射为：

- 按键事件
- 鼠标点击
- 鼠标移动（适用于摇杆）
- 滚轮滚动

enjoy3 支持多套配置（用于不同游戏或程序），你甚至可以把手柄按键映射为「切换配置」，在游戏过程中实时切换。

enjoy3 由 [@nongraphical](http://nongraphical.com) 编写，源自 [Enjoy by Sam McCall](https://yukkurigames.com/enjoyable/)。基于 MIT 协议开源。

> 本仓库的 enjoy3 版本在原 Enjoy2 基础上做了若干维护性更新：完整迁移至 Swift 5.9 + XcodeGen 工程、移除 JSONKit 第三方依赖、改用系统原生 `NSJSONSerialization`，并新增简体中文界面与一键编译脚本。旧的 Objective-C 源码完整保留在 [`oc-legacy`](https://github.com/xf8599/enjoy2/tree/oc-legacy) 分支。

## 安装与编译

### 一键编译（推荐）

仓库自带 `build.sh`，可以在 arm64 Mac 上一键完成「编译 + 重置辅助功能授权 + 启动」：

```bash
./build.sh                # 编译 + 重置授权 + 启动
./build.sh --no-reset     # 编译 + 启动（不重置权限）
./build.sh --no-open      # 只编译，不启动
./build.sh --clean        # 清理后再编译
./build.sh --help         # 查看参数说明
```

首次运行会弹出「辅助功能」授权请求，请在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 enjoy3。

### 手动编译

工程使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成，先装好 xcodegen：

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project enjoy3.xcodeproj -configuration Release -arch arm64 build
open build/Release/enjoy3.app
```

> 仓库不再提交 `enjoy3.xcodeproj`（已加入 `.gitignore`），每次拉新代码后记得跑一次 `xcodegen generate`。

## 版本与分支

| 分支 | 内容 | 适用场景 |
|---|---|---|
| `master` | **当前主线** — Swift 5.9 + XcodeGen 工程，所有功能 | 日常使用与新功能开发 |
| `oc-legacy` | 旧 Objective-C 版本（最后一个 OC commit `8aca49b`） | 找回 OC 源码、对照 Swift 翻译、查阅 Enjoy2 历史实现 |

OC 源码不会被删除，它永久保留在 `oc-legacy` 分支及之前的所有 commit 历史中。需要时：

```bash
# 本地查看 OC 版本
git checkout oc-legacy

# 或单独 clone 出来
git clone -b oc-legacy https://github.com/xf8599/enjoy2.git enjoy3-oc
# enjoy3-oc/ 里可以直接用 Xcode 打开 Enjoy2.xcodeproj 编译 (pbxproj 工程)
```

详细的 OC → Swift 翻译过程参见 [`MIGRATION_PLAN.md`](./MIGRATION_PLAN.md)。

## 使用方法

启动后，或在 enjoy3 处于暂停状态时，按下任意手柄按键或拨动摇杆，应用会自动跳转到该按键 / 摇杆对应的配置项。然后在右侧列表中选择一种映射方式即可。

如果要把摇杆轴用于鼠标移动，请选中左侧的「Analog」子项。

### 术语

- **映射（Mapping）**：定义按下某个手柄按键或拨动某个轴时，触发哪些键盘按键、鼠标按键或鼠标移动。
- **翻译（Translation）**：定义不同型号的手柄硬件按键 / 轴如何对应到统一的虚拟按键 / 轴，便于一套映射适配多种手柄。

### 鼠标映射模式

enjoy3 提供两种鼠标映射模式：全局模式与单窗口模式。默认进入全局模式，可以把手柄按键映射为「切换鼠标作用域」来在两种模式之间切换。在某些游戏中，其中一种模式可能与游戏的输入处理逻辑更兼容，可以根据实际情况选择。

## 配置文件位置

所有配置（映射与翻译）都保存在用户目录下的 Application Support 中：

```
~/Library/Application Support/enjoy3/mappings/
```

> 注：旧版本 Enjoy2 的配置保存在 `~/Library/Application Support/Enjoy2/mappings/`，升级到 enjoy3 后需要手动迁移。

配置文件使用 JSON 格式，可在不同机器之间直接复制。

## 系统要求

- macOS（推荐 Apple Silicon，原生 arm64 构建；Intel Mac 需自行调整 `build.sh` 中的 `-arch`）
- USB 游戏手柄 / 摇杆 / 控制器

## 编译依赖

- Xcode 14+（自带 Sparkle.framework、IOHIDEvent 等系统框架）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.38+（从 `project.yml` 生成 `.xcodeproj`）
- 不再需要 JSONKit（已迁移至 `NSJSONSerialization`）

## 更新日志

### enjoy3 (Swift)

- **OC → Swift 迁移**：全部业务代码（ApplicationController、Config、ConfigsController、JSAction 家族、Joystick、JoystickController、KeyInputTextView、Target 家族）从 Objective-C 改写为 Swift 5.9
- **工程现代化**：旧 pbxproj 工程替换为 XcodeGen（`project.yml`），部署目标 macOS 12，arm64 原生
- **辅助功能授权**：启动时主动调 `AXIsProcessTrustedWithOptions` 触发授权框（解决 ad-hoc 签名 app 不自动弹框的问题）
- **UI 导航死区过滤**：修复 `JoystickController` 在 axis 死区外无法选中 SubAction 的 bug（`expandRecursive` 不展开父 JSAction 导致 `row(forItem:)` 返回 -1）
- **dark mode 适配**：Config 列表 `selectionHighlightStyle=.regular` + `DarkTableHeaderView`；Joysticks 面板运行时把 cell-based NSOutlineView 替换为 view-based（解决 XIB 弃用 cell-based 模式下 dark mode 文字变黑问题）
- **窗口布局**：3 栏 744×520 → 782×520（Editor Panel 加宽 10%）
- **OC 源码保留**：旧版本完整保留在 `oc-legacy` 分支（commit `8aca49b`），永久可查
- 移除 JSONKit 第三方依赖，统一使用 `NSJSONSerialization`
- 修复 `ConfigsController` 在 add / remove / rename 后未调用 `save` 导致配置丢失的 bug
- 修复 `loadAllFromDir` 后 `currentConfig` 可能为 `NULL` 引发崩溃的 bug
- 修复 `selectedMapping` 为 `nil` 时 `NSUserDefaults` 抛异常的崩溃
- 修复 `TargetController commit` 后未立即落盘的 bug
- 新增简体中文本地化（zh-Hans.lproj）
- 新增 `build.sh` 一键编译脚本（支持 `--no-reset` / `--no-open` / `--clean`）
- Bundle ID 调整为 `net.tunah.enjoy3`，配置文件目录由 `Enjoy2` 改为 `enjoy3`

### 1.2

- 配置改为 JSON 格式存储

### 1.1

- 从 Enjoy Fork
- 新增鼠标移动支持
- 新增鼠标按键支持
- 新增滚轮支持
- 支持两种鼠标移动模式

## 致谢

- 原项目 [Enjoy by Sam McCall](https://yukkurigames.com/enjoyable/)
- [JSONKit](https://github.com/johnezang/JSONKit)（1.x 历史版本使用，enjoy3 已移除依赖）
