# Claude 侧栏设计文档

## 1. 文档信息

- 文档名称：Ghostty macOS Claude 项目/会话侧栏设计文档
- 目标仓库：`/Users/zlj/project/guidsiz`
- 当前阶段：方案设计
- 适用范围：macOS 宿主层

## 2. 背景

当前仓库基于 Ghostty。Ghostty 的终端核心、渲染、PTY、VT 解析都在 Zig 层，但 macOS 的窗口、Tab、Split、菜单、SwiftUI/AppKit 组合都在 `macos/Sources`。

本次需求不是扩展终端协议能力，而是为 macOS 宿主增加一个左侧栏，用于管理本机 Claude Code 已存在的项目目录和项目下的会话，并允许用户点击某个会话后，在右侧终端中直接恢复该 Claude 会话。

这意味着该需求本质上是一个“窗口级宿主管理功能”，不是一个“终端核心功能”。

## 3. 目标

### 3.1 总体目标

在普通 Ghostty macOS 终端窗口中增加一个可折叠左侧栏，实现以下能力：

1. 导入本地 Claude Code 已存在的项目目录。
2. 按项目展示对应 Claude 会话列表。
3. 点击会话时，如果当前应用内已经打开该会话，则直接聚焦。
4. 点击会话时，如果当前应用内尚未打开该会话，则在右侧终端中恢复该 Claude 会话。
5. 右侧继续保持 Ghostty 终端体验，不实现自定义富文本聊天消息渲染器。

### 3.2 设计原则

1. 优先复用现有 Ghostty macOS 宿主能力，不动 Zig 核心。
2. 第一阶段只支持 macOS，不试图同步到 GTK。
3. 第一阶段只接入 Claude Code 数据，不抽象成通用多 Provider 侧栏。
4. 第一阶段只做“恢复 Claude 会话”，不做“解析并渲染完整会话聊天 UI”。
5. 优先使用稳定数据源和稳定命令，不依赖脆弱的推断规则。

## 4. 非目标

以下内容明确不在本阶段范围内：

1. 不修改 `src/terminal`、`src/termio`、`src/renderer` 等 Zig 终端核心模块。
2. 不在终端区域渲染 Claude 消息流富文本界面。
3. 不实现 Linux/GTK 左侧栏。
4. 不实现对 Claude 数据的写入或编辑。
5. 不实现对任意 AI CLI 的统一管理框架。
6. 不实现“附着到某个已经存在的 Claude 外部进程”。

## 5. 用户故事

### 5.1 导入项目

作为用户，我希望选择一个本地项目目录，如果该目录在 Claude Code 中已有会话，则它能出现在左侧栏中。

### 5.2 浏览会话

作为用户，我希望展开某个项目后，看到该项目下的 Claude 会话列表，并快速区分最近活跃的会话。

### 5.3 恢复会话

作为用户，我希望点击某个会话后，右侧终端能立即恢复这个 Claude 会话，而不是只显示静态历史。

### 5.4 避免重复打开

作为用户，我希望如果某个 Claude 会话已经在当前应用内打开，点击左侧会话时直接切换过去，而不是重复打开多个终端。

### 5.5 基础管理

作为用户，我希望能刷新项目、移除项目、搜索会话，并在应用重启后保留已导入的项目列表。

## 6. 现状分析

### 6.1 Ghostty macOS 侧已有能力

当前 Ghostty macOS 宿主已经具备以下基础：

1. 使用 `TerminalController` 管理普通终端窗口。
2. 使用 `BaseTerminalController` 管理窗口内的 `surfaceTree`、焦点、Split、通知等。
3. 使用 `TerminalView` 作为 SwiftUI 根终端视图。
4. 使用 `Ghostty.SurfaceConfiguration` 在创建新 Surface 时注入：
   - `workingDirectory`
   - `command`
   - `initialInput`
   - `waitAfterCommand`
5. 使用 `TerminalController.newTab/newWindow` 创建带指定配置的新终端。

这说明“左侧栏点击会话，打开一个带指定目录和启动命令的终端”在现有宿主结构里天然可做。

### 6.2 Claude 本地数据结构

已验证本机 Claude Code 数据存在于以下目录：

```text
~/.claude/projects/<编码后的项目路径>/
```

其中关键文件为：

1. `sessions-index.json`
2. `<session-id>.jsonl`

`sessions-index.json` 中已包含高价值元数据：

