# Niri 桌面说明

## 组件关系

Niri 是可滚动平铺的 Wayland 合成器；本项目围绕它组合了一套尽量使用官方仓库、保持通用的桌面：

| 组件 | 用途 |
|---|---|
| Niri | Wayland 合成器与窗口管理 |
| Xwayland Satellite | 运行旧式 X11 应用 |
| GNOME Portal | 屏幕共享与录屏 Portal |
| GTK Portal | 配合 Thunar 提供文件选择器 |
| PipeWire + WirePlumber | 音频、视频流和屏幕共享 |
| Waybar | 顶栏、工作区和状态信息 |
| Fuzzel | 应用启动器与菜单 |
| Kitty | 默认终端 |
| SwayNC | 通知守护进程与通知中心 |
| swaylock + swayidle | 锁屏、空闲熄屏、睡眠前锁屏 |
| Fcitx5 + Rime | 中文输入框架 |
| wl-clipboard + cliphist | Wayland 剪贴板和历史 |
| grim + slurp + Satty | 截图、区域选择和标注 |
| Thunar + GVfs | 文件管理、SMB/MTP/GPhoto 访问 |
| greetd + tuigreet | 文本式图形会话登录器 |

## 模块化配置

入口为 `~/.config/niri/config.kdl`，其余内容在 `config.d`：

- `environment.kdl`：Wayland、Fcitx5 和应用兼容环境；
- `input.kdl`：键盘、鼠标、触控板和光标；
- `layout.kdl`：间距、列宽、边框和阴影；
- `startup.kdl`：面板、通知、输入法、托盘、锁屏与剪贴板监听；
- `rules.kdl`：浮动窗口、圆角和敏感窗口录屏保护；
- `binds.kdl`：快捷键；
- `outputs.kdl`：按机器设置显示器。

修改任一 KDL 后先验证：

```bash
niri validate --config ~/.config/niri/config.kdl
```

Niri 会实时重载有效配置。

## 显示器

进入 Niri 后查询输出：

```bash
niri msg outputs
```

编辑 `~/.config/niri/config.d/outputs.kdl`，例如：

```kdl
output "eDP-1" {
    mode "2560x1600@120"
    scale 1.5
    position x=0 y=0
}
```

多显示器的位置使用缩放后的逻辑像素。配置重叠或不完整时，Niri 会自动放置输出。

## 输入法

Fcitx5 会随会话启动。首次进入后运行：

```bash
fcitx5-configtool
```

在输入法列表中添加 Rime。默认可使用 `Ctrl+Space` 切换；具体行为由 Fcitx5 配置决定。

## 屏幕共享

Niri 使用 `xdg-desktop-portal-gnome` 进行 ScreenCast，使用 GTK Portal 进行文件选择。若浏览器或 OBS 看不到共享目标：

```bash
systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk
journalctl --user -b -u xdg-desktop-portal
```

## NVIDIA

现代 NVIDIA 使用开放内核模块。若黑屏，先从 TTY 检查：

```bash
journalctl -b -p err
journalctl --user -b -u niri
lspci -k | grep -A3 -E 'VGA|3D'
```

不要盲目给混合显卡写死 `/dev/dri/card*`；这些编号可能在更新后改变。只有确认自动选择失败时，才按 Niri 官方文档设置渲染设备。

## 更新配置

重新运行 `/opt/arch-niri-deploy/install-niri.sh` 会更新项目管理的默认配置。若你已经深度修改，请先复制 `~/.config/niri`；最稳妥的方法是把自己的机器差异集中放在 `outputs.kdl`，或另建模块并在入口中 `include`。
