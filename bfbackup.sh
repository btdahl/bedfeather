#!/bin/bash
# Copyright (c) 2025-2026 apario (www.apario.net)
# Copyright (c) 2025-2026 Bjorn T. Dahl (github.com/btdahl)

# Backup config files and world data from all or targeted servers

source "${BASH_SOURCE[0]%/*}/bfconfig.sh"

TARGET_SERVER=""
NOTE_TEXT=""
TIMESTAMP=$(date +"%Y-%m-%d_%H:%M:%S")

# Parse optional parameters
while [[ $# -gt 0 ]]; do
	case $1 in
		--server)
			TARGET_SERVER="$2"
			shift 2
			;;
		--note)
			NOTE_TEXT="$2"
			shift 2
			;;
		--prune-old)
			PRUNE_OLD_COUNT="$2"
			if ! [[ "$PRUNE_OLD_COUNT" =~ ^[1-9][0-9]*$ ]]; then
				echl "ERROR: --prune-old requires a positive integer." error
				exit 1
			fi
			shift 2
			;;

		*)
			echl "Usage: $0 [--server <ip>] [--note \"text\"] [--prune-old N]"
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
	CONTAINER_NAME="${DOCKER_PREFIX}${server_ip_dir//./_}" # replace dots with underscores
	CMD_FIFO="$server_path/command_pipe"
	WORLDS="$server_path/worlds"
	BACKUP_TARGET="$BACKUP_DIR/$server_ip_dir/$TIMESTAMP"

	echo "Processing server $server_ip_dir"

	# Check if container is running
	is_running=0
	if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
		is_running=1
	fi

	if [[ $is_running -eq 1 && -p "$CMD_FIFO" ]]; then
		echo "Container is running and FIFO exists, attempting graceful shutdown."
		echo "Notifying players."
		fifo_write "$CMD_FIFO" "say Server is shutting down for backup in 10 seconds"
		sleep 10
		echo "Stopping server."
		fifo_write "$CMD_FIFO" "stop"

		# Wait until container stops
		MAX_ATTEMPTS=30
		attempt=1
		while docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; do
			echl "Waiting for container $CONTAINER_NAME to stop. (attempt $attempt of $MAX_ATTEMPTS)"
			sleep 1
			((attempt++))
			if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
				echl "ERROR: container $CONTAINER_NAME did not stop after $MAX_ATTEMPTS attempts. Exiting." error
				exit 1
			fi
		done

	elif [[ $is_running -eq 1 ]]; then
		echl "Command pipe missing for $server_ip_dir; container running but cannot send stop. User intervention required. Exiting." error
		exit 1
	else
		echl "Container not running, will just backup worlds."
	fi

	# Remove old backups if requested
	if [[ -n "$PRUNE_OLD_COUNT" ]]; then
		shopt -s nullglob
		existing_backups=( "$BACKUP_DIR/$server_ip_dir"/*/ )
		shopt -u nullglob

		IFS=$'\n' existing_backups=( $(printf "%s\n" "${existing_backups[@]}" | sort) )
		unset IFS

		num_existing_backups=${#existing_backups[@]}
		num_to_delete=$(( num_existing_backups - PRUNE_OLD_COUNT + 1))

		if (( num_to_delete > 0 )); then
			echl "Pruning $num_to_delete old backup(s) for $server_ip_dir."
			for ((i=0; i<num_to_delete; i++)); do
				rm -rf -- "${existing_backups[i]}"
				echl "Deleted ${existing_backups[i]}"
			done
		fi
	fi

	# Backup worlds
	echo "Backing up worlds."
	mkdir -p "$BACKUP_TARGET/worlds"
	cp -a "$WORLDS/." "$BACKUP_TARGET/worlds/"

	# Backup config files
	for cfg in "${CONFIG_FILES[@]}"; do
		[[ -f "$server_path/$cfg" ]] && mkdir -p "$BACKUP_TARGET/config" && cp -a "$server_path/$cfg" "$BACKUP_TARGET/config/"
	done

	# Add note if provided
	[[ -n "$NOTE_TEXT" ]] && echo "$NOTE_TEXT" > "$BACKUP_TARGET/note.txt"

	# Recreate FIFO if needed before restart, then restart server
	# FIFO recreation is kept for defensive reasons
	# FIFO is created with 0666 because run_server.sh inside the container have to open it read/write
	if [[ $is_running -eq 1 ]]; then
		[[ -e "$CMD_FIFO" && ! -p "$CMD_FIFO" ]] && rm -f "$CMD_FIFO"
		[[ -p "$CMD_FIFO" ]] || mkfifo "$CMD_FIFO"
		chmod 0666 "$CMD_FIFO"

		echo "Restarting server."
		docker start "$CONTAINER_NAME" > /dev/null
	fi

	echo "Done backing up $server_ip_dir."
done

