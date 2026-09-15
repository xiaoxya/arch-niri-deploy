#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/packages.sh
source "$SCRIPT_DIR/lib/packages.sh"
# shellcheck source=lib/gpu.sh
source "$SCRIPT_DIR/lib/gpu.sh"
# shellcheck source=lib/btrfs.sh
source "$SCRIPT_DIR/lib/btrfs.sh"
# shellcheck source=lib/snapshot.sh
source "$SCRIPT_DIR/lib/snapshot.sh"
# shellcheck source=lib/terminal.sh
source "$SCRIPT_DIR/lib/terminal.sh"

deploy_user_configs() {
  local marker="$HOME/.config/.arch-niri-deploy"
  local stack_marker="$HOME/.config/.arch-niri-deploy-shorin-stack-v2"
  local dms_marker="$HOME/.config/.arch-niri-deploy-dms-v1"
  local item
  if [[ ! -e $marker ]]; then
    for item in waybar fuzzel swaync swaylock swayidle xdg-desktop-portal satty; do
      backup_path "$HOME/.config/$item"
    done
  fi
  if [[ ! -e $stack_marker ]]; then
    for item in kitty fish fontconfig fcitx5 starship.toml xdg-terminals.list; do
      backup_path "$HOME/.config/$item"
    done
    backup_path "$HOME/.local/share/fcitx5/rime"
  fi
  if [[ ! -e $dms_marker ]]; then
    backup_path "$HOME/.config/niri"
    backup_path "$HOME/.config/DankMaterialShell"
    backup_path "$HOME/.config/gtk-3.0"
    backup_path "$HOME/.config/gtk-4.0"
  fi

  install -d "$HOME/.config" "$HOME/.local/bin" "$HOME/Pictures/Screenshots"
  # Fish 与 Starship 由共享终端部署函数更新，升级时也会先备份。
  for item in niri kitty fontconfig fcitx5 xdg-desktop-portal satty; do
    copy_tree "$SCRIPT_DIR/config/$item" "$HOME/.config/$item"
  done
  if [[ ! -e $HOME/.config/kitty/dank-theme.conf ]]; then
    printf '%s\n' \
      'foreground #cdd6f4' 'background #1e1e2e' \
      'selection_foreground #cdd6f4' 'selection_background #585b70' \
      'cursor #f5e0dc' 'cursor_text_color #1e1e2e' \
      > "$HOME/.config/kitty/dank-theme.conf"
  fi
  if [[ ! -e $HOME/.config/kitty/dank-tabs.conf ]]; then
    printf '%s\n' \
      'tab_bar_edge top' 'tab_bar_style powerline' \
      'active_tab_foreground #1e1e2e' 'active_tab_background #89b4fa' \
      'inactive_tab_foreground #cdd6f4' 'inactive_tab_background #313244' \
      > "$HOME/.config/kitty/dank-tabs.conf"
  fi
  deploy_terminal_configs "$SCRIPT_DIR"
  install -m 0755 "$SCRIPT_DIR/scripts/"*.sh "$HOME/.local/bin/"
  if ! grep -Fxq 'kitty.desktop' "$HOME/.config/xdg-terminals.list" 2>/dev/null; then
    printf 'kitty.desktop\n' >> "$HOME/.config/xdg-terminals.list"
  fi
  printf 'managed-by=arch-niri-deploy\n' > "$marker"
  printf 'managed-by=arch-niri-deploy\n' > "$stack_marker"
  printf 'managed-by=arch-niri-deploy\n' > "$dms_marker"
}

configure_dms_theme_bridge() {
  local gtk_version gtk_dir gtk_css colors_css
  for gtk_version in 3.0 4.0; do
    gtk_dir="$HOME/.config/gtk-${gtk_version}"
    gtk_css="$gtk_dir/gtk.css"
    colors_css="$gtk_dir/dank-colors.css"
    install -d "$gtk_dir"
    touch "$gtk_css" "$colors_css"
    if ! grep -Fq '@import url("dank-colors.css");' "$gtk_css"; then
      printf '\n@import url("dank-colors.css");\n' >> "$gtk_css"
    fi
  done

  if command -v gsettings >/dev/null 2>&1; then
    if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
      gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
      gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark || true
      gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark || true
    elif command -v dbus-run-session >/dev/null 2>&1; then
      dbus-run-session sh -c \
        'gsettings set org.gnome.desktop.interface color-scheme prefer-dark; gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark; gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark' \
        || warn "暂时无法写入 GTK 外观设置，可登录 Niri 后在 DMS 设置中调整。"
    fi
  fi
}

