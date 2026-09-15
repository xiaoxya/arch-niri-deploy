# shellcheck shell=sh
# Sourced by POSIX login shells; never change graphical or SSH sessions.
case ${TERM-} in
  linux)
    if [ -z "${SSH_CONNECTION-}${SSH_TTY-}${DISPLAY-}${WAYLAND_DISPLAY-}" ]; then
      export LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8
    fi
    ;;
esac
