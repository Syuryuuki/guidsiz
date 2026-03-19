# Claude 侧栏实施计划

## 1. 计划目标

本计划用于指导 Claude 项目/会话侧栏功能的分阶段落地，目标是：

1. 保证每个阶段都可独立验证
2. 降低对现有 Ghostty macOS 宿主功能的回归风险
3. 先交付可用 MVP，再逐步补全恢复和体验细节

## 2. 总体周期

建议以 4 个主里程碑推进，总工期预估为 5 到 6.5 个工作日。

如果压缩范围，不做窗口恢复和一部分 UX 补强，可压缩到 3 到 4 个工作日，但不建议。

## 3. 里程碑拆分

### M1：数据层与持久化

目标：

1. 能导入 Claude 项目
2. 能读取并展示项目下会话摘要
3. 能持久化导入项目列表

预计工作量：

1 到 1.5 个工作日

交付物：

1. `ClaudeModels.swift`
2. `ClaudeIndexReader.swift`
3. `ClaudeProjectsStore.swift`
4. `AppDelegate` 中 app-global store 挂载

任务拆分：

1. 定义索引文件 DTO
2. 实现 `sessions-index.json` 解析
3. 实现项目路径匹配
4. 实现导入/移除/刷新
5. 实现 `UserDefaults` 持久化

验收标准：

1. 用户可导入一个真实 Claude 项目目录
2. 应用内可拿到该项目的会话列表
3. 重启应用后导入项目列表仍保留

风险：

1. Claude 索引格式异常
2. HOME 路径权限问题

回退策略：

1. 保留导入列表持久化
2. 允许暂时只支持手动刷新

### M2：左侧栏 UI 壳层

目标：

1. 普通 Terminal 窗口展示左侧栏
2. 右侧终端行为不回归

预计工作量：

1 到 1.5 个工作日

交付物：

1. `ClaudeSidebarView.swift`
2. `ClaudeWorkspaceView.swift`
3. `TerminalController` root view 包装

任务拆分：

1. 实现左右分栏布局
2. 实现项目折叠/展开
3. 实现会话列表展示
4. 实现搜索和刷新入口
5. 实现 basic selected/opened 样式

验收标准：

1. 左侧栏显示正常
2. 终端输入、分屏、tab、窗口操作不回归

风险：

1. SwiftUI 包装层影响焦点链
2. 左右分栏影响 content size 计算

回退策略：

1. 临时隐藏侧栏，只保留 root 包装
2. 如焦点链异常，优先回退为固定宽度布局，不做复杂自适应

### M3：会话激活与去重

目标：

1. 点击未打开会话可恢复
2. 点击已打开会话可聚焦
3. 不重复打开同一会话

预计工作量：

1.5 到 2 个工作日

交付物：

1. `ClaudeSessionRegistry.swift`
2. `ClaudeSessionLauncher.swift`
3. 左侧会话点击动作打通

任务拆分：

1. 实现 registry
2. 实现 launcher
3. 选择当前窗口新 tab 或新窗口的策略
4. 使用 `workingDirectory + initialInput`
5. 新建后补注册
6. 已打开会话的 focus 跳转

验收标准：

1. 点击未打开会话会新建 tab 并恢复
2. 点击已打开会话不会重复开 tab
3. 对应窗口会被置前

风险：

1. `claude -r` 可能不允许重复 resume
2. 新建 tab 后焦点可能落不到目标 surface

回退策略：

1. 如果不允许重复 resume，则强制“已打开只聚焦”
2. 如果 focus 不稳定，先只保证 window 置前，再修 surface focus

### M4：恢复与收尾

目标：

1. Claude 会话终端支持窗口恢复
2. 注册状态与 UI 状态一致
3. 错误路径可控

预计工作量：

1 到 1.5 个工作日

交付物：

1. `SurfaceView` 的 Claude session 上下文
2. `SurfaceView_AppKit` 的恢复扩展
3. 错误提示与失效项目状态

任务拆分：

