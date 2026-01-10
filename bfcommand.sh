#!/bin/bash
# Copyright (c) 2025-2026 apario (www.apario.net)
# Copyright (c) 2025-2026 Bjorn T. Dahl (github.com/btdahl)

# Send command to server console of all or targeted servers

source /opt/bedfeather/bfconfig.sh

COMMAND_TEXT=""
TARGET_SERVER=""

while [[ $# -gt 0 ]]; do
	case $1 in
		--server)
			TARGET_SERVER="$2"
			shift 2
			;;
		--command)
			COMMAND_TEXT="$2"
			shift 2
			;;
		*)
			echl "Usage: $0 --command '<command>' [--server <ip>]"
			exit 1
			;;
	esac
done

[[ -z "$COMMAND_TEXT" ]] && { echl "Error: --command is required" error; exit 1; }

for server_path in "$SERVER_DIR"/*; do
	[[ ! -d "$server_path" ]] && continue

	server_ip_dir=$(basename "$server_path")

	# Validate IP format
	[[ ! "$server_ip_dir" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue
	[[ -n "$TARGET_SERVER" && "$server_ip_dir" != "$TARGET_SERVER" ]] && continue

	# Per-server constants
	CONTAINER_NAME="${DOCKER_PREFIX}${server_ip_dir//./_}" # replace dots with underscores
	CMD_FIFO="$server_path/command_pipe"
	SERVER_IP="$server_ip_dir"

	if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
		echl "skipping $SERVER_IP (container not running)" warn
		continue
	fi

	if [[ ! -p "$CMD_FIFO" ]]; then
		echl "skipping $SERVER_IP (no command pipe)" warn
		continue
	fi

	echo "sending \"$COMMAND_TEXT\" to $SERVER_IP"
	fifo_write "$CMD_FIFO" "$COMMAND_TEXT"
done

