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
| DankMaterialShell (DMS) | 顶栏、启动器、通知、控制中心、锁屏、壁纸和设置管理 |
| Quickshell + dgop | DMS 图形界面与系统状态后端（由 `dms-shell-niri` 依赖安装） |
| Kitty | 默认终端，使用 FiraCode Nerd Font Mono 与中文后备字体 |
| Fcitx5 + 雾凇拼音 | 中文输入框架与简体中文词库 |
| Fish + Starship | 默认交互 Shell 与命令提示符 |
| wl-clipboard + cliphist | Wayland 剪贴板和历史 |
| grim + slurp + Satty | 截图、区域选择和标注 |
| Thunar + GVfs | 文件管理、SMB/MTP/GPhoto 访问 |
| greetd + DMS Greeter | 与 DMS 主题同步的图形登录器（AUR 二进制包） |

## 模块化配置

入口为 `~/.config/niri/config.kdl`。项目维护基础环境模块，DMS 维护可由设置界面动态修改的模块：

- `environment.kdl`：Wayland、Fcitx5 和应用兼容环境；
- `input.kdl`：基础键盘、鼠标和触控板设置；
- `startup.kdl`：Fcitx5、会话环境和剪贴板监听；
- `rules.kdl`：通用窗口规则与敏感窗口录屏保护；
- `dms/*.kdl`：DMS 生成的颜色、布局、快捷键、显示器、光标和窗口规则。

主配置使用 `include optional=true` 引入 DMS 文件，因此首次生成或 DMS 升级期间即使暂缺某个可选模块，也不会导致 Niri 因文件不存在而无法启动。

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

优先在 DMS 设置的 Displays 页面调整。也可以编辑 `~/.config/niri/dms/outputs.kdl`，例如：

```kdl
output "eDP-1" {
    mode "2560x1600@120"
    scale 1.5
    position x=0 y=0
}
```

多显示器的位置使用缩放后的逻辑像素。配置重叠或不完整时，Niri 会自动放置输出。

## 输入法

Fcitx5 会随会话启动，安装器会预先启用 Rime 并部署雾凇拼音，因此首次登录即可使用。默认按 `Ctrl+Space` 在英文键盘和 Rime 间切换。如需调整候选框、快捷键或输入方案，运行：

```bash
fcitx5-configtool
```

词库位于 `~/.local/share/fcitx5/rime`。重新运行安装器会更新雾凇拼音的上游文件，并保留额外创建的个人文件；首次部署前会备份已有目录。

环境配置保留 XWayland 所需的 `XMODIFIERS`，并为非 KWin 环境设置 Qt/SDL 输入模块；不全局强制 `GTK_IM_MODULE`，让原生 Wayland GTK 3/4 应用使用 `text-input-v3`，避免候选框闪烁。

## 字体、Shell 与终端

本项目采用 SHORiN DMS Niri 的通用部分，并补齐 DMS 实际使用的字体：Noto 基础与扩展、Noto CJK/Emoji、思源黑体/宋体简体中文、DejaVu、Liberation、Roboto、Open Sans、FiraCode/JetBrains Nerd Font、Nerd Symbols、Material Symbols 和 Font Awesome。没有引入其个人 AI、游戏、自建软件源或定制字体包。

Kitty 默认使用 Fish，`Mod+T` 打开终端。Fish 采用 SHORiN 的通用交互方式：Starship 提示符、Zoxide 接管 `cd`、Eza/Bat 命令函数、`fa`（Fastfetch）缩写，以及 Yazi 的 `y` 工作目录联动；`ll` 仍保留为项目的详细隐藏文件列表。作者机器专用的动漫壁纸、LM Studio 路径、游戏补帧、Grub 命令和私有脚本不会部署。Fontconfig 会在 DMS 默认的 FiraCode Nerd Font 后追加简体中文、Emoji 与图标后备字体。Kitty 主配置会载入 `dank-theme.conf` 和 `dank-tabs.conf`，让 DMS/Matugen 更新颜色而不覆盖字体与 Shell 设置。配置路径为：

```text
~/.config/kitty/kitty.conf
~/.config/fish/config.fish
~/.config/starship.toml
~/.config/fontconfig/fonts.conf
```

安装器会用 `fc-match` 验证 Noto CJK、Noto Color Emoji、FiraCode Nerd Font、Symbols Nerd Font 与 Material Symbols；缺少任意一项都会停止并指出具体字体，而不是带着残缺字体进入桌面。