1. 增加 `ClaudeSessionContext`
2. 编码/解码 session 元数据
3. 恢复时重建 resume 行为
4. surface/window 关闭时清理 registry
5. `claude` 缺失或恢复失败时提示

验收标准：

1. 应用重启后恢复出的 Claude 会话 terminal 行为正确
2. 左侧 open/active 状态不出现明显错乱

风险：

1. 恢复逻辑和 Ghostty 现有 window restore 冲突

回退策略：

1. 如果恢复层不稳定，先保留项目列表持久化，暂时禁用 Claude session terminal restore

## 4. 详细任务计划

### 第 1 天

目标：

完成 M1。

任务：

1. 新建数据模型
2. 实现 `sessions-index.json` 读取
3. 挂载项目 store
4. 实现项目导入和持久化

完成标志：

1. 能在日志或调试 UI 中看到导入项目和会话列表

### 第 2 天

目标：

完成 M2 大部分内容。

任务：

1. 实现左侧栏 UI
2. 实现分栏 root view
3. 接入 `TerminalController`

完成标志：

1. 普通终端窗口可看到左侧栏
2. 右侧终端无明显回归

### 第 3 天

目标：

完成 M3 核心链路。

任务：

1. 实现 registry
2. 实现 launcher
3. 点击会话恢复
4. 已打开会话聚焦

完成标志：

1. 会话点击可用

### 第 4 天

目标：

完成 M4 基础恢复。

任务：

1. surface 元数据附着
2. 恢复扩展
3. registry 清理
4. 错误提示

完成标志：

1. 重启恢复行为基本正确

### 第 5 天

目标：

打磨体验并完成回归测试。

任务：

1. 搜索
2. 刷新
3. 移除项目
4. active/opened 样式
5. 构建验证和手工回归

完成标志：

1. 达到 MVP 可演示状态

## 5. 依赖关系

关键依赖顺序如下：

1. `ClaudeModels` 先于 `ClaudeIndexReader`
2. `ClaudeIndexReader` 先于 `ClaudeProjectsStore`
3. `ClaudeProjectsStore` 先于 `ClaudeSidebarView`
4. `ClaudeSessionRegistry` 与 `ClaudeSessionLauncher` 先于点击恢复
5. `ClaudeSessionContext` 先于窗口恢复

其中，M3 依赖 M1 和 M2，M4 依赖 M3。

## 6. 每阶段验证计划

### M1 验证

命令：

```bash
zig build -Demit-macos-app=false
cd /Users/zlj/project/guidsiz/macos
nu build.nu --scheme Ghostty --configuration Debug --action build
```

手工验证：

1. 导入一个真实 Claude 项目
2. 刷新后看到会话摘要
3. 重启后导入项目仍在

### M2 验证

手工验证：

1. 打开普通终端窗口
2. 观察左侧栏布局
3. 测试 tab、split、resize、focus

### M3 验证

手工验证：

1. 点击一个未打开会话
2. 检查是否新建 tab 并恢复
3. 再次点击同一会话
4. 检查是否直接聚焦

### M4 验证

手工验证：

1. 打开几个 Claude 会话 tab
2. 退出应用
3. 重启应用
4. 检查恢复行为

## 7. 风险登记

### 风险 R1：Claude 数据格式变化

影响：

1. 解析失败
2. 左侧列表为空

缓解：

1. 优先依赖 `sessions-index.json`
2. 对缺失字段使用兜底默认值
3. 保留 `.jsonl` 兜底解析

### 风险 R2：重复 resume 同一 session

影响：

1. 出现多个 terminal 绑定同一 session
2. Claude CLI 行为不可预期

缓解：

1. registry 优先聚焦
2. 实测后决定是否强制单实例

### 风险 R3：窗口恢复语义错乱

影响：

1. 重启后 Claude 会话 terminal 退化成普通 shell

缓解：

1. 明确扩展 `SurfaceView` 编解码字段
2. 单独验证恢复链路

### 风险 R4：SwiftUI 包装影响焦点

影响：

1. 终端输入焦点丢失

