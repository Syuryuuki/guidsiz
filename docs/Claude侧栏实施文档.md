# Claude 侧栏实施文档

## 1. 文档目的

本文档描述如何在 Ghostty macOS 宿主中实施 Claude 项目/会话侧栏能力，包括：

1. 具体改动落点
2. 文件职责划分
3. 分阶段实施步骤
4. 每一步的验证方式
5. 风险与回退策略

## 2. 实施约束

### 2.1 范围约束

本次实施限定在以下范围：

1. 仅修改 `macos/Sources` 下的 Swift/AppKit/SwiftUI 宿主代码
2. 允许增加 `docs/`
3. 不修改 Zig 核心终端语义

### 2.2 技术约束

1. 右侧终端继续使用现有 `TerminalView`
2. 会话恢复优先使用 `workingDirectory + initialInput`
3. 已打开会话优先聚焦，不重复创建 tab
4. 读取 Claude 数据时优先依赖 `sessions-index.json`

### 2.3 验证约束

完成宿主层修改后至少进行以下构建验证：

```bash
zig build -Demit-macos-app=false
cd /Users/zlj/project/guidsiz/macos
nu build.nu --scheme Ghostty --configuration Debug --action build
```

## 3. 文件级实施设计

### 3.1 新增文件

建议新增目录：

```text
macos/Sources/Features/Claude Sidebar/
```

建议新增文件：

1. `ClaudeModels.swift`
2. `ClaudeIndexReader.swift`
3. `ClaudeProjectsStore.swift`
4. `ClaudeSessionRegistry.swift`
5. `ClaudeSessionLauncher.swift`
6. `ClaudeSidebarView.swift`
7. `ClaudeWorkspaceView.swift`

### 3.2 修改文件

建议修改以下文件：

1. `macos/Sources/App/macOS/AppDelegate.swift`
2. `macos/Sources/Features/Terminal/TerminalController.swift`
3. `macos/Sources/Features/Terminal/BaseTerminalController.swift`
4. `macos/Sources/Ghostty/Surface View/SurfaceView.swift`
5. `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`
6. `macos/Sources/Helpers/Extensions/UserDefaults+Extension.swift`

## 4. 各文件职责

### 4.1 ClaudeModels.swift

职责：

1. 定义 `ImportedClaudeProject`
2. 定义 `ClaudeSessionSummary`
3. 定义 `ClaudeSessionContext`
4. 定义索引文件对应的 DTO

建议包含：

1. `SessionsIndexFile`
2. `SessionsIndexEntry`
3. `ImportedClaudeProject`
4. `ClaudeSessionSummary`
5. `ClaudeSessionContext`

### 4.2 ClaudeIndexReader.swift

职责：

1. 扫描 `~/.claude/projects/**/sessions-index.json`
2. 按真实 `projectPath` 匹配目标项目
3. 解析会话列表
4. 提供兜底 `.jsonl` 解析能力

建议接口：

```swift
protocol ClaudeIndexReading {
    func findSessions(forProjectPath projectPath: String) throws -> [ClaudeSessionSummary]
    func hasClaudeData(forProjectPath projectPath: String) -> Bool
}
```

### 4.3 ClaudeProjectsStore.swift

职责：

1. 管理已导入项目
2. 管理项目到会话列表的映射
3. 持久化导入列表
4. 提供刷新、导入、移除、搜索

建议主状态：

1. `@Published var projects: [ImportedClaudeProject]`
2. `@Published var sessionsByProject: [String: [ClaudeSessionSummary]]`
3. `@Published var loadingState`
4. `@Published var searchText`

### 4.4 ClaudeSessionRegistry.swift

职责：

1. 注册已打开的 Claude session
2. 按 `sessionId` 查询已打开 Surface
3. 清理失效弱引用

建议接口：

```swift
final class ClaudeSessionRegistry {
    func register(sessionId: String, projectPath: String, surface: Ghostty.SurfaceView, controller: BaseTerminalController)
    func unregister(surface: Ghostty.SurfaceView)
    func surface(for sessionId: String) -> Ghostty.SurfaceView?
    func controller(for sessionId: String) -> BaseTerminalController?
}
```

### 4.5 ClaudeSessionLauncher.swift

职责：

1. 将 UI 点击事件转成 launch/focus 行为
2. 选择当前窗口新 tab 或新窗口
3. 通过 `initialInput` 恢复 Claude 会话

建议主接口：

