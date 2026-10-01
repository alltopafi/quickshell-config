#!/bin/sh
# usage: set-wallpaper.sh <image>   apply with a transition and remember it
#        set-wallpaper.sh --restore re-apply the remembered one (no transition)
conf="$HOME/.config/quickshell/wallpaper.conf"

fail() {
  echo "$1" >&2
  [ "$MODE" = "restore" ] || notify-send -u critical "Wallpaper not applied" "$1" 2>/dev/null
  exit 1
}

MODE=apply
if [ "$1" = "--restore" ]; then
  MODE=restore
  [ -f "$conf" ] || exit 0
  img=$(cat "$conf")
  transition="--transition-type none"
else
  img=$1
  transition="--transition-type grow --transition-pos center --transition-duration 1"
fi

[ -f "$img" ] || fail "No such image: $img"
command -v awww >/dev/null || fail "awww is not installed (sudo pacman -S awww)"

if ! awww query >/dev/null 2>&1; then
  setsid awww-daemon >/dev/null 2>&1 &
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    awww query >/dev/null 2>&1 && break
    sleep 0.2
  done
fi

# shellcheck disable=SC2086
awww img "$img" $transition || fail "awww failed to apply $img"
[ "$1" = "--restore" ] || printf '%s' "$img" > "$conf"
