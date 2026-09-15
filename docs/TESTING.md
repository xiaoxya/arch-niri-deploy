# 回滚验证说明

## 本地非破坏性检查

```bash
bash tests/network.sh
bash tests/rollback.sh
bash tests/package-checks.sh  # 可选参数：已经下载的上游源码 tar.gz
shellcheck -x -P SCRIPTDIR lib/rollback.sh lib/snapshot.sh scripts/rollback-snapshot.sh \
  scripts/enable-snapper-rollback.sh lib/rollback-package.sh install-base.sh tests/rollback.sh
```

回滚测试使用文本夹具和模拟命令，不会格式化、挂载、切换子卷或执行真实回滚。覆盖固定根参数、错误 UUID、重复根挂载项、内核和 DKMS 不匹配、initramfs 错误、错误默认 ID、来源 UUID 不匹配、只读目标、缺失配额组、创建快照失败和失败后的补偿退出码。

## 必须在可丢弃的 UEFI 虚拟机完成的验收

本地 Windows 检查不能替代以下真实 Arch/Btrfs 测试；未完成前不能称为完全验证。

1. 用空白虚拟磁盘安装基础系统，确认 5 个子卷、默认根、ESP、配额组、初始只读快照和两个 Snapper 定时器均通过检查。
2. 重启后创建快照，修改根目录内一个测试文件；先运行 `rollback-snapshot.sh --check 编号`，再确认实际回滚。重启后用 `findmnt -no FSROOT /` 与 `btrfs subvolume get-default /` 核对，新根必须是 Snapper 编号可写副本；测试文件应恢复，/home 测试文件应保留。
3. 从已经回滚过的根再创建只读快照并重复回滚；确认不是误切回旧的顶层 @。
4. 回滚已设置但未重启时，第二次调用必须拒绝执行。软件包管理器持锁时也必须拒绝，且不得删除外部创建的锁。
5. 对比跨内核升级前的快照，检查模式应拒绝；从 ISO 挂载真实默认根并重建匹配的内核/initramfs 后验证恢复过程。
6. 构建并安装 `snapper-rollback 1.0-3`，确认命令入口与项目脚本一致，旧上游配置不会选择其他磁盘，未知参数返回非零。
7. 在可恢复的虚拟机快照中模拟磁盘空间不足和回滚后检查失败；确认没有成功提示，默认 ID 恢复或明确报告严重恢复失败。断电不依赖 shell 退出钩子恢复。
8. 从固定 subvol 的旧系统执行迁移；确认备份存在，新快照可用、旧快照被拒绝；有等待重启的默认根时迁移必须停止。

回滚日志保存在 `/var/log/arch-niri-deploy/rollback-*.log`。任何失败都应保留日志和虚拟机状态，先分析再重试，不应靠清盘掩盖问题。

## 实现参考

- [Snapper classic 实现](https://github.com/openSUSE/snapper/blob/master/client/snapper/cmd-rollback.cc)：新建可写快照、设置默认子卷以及打印新编号。
- [Snapper 配额初始化](https://github.com/openSUSE/snapper/blob/master/snapper/Snapper.cc)：setupQuota 创建真实配额组，不能只填写 QGROUP。
- [mkinitcpio 镜像检查工具](https://github.com/archlinux/mkinitcpio/blob/master/lsinitcpio)：检查 initramfs 中的模块版本。
- [systemd 启动项解析](https://github.com/systemd/systemd/blob/main/src/shared/bootspec.c)：JSON 默认启动项包含 EFI 默认/一次性选择的影响。