```swift
final class ClaudeSessionLauncher {
    func activate(session: ClaudeSessionSummary, preferredController: TerminalController?) -> ActivationResult
}
```

### 4.6 ClaudeSidebarView.swift

职责：

1. 实现左侧项目/会话树 UI
2. 提供工具栏和搜索框
3. 发出导入、刷新、激活、移除动作

### 4.7 ClaudeWorkspaceView.swift

职责：

1. 作为普通 terminal window 的根容器
2. 左右分栏组合 `ClaudeSidebarView` 与 `TerminalView`
3. 管理侧栏是否显示、宽度、当前选中状态

## 5. 对现有文件的改动策略

### 5.1 AppDelegate.swift

实施内容：

1. 挂载 app-global 的 `ClaudeProjectsStore`
2. 提供导入项目的对话框入口
3. 可选地在菜单中增加“导入 Claude 项目”

建议新增属性：

```swift
let claudeProjectsStore = ClaudeProjectsStore()
```

建议新增方法：

1. `importClaudeProject()`
2. `refreshClaudeProjects()`

### 5.2 TerminalController.swift

当前 `windowDidLoad` 中设置 root view 的位置是主要挂点。  
实施内容：

1. 把 `TerminalView` 包装到 `ClaudeWorkspaceView` 中
2. 仅对普通 `TerminalController` 启用左侧栏
3. 保持原有窗口、titlebar、tab、fullscreen 流程不变

当前：

```swift
let container = TerminalViewContainer {
    TerminalView(ghostty: ghostty, viewModel: self, delegate: self)
}
```

实施后建议变成：

```swift
let container = TerminalViewContainer {
    ClaudeWorkspaceView(
        ghostty: ghostty,
        controller: self,
        projectsStore: appDelegate.claudeProjectsStore
    ) {
        TerminalView(ghostty: ghostty, viewModel: self, delegate: self)
    }
}
```

### 5.3 BaseTerminalController.swift

实施内容：

1. 在创建初始 `SurfaceView` 后，如果 base config 表示它属于 Claude session，则补注册
2. 在 surface 关闭时同步清理注册表
3. 提供“当前 controller 偏好打开 Claude 会话”的辅助能力

### 5.4 SurfaceView.swift

实施内容：

1. 给 `Ghostty.SurfaceView` 增加关联的 Claude session 上下文
2. 该上下文不影响终端核心行为，只作为宿主元数据

建议新增：

```swift
var claudeSessionContext: ClaudeSessionContext?
```

### 5.5 SurfaceView_AppKit.swift

实施内容：

1. 在 `Codable` 编解码中加入 `claudeSessionId`
2. 在恢复时，如果存在 Claude 会话上下文，则使用对应 `projectPath` 和 resume 命令重建

这是保证窗口恢复行为正确的关键修改点。

### 5.6 UserDefaults+Extension.swift

实施内容：

1. 增加已导入 Claude 项目列表 key
2. 增加侧栏显隐状态 key
3. 增加展开状态 key

## 6. 推荐实施步骤

### 阶段 A：基础数据层

目标：

1. 能导入项目
2. 能读出会话摘要
3. 能持久化导入项目列表

步骤：

1. 新增 `ClaudeModels.swift`
2. 新增 `ClaudeIndexReader.swift`
3. 新增 `ClaudeProjectsStore.swift`
4. 在 `AppDelegate` 中挂载 store
5. 临时用日志或调试菜单触发导入

验收：

1. 可成功导入至少一个有 Claude 数据的项目路径
2. 刷新后 `sessionsByProject` 中有正确会话列表

### 阶段 B：左侧 UI 壳层

目标：

1. 普通终端窗口中出现左侧栏
2. 右侧终端功能不受影响

步骤：

1. 新增 `ClaudeSidebarView.swift`
2. 新增 `ClaudeWorkspaceView.swift`
3. 修改 `TerminalController.windowDidLoad`
4. 将原 `TerminalView` 包装到新 root 中

验收：

1. 左侧栏可显示项目和会话
2. 终端仍可正常输入、分屏、开 tab

### 阶段 C：会话激活

目标：

1. 点会话可恢复
2. 已打开会话不重复开

步骤：

1. 新增 `ClaudeSessionRegistry.swift`
2. 新增 `ClaudeSessionLauncher.swift`
3. 从侧栏点击调用 launcher
4. 使用 `TerminalController.newTab/newWindow`
5. 使用 `workingDirectory + initialInput`

