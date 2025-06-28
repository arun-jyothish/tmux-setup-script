#!/bin/bash

# ---------------------------------------------
# Embedded Engineering TMUX Session Launcher
# ---------------------------------------------

# === Configuration ===

PROJECT="$HOME/projects/firmware"
TOOLS="$PROJECT/tools"
NOTES="$HOME/notes"
DEVICE_1="/dev/ttyUSB0"
DEVICE_2="/dev/ttyUSB1"
BAUD_1="115200"
BAUD_2="115200"

# Default working directories for each session
declare -A SESSION_DIRS=(
  [dev]="$PROJECT"
  [serial]="$HOME"
  [server]="$PROJECT"
  [monitor]="$HOME"
  [logs]="$PROJECT/logs"
  [notes]="$NOTES"
)

# === Logger ===

log() {
  echo "[tmux] $1"
}

# === TMUX Utility Functions ===

# Check if a session exists
session_exists() {
  tmux has-session -t "$1" 2>/dev/null
}

# Check if a window exists in a session by name
window_exists() {
  local session="$1"
  local window="$2"
  tmux list-windows -t "$session" -F '#W' 2>/dev/null | grep -Fxq "$window"
}

# Create session only once with initial window
create_session_once() {
  local session=$1
  local window=$2
  local dir=$3
  local cmd=$4

  if ! session_exists "$session"; then
    log "Creating session: $session with window: $window"
    tmux new-session -d -s "$session" -n "$window" -c "$dir"
    [ -n "$cmd" ] && tmux send-keys -t "$session:$window" "$cmd" C-m
  fi
}

# Create a window only if it doesn't already exist
create_window_safe() {
  local session="$1"
  local window="$2"
  local dir="$3"
  local cmd="$4"

  if ! window_exists "$session" "$window"; then
    log "Creating window: $session:$window"
    tmux new-window -t "$session" -n "$window" -c "$dir"
    [ -n "$cmd" ] && tmux send-keys -t "$session:$window" "$cmd" C-m
  fi
}

# Split and run a command only if the pane doesn’t exist
split_cmd_safe() {
  local target="$1"
  local dir="$2"
  local direction="$3"  # 'v' for vertical, 'h' for horizontal
  local cmd="$4"

  tmux select-window -t "$target"
  if [ "$(tmux list-panes -t "$target" | wc -l)" -gt 1 ]; then
    log "Skipping split for $target: already has multiple panes"
    return
  fi

  if [ "$direction" = "v" ]; then
    tmux split-window -v -t "$target" -c "$dir"
  else
    tmux split-window -h -t "$target" -c "$dir"
  fi
  tmux send-keys -t "$target.1" "$cmd" C-m
}

# === Session Definitions ===

declare -A dev=(
  [editor]="$PROJECT:nvim ."
  [build]="$PROJECT:make -j\$(nproc)"
  [flash]="$TOOLS:./flash.sh"
  [tests]="$PROJECT/tests:./run_tests.sh"
)

declare -A serial=(
  [minicom-1]="~:minicom -D $DEVICE_1 -b $BAUD_1"
  [minicom-2]="~:minicom -D $DEVICE_2 -b $BAUD_2"
)

declare -A server=(
  [ssh-dev]="~:ssh user@192.168.1.100"
  [ssh-prod]="~:ssh user@192.168.1.200"
  [scp-push]="$PROJECT:scp bin/firmware.bin user@192.168.1.100:/opt/firmware/"
)

declare -A logs=(
  [runtime]="$PROJECT/logs:tail -f app.log"
  [dmesg]="~:dmesg -w"
  [journal]="~:journalctl -f"
)

declare -A notes=(
  [scratch]="$NOTES:nvim scratch.md"
  [wiki]="$NOTES/wiki:nvim index.md"
  [journal]="$NOTES:nvim \$(date +%F).md"
)

# === Generic Session Setup ===

setup_session() {
  local session="$1"
  declare -n windows="$2"

  local created=0
  for window in "${!windows[@]}"; do
    IFS=":" read -r dir cmd <<< "${windows[$window]}"
    if [ $created -eq 0 ]; then
      create_session_once "$session" "$window" "$dir" "$cmd"
      created=1
    else
      create_window_safe "$session" "$window" "$dir" "$cmd"
    fi
  done
}

# === Custom Session: Monitor with Splits ===

setup_monitor() {
  create_session_once "monitor" "sys" "~" "htop"
  split_cmd_safe "monitor:sys" "~" h "watch -n1 sensors"
  split_cmd_safe "monitor:sys.1" "~" v "dmesg -w"
}

# === Main Launcher ===

main() {
  setup_session dev dev
  setup_session serial serial
  setup_session server server
  setup_session logs logs
  setup_session notes notes
  setup_monitor

  log "All sessions created. Attaching to 'dev'."
  tmux attach -t dev
}

main

