# DSH Conversation Window / 独立对话窗口

> **实验版 / Experimental · 非官方 · 尚未完成原生双窗口端到端验收**
>
> 这是 **Cordis 插件 + 指定版本的可选桌面适配补丁**，不是在原版 DSH 上安装一个插件即可使用的功能。
> 不提供应用安装包或预编译 ASAR。不要在未备份的生产环境中使用。

在左侧对话列表右键某条对话，选择「在新窗口中打开」。设计目标是创建可以独立移动、缩放、最小化和关闭的系统窗口，复用原有对话页面、会话 ID、历史和后台运行状态。主窗口保持当前页面。

## 兼容性与边界

- 插件：DSH Cordis Client 插件，使用现有会话右键菜单和通知机制。
- 桌面适配：只支持检查过的 **Windows Desktop 0.2.2-rc.3**，按原始 `app.asar` SHA-256 `14CFD81C9135BF0AFB89417543C94F9ECFE09266574452A9B106890C698725AE` 严格匹配。不是仅凭版本号匹配。
- 原版公开插件接口没有创建原生 BrowserWindow 的能力；没有适配桥时，菜单会提示需要桌面支持，不会退化成浏览器标签页。
- 桌面更新可能覆盖补丁；不要强行跳过哈希校验。修改安装资源也可能影响签名、更新与官方支持。
- 尚未验证 macOS、Linux、麦克风、浏览器客体面板以及完整快捷键多窗口行为。
- 不能将其标注为稳定版或宣称所有验收已通过。

## 安装（先阅读，再操作）

需要 Python 3.10+、Node.js 22+、本地已有合法的兼容 DSH 安装。

### 1. 本机构建桌面适配

从**未修改的原始**应用归档构建，不会覆盖源文件或启动应用：

```powershell
python scripts/build_adapter.py --source "C:\path\to\DeepSeek Harness\resources\app.asar"
```

输出到被 Git 忽略的 `build/`。输出包括完整本地应用归档和用于路由测试的本地文件，**不得上传这些输出**。

若已装过本项目早期补丁，应先恢复原始备份；安装器不会覆盖已经修改的安装。没有原始归档时，重新取得官方兼容版本，不要修改哈希。

### 2. 退出桌面应用后安装适配

最省事的方式：构建完成后双击仓库根目录的 `install-and-restart.cmd`。它不杀任何进程，打印 `WAIT` 后等你从托盘退出 DSH，再原子替换归档、校验哈希、写安装记录，并只启动一次应用。全过程写入 `build/install-restart.log`。

也可以手动执行（需先完全退出 DSH，含托盘）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-adapter.ps1 -Resources "C:\path\to\DeepSeek Harness\resources"
```

`app.asar` 在应用运行期间被独占锁定，必须退出后才能替换。脚本拒绝不匹配的原始归档，保留独立备份，安装失败自动回滚。

**补丁会随桌面端更新失效**（nightly 通道整包替换 `app.asar`）。失效后的判定、重装与版本变更重做流程见 [`docs/REPAIR.md`](docs/REPAIR.md)。

### 3. 安装 Cordis 插件

在 DSH 中请智能体使用插件管理器安装**克隆后的仓库绝对路径**：

> 请通过 plugin_manager 的 install_bundle 安装我本机的 dsh-conversation-window 仓库目录，并检查 application/warnings 和实际右键菜单。

这不是在 shell 中运行的命令。不要手动编辑个人 profile 配置。不需要 npm 安装脚本或第三方依赖。仓库发布本身不会自动安装插件。

### 回滚

先在 DSH 插件管理中停用此插件，再退出应用，运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-adapter.ps1 -Resources "C:\path\to\DeepSeek Harness\resources" -Restore
```

如果安装后应用归档又被更新过，回滚器拒绝覆盖；请使用官方安装器恢复。备份不会自动删除。

## 原理与安全边界