install_rime_ice() {
  local rime_dir="$HOME/.local/share/fcitx5/rime"
  local temp_dir
  temp_dir=$(mktemp -d)

  if ! git clone --depth 1 https://github.com/iDvel/rime-ice.git "$temp_dir/rime-ice"; then
    rm -rf -- "$temp_dir"
    die "雾凇拼音下载失败，请检查 GitHub 网络连接后重新运行。"
  fi

  install -d -m 0755 "$rime_dir"
  cp -a -- "$temp_dir/rime-ice"/. "$rime_dir"/
  rm -rf -- "$rime_dir/.git" "$temp_dir"
  install -m 0644 "$SCRIPT_DIR/config/rime/default.custom.yaml" \
    "$rime_dir/default.custom.yaml"
}

configure_fonts() {
  local family resolved
  if sudo grep -q '^FONT=' /etc/vconsole.conf; then
    sudo sed -i 's/^FONT=.*/FONT=ter-v28n/' /etc/vconsole.conf
  else
    printf 'FONT=ter-v28n\n' | sudo tee -a /etc/vconsole.conf >/dev/null
  fi
  fc-cache -f
  for family in "Noto Sans CJK SC" "Noto Color Emoji" "FiraCode Nerd Font" \
    "Symbols Nerd Font" "Material Symbols Rounded"; do
    resolved=$(fc-match -f '%{family}' "$family")
    [[ $resolved == *"$family"* ]] \
      || die "字体安装不完整：请求 ${family}，实际匹配为 ${resolved:-无}。"
  done
  ok "中文、Emoji、Nerd Font 与图标字体检查通过。"
}

configure_dms() {
  local command_path dms_bin module unit_path
  local -a generated_modules=(colors layout alttab binds)
  local -a runtime_modules=(outputs cursor windowrules)
  command -v dms >/dev/null 2>&1 || die "dms 命令不存在，DMS 安装不完整。"
  dms_bin=$(command -v dms)
  install -d "$HOME/.config/niri/dms"

  # 使用独立子命令，避免完整的交互式 `dms setup` 覆盖项目维护的
  # config.kdl 与 kitty.conf。隔离 PATH 让 DMS 稳定识别 Niri + Kitty，
  # 即使机器还残留其他 compositor 或终端也不会弹出选择菜单。
  command_path=$(mktemp -d)
  ln -s "$(command -v niri)" "$command_path/niri"
  ln -s "$(command -v kitty)" "$command_path/kitty"
  ln -s "$(command -v sudo)" "$command_path/sudo"
  for module in "${generated_modules[@]}"; do
    if [[ ! -s $HOME/.config/niri/dms/${module}.kdl ]]; then
      if ! DMS_PRIVESC=sudo PATH="$command_path" "$dms_bin" setup "$module"; then
        rm -rf -- "$command_path"
        die "DMS 生成 ${module}.kdl 失败。"
      fi
    fi
  done
  rm -rf -- "$command_path"

  # DMS 1.5 的 Niri outputs/cursor/windowrules 模板有意为空，登录后由
  # DMS 设置界面写入。因此这里只要求文件存在，不能使用 -s 判定。
  for module in "${runtime_modules[@]}"; do
    [[ -e $HOME/.config/niri/dms/${module}.kdl ]] \
      || : > "$HOME/.config/niri/dms/${module}.kdl"
  done

  # Caps Lock OSD 使用 input 组；失败只影响该提示，不应阻断桌面安装。
  if getent group input >/dev/null 2>&1; then
    sudo usermod -aG input "$USER" \
      || warn "无法把 ${USER} 加入 input 组，DMS Caps Lock OSD 可能不可用。"
  fi

  # 先移除全局用户会话自启，再只绑定到 Niri，避免在其他桌面启动或出现双面板。
  systemctl --user disable --now dms.service >/dev/null 2>&1 || true
  if ! systemctl --user add-wants niri.service dms.service; then
    unit_path=/usr/lib/systemd/user/dms.service
    [[ -f $unit_path ]] || die "找不到 dms.service 用户服务。"
    install -d "$HOME/.config/systemd/user/niri.service.wants"
    ln -sfn "$unit_path" "$HOME/.config/systemd/user/niri.service.wants/dms.service"
  fi
  systemctl --user daemon-reload || warn "用户 systemd 暂不可用，DMS 会在下次登录时加载。"
  [[ -L $HOME/.config/systemd/user/niri.service.wants/dms.service ]] \
    || die "DMS 没有成功绑定到 niri.service。"
  dms doctor || warn "DMS doctor 报告了非致命警告，请查看上方详情。"
}