- `sessionId`
- `projectPath`
- `fullPath`
- `firstPrompt`
- `messageCount`
- `created`
- `modified`
- `gitBranch`
- `isSidechain`

因此：

1. 主数据源应优先使用 `sessions-index.json`。
2. 不应依赖对“项目目录如何编码成 `-Users-...`”的硬编码推断。
3. `.jsonl` 只作为补充信息和兜底解析来源。

### 6.3 Claude CLI 恢复能力

本机 `claude` CLI 支持：

```bash
claude -r <session-id>
```

因此“恢复一个已有会话”可以通过 shell 启动后自动输入命令实现。

## 7. 总体方案

### 7.1 宿主层方案

本功能完全落在 `macos/Sources`：

1. 左侧栏 UI 在 SwiftUI 层实现。
2. 数据读取在 Swift 层实现。
3. 会话恢复通过现有 Ghostty Surface 配置能力实现。
4. 焦点切换和避免重复打开通过 app 内注册表实现。

### 7.2 右侧区域保持终端

右侧区域仍然使用现有 `TerminalView`。

本需求明确采用：

- 左侧：Claude 项目/会话管理
- 右侧：Ghostty 终端

而不采用：

- 左侧：项目/会话树
- 右侧：自定义 Claude 聊天富文本查看器

这是本设计中最重要的范围控制。

## 8. 模块分层设计

建议新增 `macos/Sources/Features/Claude Sidebar/` 目录，并按以下分层组织：

### 8.1 数据层

职责：

1. 管理已导入项目列表。
2. 扫描 Claude 项目索引。
3. 将索引解析为项目和会话摘要。
4. 将导入列表持久化。

建议文件：

- `ClaudeModels.swift`
- `ClaudeIndexReader.swift`
- `ClaudeProjectsStore.swift`

### 8.2 运行时协调层

职责：

1. 记录当前应用中已打开的 Claude 会话。
2. 提供“聚焦已打开会话”能力。
3. 提供“恢复未打开会话”能力。

建议文件：

- `ClaudeSessionRegistry.swift`
- `ClaudeSessionLauncher.swift`

### 8.3 UI 层

职责：

1. 展示项目和会话树。
2. 提供导入、刷新、搜索、移除交互。
3. 将点击事件转为 launch/focus 请求。

建议文件：

- `ClaudeWorkspaceView.swift`
- `ClaudeSidebarView.swift`

## 9. 关键数据模型

### 9.1 ImportedClaudeProject

用于表示用户已导入的一个 Claude 项目。

建议字段：

```swift
struct ImportedClaudeProject: Identifiable, Codable, Hashable {
    let id: UUID
    let projectPath: String
    let displayName: String
    let importedAt: Date
}
```

说明：

1. `projectPath` 是用户真实导入目录。
2. `displayName` 默认可取目录最后一级名称。
3. 不把 `~/.claude/projects/...` 目录名作为主键，因为它是实现细节。

### 9.2 ClaudeSessionSummary

用于表示列表中的一个 Claude 会话摘要。

建议字段：

```swift
struct ClaudeSessionSummary: Identifiable, Hashable {
    let id: String
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
```

### 9.3 ClaudeSessionContext

用于把“某个 Surface 是因哪个 Claude 会话启动”这件事附着到 Surface 上。

建议字段：

```swift
struct ClaudeSessionContext: Codable, Hashable {
    let sessionId: String
    let projectPath: String
    let openedAt: Date
}
```

### 9.4 ClaudeSessionRegistryEntry

运行时注册表项。

建议字段：

```swift
final class ClaudeSessionRegistryEntry {
    let sessionId: String
    weak var surface: Ghostty.SurfaceView?
    weak var controller: BaseTerminalController?
}
```

## 10. UI 结构设计

### 10.1 根视图结构

普通终端窗口的根结构建议调整为：

```text
ClaudeWorkspaceView
├── ClaudeSidebarView
└── TerminalView
```

也就是：

1. 右侧继续完全保留现有 `TerminalView`。
2. 左侧作为宿主壳层附加上去。

### 10.2 左侧栏内容

建议包括：

1. 顶部工具栏
   - 导入项目
   - 刷新
   - 搜索
   - 折叠/展开
2. 项目列表
   - 项目名
   - 项目路径提示
   - 会话数量
3. 会话列表
   - 首条问题摘要
   - Git 分支
   - 最近更新时间
   - 侧链标记
   - 已打开标记
   - 当前激活标记

