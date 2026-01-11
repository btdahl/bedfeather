#!/bin/bash
# Copyright (c) 2025-2026 apario (www.apario.net)
# Copyright (c) 2025-2026 Bjorn T. Dahl (github.com/btdahl)

# Stop all running servers gracefully via FIFO, force stop if FIFO is missing

source "${BASH_SOURCE[0]%/*}/bfconfig.sh"

TARGET_SERVER=""

# Parse optional parameters
while [[ $# -gt 0 ]]; do
	case $1 in
		--server)
			TARGET_SERVER="$2"
			shift 2
			;;
		*)
			echl "Usage: $0 [--server <ip>]"
			exit 1
			;;
	esac
done

for server_path in "$SERVER_DIR"/*; do
	[[ ! -d "$server_path" ]] && continue

	server_ip_dir=$(basename "$server_path")

	# Validate IP format
	[[ ! "$server_ip_dir" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue
	[[ -n "$TARGET_SERVER" && "$server_ip_dir" != "$TARGET_SERVER" ]] && continue

	# Per-server constants
	CONTAINER_NAME="${DOCKER_PREFIX}${server_ip_dir//./_}"
	CMD_FIFO="$server_path/command_pipe"

	echo "Processing server $server_ip_dir"

	# Check if container is running
	is_running=0
	if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
		is_running=1
	fi

	if [[ $is_running -eq 1 && -p "$CMD_FIFO" ]]; then
		echo "Container is running and FIFO exists, attempting graceful shutdown."
		echo "Notifying players."
		fifo_write "$CMD_FIFO" "say Server is shutting down NOW."
		echo "Stopping server..."
		fifo_write "$CMD_FIFO" "stop"

		# Wait until container stops
		MAX_ATTEMPTS=30
		attempt=1
		while docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; do
			echl "Waiting for container $CONTAINER_NAME to stop... (attempt $attempt of $MAX_ATTEMPTS)"
			sleep 1
			((attempt++))
			if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
				echl "ERROR: container $CONTAINER_NAME did not stop after $MAX_ATTEMPTS attempts." error
				break
			fi
		done

	elif [[ $is_running -eq 1 ]]; then
		echl "FIFO missing for $server_ip_dir; attempting forceful docker stop."
		docker stop -t 5 "$CONTAINER_NAME" > /dev/null 2>&1

		# Wait until container stops
		MAX_ATTEMPTS=10
		attempt=1
		while docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; do
			echl "Waiting for container $CONTAINER_NAME to stop (force)... (attempt $attempt of $MAX_ATTEMPTS)"
			sleep 1
			((attempt++))
			if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
				echl "ERROR: forceful stop failed for container $CONTAINER_NAME. Manual intervention required." error
				break
			fi
		done
	else
		echl "Container not running, nothing to do."
	fi

	echo "Done processing server $server_ip_dir"

done