验收：

1. 未打开会话可恢复
2. 已打开会话可聚焦

### 阶段 D：恢复与一致性

目标：

1. Claude session terminal 可跟随窗口恢复
2. 注册表状态和实际 UI 一致

步骤：

1. `SurfaceView` 添加 `ClaudeSessionContext`
2. `SurfaceView_AppKit` 扩展 `encode/decode`
3. 关闭 surface 时清理 registry
4. 恢复后重新注册 registry

验收：

1. 应用重启后，Claude session terminal 恢复正确

### 阶段 E：体验补强

目标：

1. 降低误操作和失败成本
2. 提供基础管理体验

步骤：

1. 增加刷新按钮
2. 增加错误提示
3. 增加移除项目
4. 增加会话搜索
5. 增加 active/opened 状态展示

## 7. 关键实现细节

### 7.1 项目导入流程

建议实现：

1. 调起 `NSOpenPanel`
2. 仅允许选择目录
3. 用户选中目录后调用 `ClaudeIndexReader.hasClaudeData`
4. 有数据则加入导入列表
5. 无数据则提示失败

### 7.2 会话恢复命令拼装

建议实现成独立方法：

```swift
func makeResumeInput(for sessionId: String) -> String {
    "claude -r \(sessionId)\n"
}
```

如果后续需要加前置检查，可统一修改这里。

### 7.3 激活逻辑伪代码

```swift
func activate(session: ClaudeSessionSummary) {
    if let surface = registry.surface(for: session.sessionId) {
        focus(surface)
        return
    }

    var config = Ghostty.SurfaceConfiguration()
    config.workingDirectory = session.projectPath
    config.initialInput = "claude -r \(session.sessionId)\n"

    let controller = currentTerminalController ?? TerminalController.newWindow(...)
    let opened = TerminalController.newTab(..., withBaseConfig: config) ?? TerminalController.newWindow(..., withBaseConfig: config)

    attachClaudeSessionContext(to: openedSurface, sessionId: session.sessionId, projectPath: session.projectPath)
    registry.register(...)
}
```

### 7.4 恢复策略

当前 `SurfaceView_AppKit` 仅恢复 `pwd`。  
需要扩展为：

1. 如果存在 `claudeSessionId + claudeProjectPath`
2. 则恢复时重新构造：
   - `config.workingDirectory = claudeProjectPath`
   - `config.initialInput = "claude -r <sessionId>\n"`
3. 否则按普通终端 restore 流程继续

### 7.5 active 状态判定

建议区分两个状态：

1. `opened`：已在应用内打开
2. `active`：当前聚焦会话

这样左侧栏可以同时表达“已开未聚焦”和“当前正在看”。

## 8. 验证清单

### 8.1 数据层验证

1. 导入一个有 `sessions-index.json` 的目录
2. 会话条数与索引一致
3. 修改时间排序正确
4. 搜索能命中 `firstPrompt`

### 8.2 UI 验证

1. 侧栏显示正常
2. 折叠展开不影响终端渲染
3. 在 tab/split 存在时布局仍稳定

### 8.3 激活验证

1. 点击未打开会话，终端能恢复该会话
2. 点击已打开会话，不会新增重复 tab
3. 会话激活后窗口置前且焦点正确

### 8.4 恢复验证

1. 重启应用后导入项目列表仍在
2. 恢复出来的 Claude 会话 terminal 仍能继续使用

### 8.5 失败验证

1. `claude` 不存在
2. 目标项目目录被删除
3. `sessions-index.json` 格式损坏
4. 目标 sessionId 无法恢复

## 9. 回退策略

如果实施过程中出现较大问题，可按以下粒度回退：

1. 仅回退 `ClaudeWorkspaceView` 包装层，恢复到纯 `TerminalView`
2. 保留数据层代码但隐藏 UI
3. 暂时禁用恢复能力，只保留项目/会话展示

建议将侧栏能力设计成可配置开关，便于临时禁用。

## 10. 后续扩展点

实施完成后，可扩展：

1. 自动监听 Claude 索引文件变化
2. 项目 pin/favorite
3. 会话按分支分组
4. 会话正文全文搜索
5. 右侧增加只读会话摘要预览面板

## 11. 逐文件实施清单

本节把“改哪些文件、先改什么、每个文件要做到什么”进一步落细。

### 11.1 `ClaudeModels.swift`

实施顺序：