configure_dms_greeter() {
  aur_install "$DMS_GREETER_AUR_PACKAGE"
  command -v dms-greeter >/dev/null 2>&1 \
    || die "DMS Greeter 安装后未找到 dms-greeter 命令。"

  # AUR 包已通过系统用户规则创建 greeter 用户。enable 仅将 greetd 指向
  # dms-greeter --command niri；先完成切换，再移除旧的 tuigreet，安装中断
  # 时仍能保留原有登录器作为回退。
  if ! dms-greeter enable; then
    die "DMS Greeter 配置失败；tuigreet 尚未移除，请检查上方日志。"
  fi
  dms-greeter sync \
    || warn "DMS Greeter 主题同步失败；可登录后运行 dms-greeter sync 重试。"
  if pacman -Q greetd-tuigreet >/dev/null 2>&1; then
    sudo pacman -R --noconfirm greetd-tuigreet
  fi
  sudo systemctl enable greetd
  grep -Eq 'dms-greeter.*--command(=|[[:space:]]+)niri' /etc/greetd/config.toml \
    || die "greetd 配置未指向 Niri 的 DMS Greeter。"
  [[ -s /etc/greetd/niri/config.kdl ]] \
    || warn "DMS Greeter 的 Niri 配置尚未生成；请登录后运行 dms-greeter sync。"
}

configure_services() {
  sudo systemctl enable --now NetworkManager
  sudo systemctl enable --now bluetooth
  sudo systemctl enable --now power-profiles-daemon.service
  systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service || \
    warn "用户音频服务将在下次登录时由 systemd 启动。"
}

main() {
  init_log
  banner "Niri 桌面环境安装"
  require_non_root
  require_arch
  require_command sudo pacman lspci systemctl getent git
  check_network
  sudo -v
  verify_btrfs_layout /

  progress_init 15
  progress_step "创建 Niri 安装前快照"
  create_snapshot "Before Niri desktop installation"
  progress_step "沿用基础系统的软件镜像"
  configure_mirror_profile
  progress_step "更新 Arch Linux 系统"
  sudo pacman -Syu --noconfirm
  progress_step "识别并安装显卡驱动"
  install_gpu_drivers
  progress_step "安装 Niri 与 Wayland 桌面组件"
  pacman_install "${NIRI_PACKAGES[@]}"
  progress_step "安装 DankMaterialShell 与 Niri 集成"
  pacman_install "${DMS_PACKAGES[@]}"
  progress_step "安装完整中英文字体与图标字形"
  pacman_install "${SHORIN_FONT_PACKAGES[@]}"
  configure_fonts
  progress_step "安装 Fcitx5 输入法框架"
  pacman_install "${SHORIN_INPUT_PACKAGES[@]}"
  progress_step "安装 Fish、Kitty 与终端工具"
  pacman_install "${SHORIN_TERMINAL_PACKAGES[@]}"
  progress_step "部署 Niri 和桌面组件配置"
  deploy_user_configs
  configure_dms_theme_bridge
  progress_step "部署雾凇拼音词库"
  install_rime_ice
  progress_step "生成 DMS 模块并绑定 Niri 会话"
  configure_dms
  progress_step "配置 DMS Greeter、网络、蓝牙、电源与音频服务"
  configure_dms_greeter
  configure_services

  progress_step "设置 Fish 为当前用户默认 Shell"
  configure_default_shell
  verify_terminal_configs

  progress_step "校验 Niri 并创建安装后快照"
  if command -v niri >/dev/null 2>&1; then
    niri validate
  fi
  create_snapshot "After Niri desktop installation"
  progress_done "Niri 桌面环境安装完成"

  banner "Niri 安装完成"
  ok "DMS、Niri 与完整字体配置已部署到 $HOME/.config。"
  info "重启后进入 Niri；Super+T 打开 Kitty，Super+Space 打开 DMS 启动器，Super+, 打开 DMS 设置。"
  if (( GPU_NEEDS_LEGACY_NVIDIA )); then
    warn "在安装兼容的 NVIDIA legacy 驱动前，请勿进入 Niri。"
  fi
}

main "$@"
