<div align="center">
  <img src="assets/readme-banner.svg" alt="Mint Bookshelf" width="100%">
  <h1>Mint Bookshelf</h1>
  <p><strong>为你的电子书库和 USB Kindle 打造的原生 macOS 应用。</strong></p>

  <p>
    <a href="README.md">English</a> ·
    <a href="README.ru.md">Русский</a> ·
    <a href="README.es.md">Español</a> ·
    <a href="README.pt.md">Português</a> ·
    <a href="README.zh.md">中文</a> ·
    <a href="README.fr.md">Français</a>
  </p>

  <p>
    <a href="../../releases"><img alt="Releases" src="https://img.shields.io/badge/releases-GitHub-86C9BB?style=flat-square"></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-0A1014?style=flat-square&logo=apple&logoColor=white">
    <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-0A1014?style=flat-square&logo=swift&logoColor=F05138">
    <img alt="Go" src="https://img.shields.io/badge/Go-core-0A1014?style=flat-square&logo=go&logoColor=00ADD8">
    <img alt="MTP" src="https://img.shields.io/badge/Kindle-MTP-86C9BB?style=flat-square">
    <img alt="MIT" src="https://img.shields.io/badge/license-MIT-97A7AC?style=flat-square">
  </p>
</div>

> **本地书库。直接 USB 访问。没有云端，也没有多余干扰。**
>
> Mint Bookshelf 将你的图书、Kindle 和日常文件操作集中在一个简洁的 macOS 应用中。

## 功能

| 书库 | Kindle | 文件 |
| --- | --- | --- |
| 封面、搜索、详情，并按标题、作者或添加日期排序。 | MTP 文件夹树，上传、下载、移动、复制、重命名和删除。 | Finder 风格的本地浏览器，支持复制、粘贴、拖放和后台操作。 |

| 转换 | 外观 | 体验 |
| --- | --- | --- |
| 通过 Calibre 转换，支持进度和取消。 | 深色与浅色主题、六种界面语言和原生 macOS 窗口行为。 | 没有多余操作栏：右键菜单、快捷键，以及清晰的列表与详情分栏。 |

## 主要能力

- 只扫描你选择的文件夹，并在下次启动时记住它。
- 从 EPUB、MOBI、AZW、AZW3、PDF 和 FB2 提取封面；缺失时生成简洁封面。
- 按标题、作者和系列搜索；按标题、作者或添加日期排序。
- 以文件夹树浏览 Kindle，并显示按字节计算的传输进度。
- 使用 Calibre 转换图书，并在活动列表中查看任务。
- 随时切换 **英语、俄语、西班牙语、葡萄牙语、中文和法语**。

## 支持的 Kindle

Mint Bookshelf 通过 libmtp 支持 **现代 MTP Kindle**。

- 已在 **Kindle Scribe** 和 2025 年当前型号上验证。
- 预期支持 Kindle Scribe、Paperwhite 5/Signature、第 11 代及更新 Kindle、Colorsoft 和 2024–2025 型号。
- **不支持：** 旧款 USB mass storage Kindle，包括 Kindle Paperwhite 2（DP75SDI，2013–2014）。

> 同一时间只能打开一个 MTP 会话。使用 Kindle 标签页前，请关闭其他 MTP 工具。

## 安装

1. 打开 [Releases](../../releases) 页面。
2. 下载 `MintBookshelf-<版本>.dmg`。
3. 打开 DMG，将 **Mint Bookshelf** 拖到 **Applications**。

当前版本适用于 **Apple Silicon**，使用 ad-hoc 签名。如果 macOS 阻止首次启动，请右键点击应用并选择 **打开**。

如需公开分发且不出现 Gatekeeper 警告，请使用 Developer ID 证书并公证。参见 `docs/BUILD.md`。

## 构建

需要 macOS 14+、Xcode、Go、Homebrew、`pkg-config`、`libmtp` 和 `libusb`。

```sh
brew install pkg-config libmtp libusb
make check-deps
make package
make dmg
```

应用位于 `macos/Mint Bookshelf.app`，DMG 位于 `build/MintBookshelf.dmg`。

## 发布

GitHub Actions 负责构建发布版本：

```sh
git tag v0.1.0
git push origin v0.1.0
```

**Release** 工作流会运行 Go 和 Swift 测试、写入版本号、构建并校验 DMG、生成 SHA-256，并将两个文件发布到 **Releases**。也可以在 **Actions → Release → Run workflow** 中手动运行。

## 架构

- **SwiftUI**，Swift 6，macOS 14+
- **Go 核心** 编译为 `libkindlecore.dylib`，通过 C ABI 和 JSON 调用
- **libmtp/libusb** 访问 Kindle
- **SQLite** 保存书库和操作历史
- **Calibre CLI** 用于可选转换

## 测试

```sh
go test ./...
make test-race
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path macos
```

## 本地化

界面已完整翻译为英语、俄语、西班牙语、葡萄牙语、简体中文和法语。语言可在右上角菜单中选择，并会在下次启动时恢复；默认跟随系统语言。

添加新语言很简单：

1. 在 `macos/Sources/MintBookshelf/Localization.swift` 的 `AppLanguage` 中添加 `case` 和显示名称。
2. 新建一个词典文件，例如 `Localization+German.swift`。
3. 在 `L10n.tables` 中注册。

所有界面文本、状态、计数和错误都使用统一的 `L10n` API。

## 说明

- 仅支持现代 MTP Kindle；不支持 USB mass storage Kindle。
- 可选择多个 Amazon 设备；会定期检测和重新连接。
- 设备上的删除不可恢复，并需要确认。
- 应用在整个运行期间保持一个 MTP 会话。
- `docs/` 包含本地研究和构建笔记。

## 许可证

MIT。参见 [LICENSE](LICENSE)。