1. 插件的菜单回调捕获**右键目标 ID**，不会读取主窗口当前选中 ID。
2. 预加载桥只发送 `sessionId`；主进程检查调用窗口归属和主 frame，校验 ID 格式后自行构造内部地址，不接受任意 URL。
3. 窗口管理器沿用现有窗口工厂；将受控子窗口加入现有 Host 认证路径，使用同一个后台。
4. 内部 `?conversation=` 启动参数优先于持久化的主窗口选择，调用现有会话导航/数据层。不存在的会话走原有错误提示，不创建空白替代会话。
5. 插件不调用 prompt、cancel 或 resume；打开和加载不发起生成。关闭只释放该窗口的资源，不关闭 Host。

**注意：**主进程做的是 ID 格式和窗口来源校验，访问权限仍由原有会话数据层负责；真实权限错误路径尚未做端到端测试。

## 实际验证与待验收

本次发布前本机执行结果：**17/17 自动化测试通过**（窗口管理器 5、插件 9、路由 3）；Client/Host JavaScript 语法检查通过；使用 Windows Desktop 0.2.2-rc.3 原始本地归档成功构建适配。GitHub CI 只运行不依赖本地应用归档的 14 项测试。

2026-11-14 补记：适配补丁已在 Windows Desktop 0.2.2-rc.3 上实际写入（`app.asar` = `EE66AA50…04EC0`，原版备份与安装记录就位），应用以补丁版正常启动；**真实双窗口与模型生成验收仍未完成**。写入过程与排障细节见 [`docs/REPAIR.md`](docs/REPAIR.md)。

自动化测试：

```powershell
node --test tests/conversation-windows.test.mjs tests/plugin.test.mjs
# 先运行上面的 Python 构建，才会存在路由测试所需的本地输出：
node --test tests/routing.test.mjs
```

覆盖目标：右键 B 与当前 A 隔离、ID/来源拒绝、局部关闭清理、失败加载清理、深链接优先级、不创建替代对话、非持久化选择，以及插件缺桥/错误通知。它们使用 mock 或提取的实际路由代码，**不等于真实模型生成和原生窗口验收**。

实机复测清单（当前均未完成）：

- [ ] 主窗口显示 A，右键 B，新窗口显示 B，主窗口仍为 A。
- [ ] 两窗口显示 B，从任一窗口各发送一条消息，两边记录一致；后台每条输入只执行一次。
- [ ] B 正在回复时开新窗口，能够接上当前流式内容。
- [ ] 回复中关闭子窗口，主窗口继续收到生成，不触发中断。
- [ ] 重新连接/重复打开不重复运行任务，原有队列和中断规则不变。
- [ ] 无效或无权 ID 走原有错误提示；外部来源不能调用窗口 IPC。
- [ ] 系统窗口移动、缩放、最小化、关闭正常。

## 相关插件

[DSH 经典 Agent 模式按钮](https://github.com/zxw219/dsh-classic-agent-button)：在 Windows 版 DSH 桌面端顶部「编辑」右侧添加按钮，单击从 DS Bot 切换到经典 Agent 模式。需要启用 DS Bot，具体适配版本见该仓库说明。

两个插件可按需分别安装、独立更新，互不依赖。
## 仓库内容

- `client.js`、`index.js`、`cordis.patch.yml`、`locale/`、`icon.svg`：原创插件。
- `adapter/conversation-windows.mjs`：窗口生命周期与 ID 校验。
- `adapter/changes.json`：最小版本固定差异，**不含完整上游编译产物**。
- `scripts/`：本机构建、显式安装/回滚、一键重装与重启；不会下载应用或修改个人 profile。
- `install-and-restart.cmd`：构建后用这个入口安装补丁（等待手动退出，不杀进程）。
- `docs/REPAIR.md`：补丁失效后的判定、重装与版本升级重做流程，含已踩过的坑。
- `tests/`：自动化测试。

原创部分采用 MIT；上游差异的来源和许可声明见 THIRD_PARTY_NOTICES.md。本项目不隶属于 DeepSeek，也不代表官方支持。
