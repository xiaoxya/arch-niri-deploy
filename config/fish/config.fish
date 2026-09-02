if status is-interactive
    set -gx EDITOR nvim
    set -gx VISUAL nvim
    fish_add_path $HOME/.local/bin

    if command -q starship
        starship init fish | source
    end

    alias ll='ls -alF'
    alias update-system='update-system.sh'
end
