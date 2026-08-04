#!/usr/bin/env bash
# Interactive translate loop for the Hyprland scratchpad terminal — see
# system-plan.md §5.11. Persistent (not one-shot): keeps reading lines
# until EOF or an explicit `.exit`, so translation history stays visible
# in the terminal's scrollback across multiple lookups in one session.
set -uo pipefail  # no -e: a single bad `trans` call shouldn't kill the loop

while IFS= read -r line; do
  [ "$line" = ".exit" ] && break
  [ -z "$line" ] && continue

  # Cyrillic present -> assume Russian input, translate to English;
  # otherwise assume English input, translate to Russian. Matches
  # system-plan.md §5.11's stated direction-detection rule.
  if [[ "$line" =~ [а-яА-ЯёЁ] ]]; then
    target=en
  else
    target=ru
  fi

  translation="$(trans -brief ":$target" "$line")"
  echo "$translation"
  printf '%s' "$translation" | wl-copy
done
