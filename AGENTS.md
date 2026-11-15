# AGENTS.md

DSH 桌面端插件（`client.js` 等）+ 一个必须打进 `resources/app.asar` 的补丁（`adapter/`）。
插件本身可随时安装；补丁会随桌面端更新失效。

## 读什么

1. `README.md` —— 这是什么、兼容边界、当前验证状态。
2. `docs/REPAIR.md` —— **补丁失效后的全部处理流程**：哈希判定 → 同版本重装 → 版本变更重做锚点 → 静态核验 → 回滚，以及已知的五个坑。

不要跳过第 2 份文档自己重新推导方案。

## 硬规则

- **修复不成功就停**，按 `docs/REPAIR.md` 开头「铁律」的五项判据执行：把版本号、`app.asar` 哈希、卡住的锚点、原始报错交给用户，等指令。不要自行改架构。
- 不改 `$patchedHash` 去迁就未验证的包；不放宽 `adapter/changes.json` 的哈希与唯一性校验；不跳过测试直接安装。
- 功能不降级为浏览器弹窗；不反复重启应用重试。
- `build/` 与任何 `.asar` 产物含上游编译产物，**不得提交或上传**。
- 安装器在应用运行时无法替换 `app.asar`（独占锁），必须等用户从托盘退出；不要改成杀进程。

## 常用入口

```powershell
# 安装 / 回滚 / 只校验
install-and-restart.cmd
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-adapter.ps1 -Restore
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-adapter.ps1 -CheckOnly

# 重建补丁包（需要本机已安装兼容版本）
python scripts/build_adapter.py --source "$env:LOCALAPPDATA\Programs\DeepSeek Harness\resources\app.asar"
node --test tests/conversation-windows.test.mjs tests/plugin.test.mjs
```
