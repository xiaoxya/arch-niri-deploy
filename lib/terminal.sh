#!/usr/bin/env bash
set -Eeuo pipefail

# 与完整安装器共用，已安装系统也可仅更新终端配置。
deploy_terminal_configs() {
  local project_dir=$1
  local config_root=${XDG_CONFIG_HOME:-$HOME/.config}
  local state_root=${XDG_STATE_HOME:-$HOME/.local/state}
  local terminal_backup_dir='' relative source_path target_path
  local -a files=(fish/config.fish starship.toml kitty/arch-niri-terminal.conf)
  require_command fish starship cmp cp install mktemp grep
  fish --no-config -n "$project_dir/config/fish/config.fish"

  # 相同内容不重复备份；每次发生更新时使用独立目录，防止同秒覆盖备份。
  for relative in "${files[@]}" kitty/kitty.conf; do
    source_path="$project_dir/config/$relative"
    target_path="$config_root/$relative"
    if [[ $relative == kitty/kitty.conf ]]; then
      if [[ -f $target_path ]] && grep -Fxq 'include arch-niri-terminal.conf' "$target_path"; then
        continue
      fi
    elif [[ -f $target_path ]] && cmp -s "$source_path" "$target_path"; then
      continue
    fi
    if [[ -e $target_path || -L $target_path ]]; then
      if [[ -z $terminal_backup_dir ]]; then
        install -d -m 0700 "$state_root/arch-niri-deploy/backups"
        terminal_backup_dir=$(mktemp -d "$state_root/arch-niri-deploy/backups/terminal.XXXXXXXX")
        info "终端原配置备份：$terminal_backup_dir"
      fi
      install -d "$terminal_backup_dir/$(dirname -- "$relative")"
      cp -a -- "$target_path" "$terminal_backup_dir/$relative"
    fi
    install -d "$config_root/$(dirname -- "$relative")"
    if [[ $relative == kitty/kitty.conf ]]; then
      printf '\ninclude arch-niri-terminal.conf\n' >> "$target_path"
    else
      install -m 0644 "$source_path" "$target_path"
    fi
  done
  ok "Fish 语法配色、Starship 分段提示符与 Kitty 字体已部署。"
}

configure_default_shell() {
  local account current_shell
  account=$(id -un)
  current_shell=$(getent passwd "$account" | cut -d: -f7)
  [[ -x /usr/bin/fish ]] || die '未找到 /usr/bin/fish。'
  if [[ $current_shell != /usr/bin/fish ]]; then
    sudo chsh -s /usr/bin/fish "$account"
  fi
}

verify_terminal_configs() {
  local config_root=${XDG_CONFIG_HOME:-$HOME/.config}
  local diagnostics rendered family resolved
  require_command fish starship fc-match mktemp
  fish --no-config -n "$config_root/fish/config.fish"

  for family in 'FiraCode Nerd Font Mono' 'Noto Sans CJK SC' 'Noto Color Emoji'; do
    resolved=$(fc-match -f '%{family}' "$family")
    [[ $resolved == *"$family"* ]] || die "终端字体缺失：$family（实际匹配 $resolved）。"
  done

  diagnostics=$(mktemp)
  # Starship 某些配置错误只写 stderr、仍返回 0，必须同时检查诊断输出。
  if ! rendered=$(TERM=xterm-256color COLORTERM=truecolor \
    STARSHIP_CONFIG="$config_root/starship.toml" STARSHIP_LOG=warn \
    starship prompt --status 0 2>"$diagnostics"); then
    cat "$diagnostics" >&2
    rm -f -- "$diagnostics"
    die 'Starship 提示符生成失败。'
  fi
  if [[ -s $diagnostics || $rendered != *''* || $rendered != *''* ]]; then
    cat "$diagnostics" >&2
    rm -f -- "$diagnostics"
    die 'Starship 主题没有正确加载，请检查上方诊断。'
  fi

  # 启动真实用户配置，检测 conf.d/旧插件等导致的初始化失败。
  if ! fish -ic 'functions fish_prompt | string match -q "*starship*"; or exit 1' \
    2>"$diagnostics"; then
    cat "$diagnostics" >&2
    rm -f -- "$diagnostics"
    die 'Fish 没有加载 Starship，请检查个人 conf.d 和 functions 中的旧主题。'
  fi
  if [[ -s $diagnostics ]]; then
    cat "$diagnostics" >&2
    warn 'Fish 启动时有额外诊断，请检查上方内容。'
  fi
  rm -f -- "$diagnostics"
  info "已检查配置：$config_root/starship.toml"
  printf '%s\n' "$rendered"
  ok '终端字体、Starship 主题渲染与 Fish 初始化检查通过。'
}
