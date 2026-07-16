# Install on macOS / macOS 安装指南

## Install / 安装

1. Download the unsigned DMG from the GitHub Release page. Do not use the repository source archive as an app installer.
2. Open the DMG and drag **Right Click Master** to **Applications**.
3. Try to launch the app once. macOS will block this unnotarized build.
4. Open **System Settings → Privacy & Security**, scroll to Security, and click **Open Anyway** for Right Click Master. Confirm with your login password.
5. Launch the app again and follow the four-step setup.

1. 从 GitHub Release 页面下载未公证的 DMG。仓库源码压缩包不是应用安装包。
2. 打开 DMG，将 **Right Click Master** 拖入 **应用程序**。
3. 先尝试启动一次；macOS 会拦截这个未公证版本。
4. 打开 **系统设置 → 隐私与安全**，滚动到“安全性”，点击 Right Click Master 对应的 **仍要打开**，并输入登录密码确认。
5. 再次启动应用，并完成四步引导。

## Setup choices / 设置选择

- Choose a terminal and editor. Ghostty and CotEditor are detected automatically when installed.
- Enable the Finder extension using the system interface opened by the app.
- Allow Home or a narrower working folder using the standard macOS folder picker.
- Run the built-in verification. All four checks should be green before finishing.

- 选择终端与编辑器；已安装的 Ghostty 和 CotEditor 会被自动识别。
- 使用应用打开的系统界面启用 Finder 扩展。
- 通过 macOS 标准文件夹选择器授权主文件夹，或范围更小的工作目录。
- 运行内置检查；四项全部变绿后即可完成。

The folder choice controls both where the Finder menu appears and where **New File** may write. You can add or revoke folders later in **Settings → System**.

One selected local folder covers all ordinary descendants. macOS treats cloud File Provider roots and other applications' protected containers as separate privacy boundaries; choose a cloud root separately if you want Right Click Master there. The app never asks to cross another application's protected container automatically.

文件夹授权同时决定右键菜单出现的范围，以及“新建文件”可写入的位置。之后可在 **设置 → 系统** 中增删授权目录。

一个本地顶层文件夹的授权会覆盖所有普通子目录。macOS 会把云盘 File Provider 根目录及其他应用的受保护容器视作独立隐私边界；如需在云盘中使用，请单独选择对应云盘根目录。应用不会自动跨越其他 App 的受保护容器。

## Permissions / 权限

Required:

- Finder extension: adds the native context menu.
- User-selected folder access: permits file creation only in folders you explicitly choose.

需要：

- Finder 扩展：添加原生右键菜单。
- 用户所选文件夹权限：仅允许在你明确选择的目录中创建文件。

Not required: Accessibility, Screen Recording, Full Disk Access, administrator access, Apple Events, account sign-in, or network access.

不需要：辅助功能、屏幕录制、完全磁盘访问、管理员权限、Apple Events、账户登录或网络权限。

## Troubleshooting / 故障排查

- No menu: confirm the app is in Applications, the Finder extension is enabled, and the current folder is inside an allowed folder. Then press **Run Checks**.
- An app is missing: open **Settings → Applications**, press **Detect Again**, or choose its `.app` manually.
- A folder permission stopped working: remove that folder under **Settings → System**, then allow it again.
- macOS blocks the app: use **Privacy & Security → Open Anyway** as described above. Do not disable Gatekeeper or remove quarantine attributes. Verify the published SHA-256 file before opening.

- 没有菜单：确认应用位于“应用程序”、Finder 扩展已启用，且当前位置属于已授权目录；然后点击“运行检查”。
- 找不到应用：打开 **设置 → 应用**，点击“重新检测”，或手动选择对应 `.app`。
- 文件夹权限失效：在 **设置 → 系统** 中移除该目录，再重新授权。
- macOS 拦截应用：按上文使用 **隐私与安全 → 仍要打开**。不要关闭 Gatekeeper，也不要移除隔离属性；打开前请核对发布的 SHA-256。
