# Right Click Master

<p align="center">
  <img src="icon.png" width="128" height="128" alt="Right Click Master 图标">
</p>

<p align="center">
  <strong>为 Finder 补齐一组小而可靠的原生右键工具。</strong><br>
  <a href="README.md">English</a>
</p>

> macOS v2 已完成实现与本地验收。公开 DMG 仍必须由配置了 Developer ID 与 Apple 公证凭据的发布工作流生成。

Right Click Master 为 macOS Finder 提供四个行为明确的操作，不修改系统默认设置：

- 新建文件
- 复制路径
- 使用偏好的终端打开
- 使用偏好的编辑器打开

安装了 Ghostty 与 CotEditor 时会自动识别；用户仍可自由更改终端和编辑器。

## 产品原则

- 使用 Finder 原生右键菜单
- 完全本地运行；无账户、无遥测、不上传路径
- 不提供任意脚本和危险的快捷删除
- 不申请辅助功能、屏幕录制、完全磁盘访问或管理员权限
- 新建文件绝不覆盖已有文件
- 支持简体中文和英文

精确的右键语义、首次引导与验收标准见 [PRODUCT.md](PRODUCT.md)。架构和安全边界见 [docs/architecture.md](docs/architecture.md) 与 [docs/security-and-release.md](docs/security-and-release.md)。

## 仓库结构

```text
MainApp/          macOS SwiftUI 主程序
FinderExtension/ macOS Finder Sync 扩展
Shared/           macOS 共用领域代码、数据契约和测试样例
Tests/            macOS 测试
docs/             架构、安全与决策记录
scripts/          本地开发和发布校验脚本
```

## macOS 开发

需要 macOS 14.5+、Xcode 26.3+ 和 [XcodeGen 2.45.4](https://github.com/yonaskolb/XcodeGen/releases/tag/2.45.4)。

```bash
xcodegen generate
xcodebuild \
  -project RightMenuMaster.xcodeproj \
  -scheme RightMenuMaster \
  -configuration Debug \
  test
```

安装与旧版隔离的本地开发构建，并注册 Finder 扩展：

```bash
APPLE_TEAM_ID="你的团队 ID" make install-debug
```

脚本会保留签名，并安装为 `RightClickMaster Dev.app`。开发构建不可用于公开分发。

最终用户的安装、权限与故障排查流程见 [macOS 安装指南](docs/install-macos.md)。

## Windows 状态

Windows 不属于 v2 支持范围，不参与构建、测试、打包或发布。

## 分发与安全

免费的 GitHub Beta 使用 ad-hoc 签名且未经 Apple 公证。macOS 会拦截首次启动，用户需要在“隐私与安全”中明确点击“仍要打开”。未来若要实现低摩擦安装，仍需 Developer ID 签名与 Apple 公证。

项目不会要求用户移除隔离属性或关闭 Gatekeeper。完整发布门禁见 [docs/security-and-release.md](docs/security-and-release.md)。

## 许可证

MIT
