#!/usr/bin/env bash
linux_windows() { log "Setting $LINUX_STATE BootNext to Windows, then clean reboot..."; remote_action "$LINUX_STATE" windows; }
linux_off() { log "Requesting clean $LINUX_STATE shutdown..."; remote_action "$LINUX_STATE" off; }
linux_bootnext() { log "Setting $LINUX_STATE BootNext to $1 without reboot..."; remote_action "$LINUX_STATE" "bootnext-${1,,}"; }
linux_reboot() { log "Setting $LINUX_STATE BootNext to $1, then clean reboot..."; remote_action "$LINUX_STATE" "reboot-${1,,}"; }
