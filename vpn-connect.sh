#!/bin/bash
# Launched in a terminal by the VPN Pineapple widget's Connect button.
# Same as the `vpn-up` alias. Eddie uses the login saved by --remember.
start=$SECONDS
# --elevation=sudo: Eddie's auto-detect parses `groups` output and can fall
# back to `su` (root password, which Omarchy doesn't use).
eddie-cli --mode.type=wireguard --elevation=sudo --connect
rc=$?
# A quick exit means it never stayed connected (no saved login, bad sudo,
# etc.), so keep the window open to read why. A normal disconnect from the
# widget closes the window on its own.
if (( SECONDS - start < 20 )); then
  echo
  echo "Eddie exited ($rc) without staying connected. Press Enter to close."
  read -r
fi
