# Margin 架构

简体中文（当前） · [English](architecture.en.md)

本文描述当前源码中的长期架构约束。源码和测试是行为的最终依据；构建、评测与平台支持
范围分别见 [building.md](building.md)、[evaluation.md](evaluation.md) 和
[compatibility-spike.md](compatibility-spike.md)。

## 目标与边界

Margin 是一个以 macOS 为主要平台的 Apple Books 英文阅读助手。它只处理用户明确选中的
文字，将英语单词或短段落转换为适合继续阅读的简体中文结果。

核心边界如下：

- 发送给云端服务商的书籍内容只有经清理、规范化的用户选区；请求还包含翻译所需的
  固定指令，以及模型、语言和风格等控制字段。
- Apple Books 可能在复制内容后附加书名、作者等来源元数据；Margin 会在本地删除完整
  匹配的来源尾注，不会另行采集页码或选区周围文本。
- 使用用户自己的云端服务商 API Key；Margin 不是离线翻译工具。
- 单词与段落共用查询管线，但使用不同的数据模型、校验规则和界面。
- macOS 是已经验证的主路径；iOS App 与 Action Extension 仍是实验性外壳。
- 不提供 OCR、截图识别、整本书翻译、账户系统或云端历史。

## 模块地图

| 路径 | 职责 |
|---|---|
| `Apps/macOS/` | 全局快捷键、辅助功能选区捕获、AppKit 浮层和 macOS 生命周期 |
| `Apps/iOS/`、`Apps/ActionExtension/` | iOS 容器、App Intent 与文本 Action Extension |
| `Apps/SharedUI/` | 查询会话、首次运行、设置、历史以及跨平台 SwiftUI 结果界面 |
| `Sources/LookupCore/` | 输入规范化、请求与结果模型、服务商协议、校验、缓存和收藏存储 |
| `Sources/ApplePlatformSupport/` | Apple Keychain 等平台安全能力 |
| `Evaluation/` | 本地、无网络的盲测工具；不参与应用运行 |
| `Tests/` | 核心包、macOS 宿主、存储、服务商和界面状态的行为验证 |

`Package.swift` 定义可独立测试的 `LookupCore` 与 `ApplePlatformSupport`。`project.yml`
是 macOS App、iOS App 和 Action Extension 的 XcodeGen 源文件；生成的
`BooksTranslator.xcodeproj` 不应手工维护。

## macOS 查询流程

```mermaid
flowchart LR
    A["Apple Books 中的选区"] --> B["⌃⌥M"]
    B --> C["辅助功能触发 Copy"]
    C --> D["LookupSession"]
    D --> E["LookupRequest：清理、规范化、分类"]
    E --> F{"缓存命中？"}
    F -- "是" --> K["完整 LookupOutcome"]
    F -- "否" --> G["服务商结构化请求"]
    G --> I["取得并校验完整结果"]
    I --> L["尽力写入有界缓存"]
    L --> K
    K --> M["单词卡片或段落阅读界面"]
```

`SelectionShortcutController` 注册 `⌃⌥M`。获得用户批准的辅助功能权限后，
`SelectedTextCapture` 发送一次 `⌘C`，并且只有在系统剪贴板确实发生变化时才读取新的
选区。捕获结果交给 `LookupSession`；较旧的异步捕获会被 generation token 丢弃，不能
覆盖更新的查询。

`LookupSession` 是主线程上的界面编排边界，也是查询状态的单一来源。状态沿
`idle → loading → result/failure` 演进；每次新查询都会取消旧任务并推进 generation，
只有当前 generation 可以发布后续状态。

查询界面只使用一个懒加载、可复用的 AppKit `NSPanel`。它可以出现在所有 Spaces 和
全屏 Apple Books 旁边，关闭时隐藏而不是销毁。设置与已收藏内容使用独立窗口。

## 输入、模型与翻译契约

`LookupRequest` 在发起网络请求前完成以下处理：