### 命令行美化与已安装系统更新

Starship 现在采用 [SHORiN Niri](https://github.com/SHORiN-KiWATA/shorin-niri/blob/main/dotfiles/.config/starship.toml) 风格的圆角 Powerline 分段：Arch 图标和用户名、目录、Git 分支/状态、开发环境、时间，第二行显示命令输入箭头。Git 和语言内容仅在相关目录显示。配色使用静态粉色调，所有颜色均有定义；开发环境文字使用浅色，确保深色背景下可读。此配置没有接入上游的壁纸动态取色，DMS 仍可独立改变 Kitty 的背景颜色。

旧项目的 `starship.toml` 只包含简化目录提示符，并且引用了未定义的 `mauve` 颜色；安装 Fish/Starship 软件包本身不会补上上游主题。新版同时设置 Fish 命令、参数、错误和历史建议的颜色，并将 `STARSHIP_CONFIG` 指向当前 Fish 配置目录旁的 `starship.toml`，覆盖遗留的其他主题路径。TTY 或 SSH 客户端若无法显示 Nerd Font 图标，请在已配置字体的 Kitty 中查看。

已安装系统只需下载并解压新版项目，进入该项目目录，以当前桌面普通用户运行（不要在命令前加 `sudo`）：

```bash
bash scripts/update-terminal.sh
```

若新版文件已经放到 `/opt/arch-niri-deploy`，也可运行：

```bash
bash /opt/arch-niri-deploy/scripts/update-terminal.sh
```

依赖已齐全时不会调用 Pacman；缺少依赖时使用当前软件源进行完整系统升级并补装。工具会更新 Fish 主配置和 Starship 主题，为 Kitty 添加 `include arch-niri-terminal.conf`，保留已有的其他 Kitty 设置和 DMS 生成颜色。发生改变的旧文件备份至 `~/.local/state/arch-niri-deploy/backups/terminal.*`，相同内容再次运行不重复备份；设置了 `XDG_CONFIG_HOME` / `XDG_STATE_HOME` 时使用对应目录。恢复时把备份内相应文件复制回配置目录，再重新打开终端即可。

工具会验证字体、渲染 Starship 预览并启动一次 Fish 检查初始化。关闭并重新打开 Kitty 后即可看到新效果，无需重装 Niri。完整桌面安装也会执行同样的部署和校验。如果仍有异常，请保留该工具输出的日志；可先检查：

```fish
status is-interactive
echo $STARSHIP_CONFIG
functions fish_prompt
starship explain
```

`fa` 仍为手动启动 Fastfetch 的缩写，不会在每次新建终端时自动运行。

## DMS 管理

安装器使用 Arch 官方 `dms-shell-niri`，通过 `dms setup colors/layout/alttab/binds` 独立生成当前版本兼容的模块，并把 `dms.service` 仅绑定到 `niri.service`。这种方式不会覆盖项目维护的 `config.kdl` 或 Kitty 主配置，也不会同时启动 Waybar、SwayNC、Fuzzel 或 swaylock。

登录界面使用 AUR 的 `greetd-dms-greeter-bin`，由 `dms-greeter enable` 写入 greetd 的 Niri 会话，并通过 `dms-greeter sync` 同步 DMS 的主题、壁纸和设置。它会替换并卸载旧的 `greetd-tuigreet`，不再显示黑底文字登录器。

安装器还会保留现有 GTK 配置的备份，再让 GTK 3/4 的 `gtk.css` 引入 DMS 维护的 `dank-colors.css`，并设置 `adw-gtk3-dark` 与 `Papirus-Dark`。这样 Thunar 等 GTK 程序能跟随 DMS 的动态配色与图标主题。

常用检查命令：

```bash
dms doctor
systemctl --user status dms
journalctl --user -b -u dms
dms restart
```

`outputs.kdl`、`cursor.kdl` 与 `windowrules.kdl` 初始为空是 DMS 1.5 的正常行为，登录后可由 DMS 设置界面写入。安装器只检查这三个文件存在，不再把空文件误判为安装失败。

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

重新运行 `/opt/arch-niri-deploy/install-niri.sh` 会更新项目管理的基础配置，但保留已有且非空的 DMS 模块。首次从旧版 Waybar 配置迁移到 DMS 时，会备份 `~/.config/niri` 与 `~/.config/DankMaterialShell`。显示器、颜色和布局优先通过 DMS 设置修改。
