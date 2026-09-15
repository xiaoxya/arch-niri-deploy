# 安装指南

## 1. 准备

你需要：

- x86_64、支持 UEFI 的电脑；
- 一块允许被完整清空的目标磁盘；
- Arch Linux 安装介质与可用网络；
- 重要数据的独立备份。

固件中请启用 UEFI，关闭 Legacy/CSM。脚本暂不配置 Secure Boot；若已启用，可先关闭，安装完成后自行用 `sbctl` 签名。

## 2. 在 Arch ISO 中联网

有线网络通常自动可用。无线网络可使用：

```bash
iwctl
station wlan0 connect 你的无线网络名
exit
ping -c 3 archlinux.org
```

把项目复制到 ISO 环境后进入项目目录：

```bash
chmod +x install-base.sh install-niri.sh install-apps.sh scripts/*.sh
sudo ./install-base.sh
```

安装器会依次询问：

- 主机名；
- 普通用户名；
- 时区（默认 `Asia/Shanghai`）；
- TTY 键盘布局；
- 系统语言（默认简体中文，也可选英文）；
- 新系统网络：DHCP（默认）或有线固定 IPv4；
- 是否安装 `snapper-rollback`（默认安装，会增加构建依赖）；
- 普通用户密码（至少 3 个字符）；
- 保持 root 锁定，或为 root 设置独立密码；
- 从自动扫描结果中按编号选择整块目标磁盘。

### 中文与本机 TTY