### 10.3 交互行为

建议规则：

1. 单击项目：展开或收起。
2. 单击会话：
   - 若已打开：聚焦
   - 若未打开：恢复
3. 右键项目：
   - 刷新
   - 在 Finder 中显示
   - 移除
4. 右键会话：
   - 在当前窗口打开
   - 在新窗口打开
   - 复制 Session ID

## 11. 会话激活设计

### 11.1 激活优先级

点击会话时按以下顺序处理：

1. 查询注册表中是否已有该 `sessionId` 对应 Surface。
2. 如果存在且 Surface 仍有效：
   - 激活所在 window
   - 聚焦到对应 surface
   - 左侧栏更新当前激活状态
3. 如果不存在：
   - 新建 tab 或 window
   - 以目标 `projectPath` 作为工作目录
   - shell 启动后自动执行 `claude -r <session-id>`

### 11.2 为什么默认新建 Tab

默认不覆盖当前 terminal，原因是：

1. 用户当前 shell 可能正在执行命令。
2. 直接复用当前 shell 破坏性强。
3. macOS 宿主已经原生支持开新 tab。

因此默认策略建议为：

1. 有普通终端窗口时：当前窗口新建 tab。
2. 无普通终端窗口时：新建窗口。

### 11.3 为什么使用 initialInput

恢复命令建议通过 `initialInput` 注入：

```bash
claude -r <session-id>
```

而不是直接覆盖 `command`。

原因：

1. 覆盖 `command` 容易绕过 shell 初始化。
2. 直接输入命令能保留用户 shell 环境。
3. 与 Ghostty 现有“打开文件执行”的思路一致。

## 12. 数据读取设计

### 12.1 主数据源

对于每个已导入项目：

1. 扫描 `~/.claude/projects/**/sessions-index.json`
2. 找到 `originalPath` 或 `entries[].projectPath` 与导入路径匹配的索引文件
3. 解析其中的 `entries`

### 12.2 匹配规则

匹配原则：

1. 优先 `originalPath == projectPath`
2. 其次允许 `entries` 中所有 `projectPath` 等于目标路径
3. 不以目录名编码规则作为主匹配逻辑

### 12.3 兜底来源

如果不存在 `sessions-index.json`：

1. 扫描对应目录下的 `.jsonl`
2. 从首条 `user` 消息和顶层字段中抽取基础摘要

### 12.4 刷新策略

第一阶段：

1. 手动刷新
2. App 启动刷新
3. 导入后刷新

第二阶段可扩展：

1. 文件监听自动刷新

## 13. 运行时注册表设计

### 13.1 目的

注册表负责解决两个问题：

1. 防止同一 Claude 会话被重复打开多个 terminal
2. 让左侧栏能知道哪些会话已打开、哪些会话是当前激活状态

### 13.2 注册时机

注册表建议在以下时机维护：

1. 创建 Claude 会话 terminal 成功后注册
2. Surface 关闭时移除
3. Window 关闭时清理失效引用
4. 应用恢复窗口后重新注册

### 13.3 注册方式

推荐由 Swift 宿主维护 `sessionId -> Weak<SurfaceView>` 映射，而不是由 Zig 层维护。

原因：

1. 这是 macOS 宿主语义，不是终端语义。
2. SurfaceView 和窗口焦点都在 Swift 层。

## 14. 持久化设计

### 14.1 App 级持久化

使用 `UserDefaults.ghostty` 保存：

1. 已导入项目列表
2. 侧栏显示状态
3. 项目展开状态
4. 最近选中项目

### 14.2 Surface 级持久化

如果某个 terminal 是通过 Claude 会话启动，则需要把 `ClaudeSessionContext` 跟着 Surface 一起编码。

当前 Surface restore 只保存：

1. `pwd`
2. `uuid`
3. `title`
4. `isUserSetTitle`

因此必须扩展编码字段，例如：

1. `claudeSessionId`
2. `claudeProjectPath`

## 15. 错误处理设计

### 15.1 Claude CLI 不存在

场景：

1. 用户点击会话时系统找不到 `claude`

处理：

1. 不打开空 terminal
2. 弹窗提示 CLI 不存在
3. 提示用户检查 PATH 或安装 Claude Code

### 15.2 项目索引不存在

场景：

1. 导入路径没有任何 Claude 数据

处理：

1. 导入失败
2. 明确提示“该目录在 Claude Code 中暂无可识别会话”

