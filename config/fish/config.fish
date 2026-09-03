if status is-interactive
    set -g fish_greeting ""
    set -gx TERMINAL foot
    fish_add_path $HOME/.local/bin

    if command -q nvim
        set -gx EDITOR nvim
        set -gx VISUAL nvim
    else if command -q vim
        set -gx EDITOR vim
        set -gx VISUAL vim
    end

    if command -q starship
        starship init fish | source
    end

    if command -q zoxide
        zoxide init fish --cmd cd | source
    end

    if command -q eza
        alias ls='eza --icons=auto'
        alias ll='eza -la --icons=auto'
        alias lt='eza --tree --icons=auto'
    end

    if command -q bat
        alias cat='bat --paging=never'
    end

    alias update-system='update-system.sh'
end
