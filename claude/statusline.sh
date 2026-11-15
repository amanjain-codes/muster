#!/bin/bash
# Claude Code status line: model, folder, git branch, context meter, session cost.
input=$(cat)
model=$(echo "$input" | jq -r '.model.display_name // "claude"')
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0 | floor')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
branch=$(git -C "$dir" branch --show-current 2>/dev/null)

# Share this session's exact context % with the dash pane.
sid=$(echo "$input" | jq -r '.session_id // empty')
if [ -n "$sid" ]; then
  mkdir -p "$HOME/.cache/muster/ctx"
  printf '{"pct":%s,"model":"%s","ts":%s}\n' "$pct" "$model" "$(date +%s)" > "$HOME/.cache/muster/ctx/$sid.json"
fi

# Green under 50%, yellow under 80%, red above: warns before context gets expensive.
if [ "$pct" -lt 50 ]; then c="\033[32m"; elif [ "$pct" -lt 80 ]; then c="\033[33m"; else c="\033[31m"; fi
filled=$((pct / 10)); bar=""
for i in 1 2 3 4 5 6 7 8 9 10; do [ "$i" -le "$filled" ] && bar+="▰" || bar+="▱"; done

out="\033[36m${model}\033[0m  \033[33m${dir##*/}\033[0m"
[ -n "$branch" ] && out="$out  \033[32m ${branch}\033[0m"
out="$out  ${c}${bar} ${pct}%\033[0m  \033[35m\$$(printf '%.2f' "$cost")\033[0m"
# dash: show the next meeting (from dash's last Calendar fetch) from 30 min before until 5 min after it starts.
comms="$HOME/.cache/muster/comms.json"
mt=$(stat -f %m "$comms" 2>/dev/null || echo 0)

# dash: refresh Calendar/Jira in the background at most every 30 min while any session is active.
# fetch.py locks itself, read-only tools, about $0.01 a run.
kick="$HOME/.cache/muster/fetch.kick"
now=$(date +%s); kt=$(stat -f %m "$kick" 2>/dev/null || echo 0)
if [ $((now - mt)) -gt 1800 ] && [ $((now - kt)) -gt 300 ]; then
  touch "$kick"
  (nohup python3 "@MUSTER_DIR@/fetch.py" >/dev/null 2>&1 &)
fi
if [ -f "$comms" ] && [ "$(date -r "$mt" +%F)" = "$(date +%F)" ]; then
  now_m=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
  meet=$(jq -r '.today[]? | "\(.start)\t\(.title | tostring | gsub("[[:cntrl:]\\\\%]"; ""))"' "$comms" 2>/dev/null | while IFS=$'\t' read -r s t; do
    [[ "$s" =~ ^[0-9]{1,2}:[0-9]{2}$ ]] || continue
    d=$(( 10#${s%%:*} * 60 + 10#${s##*:} - now_m ))
    if [ "$d" -ge -5 ] && [ "$d" -le 30 ]; then
      if [ "$d" -le 0 ]; then echo "⏰ ${t:0:22} now"; else echo "⏰ ${t:0:22} in ${d}m"; fi
      break
    fi
  done)
  [ -n "$meet" ] && out="$out  \033[1;33m${meet}\033[0m"
fi

# Key hints styled as buttons for the herdr dash plugin: left Option+d / Option+e.
out="$out  \033[30;46m ⌥d dash \033[0m \033[30;46m ⌥e ide \033[0m \033[30;46m ⌥n fresh \033[0m"
printf "%b" "$out"