选择中文后，桌面和支持中文字体的终端仍使用 `zh_CN.UTF-8`；本机内核 TTY（黑底登录界面）单独使用英文 UTF-8。内核控制台不能完整显示中文，安装 Noto/思源字体也不会让它具备 Kitty 的字体渲染能力。具体限制见 [ArchWiki 中文本地化](https://wiki.archlinux.org/title/Localization/Simplified_Chinese)。

安装器为 `getty@.service` 写入仅针对控制台登录的语言设置，并配置 Bash/POSIX 登录 Shell 与 Fish 的 TTY 回退。`LC_ALL=en_US.UTF-8` 只在本机控制台会话内生效，不写入全局 `/etc/locale.conf`；桌面和 SSH 保留所选语言。此修改让系统提示、命令报错和日期可读，不能让 TTY 显示中文文件名或脚本中写死的中文文本。安装菜单本身为中文，建议通过有中文字体的 SSH 客户端运行。

已经安装好的系统不需要重装。将新版项目解压后进入项目目录，运行：

```bash
sudo bash scripts/fix-console-locale.sh
```

工具会备份原文件到 `/root/arch-niri-console-backup.*`，补齐英文 locale 并写入控制台设置；不会重启现有登录会话。保存工作后重启生效。立即临时恢复当前 TTY 的命令输出，可按所用 Shell 执行：

```bash
# Bash
export LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8
```

```fish
# Fish
set -gx LANG en_US.UTF-8
set -gx LANGUAGE en_US:en
set -gx LC_ALL en_US.UTF-8
```

选择磁盘后，安装器会先显示完整配置摘要。基础阶段固定安装 `linux` 内核、Btrfs、systemd-boot、NetworkManager 与 OpenSSH，网络默认 DHCP，也可选择有线固定 IPv4；不会安装桌面、显卡驱动、音频服务或个人化软件。

### 有线固定 IPv4

选择固定 IPv4 后，会扫描有线网卡，显示名称、链路状态、当前 IPv4 和 MAC，再询问地址/前缀、网关和 DNS。例如：

```text
地址/前缀：192.168.1.50/24
网关：192.168.1.1
DNS：223.5.5.5,119.29.29.29
```

只支持普通局域网的 `/1` 至 `/30` 前缀；拒绝网络地址、广播地址、非法 IPv4 和异网段网关。没有默认网关时输入 `-`。DNS 用英文逗号分隔。IP 应在路由器中预留或置于 DHCP 地址池之外，安装器无法仅凭格式检查确认地址没有被占用。

配置按永久 MAC 绑定网卡，避免安装介质与新系统的网卡名称变化导致失效；输出路径为 `/etc/NetworkManager/system-connections/arch-niri-static.nmconnection`，权限为 root 的 `0600`。写入后用 NetworkManager 的离线模式检查配置，不启动目标系统网络服务。设置在重启进入新系统后生效，当前 Live 网络与 SSH 连接不会被切换。固定 IPv4 模式关闭该连接的 IPv6；其他网卡不受影响。无线网络、VLAN、网桥及 `/31`、`/32` 等特殊网络请在进入系统后用 `nmtui` 或 `nmcli` 配置。

重启后可检查：

```bash
nmcli connection show arch-niri-static
ip -4 address
ip -4 route
```

### snapper-rollback 软件包

[`snapper-rollback`](https://github.com/jrabinow/snapper-rollback) 是 AUR 中的第三方工具，不能直接当作 Arch 官方包交给 `pacstrap`。安装器提供默认开启的可选项，使用项目维护的 `packaging/snapper-rollback/PKGBUILD` 构建真实 Pacman 包，保留该包名称；不是直接执行滚动更新的 AUR 配方。

当前固定上游提交 `04488f2350e8ec214277fe7de608492a9ee665a7`，以 SHA-256 验证源码；清盘前下载源码，基础系统安装后以新建的普通用户运行 `makepkg`，再由 root 安装。增加并保留 `base-devel` 构建依赖，检查工具所需的 `jq` 同时属于基础包。构建目录和软件包保留在 `/var/tmp/arch-niri-rollback-build.*`。安装器检查 `snapper-rollback --help`，不会执行回滚。

从本项目的 `1.0-3` 起，命令入口统一调用项目安全检查和 Snapper classic，避免上游吞掉错误以及两套回滚方式混用；上游原始代码与配置仅保留作参考。项目脚本和包内脚本分别部署，修改项目不会自动覆盖已安装的包。本地版本不会从官方镜像自动更新。检查范围与离线恢复限制见 [恢复指南](RECOVERY.md#额外的-snapper-rollback-包)。

已安装系统可使用新版项目脚本，或以普通用户重新构建安全封装包（不要重跑基础安装器）：

```bash
sudo pacman -Syu --needed base-devel jq diffutils mkinitcpio snapper btrfs-progs
cd /opt/arch-niri-deploy  # 此目录必须已替换为新版项目
build_dir=$(mktemp -d)
cp packaging/snapper-rollback/{PKGBUILD,launcher.sh} "$build_dir/"
cp scripts/rollback-snapshot.sh lib/rollback.sh "$build_dir/"
cp LICENSE "$build_dir/PROJECT-LICENSE"
cd "$build_dir"
makepkg -si
```

本地输入文件也有校验和；修改回滚代码后需同步维护 PKGBUILD 中的校验和。构建失败不会触发磁盘回滚。

安装时可选择软件镜像，默认中科大 USTC；也可选择清华大学 TUNA。两者均同时用于 Arch Linux 官方仓库和 Arch Linux CN 社区仓库。

USTC（默认）：

```text
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
```

清华 TUNA（可选）：

```text
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
```

所选镜像的 Arch Linux CN 配置为：

```text
[archlinuxcn]
Server = https://mirrors.ustc.edu.cn/archlinuxcn/$arch
# 或
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch
```

这两项配置都会写入安装介质当前环境和新系统；基础阶段会安装 `archlinuxcn-keyring`。安装器会明确回显写入的路径，并启用 5 路 Pacman 并行下载。在开始约 767 MiB 的基础包下载前，安装器会用 IPv4 请求所选镜像的 `core.db`，显示连接速度；无法连接会立即停止，低于 64 KiB/s 时需要人工确认。`reflector.timer` 会被屏蔽，防止它自动覆盖所选镜像。原镜像列表与 Pacman 配置仅首次分别保存为 `/etc/pacman.d/mirrorlist.pre-arch-niri-deploy`、`/etc/pacman.conf.pre-archlinuxcn`；选择会保存为 `/etc/arch-niri-deploy/mirror-profile`，后续 Niri 和应用安装会沿用它。

三个安装器都会显示总体阶段、步骤数和百分比，例如：

```text
进度 [#########-------------------]  33% (3/8) 配置所选镜像并刷新软件数据库
```

下载及软件包安装期间还会保留 Pacman 自带的单包进度，因此可以同时判断总体阶段和当前软件包状态。对分区同步、Btrfs 全盘 TRIM、镜像/密钥环刷新、下载解压和安全卸载等可能耗时的阶段，安装器还会额外回显当前正在等待的操作。安装日志中也会记录这些阶段进度。

所选镜像连通性与软件数据库/密钥环检查在清盘前执行，检测失败时不会破坏目标磁盘；该预检不保证之后每个软件包下载都成功。检查完成后会再次验证磁盘没有被挂载或用作安装介质。每个阶段结束时回显该阶段耗时，完成时显示总耗时，方便区分网络下载、格式化和本地配置的时间。前置检查发现 `/mnt` 已被占用时会直接退出，退出清理只卸载本次安装器自己接管的挂载。

## 3. 磁盘布局

`install-base.sh` 会永久清空所选磁盘，并建立：

| 分区 | 大小 | 文件系统 | 挂载点 |
|---|---:|---|---|
| EFI System | 1 GiB | FAT32 | `/boot` |
| Arch Linux | 剩余空间 | Btrfs | `/` 及子卷 |

Btrfs 子卷：

| 子卷 | 挂载点 | 目的 |
|---|---|---|
| `@` | `/` | 系统根目录 |
| `@home` | `/home` | 用户数据 |
| `@log` | `/var/log` | 日志独立于根快照 |
| `@cache` | `/var/cache` | 缓存独立于根快照 |
| `@snapshots` | `/.snapshots` | Snapper 快照 |

默认挂载参数为 `noatime,compress=zstd:1,ssd,discard=async,space_cache=v2`。

脚本会列出磁盘编号、设备路径、容量、型号、接口和序列号。选择后，分区前还有两次不可跳过的确认：完整设备路径和随机确认码。请通过显示的型号、容量和现有分区再次核对。

安装器会自动识别并排除当前 Arch 安装介质，同时拒绝只读设备、小于 16 GiB 的磁盘、已有挂载分区或活动交换分区的磁盘。它不会替你强制卸载这些设备，以免中断当前系统或 SSH 会话。

## 4. 基础系统内容

第一阶段只安装：Linux 内核、对应 CPU 微码、Btrfs、systemd-boot、NetworkManager、OpenSSH、sudo、reflector、Snapper 和基础维护工具。Reflector 仅作为手动维护工具保留，其定时服务不会启用。基础阶段不会安装显示服务、声卡服务或桌面环境。

安装结束后：

脚本会在结束前检查用户、sudo、服务、内核、initramfs、systemd-boot、USTC 镜像、fstab 与全部 Btrfs 子卷。`@` 会被设为 Btrfs 默认子卷；根目录的 fstab 和 systemd-boot 启动项不会固定 `subvol=@`，以便 Snapper 能在回滚时切换默认子卷。其余四个子卷仍由 fstab 显式挂载。通过后，它会把日志保存为 `/var/log/arch-niri-deploy/base-install.log`，执行 `sync`，递归卸载 `/mnt` 并确认没有残留挂载点。只有自动卸载成功后才会显示可以重启；如果有进程占用目标系统，安装器会列出残留挂载并以错误状态退出。

```bash
reboot
```

拔出安装介质，登录新系统。若要远程完成后续步骤，可先查询地址：

```bash
ip address
```

项目会保存在 `/opt/arch-niri-deploy`。

## 5. 安装 Niri

以普通用户运行：

```bash
cd /opt/arch-niri-deploy
./install-niri.sh
```

脚本会：

1. 创建安装前快照；
2. 完整更新 Arch；
3. 识别 Intel、AMD、NVIDIA 或混合显卡并安装驱动；
4. 安装 Niri、PipeWire、Portal、greetd、Arch 官方 `dms-shell-niri` 与 AUR 的 DMS Greeter；
5. 安装 Noto/思源中文、Emoji、FiraCode/JetBrains Nerd Font 与图标字形；
6. 安装 Fcitx5、Fish、Kitty 与终端工具；
7. 备份已有用户配置，部署雾凇拼音与模块化配置；
8. 用 `dms setup` 的独立子命令生成 DMS 模块，把 `dms.service` 绑定到 `niri.service`，并部署 DMS Greeter 图形登录界面；
9. 校验字体、DMS 与 Niri KDL，并创建安装后快照。

雾凇拼音从其上游 GitHub 仓库下载，不启用 ArchLinuxCN 或 SHORiN 的个人软件仓库。若所在网络无法访问 GitHub，安装器会保留安装前快照、明确停止在“部署雾凇拼音词库”阶段，可恢复网络后直接重跑。

显卡厂商通过 PCI ID 判断（AMD `1002`、Intel `8086`、NVIDIA `10de`），不会依赖设备描述中的模糊文本。当前 Arch 已把 Mesa 的 VA-API 后端合并到 `mesa`，AMD 分支不再请求已经移除的 `mesa-vdpau` 等旧拆分包。

对于 NVIDIA Turing/RTX 20 系列及更新显卡，脚本使用 Arch 官方 `nvidia-open`。由于 NVIDIA 590+ 已停止支持 Pascal/Maxwell 及更旧架构，检测到此类显卡时脚本会避免自动装入不兼容内核模块，并要求人工安装 legacy AUR 驱动。

完成后重启：

```bash
reboot
```

登录后，`Super+T` 打开 Kitty，`Super+Space` 打开 DMS 启动器，`Super+,` 打开 DMS 设置。Waybar、SwayNC、Fuzzel 与 swaylock 不再作为活动桌面组件启动，避免与 DMS 的面板、通知、启动器和锁屏重复。

## 6. 可选应用

```bash
cd /opt/arch-niri-deploy
./install-apps.sh
```

输入一个或多个编号即可组合安装。LocalSend 来自 AUR，安装时会构建 `yay-bin`；其余分组尽量使用 Arch 官方仓库。游戏分组会自动启用 multilib。

## 7. 重复运行

- `install-niri.sh` 与 `install-apps.sh` 使用 `pacman --needed`，可以安全重跑。
- 三个安装器都会重新写入所选镜像配置；没有保存选择的旧系统会默认使用 USTC。
- 第一次部署桌面时，已有配置会保存为 `.bak.日期-时间`。
- 后续重跑只更新本项目管理的文件，不反复制造整目录备份。
- 后续重跑会拉取最新雾凇拼音文件；首次接管已有 Rime 配置时会先备份。
- `install-base.sh` 不是升级脚本，每次运行都会重新分区，绝不能对在用磁盘执行。
- 安装器启动时要求 `/mnt` 没有挂载且目录为空；不会擅自清理已有挂载或文件。
