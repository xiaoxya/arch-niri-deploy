# 恢复指南

## 先判断故障层级

1. 能否看到 systemd-boot 菜单？
2. 能否进入 TTY（`Ctrl+Alt+F2`）？
3. 网络是否可用？
4. 是系统无法启动，还是只有 greetd/Niri 失败？

如果仅桌面失败，通常不需要回滚整个系统。

## 基础安装在 pacstrap 阶段失败

如果日志以 `Failed to install packages to new root`、下载超时或 `Truncated tar archive` 结束，说明新系统尚未安装完整，不能从目标磁盘启动。保持在 Arch ISO 中，确认网络恢复后，从保存项目的目录重新运行：

```bash
sudo ./install-base.sh
```

基础安装器会重新创建所选磁盘的分区和文件系统，因此仍会要求两次磁盘清空确认。新版脚本会重新询问 USTC（默认）或清华 TUNA 镜像，并重新下载软件包；不要尝试在不完整的 `/mnt` 中继续执行后续 Niri 安装。

可先核对当前安装环境使用的源：

```bash
cat /etc/pacman.d/mirrorlist
```

应当包含所选的其中一个地址：

```text
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
# 或
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
```

## Niri 或 greetd 失败

如果显卡驱动阶段出现：

```text
error: target not found: mesa-vdpau
```

说明正在使用旧版 `lib/gpu.sh`。旧规则中的 `ATI` 会误匹配 `VGA compatible controller`，从而把 Intel 显卡错误识别为 AMD。更新项目后直接重新运行 `./install-niri.sh` 即可；此故障发生在桌面软件安装前，不需要回滚基础系统。

切换到 TTY 登录：

```bash
sudo systemctl status greetd
journalctl -b -u greetd
journalctl --user -b -u niri
niri validate --config ~/.config/niri/config.kdl
```

临时停用登录器并从 TTY 测试：

```bash
sudo systemctl disable --now greetd
niri-session
```

恢复安装器备份的配置：

```bash
ls -d ~/.config/niri.bak.*
mv ~/.config/niri ~/.config/niri.failed
cp -a ~/.config/niri.bak.时间戳 ~/.config/niri
```

确认恢复后再启用登录器：

```bash
sudo systemctl enable --now greetd
```

## DMS 没有面板、字体异常或出现双面板

先在 TTY 或 Kitty 中运行：

```bash
dms doctor
systemctl --user status dms
journalctl --user -b -u dms
fc-match "Noto Sans CJK SC"
fc-match "Noto Color Emoji"
fc-match "FiraCode Nerd Font"
niri validate --config ~/.config/niri/config.kdl
```

DMS 应当只通过 `niri.service.wants` 启动。检查绑定：

```bash
ls -l ~/.config/systemd/user/niri.service.wants/dms.service
```

`outputs.kdl` 在首次进入 Niri 前可以为空，这是 DMS 预留给显示器设置的运行时文件：

```bash
test -e ~/.config/niri/dms/outputs.kdl && echo "outputs.kdl 已就绪"
```

如果曾经手动全局启用 DMS，或者在 Niri 配置里同时写了 `spawn-at-startup "dms" "run"`，可能启动两个实例。可以重建为仅 Niri 会话启动：

```bash
systemctl --user disable --now dms.service
systemctl --user add-wants niri.service dms.service
systemctl --user daemon-reload
```

若同时看到旧 Waybar，先确认新版 `~/.config/niri/config.d/startup.kdl` 中已没有 `waybar`、`swaync` 或 `swaybg`，然后注销并重新登录。旧软件包留在系统中不会自行启动，不必急于卸载。

首次迁移前的配置保存在 `~/.config/niri.bak.*` 和 `~/.config/DankMaterialShell.bak.*`。DMS 的动态模块位于 `~/.config/niri/dms/`；不要在未备份时删除整个目录。

## 使用 Snapper 检查和回滚

基础安装器在 Arch ISO 的 chroot 环境中使用 `snapper --no-dbus` 创建初始快照，因为此时 `snapperd` 和系统 D-Bus 尚未运行。

查看快照：

```bash
sudo snapper -c root list
sudo snapper -c root status 快照号..0
sudo snapper -c root diff 快照号..0
```

