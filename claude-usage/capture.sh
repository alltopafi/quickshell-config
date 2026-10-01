#!/bin/sh
# Claude Code status line command. Receives session JSON on stdin; saves the
# plan rate-limit windows for the bar's usage popup and prints a short status.
out="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/claude-usage.json"
input=$(cat)

rl=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
if [ -n "$rl" ]; then
  mkdir -p "$(dirname "$out")"
  tmp="$out.$$"
  printf '%s' "$rl" | jq -c --argjson now "$(date +%s)" '{updated: $now, rate_limits: .}' > "$tmp" \
    && mv "$tmp" "$out" || rm -f "$tmp"
fi

printf '%s' "$input" | jq -r '[
  (.model.display_name // empty),
  (.rate_limits.five_hour.used_percentage // empty | "5h \(floor)%"),
  (.rate_limits.seven_day.used_percentage // empty | "7d \(floor)%")
] | join(" · ")' 2>/dev/null