1. 先定义 `sessions-index.json` DTO
2. 再定义业务模型
3. 最后定义错误类型

建议包含：

```swift
enum ClaudeDataError: Error {
    case projectNotFound
    case noSessionsIndex
    case malformedIndex
    case claudeCliNotFound
}
```

### 11.2 `ClaudeIndexReader.swift`

实施内容：

1. 封装 `FileManager` 扫描
2. 统一 JSONDecoder 的日期解析策略
3. 先实现主路径：`sessions-index.json`
4. 暂不实现复杂 `.jsonl` 解析，只做简化兜底

建议方法：

```swift
func findIndexFiles() throws -> [URL]
func loadIndex(at url: URL) throws -> SessionsIndexFile
func matchIndex(for projectPath: String) throws -> URL?
func findSessions(for projectPath: String) throws -> [ClaudeSessionSummary]
```

### 11.3 `ClaudeProjectsStore.swift`

实施内容：

1. 初始化时从 `UserDefaults` 恢复导入列表
2. 提供串行刷新，避免并发覆盖
3. 将刷新状态细化到项目级别

建议方法：

```swift
func restoreImportedProjects()
func persistImportedProjects()
func importProject(at path: String) async throws
func refreshAll() async
func refreshProject(_ project: ImportedClaudeProject) async
func removeProject(_ project: ImportedClaudeProject)
```

### 11.4 `ClaudeSidebarView.swift`

实施内容：

1. 左侧顶栏
2. 搜索框
3. 项目列表
4. 会话列表
5. 上下文菜单

建议拆分子视图：

1. `ClaudeSidebarHeader`
2. `ClaudeProjectSectionView`
3. `ClaudeSessionRowView`

### 11.5 `ClaudeWorkspaceView.swift`

实施内容：

1. 负责左右分栏
2. 持有 `selectedSessionId`
3. 持有 `sidebarVisible`
4. 持有 `sidebarWidth`

建议使用：

1. `HSplitView` 或自定义 `NavigationSplitView` 风格容器
2. 初期优先简单稳定，不做过多标题栏联动

### 11.6 `ClaudeSessionRegistry.swift`

实施内容：

1. 用弱引用避免循环持有
2. 提供定期或按需 `compact` 机制

建议方法：

```swift
func compact()
func isOpen(_ sessionId: String) -> Bool
func allOpenSessionIds() -> Set<String>
```

### 11.7 `ClaudeSessionLauncher.swift`

实施内容：

1. 先查 registry
2. 再查 `claude` CLI 是否存在
3. 组装 `SurfaceConfiguration`
4. 新建 tab/window

建议检查逻辑：

```swift
func resolveClaudeExecutable() -> String?
```

如果未来 `claude` 不在默认 PATH，可考虑：

1. 先读取用户 shell PATH
2. 或提供设置项

### 11.8 `AppDelegate.swift`

实施内容：

1. 新增项目导入入口
2. 提供到 `ClaudeProjectsStore` 的共享访问
3. 可选菜单项先不做 nib 改动，先通过代码或命令面板挂入口

### 11.9 `TerminalController.swift`

实施内容：

1. 在 `windowDidLoad` 替换 root view
2. 保持 `initialContentSize` 逻辑可用
3. 不破坏 titlebar、fullscreen、tab 恢复

建议先做一个开关：

```swift
let claudeSidebarEnabled = true
```

这样调试时可以快速回退 root 包装。

### 11.10 `SurfaceView.swift` 与 `SurfaceView_AppKit.swift`

实施内容：

1. 增加 Claude session context 挂载点
2. 增加编解码字段
3. 恢复时重建 resume 行为

建议新增编码键：

1. `claudeSessionId`
2. `claudeProjectPath`

## 12. 接口与调用链细化

### 12.1 导入调用链

```text
ClaudeSidebarView
-> AppDelegate.importClaudeProject()
-> NSOpenPanel
-> ClaudeProjectsStore.importProject(at:)
-> ClaudeIndexReader.matchIndex(for:)
-> ClaudeProjectsStore.refreshProject(_:)
```

### 12.2 激活调用链

```text
ClaudeSidebarView.onTapSession
-> ClaudeSessionLauncher.activate(session, preferredController:)
-> ClaudeSessionRegistry.surface(for:)
-> TerminalController.newTab/newWindow
-> Surface 注册
-> Ghostty.moveFocus(to:)
```

### 12.3 恢复调用链

