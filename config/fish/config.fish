if status is-interactive
    set -g fish_greeting ""
    set -gx TERMINAL kitty
    fish_add_path ~/.local/bin

    # 使用与安装器一致的配置位置，避免旧 STARSHIP_CONFIG 指向其他主题。
    set -gx STARSHIP_CONFIG "$__fish_config_dir/../starship.toml"
    # 覆盖旧 universal 主题的命令、参数、错误和历史建议颜色。
    set -g fish_color_normal eedfe3
    set -g fish_color_command feb0d3
    set -g fish_color_param fdd9e7
    set -g fish_color_keyword f2bb99
    set -g fish_color_quote a6da95
    set -g fish_color_redirection f2bb99
    set -g fish_color_end e0bdcb
    set -g fish_color_error f38ba8
    set -g fish_color_comment 92838b
    set -g fish_color_autosuggestion 92838b
    set -g fish_color_operator f2bb99
    set -g fish_color_escape e0bdcb
    set -g fish_color_search_match --background=59404b
    set -g fish_color_selection --background=59404b
    set -g fish_pager_color_prefix feb0d3 --bold
    set -g fish_pager_color_completion eedfe3
    set -g fish_pager_color_description e0bdcb
    set -g fish_pager_color_progress f2bb99

    if command -q nvim
        set -gx EDITOR nvim
        set -gx VISUAL nvim
    else if command -q vim
        set -gx EDITOR vim
        set -gx VISUAL vim
    end

    if command -q starship
        starship init fish | source
    else
        printf '提示：缺少 starship，美化未加载；请运行项目的 scripts/update-terminal.sh。\n' >&2
    end

    if command -q zoxide
        zoxide init fish --cmd cd | source
    end

    # 与 SHORiN 的 Yazi 工作目录联动：退出文件管理器后，终端会进入最后所在目录。
    if command -q yazi
        function y
            set tmp (mktemp -t "yazi-cwd.XXXXXX")
            yazi $argv --cwd-file="$tmp"

            if read -z cwd < "$tmp"; and test -n "$cwd"; and test "$cwd" != "$PWD"
                builtin cd -- "$cwd"
            end

            rm -f -- "$tmp"
        end
    end

    if command -q bat
        function cat
            command bat --theme="base16" -- $argv
        end
    end

    if command -q eza
        function ls
            command eza --icons=auto -- $argv
        end

        function lt
            command eza --icons=auto --tree -- $argv
        end

        function la
            command eza -l --icons=auto -- $argv
        end

        # 保留项目原有的常用详细列表入口。
        function ll
            command eza -la --icons=auto -- $argv
        end
    end

    if command -q fastfetch
        abbr fa fastfetch
    end

    abbr reboot 'systemctl reboot'
    abbr update-system 'update-system.sh'
end
