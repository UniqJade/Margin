# Margin｜Mac 上的 Apple Books 语境阅读

> **Read English. Stay in the book.｜读英文，不离开书页。**

[![Public source validation](https://github.com/UniqJade/Margin/actions/workflows/ci.yml/badge.svg)](https://github.com/UniqJade/Margin/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/UniqJade/Margin?display_name=tag)](https://github.com/UniqJade/Margin/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS: verified](https://img.shields.io/badge/macOS-verified-d97757)

[English](README.md)

Margin 把一句读不懂的英文，**在不离开 Apple Books 的前提下**变成自然的简体中文。
选中一个词或一小段，按一次快捷键，译文就在书页旁的小浮层里打开；关掉它，你立刻
回到书里——不切换应用，也不丢失阅读位置。

它只做一件事，并尽力做好。Margin 不是词典、不是 OCR、也不是文档翻译器，它只想让
"读英文时查一下"这一次小小的打断，几乎消失。

## 看看效果

![在 Apple Books 中选中文字，按 Control–Option–M，在书页旁读译文，并可在自然译文与双语对照之间切换](docs/images/margin-books-demo-v012.gif)

*段落为自写演示文本；Apple Books 选区与 Margin 浮层均截取自真实应用。*

## 怎么用

1. 在 Apple Books 里**选中**一个词，或一两句话。
2. 按 **⌃⌥M**（Control–Option–M）。
3. 在书页旁的浮层里读结果。换别的内容再按一次，或关掉继续读。

**段落**默认以**自然译文**打开——先给完整中文，英文原文收在一个折叠里，需要时再
展开。当一段能拆成两句或更多对齐句子时，可切到**双语对照**，读带编号的英—中对照
块。两种视图是*同一份*译文，措辞不会自相矛盾。

**单词**返回一张紧凑卡片：发音、按词性归类的释义、几个双语例句——够你接着读，而
不是一部完整词典。

浮层始终不碍事：小窗口，跟随浅色 / 深色 / 系统，复制、朗读、收藏、重试都一键
可达。

## 它为什么擅长这件事

- **为书面语设计，而非逐词直译。** 翻译提示词追求自然、可出版质量的中文，专门针对
  你在小说、传记、非虚构里真正会遇到的 2–4 句选区。
- **只在需要时加一句说明。** 只有当歧义会改变含义、语气或指代对象时，才附一句简短
  提示——不是每次都给。
- **只发送你选中的文字。** 绝不发送书名、作者、页码或选区周围的内容。

Apple"查询"、有道、欧路有更深的词库、OCR 和离线数据。Margin 唯一的优势，是一条
更安静的 Apple Books 流程和专注书面中文的翻译。它由 AI 生成的内容不是权威词典，
可能出错。

## 翻译到底好不好

Margin 内置一个本地、离线的 A/B 盲测工具。锁定的 v0.1.0 评测在**采集任何译文之前**
就固定了 40 段文本的书目与类别，再对比 DeepSeek 与 Apple：

| 指标 | 结果 | 门槛 |
|---|---:|---:|
| 自然度更受偏好 | **37 / 40** | ≥ 24 |
| 准确度不低于 Apple | **37 / 40** | ≥ 36 |
| 重大语义错误 | **0** | ≤ 1 |

这是一次单评测者、作者自测——对这 40 段诚实可辩护，但不代表 Margin 对每本书、每位
读者都胜过 Apple。方法与局限见 [docs/evaluation.md](docs/evaluation.md)。

## 你的数据仍归你

Margin 以数据最小化为设计：请求只包含你选中的文字和它的语言——绝不含书名、作者或
页码。API Key 存在仅限本机的钥匙串项里；结果放在可随时清除的小型本地缓存中；不按
收藏就不会进入**已收藏**。选中文字仍会发送给你配置的服务商，所以 Margin 是隐私
优先，而非离线。详见 [SECURITY.md](SECURITY.md)。

## 在你的 Mac 上运行

Margin **只发布源码、自带 Key**：你在 Xcode 里自行构建并签名，用自己的 DeepSeek
API Key，没有现成下载。配置好后，一条命令即可安装：

```
./scripts/install-mac.sh
```

完整环境要求、签名与首次设置见 **[构建 Margin](docs/building.md)**。已在 macOS
26.5 + Apple Books 8.5 验证；首次按 ⌃⌥M 时，在**隐私与安全性 → 辅助功能**里允许
Margin，再按一次。

## 范围

仅 macOS，仅英语 → 简体中文，依赖云端服务商。个人源码构建——没有公共二进制、账户
同步、OCR 或文档翻译。AI 输出可能误译或遗漏语气；单词结果不引用获授权的权威词典。

## 许可证

[MIT](LICENSE)。评测语料保留各自的来源与许可说明。
