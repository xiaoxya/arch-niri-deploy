# 默认快捷键

快捷键由当前安装版本的 DMS 通过 `dms setup` 生成到 `~/.config/niri/dms/binds.kdl`。这能避免项目内的静态配置落后于 DMS IPC。`Mod` 在正常 Niri 会话中是 Super/Windows 键。

## DMS 与应用

| 快捷键 | 操作 |
|---|---|
| `Mod+T` | Kitty 终端 |
| `Mod+Space` | DMS 应用启动器 |
| `Alt+Space` | DMS Spotlight Bar |
| `Mod+V` | DMS 剪贴板管理器 |
| `Mod+M` | DMS 任务管理器 |
| `Mod+,` | DMS 设置 |
| `Mod+N` | DMS 通知中心 |
| `Mod+Shift+N` | DMS 记事本 |
| `Mod+Y` | DMS 壁纸界面 |
| `Super+X` | DMS 电源菜单 |
| `Mod+Alt+L` | DMS 锁屏 |
| `Mod+Shift+/` | Niri 快捷键提示 |

## Niri 窗口操作

| 快捷键 | 操作 |
|---|---|
| `Mod+O` 或 `Mod+Tab` | 总览 |
| `Mod+Q` | 关闭窗口 |
| `Mod+F` | 最大化当前列 |
| `Mod+Shift+F` | 窗口全屏 |
| `Mod+Shift+T` | 浮动/平铺切换 |
| `Mod+W` | 列标签显示模式 |
| `Mod+H/J/K/L` 或方向键 | 移动焦点 |
| `Mod+Shift+H/J/K/L` | 移动列或窗口 |
| `Mod+Ctrl+H/J/K/L` | 聚焦相邻显示器 |
| `Mod+Shift+Ctrl+H/J/K/L` | 把当前列移到相邻显示器 |
| `Mod+Shift+E` | 退出 Niri |

音量、麦克风、媒体播放与屏幕亮度功能键也通过 DMS IPC 管理。DMS 版本更新后，按 `Mod+Shift+/` 查看机器上实际生效的完整列表，或直接查看：

```bash
less ~/.config/niri/dms/binds.kdl
```
