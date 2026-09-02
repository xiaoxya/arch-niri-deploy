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
- 用户密码；
- 从自动扫描结果中按编号选择整块目标磁盘。

安装器固定使用中科大 USTC Arch Linux 镜像：

```text
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
```

该地址会同时写入安装介质当前环境和新系统；`reflector.timer` 会被屏蔽，防止它自动覆盖固定镜像。原镜像列表仅首次保存为 `/etc/pacman.d/mirrorlist.pre-ustc`。

三个安装器都会显示总体阶段、步骤数和百分比，例如：

```text
进度 [#########-------------------]  33% (3/8) 配置 USTC 镜像并刷新软件数据库
```

下载及软件包安装期间还会保留 Pacman 自带的单包进度，因此可以同时判断总体阶段和当前软件包状态。安装日志中也会记录这些阶段进度。

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

## 4. 基础系统内容

第一阶段只安装：Linux 内核、对应 CPU 微码、Btrfs、systemd-boot、NetworkManager、OpenSSH、sudo、reflector、Snapper 和基础维护工具。Reflector 仅作为手动维护工具保留，其定时服务不会启用。基础阶段不会安装显示服务、声卡服务或桌面环境。

安装结束后：

脚本会先执行 `sync`，递归卸载 `/mnt` 并确认没有残留挂载点。只有自动卸载成功后才会显示可以重启；如果有进程占用目标系统，安装器会列出残留挂载并以错误状态退出。

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
4. 安装 Niri、PipeWire、Portal、输入法、桌面组件与 greetd；
5. 备份已有用户配置并部署默认配置；
6. 校验 Niri KDL；
7. 创建安装后快照。

对于 NVIDIA Turing/RTX 20 系列及更新显卡，脚本使用 Arch 官方 `nvidia-open`。由于 NVIDIA 590+ 已停止支持 Pascal/Maxwell 及更旧架构，检测到此类显卡时脚本会避免自动装入不兼容内核模块，并要求人工安装 legacy AUR 驱动。

完成后重启：

```bash
reboot
```

## 6. 可选应用

```bash
cd /opt/arch-niri-deploy
./install-apps.sh
```

输入一个或多个编号即可组合安装。LocalSend 来自 AUR，安装时会构建 `yay-bin`；其余分组尽量使用 Arch 官方仓库。游戏分组会自动启用 multilib。

## 7. 重复运行

- `install-niri.sh` 与 `install-apps.sh` 使用 `pacman --needed`，可以安全重跑。
- 三个安装器都会重新写入固定的 USTC 镜像配置，避免被旧镜像列表影响。
- 第一次部署桌面时，已有配置会保存为 `.bak.日期-时间`。
- 后续重跑只更新本项目管理的文件，不反复制造整目录备份。
- `install-base.sh` 不是升级脚本，每次运行都会重新分区，绝不能对在用磁盘执行。
