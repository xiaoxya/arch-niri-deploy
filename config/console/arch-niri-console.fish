# Fish does not source /etc/profile.d. Restrict this override to kernel VTs.
if test "$TERM" = linux
    if not set -q SSH_CONNECTION; and not set -q SSH_TTY; and not set -q DISPLAY; and not set -q WAYLAND_DISPLAY
        set -gx LANG en_US.UTF-8
        set -gx LANGUAGE en_US:en
        set -gx LC_ALL en_US.UTF-8
    end
end
