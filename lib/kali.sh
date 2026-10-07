#!/usr/bin/env bash
kali_windows() { log 'Setting Kali BootNext to Windows, then clean reboot...'; remote_action KALI windows; }
kali_off() { log 'Requesting clean Kali shutdown...'; remote_action KALI off; }
