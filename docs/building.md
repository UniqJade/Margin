# Building Margin from source

[简体中文说明](#简体中文)

Margin v0.1.0 is a source-only personal build. These instructions do not produce
a public distribution binary and do not change the client-side BYOK security
boundary described in `SECURITY.md`.

## Requirements

- Xcode 26.6 or newer
- macOS 26 for the documented development environment
- XcodeGen 2.45 or newer (`brew install xcodegen`)
- Git and the command-line tools selected through the full Xcode installation
- a personal DeepSeek API key for live lookup

Deployment targets are macOS 15 and iOS/iPadOS 18. The verified Apple Books path
is narrower than those compilation targets; see `compatibility-spike.md`.

## 1. Create local signing configuration

Copy the public template and edit only the ignored copy:

```bash
cp Local.xcconfig.example Local.xcconfig
```

Replace every placeholder in `Local.xcconfig` with your own Apple development
team and unique bundle configuration. The template is the canonical list of
required values. Do not edit generated `BooksTranslator.xcodeproj` settings as a
substitute: XcodeGen will overwrite them.

Confirm that Git ignores the populated file:

```bash
git check-ignore -v Local.xcconfig
```

Never commit `Local.xcconfig`, API keys, certificates, private keys,
provisioning profiles, or exported `.p12` files. The owner's local configuration
keeps the established TeamIdentifier and bundle identifiers unchanged so the
fixed Mac installation continues to be recognized by Accessibility and Keychain.
Forks must use their own values.

## 2. Generate and run deterministic tests

From the repository root:

```bash
xcodegen generate
swift test
./scripts/test-mac.sh
node --test Evaluation/tests/core.test.cjs
```

`swift test` exercises the shared packages without a host app.
`scripts/test-mac.sh` regenerates the project, runs hosted Mac tests in an ignored
`.noindex` DerivedData path, and unregisters temporary Margin products even when
the test fails. The evaluator test uses only Node's built-in test runner and does
not install packages.

For an unsigned Mac compile without hosted tests:

```bash
xcodebuild -project BooksTranslator.xcodeproj \
  -scheme BooksTranslatorMac \
  -configuration Debug \
  -derivedDataPath .build/XcodeDerivedData.noindex \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 3. Create a valid Apple Development identity

In Xcode, open **Settings → Accounts**, select your Apple Account, choose
**Manage Certificates**, and create or download **Apple Development**.

In Terminal, verify that macOS sees a signing identity:

```bash
security find-identity -v -p codesigning
```

Continue only when the output lists a valid Apple Development identity. In
Keychain Access, a usable certificate appears with its private key beneath it.
A certificate record without its matching private key cannot sign Margin.

The certificate name shown in Xcode is not enough evidence by itself: the
command-line identity and private key must both be available in the login
Keychain used by the build.

## 4. Install the fixed daily Mac copy

Run:

```bash
./scripts/install-mac.sh
```

The installer:

1. requires populated local signing configuration and a valid Apple Development
   identity;
2. regenerates the Xcode project;
3. builds Release with automatic provisioning;
4. verifies the expected bundle ID, TeamIdentifier, Apple Development authority,
   and absence of Mac sandbox/App Group/shared-Keychain entitlements;
5. unregisters temporary DerivedData copies;
6. replaces only `~/Applications/Margin.app` and verifies that exact executable
   is running.

Use `~/Applications/Margin.app` for reading. Do not open a Margin product from
`.build`, Xcode Products, or DerivedData as the daily copy. Those products can
appear as duplicate Spotlight results and have a different signing identity,
which causes repeated Accessibility or data-container prompts.

Opening the fixed app does not request Accessibility. The native permission flow
begins only when you press `Control–Option–M` for selection capture.

## 5. Configure DeepSeek

On first launch:

1. enter your DeepSeek API key;
2. use **Save and test**; Margin sends the harmless word `book`;
3. finish the shortcut and privacy explanation;
4. in Apple Books, select text and press `⌃⌥M`.

The key is stored in the device-only Keychain, not in `Local.xcconfig` or source
control. `deepseek-v4-flash` is the only certified v0.1.0 model. Custom
OpenAI-compatible configuration is exposed under Advanced for best-effort future
experimentation only.

## iOS/iPadOS simulator build

The iOS app and Action Extension can be compiled without signing:

```bash
xcodegen generate
xcodebuild -project BooksTranslator.xcodeproj \
  -scheme BooksTranslatorIOS \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath .build/XcodeDerivedData-iOS.noindex \
  CODE_SIGNING_ALLOWED=NO \
  build
```

This proves compilation and extension embedding; it does **not** prove Apple
Books selection delivery.

## iPhone/iPad physical-device experiment

1. Open `BooksTranslator.xcodeproj` in Xcode.
2. Select your development team for both `BooksTranslatorIOS` and
   `BooksTranslatorAction`.
3. Ensure the App Group and shared Keychain capabilities described by
   `Local.xcconfig.example` exist for both targets in your developer account.
4. Connect and trust the device, choose it as the run destination, and run the
   iOS scheme.
5. Enter the API key again on the device; Mac Keychain data is not synchronized.
6. Follow every word, sentence, and multiline case in
   `compatibility-spike.md` before describing the Books integration as supported.

Free Personal Team provisioning may not expose every required shared capability
and expires frequently. Margin does not promise that the experimental iOS flow
works with every free or paid developer-account configuration.

## Generated project discipline

`project.yml` is the source of truth for the Xcode project. After changing it:

```bash
xcodegen generate
git diff -- BooksTranslator.xcodeproj
xcodegen generate
git diff --exit-code -- BooksTranslator.xcodeproj
```

The second generation must not drift. Do not hand-edit a generated signing value
or source list without also changing `project.yml`.

## Release checks

Before sharing source or tagging a release:

```bash
git diff --check
./scripts/audit-public-repo.sh
swift test
./scripts/test-mac.sh
node --test Evaluation/tests/core.test.cjs
```

Then run the iOS simulator build above and verify the signed Mac installation.
Live provider calls remain opt-in and outside normal automated tests.

## Reclaim build storage

Repository build products are reproducible:

```bash
./scripts/clean-local-builds.sh
```

This removes only repository `.build` and `DerivedData` directories. To also
remove Xcode's project-specific `BooksTranslator-*` DerivedData:

```bash
./scripts/clean-local-builds.sh --xcode-derived-data
```

The cleanup script deliberately leaves `~/Applications/Margin.app`, Application
Support data, Keychain, and Xcode's shared ModuleCache untouched. Future builds
will recreate cache space.

---

## 简体中文

Margin v0.1.0 只提供个人源码构建，不生成公共分发二进制，也不会改变
`SECURITY.md` 中说明的客户端 BYOK 安全边界。

### 环境要求

- Xcode 26.6 或更新版本
- 文档所记录的开发环境为 macOS 26
- XcodeGen 2.45 或更新版本（`brew install xcodegen`）
- 通过完整 Xcode 选择的 Git 与命令行工具
- 用于真实查询的个人 DeepSeek API Key

部署目标是 macOS 15 和 iOS/iPadOS 18；能够编译不等于 Apple Books 集成已经
验证，准确边界见 `compatibility-spike.md`。

### 1. 创建本地签名配置

```bash
cp Local.xcconfig.example Local.xcconfig
```

只编辑被 Git 忽略的 `Local.xcconfig`，用自己的 Apple Team 和唯一 Bundle 配置
替换所有占位值。模板是所需字段的唯一准确信息来源。不要直接修改生成工程中的
签名设置，因为 XcodeGen 会覆盖它们。

```bash
git check-ignore -v Local.xcconfig
```

不得提交 `Local.xcconfig`、API Key、证书、私钥、Provisioning Profile 或导出的
`.p12`。项目所有者的本地值必须保持现有 TeamIdentifier 和 Bundle ID 不变，才能
维持辅助功能与钥匙串对固定安装版的识别；Fork 用户必须换成自己的值。

### 2. 生成工程并测试

```bash
xcodegen generate
swift test
./scripts/test-mac.sh
node --test Evaluation/tests/core.test.cjs
```

只做无签名 Mac 编译时：

```bash
xcodebuild -project BooksTranslator.xcodeproj \
  -scheme BooksTranslatorMac \
  -configuration Debug \
  -derivedDataPath .build/XcodeDerivedData.noindex \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### 3. 检查 Apple Development 证书

在 Xcode 的**设置 → 账户 → Manage Certificates** 中创建或下载 Apple
Development，然后在终端运行：

```bash
security find-identity -v -p codesigning
```

只有命令列出有效 identity，而且“钥匙串访问”中证书下方存在对应私钥时，才能
继续。Xcode 界面只显示证书名称并不足以证明它可用于签名。

### 4. 安装固定 Mac 版本

```bash
./scripts/install-mac.sh
```

脚本会检查本地签名配置、构建 Release、验证 Bundle ID、TeamIdentifier、Apple
Development 签名以及 Mac 不含 Sandbox/App Group/共享钥匙串 entitlement，然后
只替换 `~/Applications/Margin.app`。

日常阅读只能打开这个固定路径。不要从 `.build`、Xcode Products 或 DerivedData
打开 Margin，否则可能出现 Spotlight 重复项目，以及重新申请辅助功能或数据容器
权限。正常启动不会申请辅助功能；只有按下 `⌃⌥M` 捕获选区时才进入系统授权流程。

### 5. 配置 DeepSeek

首次启动时输入 DeepSeek API Key，点击“保存并测试”；Margin 会发送无敏感内容
的 `book`。Key 只保存在本设备钥匙串，不应写进 `Local.xcconfig`。v0.1.0 只认证
`deepseek-v4-flash`；高级设置中的自定义兼容接口只属于尽力兼容实验。

### iOS/iPadOS 模拟器

```bash
xcodegen generate
xcodebuild -project BooksTranslator.xcodeproj \
  -scheme BooksTranslatorIOS \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath .build/XcodeDerivedData-iOS.noindex \
  CODE_SIGNING_ALLOWED=NO \
  build
```

该命令只证明 App 和扩展能够编译、嵌入，不证明 Apple Books 会传递选区。

### iPhone/iPad 真机实验

1. 在 Xcode 中打开工程。
2. 为 iOS App 与 Action Extension 选择自己的 Team。
3. 按 `Local.xcconfig.example` 为两个 Target 配好 App Group 和共享钥匙串能力。
4. 连接并信任设备，选择真机后运行 iOS Scheme。
5. 在设备上重新输入 API Key；Mac 钥匙串不会同步。
6. 按 `compatibility-spike.md` 完成单词、句子和多行选区测试。

免费 Personal Team 可能没有全部共享能力，而且描述文件会频繁过期；Margin 不承诺
实验性 iOS 流程能在每种免费或付费账号配置下工作。

### 生成工程与发布检查

`project.yml` 是工程配置的事实来源。修改后连续生成两次，第二次必须无差异。
公开源码前运行：

```bash
git diff --check
./scripts/audit-public-repo.sh
swift test
./scripts/test-mac.sh
node --test Evaluation/tests/core.test.cjs
```

随后完成 iOS 模拟器构建和签名 Mac 安装验证。常规自动测试不会调用真实 API。

### 清理开发空间

```bash
./scripts/clean-local-builds.sh
```

默认只清理仓库 `.build` 与 `DerivedData`。如需同时清理 Xcode 中该项目的
`BooksTranslator-*` DerivedData：

```bash
./scripts/clean-local-builds.sh --xcode-derived-data
```

脚本不会删除 `~/Applications/Margin.app`、Application Support、钥匙串或 Xcode
共享 ModuleCache；下次构建会重新产生缓存。
