# DSH Controller

一个 macOS 菜单栏轻量控制器，用于管理 [DeepSeek Harness](https://github.com/anywhere-labs)（`dsh web`）服务：启动 / 关闭 / 重启，并实时显示运行状态与 PID。

原生 Swift + AppKit 实现，无 Electron、无 Dock 图标，常驻内存约 50MB。

## 功能

- 菜单栏图标显示服务状态：🟢 运行中（绿色 DeepSeek 图标）/ ⚪ 已停止（灰色）
- 启动 / 关闭 / 重启 dsh 服务
- 状态每 5 秒自动刷新，打开菜单时即时刷新
- 显示当前进程 PID

## 原理

dsh 服务由 launchd 托管（`~/Library/LaunchAgents/com.dsh.web.plist`），且配置了 `KeepAlive`。因此：

| 操作 | 命令 |
| --- | --- |
| 启动 | `launchctl bootstrap gui/<uid> <plist>` + `launchctl kickstart` |
| 关闭 | `launchctl bootout gui/<uid>/com.dsh.web`（卸载，避免 KeepAlive 自动拉起）|
| 重启 | `launchctl kickstart -k gui/<uid>/com.dsh.web` |

图标使用来自 [simpleicons](https://simpleicons.org) 的 DeepSeek 矢量路径，运行时按状态填充绿色 / 灰色。

## 构建

需要 Xcode Command Line Tools（`swiftc`）。

```bash
./build.sh
```

会在 `/Applications/DSH Controller.app` 生成应用并清除 quarantine。之后用 `open` 启动，或加到「系统设置 → 通用 → 登录项」开机自启。

## 文件

- `main.swift` — AppKit 菜单栏应用主体
- `Info.plist` — `LSUIElement=true`（纯菜单栏，无 Dock 图标）
- `build.sh` — 编译并组装 .app 包

## 前置要求

- macOS 11+（Apple Silicon / Intel 通用，当前构建目标为 arm64）
- 已通过 `dsh` CLI 安装并配置好 `com.dsh.web` 服务

## License

MIT