缓解：

1. 先做最薄包装
2. 不在 `TerminalView` 内部直接插入大量新状态

## 8. 发布策略

建议发布方式：

1. 先完成 MVP
2. 在本地长期使用和回归几轮
3. 再继续考虑更深层体验优化

建议阶段性提交：

1. `Add Claude session index models and store`
2. `Add macOS Claude sidebar shell`
3. `Add Claude session activation and focus registry`
4. `Persist Claude session context for restore`

## 9. 后续迭代路线

MVP 完成后，建议优先迭代：

1. 自动刷新
2. pinned projects
3. 会话按分支聚合
4. 失败会话重试入口
5. 只读预览面板

## 10. 计划结论

建议严格按照以下顺序推进：

1. 数据层
2. UI 壳层
3. 激活链路
4. 恢复与收尾

这样每一个阶段都能形成可运行、可验证、可回退的中间状态，风险最低，也最符合当前 Ghostty macOS 宿主的结构。

## 11. 每个里程碑的进入与退出条件

### 11.1 M1 进入条件

1. 已确认 `~/.claude/projects` 数据结构可读
2. 已确定使用 `sessions-index.json` 作为主数据源

### 11.2 M1 退出条件

1. 至少一个真实项目可导入
2. 导入数据可持久化
3. 会话摘要可正确排序

### 11.3 M2 进入条件

1. Store 已可稳定提供项目和会话列表

### 11.4 M2 退出条件

1. 左侧栏渲染稳定
2. 右侧终端无明显焦点和布局回归

### 11.5 M3 进入条件

1. 左侧栏点击事件已打通
2. 已验证当前 `TerminalController.newTab/newWindow` 可接受目标配置

### 11.6 M3 退出条件

1. 未打开会话可恢复
2. 已打开会话可聚焦
3. 去重逻辑可工作

### 11.7 M4 进入条件

1. `ClaudeSessionContext` 已加入运行时结构

### 11.8 M4 退出条件

1. 退出重启后恢复行为正确
2. registry 状态与实际 UI 状态一致

## 12. 工作分解结构

### 12.1 WBS-1 数据层

1. 定义模型
2. 解析索引
3. 持久化项目
4. 搜索和排序

### 12.2 WBS-2 宿主 UI 层

1. 侧栏 root
2. 项目 section
3. 会话 row
4. 搜索与工具栏

### 12.3 WBS-3 激活层

1. registry
2. launcher
3. focus
4. 去重

### 12.4 WBS-4 恢复层

1. surface metadata
2. encoding/decoding
3. restore rehydrate
4. cleanup

## 13. 验收矩阵

| 能力 | M1 | M2 | M3 | M4 |
| --- | --- | --- | --- | --- |
| 导入项目 | ✅ | ✅ | ✅ | ✅ |
| 列出会话 | ✅ | ✅ | ✅ | ✅ |
| 左侧栏显示 |  | ✅ | ✅ | ✅ |
| 点击恢复 |  |  | ✅ | ✅ |
| 已打开聚焦 |  |  | ✅ | ✅ |
| 重启恢复 |  |  |  | ✅ |

## 14. 质量门禁

在进入下一里程碑前，建议满足以下门禁：

### 14.1 编译门禁

```bash
zig build -Demit-macos-app=false
cd /Users/zlj/project/guidsiz/macos
nu build.nu --scheme Ghostty --configuration Debug --action build
```

### 14.2 行为门禁

1. 终端输入不可失焦
2. 新 tab / split / close 不可明显回归
3. 左侧栏不阻塞窗口启动

### 14.3 失败门禁

1. `claude` 缺失时不能造成空白死状态
2. 读取失败时不能导致窗口不可用

## 15. 建议的迭代节奏

如果按实际开发推进，建议每个里程碑都采用：

1. 先做最小可运行骨架
2. 再补全状态和错误处理
3. 最后做样式和交互优化

具体顺序建议：

1. 先跑通数据
2. 再挂 UI
3. 再打通会话恢复
4. 最后做恢复和 polish

