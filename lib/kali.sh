#!/usr/bin/env bash
kali_windows() { log 'Setting Kali BootNext to Windows, then clean reboot...'; remote_action KALI windows; }
kali_off() { log 'Requesting clean Kali shutdown...'; remote_action KALI off; }
kali_bootnext() { log "Setting Kali BootNext to $1 without reboot..."; remote_action KALI "bootnext-${1,,}"; }
kali_reboot() { log "Setting Kali BootNext to $1, then clean reboot..."; remote_action KALI "reboot-${1,,}"; }
