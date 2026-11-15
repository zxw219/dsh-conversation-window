# 修复手册 / Repair runbook

> 给未来的智能体或自己看：补丁失效后按本文件操作，不要从头推断。
> 适用对象：Windows Desktop `0.2.2-rc.3` + 本仓库 `adapter` 补丁。
> 下文用 `$env:LOCALAPPDATA\Programs\DeepSeek Harness\resources` 表示资源目录，按实际安装位置替换。

## 0. 三十秒判定

```powershell
(Get-FileHash "$env:LOCALAPPDATA\Programs\DeepSeek Harness\resources\app.asar" -Algorithm SHA256).Hash
```

| 哈希 | 含义 | 动作 |
|---|---|---|
| `EE66AA50B281CD0E32C4B1EC3B359F6C7528F6CD5BAA57541E6C83E17CB04EC0` | 补丁在位（rc.3） | 无需处理；功能异常看第 5 节 |
| `14CFD81C9135BF0AFB89417543C94F9ECFE09266574452A9B106890C698725AE` | 官方原版 rc.3 | 走第 2 节（同版本重装） |
| 其他 | 应用已升级，版本不是 rc.3 | 走第 3 节（重做锚点） |

症状对照：右键菜单提示「此功能需要兼容的 DSH 桌面对话窗口适配补丁」= `window.dshDesktop.conversations` 不存在 = 补丁没生效。

## 1. 为什么会失效

- 桌面端走 **nightly** 通道（`resources/app-update.yml`：provider `generic`，`download.deepseek.com/dsh-desk/feeds/win-x64/`），自动更新是**整包替换** `resources/app.asar`，补丁一并消失。
- 已有先例：2026-11-13 02:30 的一次安装把 asar 换回官方版，插件随即失效。

## 2. 同版本（0.2.2-rc.3）重新安装

1. 双击仓库根目录 `install-and-restart.cmd`（**不要**在 DSH 自带终端或 DSH 派生的 shell 里跑）。
2. 窗口打印 `WAIT DeepSeek Harness is running` 后，**托盘图标 → 退出**（点窗口叉只是隐藏）。
3. 脚本自动：备份原版 → 暂存候选 → `File.Replace` 原子替换 → 校验哈希 → 写 `conversation-window-plugin.sha256` → 只启动一次 DSH。
4. 看到 `OK` 即成功。全过程记录在 `build/install-adapter.log`。

要点：

- 安装与回滚是**同一个脚本** `scripts/install-adapter.ps1`（`-Restore` 是反向操作），`install-and-restart.cmd` 只是入口，没有第二份实现。
- 备份文件 `app.before-conversation-window-plugin.asar` 不存在时脚本会自动从当前原版创建并校验；已存在则先验证是否等于原版哈希，不等就拒绝。
- 候选包哈希必须等于脚本里的 `$patchedHash`；重新构建后要同步更新该常量，脚本会拒绝来历不明的包。
- 脚本先做祖先进程检查：发现自己在 DSH 进程树内直接拒绝，不会自杀。

## 3. 版本变更后重做

`adapter/changes.json` 里三个文件的锚点和哈希全部失效，必须重写。

### 3.1 取新版本号与原始文件

```python
import json, os, struct, pathlib
res = pathlib.Path(os.environ['LOCALAPPDATA']) / 'Programs' / 'DeepSeek Harness' / 'resources'
src = res / 'app.asar'
out = pathlib.Path(os.environ['USERPROFILE']) / 'dsh-asar-new'; out.mkdir(exist_ok=True)
f = open(src, 'rb'); a, hs, z, js = struct.unpack('<4I', f.read(16)); h = json.loads(f.read(js)); base = 8 + hs
def leaves(t, p=''):
    for n, e in t['files'].items():
        q = p + n
        yield from (leaves(e, q + '/') if 'files' in e else [(q, e)])
d = dict(leaves(h))
def read(k):
    e = d[k]; f.seek(base + int(e['offset'])); return f.read(e['size'])
print('version:', json.loads(read('package.json'))['version'])
for k in ['lib/main.js', 'lib/preload-app.cjs',
          'dsh/node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js']:
    (out / pathlib.Path(k).name).write_bytes(read(k))
```

### 3.2 重写 `adapter/changes.json`

| 字段 | 规则 |
|---|---|
| `desktopVersion` | 新版本号 |
| `sha256` | 上述提取出的**原始**文件 SHA-256（小写十六进制） |
| `edits[].old` | 在新文件里重新定位同一段代码；必须与原文逐字一致（含制表符、引号），且在全文唯一 |
| `edits[].new` | 保持原改动意图，只替换定位用的原文 |
| `resultSha256` | 整文件应用完所有 edit 后的 SHA-256 |

三个文件共 17 条 edit。锚点语义见第 4 节。改错不会静默通过：`build_adapter.py` 校验原始哈希、原文唯一性、结果哈希，任一不符即报错不产出。

### 3.3 构建与回归