### 15.3 会话恢复失败

场景：

1. `claude -r <session-id>` 执行失败

处理：

1. terminal 仍保留
2. 左侧栏不把该会话标记为成功激活
3. 后续可考虑从终端输出中识别失败提示

### 15.4 失效项目

场景：

1. 用户删除了本地项目目录
2. `~/.claude/projects` 对应索引失效

处理：

1. 左侧项目标记为 unavailable
2. 提供移除和重试刷新

## 16. 性能设计

### 16.1 读取策略

避免在主线程直接扫描大量 Claude 文件。

建议：

1. 后台线程读取索引
2. 主线程发布结果

### 16.2 缓存策略

第一阶段可只缓存解析结果到内存，不做复杂持久化缓存。

后续可扩展：

1. 缓存 `sessions-index.json` 的 `mtime`
2. 仅当文件变化时重新解析

## 17. 安全与边界

### 17.1 可接受风险

本功能会读取用户 HOME 下的 Claude 会话索引文件。这是用户明确需求的一部分，因此可接受，但需要注意：

1. 只读取最小必要字段
2. 不上传
3. 不修改 Claude 数据

### 17.2 命令执行风险

恢复会话会在 shell 中执行：

```bash
claude -r <session-id>
```

这是用户主动触发行为，风险可接受。  
不应在后台自动批量恢复任何会话。

## 18. 兼容性结论

### 18.1 第一阶段支持

1. macOS 普通 TerminalController 窗口
2. 当前本机 Claude CLI
3. 当前 Claude 本地索引布局

### 18.2 第一阶段不支持

1. Quick Terminal
2. GTK
3. 通用外部 AI CLI

## 19. 验收标准

满足以下条件视为设计达标：

1. 用户可以导入一个本地 Claude 项目目录。
2. 左侧栏能显示该项目下的 Claude 会话列表。
3. 会话按最近修改时间排序。
4. 点击未打开会话会在右侧打开并恢复。
5. 点击已打开会话会直接聚焦，不重复打开。
6. 应用重启后，导入项目列表仍保留。
7. 恢复出来的 Claude 会话 terminal 在窗口恢复后行为正确。

## 20. 开放问题

以下问题建议在实施中尽快验证：

1. Claude CLI 是否允许同一 `sessionId` 被多个终端同时恢复。
2. 是否要支持“固定项目”与“最近项目”分组。
3. 是否要支持项目内按分支聚合会话。
4. 是否要支持会话搜索正文，而不仅是首条 prompt。
5. Quick Terminal 是否需要禁用左侧栏还是复用同一逻辑。

## 21. 需求分解与优先级

为避免范围蔓延，建议将需求拆为 P0、P1、P2：

### 21.1 P0 必做

1. 导入 Claude 项目目录
2. 列出项目下会话
3. 点击会话恢复到右侧终端
4. 已打开会话聚焦而非重复创建
5. 已导入项目持久化

### 21.2 P1 应做

1. 项目刷新
2. 会话搜索
3. active/opened 状态标记
4. 错误提示
5. 窗口恢复时保留 Claude 会话上下文

### 21.3 P2 可选

1. 自动文件监听刷新
2. 按分支分组
3. pin/favorite
4. 项目级排序和最近使用记录
5. 只读预览面板

## 22. 关键时序

### 22.1 导入项目时序

```text
用户选择目录
-> AppDelegate 打开目录选择框
-> ClaudeProjectsStore.importProject(path)
-> ClaudeIndexReader.hasClaudeData(path)
-> 成功：写入持久化 + 触发 refresh
-> 失败：返回错误并弹窗
```

### 22.2 刷新项目时序

```text
用户点击刷新
-> ClaudeProjectsStore.refresh(project)
-> 后台线程读取 sessions-index.json
-> 解析为 ClaudeSessionSummary[]
-> 主线程发布 sessionsByProject 更新
-> Sidebar 重绘
```

### 22.3 激活会话时序

```text
用户点击会话
-> ClaudeSessionLauncher.activate(session)
-> ClaudeSessionRegistry 查询是否已打开
-> 已打开：focus window + focus surface
-> 未打开：组装 SurfaceConfiguration
-> TerminalController.newTab/newWindow
-> Surface 创建成功后挂载 ClaudeSessionContext
-> Registry 注册
-> Sidebar 更新 active/opened 状态
```

### 22.4 应用恢复时序