本项目的 `@home` 独立挂载，因此根快照不会回滚个人文件，这是有意的安全设计。

若系统仍能启动，可针对文件恢复：

```bash
sudo cp -a /.snapshots/快照号/snapshot/etc/目标文件 /etc/目标文件
```

新安装的系统将 `@` 设为默认根子卷，fstab 和启动项均不固定根子卷。回滚工具显式使用 Snapper `classic`，但不会仅凭命令退出码或默认子卷变化就报告成功。先检查，再执行：

```bash
sudo bash /opt/arch-niri-deploy/scripts/rollback-snapshot.sh --check 8
sudo bash /opt/arch-niri-deploy/scripts/rollback-snapshot.sh 8
# 只有看到“回滚已校验”后，才执行：
sudo reboot
```

检查包括：当前根必须是默认的可写子卷；独立子卷必须正确挂载；来源必须是本文件系统的只读快照；当前与目标 fstab 必须兼容；实际默认启动项必须为本项目的 `arch.conf`；ESP 内核、目标内核及模块（含 DKMS）、initramfs 的内核版本必须一致。确认后会再次检查，并持有项目回滚锁和 Pacman 数据库锁。`--check`/`--dry-run` 不创建快照、不切换默认根，但会使用项目锁文件。

执行后校验新编号快照是指定来源的可写副本，且它的子卷 ID 正是默认 ID，同时重新核对内核及启动文件。如果命令或校验失败，会尝试恢复原默认 ID，保留已创建的快照供排查并返回非零状态。若提示无法恢复，请勿重启；按下面的 ISO 流程处理。不要与其他手工 Snapper/Btrfs 操作并行运行：项目锁无法约束外部命令。断电、强制杀进程及手工修改 ESP 不属于脚本可自动恢复的情况。

整根回滚只影响根子卷；`@home`、`@log`、`@cache` 和 `@snapshots` 不回滚。`/boot` 在 ESP（FAT）上，也不在根快照内。**在线工具会拒绝跨内核版本或模块不同的回滚**，不会冒险要求先重启后修复。需要恢复这类快照时，必须从 Arch ISO 选择目标、挂载新的可写根，然后在重启前重装内核并重建 initramfs。它不是“任意快照都能一键启动”的方案，也不是独立备份。

### 额外的 snapper-rollback 包

基础安装器可安装项目维护的 `snapper-rollback 1.0-3` 包。**这个版本的命令入口已统一调用上述安全检查 + Snapper classic，不再执行上游的“改名 @ 再创建 @”流程。** 来源仍固定并校验，上游原始代码仅作为非可执行参考文件保存在 `/usr/share/snapper-rollback/upstream/`。上游配置文件保留供参考，安全入口不读取其中的磁盘或子卷设置。

新版包使用自带的 `/usr/lib/snapper-rollback/` 文件，不依赖 `/opt` 项目路径。只支持 root 配置、一个正整数快照号，以及 `--help`、`--check`、`--dry-run`；其他上游选项明确报错。执行前必须输入 `ROLLBACK-快照号`，不再使用上游的 `CONFIRM`。

先检查（无需确认，不执行回滚）：

```bash
sudo snapper-rollback --dry-run 8
```

旧的 `1.0-2` 或 AUR 包没有这些保护。更新项目文件不会自动更新已经安装的包；完成包升级前请使用新版项目里的 `scripts/rollback-snapshot.sh`，不要使用旧的 `snapper-rollback`。包升级方法见 INSTALL.md。回滚到更旧快照也会恢复其中的旧脚本/旧包，下一次回滚前需要重新核对工具版本。

### 修复已安装的旧版本（classic 布局）

旧版本安装器会把 `@` 写死到根 fstab 和 systemd-boot 启动参数，因此会出现“默认子卷未知”的错误，也会阻止 Snapper 的回滚结果被启动。更新项目文件后，在已安装系统中运行：

```bash
sudo bash /opt/arch-niri-deploy/scripts/enable-snapper-rollback.sh
```