```powershell
python scripts/build_adapter.py --source "$env:LOCALAPPDATA\Programs\DeepSeek Harness\resources\app.asar"
node --test tests/conversation-windows.test.mjs tests/plugin.test.mjs
node --test tests/routing.test.mjs   # 需要上一步的本地产物
```

### 3.4 更新固定哈希并安装

把新 `build/app.conversation-window.asar` 的 SHA-256 写入 `scripts/install-adapter.ps1` 的 `$patchedHash`，然后走第 2 节。

## 4. 补丁改了什么（锚点语义）

`lib/main.js`
1. 顶部 `import { createConversationWindows } from './conversation-windows.mjs'`。
2. `installDesktopDirectoryPicker` / `installDesktopShortcuts` 增加 `resolveOwner` 参数，按 IPC 来源窗口解析归属，而非固定 `mainWindow`。
3. `assertProductSender` 允许「主窗口 或 会话窗口」，返回实际 owner。
4. 注册 `ipcMain.handle('dsh-desktop:conversation-open', ...)`。
5. WebSocket 头注入与水合校验（`DESKTOP_IPC.boot` 关联的 `webContentsId` 检查）放行会话窗口。
6. `assertMainApplication` 统一为 `assertProductSender`；`localeBootstrap` 同样。

`lib/preload-app.cjs`
7. `createProductApi()` 返回 `conversations: { openWindow(sessionId) }`，桥接上面的 IPC。

`dsh/.../dsh-client-ui-workspace/lib/client.js`
8. `?conversation=` 存在时选择快照不落盘（`persist` 关闭），避免污染主窗口的 `dsh.sessions.current`。
9. `restoreSelection()` 开头读取 `?conversation=`，命中就直接 `replaceMain(id, lifetime.signal, 'reveal')` 并返回。

`lib/conversation-windows.mjs`（新增文件，不打补丁，直接整文件注入）
- 校验 sessionId（`^[A-Za-z0-9_-]{1,512}$`），拒绝任意 URL。
- `createWindow(preload, false, true)`：与主窗口同款 `titleBarStyle: hidden` 变体，否则渲染层预留的 40px 标题带会和原生边框叠成双标题栏。
- 窗口创建失败即销毁，不残留。

## 5. 已踩过的坑（都会伪装成"补丁没装好"）

| 现象 | 真因 | 处理 |
|---|---|---|
| （历史）安装日志停在 `Stopping only the verified desktop executable (N processes).` 之后无输出 | 已删除的旧版脚本先杀 DSH 进程，自己被连带终止，复制从未执行 | 杀进程方案已废弃，现为等待手动退出 |
| `app.asar` 无法替换，独占打开/重命名都失败 | Electron 运行期间独占锁定 | 必须先完全退出 DSH（含托盘）；脚本会自动等 |
| 用 `Start-Process` 启动后进程立即退出，退出码 0，无窗口 | 宿主环境带 `ELECTRON_RUN_AS_NODE=1`，exe 以 Node 模式运行 | 启动前 `Remove-Item Env:ELECTRON_RUN_AS_NODE` |
| `Remove-Item` 删 `resources` 下临时文件被拦 | 安全包装的回收站失败即 fail-closed | 改用 `[System.IO.File]::Delete()` |
| 脚本报「This console is a child of DeepSeek Harness」 | 在 DSH 派生的终端里运行 | 从资源管理器双击 `install-and-restart.cmd` |

## 6. 安装前后自检

```powershell
$res = "$env:LOCALAPPDATA\Programs\DeepSeek Harness\resources"
foreach ($f in @("app.asar","app.before-conversation-window-plugin.asar","conversation-window-plugin.sha256")) {
  $p = Join-Path $res $f
  if (Test-Path -LiteralPath $p) { "{0} {1}" -f $f,(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { "$f MISSING" }
}
Get-Content (Join-Path $res "conversation-window-plugin.sha256")
```

安装成功后：`app.asar` = `$patchedHash`，备份 = 原版哈希，记录文件 = `$patchedHash`。

## 7. 回滚

先在 DSH 插件管理里停用本插件，再运行（脚本会自己等你退出应用）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-adapter.ps1 -Restore
```

`-Restore` 与安装是同一个脚本：校验备份 = 原版 → 等应用退出 → 换回原版 → 删除安装记录 → 启动一次。若安装后又更新过应用，回滚会拒绝覆盖，改用官方安装器恢复。

## 8. 实测记录

- 2026-11-13 02:30 应用安装（nightly），覆盖掉更早的补丁；此后菜单一直提示需要适配补丁。
- 2026-11-14 23:15 用 `File.Replace` 换入 `EE66AA50…04EC0`，备份与记录文件就位；DSH 以补丁版正常启动（窗口标题 `DeepSeek Harness`，无异常退出）。
- 自动化测试 17 项通过（窗口管理 5 / 插件 9 / 路由 3），均基于 mock 或提取的路由代码，**不等于**实机双窗口验收。
- 真实双窗口、同会话双发、流式接管、关闭不中断等项仍待人工验收；见 README「实机复测清单」。
