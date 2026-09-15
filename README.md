# Arch Niri Deploy

一套分层、可审计的 Arch Linux + Niri 部署项目。基础系统、桌面环境和可选应用彼此独立：

1. `install-base.sh`：从 Arch ISO 安装 UEFI/GPT + Btrfs 基础系统，支持 DHCP/有线固定 IPv4，可选安装 `snapper-rollback`。
2. `install-niri.sh`：重启进入基础系统后安装 Niri 桌面。
3. `install-apps.sh`：按需安装日常、游戏、开发、虚拟化和创作软件。

设计借鉴了 SHORiN-KiWATA 的 DMS/Niri 组件组合与配置拆分思路，使用 Arch 官方 `dms-shell-niri` 与 DMS Greeter（AUR 二进制包）、完整中英文字体、Fcitx5 + 雾凇拼音、Fish + Starship/Zoxide 和 Kitty。命令提示符采用 SHORiN 风格的粉色 Powerline 分段；不包含个人壁纸、专属仓库、AI 输入法或其他作者个人化软件。

已安装桌面但终端美化不完整时，在新版项目目录以普通用户运行 `bash scripts/update-terminal.sh`，可单独备份和更新 Fish/Starship/Kitty 配置。详见 [终端美化与更新](docs/NIRI.md#命令行美化与已安装系统更新)。

## 快速开始

> `install-base.sh` 会清空所选磁盘。请先备份数据，并仔细核对磁盘型号与容量。

```bash
# 在 Arch ISO 中
chmod +x install-*.sh scripts/*.sh
sudo ./install-base.sh

# 重启并登录基础系统后
./install-niri.sh

# 可选应用
./install-apps.sh
```

完整步骤见 [`docs/INSTALL.md`](docs/INSTALL.md)，快捷键见 [`docs/KEYBINDS.md`](docs/KEYBINDS.md)，恢复指南见 [`docs/RECOVERY.md`](docs/RECOVERY.md)。

## 目录

```text
.
├── install-base.sh           # Arch ISO 基础安装器（破坏性磁盘操作）
├── install-niri.sh           # Niri 桌面安装器
├── install-apps.sh           # 可选应用安装器
├── lib/                      # UI、磁盘、Btrfs、GPU、包管理、快照库
├── config/                   # Niri 及桌面组件的默认配置
├── scripts/                  # 用户侧日常工具
├── packaging/                # 固定版本第三方软件的本地构建配方
├── tests/                    # 网络参数与配置生成检查
└── docs/                     # 安装、Niri、快捷键、恢复文档
```

## 约束与兼容性

- 仅支持 x86_64、UEFI 启动的 Arch Linux。
- 基础安装默认使用整块磁盘：1 GiB ESP + 剩余空间 Btrfs。
- NVIDIA Turing 及更新架构使用官方 `nvidia-open`；Pascal/Maxwell 及更旧显卡不会自动安装 AUR 驱动，会明确提示人工处理。
- Niri 配置使用 `include`，要求 Arch 当前仓库中的现代 Niri 版本。
- 重复运行桌面/应用安装器是安全的；已存在的用户配置会先备份。

## 安全

基础安装器会排除当前 Arch 安装介质，并拒绝只读、容量不足、仍在挂载或含活动交换分区的目标盘。分区前先显示完整配置摘要，再要求两次确认：输入完整磁盘路径和随机确认码。日志默认保存到 `/tmp/arch-niri-deploy-*.log`，安装完成后复制到新系统的 `/var/log/arch-niri-deploy/base-install.log`；密码不会写入日志。

## 许可

本项目代码使用 MIT，见 [`LICENSE`](LICENSE)。安装器下载的第三方软件保留其各自许可；`snapper-rollback` 包保留上游 GPLv3 源码许可和项目安全封装的 MIT 许可。

## 回滚安全范围

项目回滚脚本及 `snapper-rollback 1.0-3` 安全入口统一使用 Snapper classic。提供 `--check`，检查默认根、fstab、实际启动项、内核及模块；失败时尝试恢复原默认根。ESP 不在根快照内，因此会拒绝在线跨内核回滚。初始快照或配额初始化失败会中止基础安装。

详见 [恢复指南](docs/RECOVERY.md) 与 [测试和虚拟机验收](docs/TESTING.md)。本地模拟检查不代表已经完成真实机器重启验收，不承诺任意快照都能无条件恢复。
