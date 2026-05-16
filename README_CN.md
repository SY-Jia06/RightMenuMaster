# RightMenu Master

<p align="center">
  <img src="icon.png" width="128" height="128" alt="RightMenu Master Icon">
</p>

<p align="center">
  <strong>macOS Finder 右键菜单增强工具</strong><br>
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.5%2B-blue" alt="macOS 14.5+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/github/license/SY-Jia06/RightMenuMaster" alt="MIT License">
</p>

RightMenu Master 通过 Finder Sync Extension 为 macOS Finder 添加实用的右键菜单功能：新建文件、复制路径、打开终端、快速删除等。

## 功能

| 操作 | 说明 |
| --- | --- |
| **新建文件** | 从模板创建文件（Markdown、Swift、Python、JS、Shell、纯文本）。直接点击创建 Markdown，悬停子菜单选择其他模板 |
| **复制文件路径** | 复制选中项的完整路径到剪贴板 |
| **复制文件名** | 复制选中项的文件名到剪贴板 |
| **在此打开终端** | 在当前目录打开 Terminal.app |
| **在此打开 iTerm** | 在当前目录打开 iTerm2 |
| **快速删除** | 将选中项移到废纸篓 |
| **自动重命名** | 创建文件后自动进入重命名模式（需要辅助功能权限） |

### 内置模板

| 模板 | 扩展名 | 内容 |
| --- | --- | --- |
| 纯文本 | `.txt` | 空文件 |
| Markdown | `.md` | `# ` 标题 |
| Swift 文件 | `.swift` | `import Foundation` |
| Python 文件 | `.py` | shebang + `main()` 脚手架 |
| JavaScript 文件 | `.js` | shebang |
| Shell 脚本 | `.sh` | `set -euo pipefail` |

## 安装

### 下载安装（推荐）

1. 从 [Releases](https://github.com/SY-Jia06/RightMenuMaster/releases) 下载 `RightMenuMaster-v1.0.0.dmg`
2. 打开 DMG，将 `RightMenuMaster.app` 拖入 `/Applications`
3. 移除隔离属性（未签名应用必须执行）：

   ```bash
   xattr -cr /Applications/RightMenuMaster.app
   ```

4. 打开应用
5. 启用 Finder 扩展：**系统设置 → 通用 → 登录项与扩展 → Finder 扩展 → RightMenu Master**

   或通过命令行：

   ```bash
   pluginkit -e use -i com.rightmenu.master.finder-extension
   ```

### 从源码构建

```bash
git clone https://github.com/SY-Jia06/RightMenuMaster.git
cd RightMenuMaster
open RightMenuMaster.xcodeproj
```

在 Xcode 中：选择 `RightMenuMaster` scheme → My Mac → Run (Cmd+R)。

## 使用方法

- **创建 Markdown**：在 Finder 中右键 → **New File**（创建 `untitled.md`）
- **创建其他文件**：右键 → **New File** → 悬停子菜单 → 选择模板
- **复制路径**：右键文件 → **Copy File Path**
- **打开终端**：右键文件夹 → **Open Terminal Here**
- **删除**：右键 → **Quick Delete**

### 自动重命名（可选）

创建文件后，RightMenu Master 可以自动进入重命名模式（选中文件名，不含扩展名）。启用方法：

1. 打开 RightMenu Master 设置（点击菜单栏图标 → Open Settings）
2. 进入 Permissions 标签页 → 点击 "Enable Rename"
3. 在系统设置中授予辅助功能权限

## 设置

通过菜单栏图标可以打开设置界面：

- **Menu Items**：启用、禁用、重命名、排序右键菜单项
- **Templates**：管理自定义文件模板
- **Scripts**：编辑 Run Script 操作的 shell 脚本
- **Permissions**：管理文件夹访问权限和辅助功能权限

## 已知限制

- **iCloud Drive**：iCloud Drive 目录中不显示右键菜单（macOS Finder Sync 系统限制）
- **未签名**：没有 Developer ID 签名，首次打开需执行 `xattr -cr` 或右键 → 打开
- **自动重命名**：需要辅助功能权限，未授权时文件正常创建但不会自动进入重命名模式

## 许可证

MIT