1. 只在完整匹配时移除 Apple Books 附加的来源与版权尾注。
2. 合并多余空白，拒绝空选区，并将长度限制为 2,000 个字符。
3. 将单个词形分类为 `word`，其余内容分类为 `passage`。
4. 固定源语言为英语、目标语言为简体中文、风格为自然书面中文。

单词结果由读音、词性、释义和双语例句组成，同时保留旧版扁平缓存格式的解码兼容。

段落先在本地拆分为带编号的英语句子。服务商返回的每个对齐块必须按顺序、无遗漏且
不重复地覆盖全部句子。自然译文直接由这些中文块拼接而成，因此“自然译文”和
“双语对照”不会生成两份相互矛盾的译文。只有一个或没有可用对齐块时，界面只显示
自然译文。

`TranslationContract.version` 参与服务商标识和缓存键。只要提示词、结构化输出或校验
语义发生可能影响结果的变化，就必须升级该版本，并重新判断既有评测是否仍然适用。

## 服务商与校验

应用通过 `TranslationProvider` 隔离服务商实现。当前默认配置使用 DeepSeek，同时保留
一个尽力而为的 OpenAI-compatible 接口。

- 选区作为 JSON 数据放入 user message；system message 明确将书中文字视为不可信输入。
- 单词与段落都必须通过严格的结构、数量和非空字段校验。
- 段落还必须通过句子覆盖校验和可用中文校验。
- DeepSeek 的结构化段落失败时，可进行一次自然译文 fallback；通用兼容服务商使用一次
  结构化修复请求。
- 服务商响应正文和 API Key 不进入诊断记录。

## 浮层与阅读界面

- 当前 UI policy 以 540 pt 为浮层目标宽度；段落内容高度在约 280–620 pt 之间自适应，
  单词卡片使用约 620 pt 的阅读高度。
- 内容高度变化时保持浮层顶部位置稳定，并将完整窗口限制在当前屏幕的可见区域内。
- 单词结果在一个可滚动文档中展示全部常见词性；词性标签是滚动锚点，不会替换内容。
- 段落默认显示完整自然中文，英文原文折叠；至少有两个对齐块时才提供双语对照切换。
- 两种段落视图共用相同的 `PassageLookupResult`。复制与朗读始终跟随当前可见模式。
- System、Light 和 Dark 是设备本地偏好；橙色只用于标记、导航和有限的交互反馈。

## 本地数据与隐私

- API Key 保存在不可同步、仅限当前设备的 Keychain 项目中。
- 缓存键是规范化请求、服务商标识和翻译契约命名空间的 SHA-256；键中不暴露原文。
- 当前响应缓存是约 10 MB 的本地 LRU JSON 存储；写入失败不应让一次成功查询失败。
- 查询本身不会自动写入历史。只有用户主动点击收藏，结果才进入收藏存储。
- 响应缓存与收藏这两个 JSON 存储通过 sidecar 文件锁和原子替换避免并发实例相互覆盖。
- 当前本地诊断由 actor 串行化，并通过临时文件替换写入；最多保留 50 条结构化事件，
  只记录阶段、错误类型、状态码和 token 数等元数据。
- macOS 数据位于应用支持目录；iOS 容器和 Action Extension 通过 App Group 共享本地数据。

选中文字仍会发送给用户配置的云端服务商，因此这些措施表示数据最小化，而不是离线或
零披露。

## 源码真相与变更纪律

- 输入、模型和存储：`Sources/LookupCore/`
- macOS 捕获与浮层：`Apps/macOS/`
- 会话与呈现：`Apps/SharedUI/`
- Keychain：`Sources/ApplePlatformSupport/`
- 核心测试：`Tests/LookupCoreTests/`
- macOS 宿主测试：`Tests/MacAppTests/`

修改架构不变量时，应在同一变更中更新对应测试和本文件。常用验证命令：

```bash
swift test
./scripts/test-mac.sh
./scripts/verify-xcodegen-determinism.sh
./scripts/audit-public-repo.sh
```