```text
AppKit 恢复窗口
-> TerminalWindowRestoration 恢复 surface tree
-> SurfaceView 解码 claudeSessionContext
-> 若存在 session context：
   使用 projectPath + initialInput("claude -r <session-id>") 重建
-> Surface 创建完成
-> Registry 补注册
```

## 23. 状态模型

### 23.1 项目状态

建议为项目引入以下状态：

1. `idle`
2. `loading`
3. `loaded`
4. `empty`
5. `unavailable`
6. `error`

含义：

1. `idle`：尚未刷新
2. `loading`：正在读取 Claude 索引
3. `loaded`：已成功拿到会话
4. `empty`：目录存在但没有会话
5. `unavailable`：目录或索引失效
6. `error`：读取或解析失败

### 23.2 会话状态

建议为会话引入以下视图状态：

1. `closed`
2. `opening`
3. `opened`
4. `active`
5. `failed`

含义：

1. `closed`：未在应用中打开
2. `opening`：正在创建 terminal
3. `opened`：已打开但未聚焦
4. `active`：当前聚焦会话
5. `failed`：上次恢复失败

## 24. 与现有代码映射

为减少后续误改，建议将功能映射到现有代码位置：

### 24.1 Root View 挂载点

现有入口：

- `macos/Sources/Features/Terminal/TerminalController.swift`
- `windowDidLoad`
- `TerminalViewContainer { TerminalView(...) }`

目标：

1. 不改 `TerminalView` 本身结构
2. 用 `ClaudeWorkspaceView` 包住它

### 24.2 Surface 创建能力

现有入口：

- `macos/Sources/Ghostty/Surface View/SurfaceView.swift`
- `SurfaceConfiguration`

目标：

1. 继续复用 `workingDirectory`
2. 继续复用 `initialInput`
3. 不直接侵入 libghostty C API

### 24.3 新 Tab / 新 Window 能力

现有入口：

- `TerminalController.newWindow`
- `TerminalController.newTab`

目标：

1. 把 Claude 恢复也视为一种“带基础配置的新终端”
2. 不额外发明另一套窗口创建器

### 24.4 窗口恢复能力

现有入口：

- `SurfaceView_AppKit.swift`
- `TerminalRestorable.swift`

目标：

1. 在现有恢复链路上扩展 Claude 元数据
2. 不重写整套 window restoration 机制

## 25. 建议的最小演示路径

为了尽快看到结果，建议按以下最小路径实现：

1. 固定一个测试项目路径
2. 读取会话列表并在左侧显示
3. 点击会话时打印将执行的命令
4. 打通 `newTab + initialInput`
5. 打通 registry 去重
6. 最后再补导入和恢复

这个顺序可以减少 UI、数据、启动链路同时调试的复杂度。

## 26. Swift 数据模型草案

本节给出建议的 Swift 结构草案，作为实现时的直接参考。

### 26.1 Claude 索引 DTO

```swift
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
```

设计说明：

1. 时间字段先按字符串接，再由 Reader 统一转 `Date`
2. 对 Claude 未来版本新增字段保持宽容
3. 所有非必须字段保持可选，降低格式变动风险

### 26.2 业务模型

```swift
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

### 26.3 视图状态模型

```swift
enum ClaudeProjectLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case unavailable
    case error(String)
}

enum ClaudeSessionOpenState: Equatable {
    case closed
    case opening
    case opened
    case active
    case failed(String)
}
```

### 26.4 运行时注册表模型

```swift
final class ClaudeSessionRegistryEntry {
    let sessionId: String
    let projectPath: String
    weak var surface: Ghostty.SurfaceView?
    weak var controller: BaseTerminalController?

    init(
        sessionId: String,
        projectPath: String,
        surface: Ghostty.SurfaceView,
        controller: BaseTerminalController
    ) {
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.surface = surface
        self.controller = controller
    }
}
```

## 27. ClaudeWorkspaceView 视图树与状态流

### 27.1 建议视图树

```text
ClaudeWorkspaceView
├── SidebarHost
│   ├── ClaudeSidebarHeader
│   ├── SearchField
│   └── ProjectsList
│       ├── ClaudeProjectSectionView
│       │   ├── ProjectHeaderRow
│       │   └── ClaudeSessionRowView
│       └── ...
└── TerminalHost
    └── TerminalView