```text
AppKit restoration
-> SurfaceView decode
-> 读取 ClaudeSessionContext
-> 组装 baseConfig
-> Surface 初始化
-> ClaudeSessionRegistry 注册
```

## 13. 实现时的关键取舍

### 13.1 是否复用当前 shell

结论：

不复用，默认新建 tab。

原因：

1. 不可打断用户当前 shell
2. 更符合“会话工作区”的语义

### 13.2 是否将侧栏做成 app-global 单例 UI

结论：

不做 app-global 单例 UI。  
项目 store 是 app-global，选中状态是 window-local。

### 13.3 是否先做窗口恢复

结论：

功能上可以放到 M4，但代码设计上从第一版起就要预留 `ClaudeSessionContext`，否则后面会返工。

## 14. 测试矩阵

### 14.1 正常路径

1. 导入单项目，单会话
2. 导入单项目，多会话
3. 导入多项目
4. 当前窗口新 tab 恢复
5. 无窗口时新建 window 恢复

### 14.2 去重路径

1. 连续点击同一会话两次
2. 先打开会话，再从侧栏点击同一会话
3. 关闭会话后再次点击

### 14.3 异常路径

1. `claude` CLI 缺失
2. 项目路径不存在
3. `sessions-index.json` 损坏
4. `sessionId` 不可恢复

### 14.4 恢复路径

1. 退出前打开两个 Claude 会话 tab
2. 重启后自动恢复
3. 再点击左侧同一会话，检查是否聚焦而不是重复打开

## 15. 推荐提交粒度

为降低回归风险，建议按以下粒度提交：

1. `Add Claude data models and project store`
2. `Add Claude sidebar shell for macOS terminal windows`
3. `Add Claude session launch and focus registry`
4. `Persist Claude session context across restore`
5. `Refine Claude sidebar UX and error handling`

## 16. 实施完成定义

只有同时满足以下条件，才算“实施完成”：

1. 构建通过
2. 普通终端窗口能稳定显示左侧栏
3. 导入至少一个真实 Claude 项目可用
4. 会话恢复链路可用
5. 去重聚焦可用
6. 重启恢复行为正确
7. 无明显终端焦点回归

## 17. 可直接编码的数据结构草案

### 17.1 `ClaudeModels.swift` 建议内容

```swift
import Foundation

struct ClaudeSessionsIndexFile: Codable {
    let version: Int
    let entries: [ClaudeSessionsIndexEntry]
    let originalPath: String?
}

struct ClaudeSessionsIndexEntry: Codable {
    let sessionId: String
    let fullPath: String?
    let fileMtime: Double?
    let firstPrompt: String?
    let messageCount: Int?
    let created: String?
    let modified: String?
    let gitBranch: String?
    let projectPath: String?
    let isSidechain: Bool?
}

struct ImportedClaudeProject: Identifiable, Codable, Hashable {
    let id: UUID
    let projectPath: String
    let displayName: String
    let importedAt: Date
}

struct ClaudeSessionSummary: Identifiable, Hashable {
    var id: String { sessionId }

    let sessionId: String
    let projectPath: String
    let transcriptPath: String
    let firstPrompt: String?
    let gitBranch: String?
    let messageCount: Int?
    let createdAt: Date?
    let modifiedAt: Date?
    let isSidechain: Bool
}

struct ClaudeSessionContext: Codable, Hashable {
    let sessionId: String
    let projectPath: String
    let openedAt: Date
}
```

### 17.2 错误类型建议

```swift
enum ClaudeDataError: LocalizedError {
    case projectNotFound
    case noSessionsIndex
    case malformedIndex
    case claudeCliNotFound
    case terminalCreateFailed
    case surfaceUnavailable
}
```

## 18. `ClaudeSessionLauncher.swift` 实现草案

### 18.1 建议类型

```swift
enum ActivationResult {
    case focusedExisting
    case openedNew
    case failed(ClaudeDataError)
}

final class ClaudeSessionLauncher {
    private let registry: ClaudeSessionRegistry

    init(registry: ClaudeSessionRegistry) {
        self.registry = registry
    }

    func activate(
        session: ClaudeSessionSummary,
        preferredController: TerminalController?
    ) -> ActivationResult
}
```

### 18.2 建议步骤

实现顺序建议严格按以下步骤：