## 16. 下一轮细化建议

当开始真正编码前，建议再继续细化以下文档内容：

1. 给 `ClaudeModels.swift` 写出完整 Swift 结构体草案
2. 给 `ClaudeSessionLauncher.swift` 写出完整伪代码
3. 给 `ClaudeWorkspaceView.swift` 写出状态流和视图树草图
4. 给 `SurfaceView_AppKit.swift` 写出恢复字段变更清单

这四项细化完成后，就可以直接进入代码实施。

## 17. 下一阶段的可执行子计划

现在三份文档已经补到了“可编码草案”粒度，下一阶段如果开始真正实施，建议按下面的小步节奏推进。

### Step 1：模型与 Reader

目标：

1. 创建 `ClaudeModels.swift`
2. 创建 `ClaudeIndexReader.swift`
3. 能用测试数据跑通解析

建议工时：

0.5 到 1 天

完成定义：

1. `findSessions(forProjectPath:)` 可返回正确排序结果

### Step 2：Store 与持久化

目标：

1. 创建 `ClaudeProjectsStore.swift`
2. 接通 `UserDefaults.ghostty`
3. 导入/刷新/移除可用

建议工时：

0.5 天

完成定义：

1. 重启后已导入项目仍在

### Step 3：Workspace 与 Sidebar

目标：

1. 创建 `ClaudeWorkspaceView.swift`
2. 创建 `ClaudeSidebarView.swift`
3. 普通 terminal window 中看到左侧栏

建议工时：

1 天

完成定义：

1. 左侧栏显示稳定，右侧终端不回归

### Step 4：Registry 与 Launcher

目标：

1. 创建 `ClaudeSessionRegistry.swift`
2. 创建 `ClaudeSessionLauncher.swift`
3. 点击会话可恢复并聚焦

建议工时：

1 到 1.5 天

完成定义：

1. 去重逻辑可用
2. 未打开会话可恢复

### Step 5：Surface 恢复扩展

目标：

1. 给 `SurfaceView` 增加 `ClaudeSessionContext`
2. 扩展 `SurfaceView_AppKit` 编解码
3. 验证退出重启后的恢复行为

建议工时：

1 天

完成定义：

1. Claude session terminal 恢复后仍语义正确

## 18. 建议的单次提交工作包

为了让每个提交都可审阅、可回滚，建议工作包如下：

### 包 A：仅数据层

包含：

1. `ClaudeModels.swift`
2. `ClaudeIndexReader.swift`
3. `ClaudeProjectsStore.swift`

不包含：

1. UI
2. 恢复逻辑

### 包 B：仅 UI 壳层

包含：

1. `ClaudeWorkspaceView.swift`
2. `ClaudeSidebarView.swift`
3. `TerminalController` root 包装

不包含：

1. 会话恢复逻辑

### 包 C：仅激活链路

包含：

1. `ClaudeSessionRegistry.swift`
2. `ClaudeSessionLauncher.swift`
3. 侧栏点击事件

### 包 D：仅恢复层

包含：

1. `ClaudeSessionContext`
2. `SurfaceView` 编解码扩展
3. registry 清理和重建

## 19. 建议的回归顺序

每完成一个工作包，建议按以下顺序回归：

1. 打开普通 terminal window
2. 测试输入
3. 测试新 tab
4. 测试 split
5. 测试关闭窗口
6. 测试重启恢复

这样可以尽早发现侧栏包装对宿主焦点链和布局的影响。

## 20. 从文档到代码的进入条件

当前文档已经具备以下条件：

1. 有清晰的范围定义
2. 有文件级实施清单
3. 有 Swift 结构草案
4. 有 Launcher 伪代码
5. 有视图树和状态流
6. 有恢复字段变更清单

因此如果你下一步切换到编码阶段，不需要再先补文档，可以直接按：

1. 模型
2. Reader
3. Store
4. Sidebar/Workspace
5. Registry/Launcher
6. Surface 恢复

这个顺序开始实现。
