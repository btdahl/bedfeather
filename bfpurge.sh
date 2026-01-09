#!/bin/bash
# Copyright (c) 2025-2026 apario (www.apario.net)
# Copyright (c) 2025-2026 Bjorn T. Dahl (github.com/btdahl)

# Remove any orphaned containers or images that don't have a server directory
# Default behavior: list orphaned containers/images
# Use --purge to actually remove them

source /opt/bedfeather/bfconfig.sh

PURGE_MODE=0
if [[ "$1" == "--purge" ]]; then
        PURGE_MODE=1
fi

echo "Checking for orphaned Bedrock containers/images..."

found_orphan=0

# --- Check orphaned containers ---
for container_name in $(docker ps -a --format '{{.Names}}' | grep "^${DOCKER_PREFIX}"); do
        server_ip_dir="$SERVER_DIR/${container_name//${DOCKER_PREFIX}/}"
        server_ip_dir="${server_ip_dir//_/\.}"

        if [[ ! -d "$server_ip_dir" ]]; then
                found_orphan=1
                image_name="$container_name"

                if [[ $PURGE_MODE -eq 0 ]]; then
                        echl "Orphaned container found: $container_name (image: $image_name)" warn
                else
                        echl "Purging container $container_name and image $image_name..." warn

                        # Stop container if running
                        if docker ps --format '{{.Names}}' | grep -qx "$container_name"; then
                                echo "Stopping $container_name..."
                                docker stop "$container_name" > /dev/null
                        fi

                        # Remove container
                        docker rm "$container_name" > /dev/null
                        echo "Removed container $container_name"

                        # Remove image if exists
                        image_id=$(docker image ls -q "$image_name")
                        if [[ -n "$image_id" ]]; then
                                docker rmi "$image_name" > /dev/null
                                echo "Removed image $image_name"
                        fi
                fi
        fi
done

# --- Check orphaned images ---
for image_name in $(docker image ls --format '{{.Repository}}' | grep "^${DOCKER_PREFIX}"); do
        server_ip_dir="$SERVER_DIR/${image_name//${DOCKER_PREFIX}/}"
        server_ip_dir="${server_ip_dir//_/\.}"

        # If the folder does not exist, the image is orphaned
        if [[ ! -d "$server_ip_dir" ]]; then
                found_orphan=1
                if [[ $PURGE_MODE -eq 0 ]]; then
                        echl "Orphaned image found: $image_name" warn
                else
                        echl "Purging image $image_name..." warn
                        docker rmi "$image_name" > /dev/null
                        echo "Removed image $image_name"
                fi
        fi
done

# --- Summary messages ---
if [[ $found_orphan -eq 0 ]]; then
        echo "No orphaned containers or images found."
elif [[ $PURGE_MODE -eq 0 ]]; then
        echl "Add --purge to actually remove these containers and images." warn
else
        echo "Purge complete."
fi

