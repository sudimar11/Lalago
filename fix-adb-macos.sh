#!/bin/bash
# Fix ADB daemon crash on macOS 26 (OSP_CHECK netmask bug)
# Solution: disable mDNS with ADB_MDNS=0

echo "Fix applied: ADB_MDNS=0 added to ~/.zshrc"
echo ""
echo "For current session, run:"
echo "  export ADB_MDNS=0"
echo "  adb kill-server && adb start-server"
