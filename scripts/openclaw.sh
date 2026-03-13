#!/usr/bin/env bash

# todo: don't hardcode nixstore
ssh -t sauron -- sudo -u openclaw OPENCLAW_STATE_DIR=/var/lib/openclaw OPENCLAW_CONFIG_PATH=/var/lib/openclaw/openclaw.json /nix/store/ak1k17qabbg829zzfc1nikpg63fki6dr-openclaw-gateway-unstable-f7416da9/bin/openclaw $@
