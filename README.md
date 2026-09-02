# Arch Niri Deploy

一套分层、可审计的 Arch Linux + Niri 部署项目。基础系统、桌面环境和可选应用彼此独立：

1. `install-base.sh`：仅从 Arch ISO 安装 UEFI/GPT + Btrfs 基础系统。
2. `install-niri.sh`：重启进入基础系统后安装 Niri 桌面。
3. `install-apps.sh`：按需安装日常、游戏、开发、虚拟化和创作软件。

设计借鉴了 SHORiN-KiWATA 的 Wayland/Niri 组件组合与配置拆分思路，但不包含个人主题、壁纸、专属仓库、AI 输入法或其他作者个人化软件。

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
└── docs/                     # 安装、Niri、快捷键、恢复文档
```

## 约束与兼容性

- 仅支持 x86_64、UEFI 启动的 Arch Linux。
- 基础安装默认使用整块磁盘：1 GiB ESP + 剩余空间 Btrfs。
- NVIDIA Turing 及更新架构使用官方 `nvidia-open`；Pascal/Maxwell 及更旧显卡不会自动安装 AUR 驱动，会明确提示人工处理。
- Niri 配置使用 `include`，要求 Arch 当前仓库中的现代 Niri 版本。
- 重复运行桌面/应用安装器是安全的；已存在的用户配置会先备份。

## 安全

基础安装器在分区前要求两次确认：先输入完整磁盘路径，再输入随机显示的确认码。日志默认保存到 `/tmp/arch-niri-deploy-*.log`，密码不会写入日志。

## 许可

MIT，见 [`LICENSE`](LICENSE)。