该工具需要确认，会备份原 fstab、启动项及默认 ID；发生失败时尝试恢复。若默认根已指向另一个子卷，会拒绝覆盖，避免取消等待重启的回滚。完成后重启并创建新的只读快照；旧只读快照中的 fstab 不会被篡改，因此可能仍需离线恢复。更新系统中缺少的检查依赖可运行 `sudo pacman -Syu --needed jq diffutils mkinitcpio`。不要通过重跑 install-base.sh 更新在用系统，它会重新清盘。

旧系统的配额组可以在更新项目后单独修复（不删除快照）：

```bash
sudo bash -c 'source /opt/arch-niri-deploy/lib/snapshot.sh; configure_snapper_quota'
sudo snapper -c root create --description 'After rollback layout migration' --cleanup-algorithm number
```

新版安装会验证配额组及初始只读快照，任一步骤失败都不报告基础安装成功。配额重扫描可能花费时间；数量和空间清理限制是清理策略，不保证磁盘永不写满，也不会清理独立的 @home。

## 从 Arch ISO 修复基础系统

假设根分区是 `/dev/nvme0n1p2`，ESP 是 `/dev/nvme0n1p1`：

```bash
mount -o subvolid=5 /dev/nvme0n1p2 /mnt
btrfs subvolume get-default /mnt
btrfs subvolume list /mnt
```

不要固定挂载 `@`：classic 回滚后，真实默认根可能是 `@snapshots/编号/snapshot`。从上面输出核对默认 ID（不能是顶层 ID 5），以下假设核对后的可写根 ID 是 **300**，请替换为实际数值：

```bash
mount --mkdir -o subvolid=300 /dev/nvme0n1p2 /mnt/root
btrfs property get -ts /mnt/root ro
# 必须为 ro=false，才能继续修复。不要把历史只读快照改成可写。
mount --mkdir -o subvol=/@snapshots /dev/nvme0n1p2 /mnt/root/.snapshots
mount --mkdir -o subvol=/@home /dev/nvme0n1p2 /mnt/root/home
mount --mkdir -o subvol=/@log /dev/nvme0n1p2 /mnt/root/var/log
mount --mkdir -o subvol=/@cache /dev/nvme0n1p2 /mnt/root/var/cache
mount --mkdir /dev/nvme0n1p1 /mnt/root/boot
arch-chroot /mnt/root
```

进入 chroot 后，若当前挂载的就是需要修复的目标可写根：

```bash
pacman -Syu linux linux-firmware
mkinitcpio -P
bootctl --esp-path=/boot install
systemctl enable NetworkManager
```

如果需要离线恢复另一个历史快照，先在挂载好的当前根 chroot 中查看 `snapper --no-dbus -c root list`，确认编号后执行 `snapper --no-dbus --ambit classic -c root rollback --print-number 编号`。它不会同步 ESP；此时**不要重启**。退出 chroot、`umount -R /mnt/root`，重新读取 `/mnt` 上的默认 ID，然后按上面的步骤挂载这个新 ID 及全部独立子卷，重新进入 chroot，执行内核重装和 initramfs 重建。

旧快照若含固定 `subvol`/`subvolid`，只修正新可写副本的 `/etc/fstab` 根行，使其使用默认子卷；核对 `/boot/loader/entries/arch.conf` 的 UUID 并移除固定子卷参数。完整系统升级会更新快照里的软件版本，这是此恢复方式的取舍。所有命令都成功、内核和 initramfs 文件完整后，才能卸载重启；如需保留旧包版本，需要自行准备匹配的软件包和离线恢复方案。

离开并卸载：

```bash
exit
umount -R /mnt
reboot
```

设备名必须以 `lsblk -f` 的实际结果为准，不要照抄示例。

## 网络和 SSH

```bash
sudo systemctl enable --now NetworkManager sshd
nmcli device status
ip address
```

## 包管理更新中断

不要删除 pacman 数据库或强行覆盖大量文件。先确认没有其他 pacman 进程；只有确定没有进程在运行时，才删除遗留锁：

```bash
pgrep -a pacman
sudo rm /var/lib/pacman/db.lck
sudo pacman -Syu
```

如果涉及 NVIDIA 大版本迁移，先阅读当日 Arch News，再决定驱动分支。