1. `registry.compact()`
2. 查找是否已打开
3. 已打开则直接聚焦并返回
4. 检查 `claude` 可执行文件
5. 组装 `Ghostty.SurfaceConfiguration`
6. 优先当前窗口 `newTab`
7. 回退 `newWindow`
8. 找到新创建的首个 surface
9. 绑定 `ClaudeSessionContext`
10. 注册进 registry
11. 聚焦并返回

### 18.3 关键实现点

#### A. `claude` 可执行文件探测

MVP 建议：

1. 使用 `/usr/bin/which claude`
2. 失败则弹窗并中止

#### B. surface 获取

新建 `TerminalController` 后，建议从：

1. `openedController.surfaceTree`
2. 取 root 下唯一 leaf surface

来获取初始 surface。

#### C. 绑定上下文

建议直接在 `Ghostty.SurfaceView` 上挂：

```swift
surface.claudeSessionContext = .init(
    sessionId: session.sessionId,
    projectPath: session.projectPath,
    openedAt: Date()
)
```

## 19. `ClaudeWorkspaceView.swift` 视图实现草案

### 19.1 建议签名

```swift
struct ClaudeWorkspaceView<Content: View>: View {
    @ObservedObject var ghostty: Ghostty.App
    @ObservedObject var controller: TerminalController
    @ObservedObject var projectsStore: ClaudeProjectsStore

    @State private var sidebarVisible: Bool = true
    @State private var sidebarWidth: CGFloat = 280
    @State private var selectedProjectPath: String?
    @State private var selectedSessionId: String?

    let content: () -> Content
}
```

### 19.2 建议 body 结构

```swift
var body: some View {
    HStack(spacing: 0) {
        if sidebarVisible {
            ClaudeSidebarView(
                store: projectsStore,
                selectedProjectPath: $selectedProjectPath,
                selectedSessionId: $selectedSessionId,
                preferredController: controller
            )
            .frame(width: sidebarWidth)
        }

        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

### 19.3 状态流要求

1. `projectsStore` 是 app-global 数据源
2. `selectedProjectPath` 和 `selectedSessionId` 是 window-local
3. `sidebarVisible` 是 window-local，但可以初始化自 `UserDefaults`
4. active/opened 状态来源于 registry，而不是仅靠本地选中状态

## 20. `SurfaceView_AppKit.swift` 恢复字段变更清单

### 20.1 CodingKeys 变更

当前：

```swift
case pwd
case uuid
case title
case isUserSetTitle
```

建议扩展为：

```swift
case pwd
case uuid
case title
case isUserSetTitle
case claudeSessionId
case claudeProjectPath
```

### 20.2 encode 变更

新增：

```swift
try container.encode(claudeSessionContext?.sessionId, forKey: .claudeSessionId)
try container.encode(claudeSessionContext?.projectPath, forKey: .claudeProjectPath)
```

### 20.3 decode 变更

建议流程：

1. 解码 `uuid`
2. 解码 `pwd`
3. 尝试解码 `claudeSessionId` 与 `claudeProjectPath`
4. 如果两者存在：
   - 构造 `Ghostty.SurfaceConfiguration`
   - `workingDirectory = claudeProjectPath`
   - `initialInput = "claude -r <sessionId>\n"`
5. 初始化 surface 后再把 `claudeSessionContext` 回写到实例上

### 20.4 恢复失败降级策略

如果 Claude 字段存在但恢复失败：

1. 允许降级为普通 shell
2. 不阻止整个 window restore
3. 在日志中明确记一条 warning

## 21. 真实编码顺序建议

如果现在就开始写代码，建议按下面顺序逐文件推进：

1. `ClaudeModels.swift`
2. `ClaudeIndexReader.swift`
3. `ClaudeProjectsStore.swift`
4. `ClaudeSidebarView.swift`
5. `ClaudeWorkspaceView.swift`
6. `ClaudeSessionRegistry.swift`
7. `ClaudeSessionLauncher.swift`
8. `AppDelegate.swift`
9. `TerminalController.swift`
10. `SurfaceView.swift`
11. `SurfaceView_AppKit.swift`

原因：

1. 先稳定数据
2. 再挂 UI
3. 最后处理运行时与恢复层

## 22. 编码前检查表

开始实施前，建议逐项确认：

1. `claude --help` 在目标机器可用
2. `~/.claude/projects` 在目标机器存在
3. 至少有一个真实项目包含 `sessions-index.json`
4. `TerminalController.newTab/newWindow` 当前行为正常
5. `SurfaceView` restore 当前行为稳定

只有这 5 项都成立，编码效率才会比较高。
