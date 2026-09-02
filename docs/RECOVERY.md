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

基础安装器会重新创建所选磁盘的分区和文件系统，因此仍会要求两次磁盘清空确认。新版脚本会固定使用 USTC 镜像，并重新下载软件包；不要尝试在不完整的 `/mnt` 中继续执行后续 Niri 安装。

可先核对当前安装环境使用的源：

```bash
cat /etc/pacman.d/mirrorlist
```

应当包含：

```text
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
```

## Niri 或 greetd 失败

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

## 使用 Snapper 检查和回滚

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

整根回滚在 Btrfs 子卷布局下涉及改变默认/启动子卷，不同现场风险较高。本项目不提供盲目的一键回滚命令；建议从 Arch ISO 挂载后明确选择一个快照克隆为新的 `@`。

## 从 Arch ISO 修复基础系统

假设根分区是 `/dev/nvme0n1p2`，ESP 是 `/dev/nvme0n1p1`：

```bash
mount -o subvol=@ /dev/nvme0n1p2 /mnt
mount --mkdir -o subvol=@home /dev/nvme0n1p2 /mnt/home
mount --mkdir -o subvol=@log /dev/nvme0n1p2 /mnt/var/log
mount --mkdir -o subvol=@cache /dev/nvme0n1p2 /mnt/var/cache
mount --mkdir -o subvol=@snapshots /dev/nvme0n1p2 /mnt/.snapshots
mount --mkdir /dev/nvme0n1p1 /mnt/boot
arch-chroot /mnt
```

进入 chroot 后常用修复：

```bash
pacman -Syu linux linux-firmware
mkinitcpio -P
bootctl --esp-path=/boot install
systemctl enable NetworkManager
```

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