```

### 27.2 Workspace 级状态

建议 `ClaudeWorkspaceView` 持有：

```swift
@State private var sidebarVisible: Bool
@State private var sidebarWidth: CGFloat
@State private var selectedProjectPath: String?
@State private var selectedSessionId: String?
```

### 27.3 侧栏与右侧终端的关系

原则：

1. 左侧栏只做浏览和调度
2. 右侧终端只做终端
3. 左侧栏不直接持有 `Ghostty.SurfaceView`
4. 右侧终端不直接依赖 Claude 数据结构

这样可以把耦合压到 `ClaudeSessionLauncher` 和 `ClaudeSessionRegistry` 两层。

### 27.4 焦点流

建议焦点流如下：

```text
点击会话行
-> Sidebar 改 selectedSessionId
-> Launcher 执行 activate
-> 若打开新会话：新 tab 创建
-> 若已有会话：focus existing surface
-> Workspace 根据 registry 更新 active 样式
```

## 28. ClaudeSessionLauncher 伪代码

以下伪代码用于指导实际实现：

```swift
final class ClaudeSessionLauncher {
    private let registry: ClaudeSessionRegistry

    init(registry: ClaudeSessionRegistry) {
        self.registry = registry
    }

    func activate(
        session: ClaudeSessionSummary,
        preferredController: TerminalController?
    ) -> ActivationResult {
        registry.compact()

        if let surface = registry.surface(for: session.sessionId),
           let controller = registry.controller(for: session.sessionId) {
            controller.window?.makeKeyAndOrderFront(nil)
            Ghostty.moveFocus(to: surface)
            return .focusedExisting
        }

        guard resolveClaudeExecutable() != nil else {
            return .failed(.claudeCliNotFound)
        }

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = session.projectPath
        config.initialInput = "claude -r \(session.sessionId)\n"

        let controller = preferredController
        let openedController: TerminalController?

        if let controller, let window = controller.window {
            openedController = TerminalController.newTab(
                controller.ghostty,
                from: window,
                withBaseConfig: config
            )
        } else {
            openedController = TerminalController.newWindow(
                NSApp.delegateAsAppDelegate.ghostty,
                withBaseConfig: config
            )
        }

        guard let openedController else {
            return .failed(.terminalCreateFailed)
        }

        // 后续需要一个机制找到这个新建 controller 中的初始 surface
        guard let surface = openedController.surfaceTree.first else {
            return .failed(.surfaceUnavailable)
        }

        surface.claudeSessionContext = .init(
            sessionId: session.sessionId,
            projectPath: session.projectPath,
            openedAt: Date()
        )

        registry.register(
            sessionId: session.sessionId,
            projectPath: session.projectPath,
            surface: surface,
            controller: openedController
        )

        openedController.window?.makeKeyAndOrderFront(nil)
        Ghostty.moveFocus(to: surface)
        return .openedNew
    }

    private func resolveClaudeExecutable() -> String? {
        // MVP 可先用 /usr/bin/which 或 PATH 探测
        return "claude"
    }
}
```

### 28.1 ActivationResult 建议

```swift
enum ActivationResult {
    case focusedExisting
    case openedNew
    case failed(ActivationError)
}

enum ActivationError: Error {
    case claudeCliNotFound
    case terminalCreateFailed
    case surfaceUnavailable
}
```

## 29. Surface 恢复字段设计

### 29.1 当前已有字段

当前 `SurfaceView_AppKit` 已编码：

1. `pwd`
2. `uuid`
3. `title`
4. `isUserSetTitle`

### 29.2 建议新增字段

建议新增：

1. `claudeSessionId`
2. `claudeProjectPath`

如果未来要扩展，也可以直接保存一个结构化对象，但第一版建议用扁平字段以降低兼容复杂度。

### 29.3 编码策略

编码时：

1. 若 `claudeSessionContext == nil`，则新字段写空
2. 若存在，则写入 `sessionId` 与 `projectPath`

### 29.4 解码策略

解码时：

1. 先读旧字段，保证兼容
2. 再尝试读 `claudeSessionId/projectPath`
3. 若两者存在：
   - `config.workingDirectory = claudeProjectPath`
   - `config.initialInput = "claude -r <sessionId>\n"`
4. 若不存在：
   - 继续走普通终端恢复

### 29.5 兼容性要求

恢复逻辑必须满足：

1. 新版本能读取旧版本 surface state
2. 旧版本行为不会因缺失新字段而崩溃
3. Claude session terminal 恢复失败时，窗口至少还能打开为普通 shell，而不是整个恢复链路失败
