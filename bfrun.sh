#!/bin/bash
# Copyright (c) 2025-2026 apario (www.apario.net)
# Copyright (c) 2025-2026 Bjorn T. Dahl (github.com/btdahl)

# Build and run docker environment, images and containers for all or targeted servers
# Rebuilds and restarts containers if changes detected, image missing, or --force-rebuild

source "${BASH_SOURCE[0]%/*}/bfconfig.sh"

SKEL_DIR="$BASE_DIR/skel/server"

# Default values
FORCE_REBUILD=0
TARGET_SERVER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		--force-rebuild)
			FORCE_REBUILD=1
			shift
			;;
		--server)
			TARGET_SERVER="$2"
			shift 2
			;;
		*)
			echo "Usage: $0 [--force-rebuild] [--server <server_ip>]"
			exit 1
			;;
	esac
done

# Create macvlan network if missing
if ! docker network ls --format '{{.Name}}' | grep -qx "$MACVLAN_NETWORK"; then
	echo "Creating macvlan network $MACVLAN_NETWORK..."
	docker network create -d macvlan \
		--subnet="$SUBNET" \
		--gateway="$GATEWAY" \
		-o parent="$NETWORK_IF" \
		"$MACVLAN_NETWORK"
fi

# Loop through all server directories
for server_path in "$SERVER_DIR"/*; do
	[[ ! -d "$server_path" ]] && continue

	server_ip_dir=$(basename "$server_path")
	[[ -n "$TARGET_SERVER" && "$server_ip_dir" != "$TARGET_SERVER" ]] && continue

	# Per-server constants
	CMD_FIFO="$server_path/command_pipe"
	HASH_FILE="$server_path/.bedfeather_file_hashes"
	TRACKED_FILES=()
	CONTAINER_NAME="${DOCKER_PREFIX}${server_ip_dir//./_}"
	IMAGE_NAME="$CONTAINER_NAME"
	SERVER_IP="$server_ip_dir"
	CRITICAL_FILE_CHANGE=0

	declare -A OLD_HASHES
	declare -A NEW_HASHES

	# Skip if not a valid IPv4 address
	if [[ ! "$server_ip_dir" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echl "Skipping $server_path: not a valid IPv4 directory name." warn
		continue
	fi

	# Skip if not in IP subnet
	# ip_in_subnet resides in bfconfig.sh
	if ! ip_in_subnet "$SERVER_IP" "$SUBNET"; then
		echl "Error: server IP $SERVER_IP is outside of macvlan subnet $SUBNET. Skipping." error
		continue
	fi

	# Copy any missing skel files and add all skel files to tracker list
	# Make sure they have correct permissions
	if [[ -d "$SKEL_DIR" ]]; then
		find "$SKEL_DIR" -type f -exec chown root:root {} +
		find "$SKEL_DIR" -type f -exec chmod 644 {} +
		chmod +x "$SKEL_DIR/run_fifopipeprocess.sh"
		echo "Copying missing skeleton files to $server_path, if any"
		cp -anv "$SKEL_DIR/." "$server_path/"
		# Add to list of files to track for changes
		for file in $(find "$SKEL_DIR" -type f | sed "s|^$SKEL_DIR/||"); do
			TRACKED_FILES+=("$file")
		done
	fi

	# Add other files to tracker list
	for cfg in "${CONFIG_FILES[@]}"; do TRACKED_FILES+=("$cfg"); done
	TRACKED_FILES+=("bedrock_server")

	# Compare old file hashes to new in tracked files
	# This is not whitespace in filename-safe, but if you create crucial files with whitespace you need help
	if [[ -f "$HASH_FILE" ]]; then
		while IFS=" " read -r file hash; do
			OLD_HASHES["$file"]="$hash"
		done < "$HASH_FILE"
	fi

	for file in "${TRACKED_FILES[@]}"; do
		server_file_path="$server_path/$file"
		if [[ -f "$server_file_path" ]]; then
			new_file_hash=$(sha256sum "$server_file_path" | awk '{print $1}')
			NEW_HASHES["$file"]="$new_file_hash"
			if [[ "${OLD_HASHES[$file]}" != "$new_file_hash" ]]; then
				CRITICAL_FILE_CHANGE=1
				echl "$file has changed or is new, marking for rebuild." warn
			fi
		else
			# File missing in server, keep empty hash
			NEW_HASHES["$file"]=""
			if [[ -n "${OLD_HASHES[$file]}" ]]; then
				CRITICAL_FILE_CHANGE=1
				echl "$file was deleted, or this is a new server, marking for rebuild." warn
			fi
		fi
	done

	# Determine if we need to rebuild/run
	image_exists=$(docker images -q "$IMAGE_NAME")
	if [[ $CRITICAL_FILE_CHANGE -eq 0 && $FORCE_REBUILD -eq 0 && -n "$image_exists" ]]; then
		echl "No changes and image exists for $SERVER_IP; skipping rebuild and restart."
		continue
	fi

	# Stop/remove existing container and its image if needed
	echo "Finding any running containers called $CONTAINER_NAME and stopping them."
	if docker ps -a -q -f name="^${CONTAINER_NAME}$" | grep -q .; then
		echo "Found container $CONTAINER_NAME, let's check if it is running."
		if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
			echo "Container $CONTAINER_NAME is indeed running."
			if [[ -p "$CMD_FIFO" ]]; then
				echo "FIFO exists, attempting graceful shutdown."
				fifo_write "$CMD_FIFO" "say Server is shutting down for rebuild in 10 seconds"
				sleep 10
				fifo_write "$CMD_FIFO" "stop"

				# Wait until container stops
				MAX_ATTEMPTS=30
				attempt=1
				while docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; do
					echl "Waiting for container $CONTAINER_NAME to stop... (attempt $attempt of $MAX_ATTEMPTS)"
					sleep 1
					((attempt++))
					if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
						echl "WARNING: container $CONTAINER_NAME did not stop after $MAX_ATTEMPTS attempts. Forcing stop." warn
						docker stop "$CONTAINER_NAME" > /dev/null
						sleep 10
						break
					fi
				done

			else
				# FIFO missing, force stop
				echl "WARNING: FIFO missing for container $CONTAINER_NAME. Forcing stop." warn
				docker stop "$CONTAINER_NAME" > /dev/null
				sleep 10
			fi
		else
			# Container exists but not running
			echl "$CONTAINER_NAME exists but is not running; removing..."
		fi

		# Remove container
		echo "Removing container $CONTAINER_NAME."
		docker rm "$CONTAINER_NAME" > /dev/null || { echl "Failed removing container $CONTAINER_NAME. Exiting." error ; exit 1; }
	fi

	# Remove old image if present since rebuild is happening
	image_exists=$(docker images -q "$IMAGE_NAME")
	image_in_use=$(docker ps -a --format '{{.Image}}' | grep -x "$IMAGE_NAME")
	if [[ -n "$image_exists" && -z "$image_in_use" ]]; then
		echo "Removing old image $IMAGE_NAME before rebuild..."
		docker rmi "$IMAGE_NAME" > /dev/null || echl "Failed removing image $IMAGE_NAME.." warn
	elif [[ -n "$image_exists" && -n "$image_in_use" ]]; then
		echl "Image $IMAGE_NAME still in use by a container, skipping removal." warn
	else
		echo "Image $IMAGE_NAME does not exist, nothing to remove."
	fi

	# Build image
	echo "Building $IMAGE_NAME from $server_path"
	docker build -t "$IMAGE_NAME" "$server_path"

	# Create worlds directory
	echo "Making sure worlds resource exists with correct permissions."
	mkdir -p "$server_path/worlds"
	chown -R 1000:1000 "$server_path/worlds"

	# Create FIFO for commands
	# FIFO is created with 0666 because run_server.sh inside the container have to open it read/write
	echo "Creating FIFO for command piping if not already present."
	[[ -e "$CMD_FIFO" && ! -p "$CMD_FIFO" ]] && rm -f "$CMD_FIFO"
	[[ -p "$CMD_FIFO" ]] || mkfifo "$CMD_FIFO"
	chmod 0666 "$CMD_FIFO"

	# Run container
	echo "Running container $CONTAINER_NAME with IP $SERVER_IP"
	docker run -d \
		--name "$CONTAINER_NAME" \
		--network "$MACVLAN_NETWORK" \
		--ip "$SERVER_IP" \
		-v "$server_path/worlds:/bedrock/worlds" \
		-v "$CMD_FIFO:/bedrock/command_pipe" \
		"$IMAGE_NAME" > /dev/null

	# Update tracked files hash list
	echo "Saving new file hash list."
	> "$HASH_FILE"
	for file in $(printf "%s\n" "${!NEW_HASHES[@]}" | sort); do
		echo "$file ${NEW_HASHES[$file]}" >> "$HASH_FILE"
	done
done

