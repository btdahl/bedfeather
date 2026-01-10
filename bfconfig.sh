#!/bin/bash
# Copyright (c) 2025-2026 apario (www.apario.net)
# Copyright (c) 2025-2026 Bjorn T. Dahl (github.com/btdahl)

# Common config, fallbacks and functions for bedfeather
# Will create config.sh if it is missing
# Will calculate fallbacks for missing config and yell about it
# This file is not for user editing

# Change BEDFEATHER_DIR before running bfconfig.sh if you want Bedfeather to live elsewhere
# Changing this requires knowledge of what you are doing. Systemd will not work without update
BEDFEATHER_DIR="/opt/bedfeather"
CONFIG_FILE="$BEDFEATHER_DIR/config.sh"

# Highlighted echo
function echl() {
	local text="$1"
	local type="${2:-info}"
	local color
	case "$type" in
		error)
			color="\033[1;31m"   # bright red
			>&2 echo -e "${color}${text}\033[0m"
			return
			;;
		warn)  color="\033[1;33m" ;; # bright yellow
		info)  color="\033[1;34m" ;; # bright blue
		*) color="\033[0m" ;;
	esac
	echo -e "${color}${text}\033[0m"
}

# Helper to write to fifos, since they may be brittle to deal with
function fifo_write() {
	local fifo="$1"
	local command="$2"
	local timeout_sec="${3:-5}" # default 5 seconds

	if [[ -z "$fifo" || -z "$command" ]]; then
		echl "ERROR (fifo_write): missing fifo or command" error
		return 1
	fi

	if [[ ! -p "$fifo" ]]; then
		echl "ERROR (fifo_write): $fifo is not a FIFO" error
		return 1
	fi

	# Use coreutils timeout to avoid blocking indefinitely
	timeout "$timeout_sec"s bash -c "echo '$command' > '$fifo'"
	local rc=$?

	if [[ $rc -ne 0 ]]; then
		if [[ $rc -eq 124 ]]; then
			echl "ERROR (fifo_write): timeout sending to $fifo after $timeout_sec seconds" error
		else
			echl "ERROR (fifo_write): write failed to $fifo (rc=$rc)" error
		fi
		return $rc
	fi

	return 0
}

# Pure Bash function to calculate network start address from IP and CIDR prefix
# A lot of overlap with ip_in_subnet, but abstraction just add lines and complexity
function network_start() {
	local ip="$1"
	local prefix="$2"

	# Convert IP to 32-bit integer
	IFS=. read -r i1 i2 i3 i4 <<< "$ip"
	local ipint=$(( (i1 << 24) | (i2 << 16) | (i3 << 8) | i4 ))

	# Compute mask
	local mask=$(( 0xFFFFFFFF << (32 - prefix) & 0xFFFFFFFF ))

	# Compute network start
	local netint=$(( ipint & mask ))

	# Convert back to dotted quad
	local n1=$(( (netint >> 24) & 0xFF ))
	local n2=$(( (netint >> 16) & 0xFF ))
	local n3=$(( (netint >> 8) & 0xFF ))
	local n4=$(( netint & 0xFF ))
	echo "$n1.$n2.$n3.$n4"
}

# Pure bash function to see if IP $1 is within the CIDR range $2
# A lot of overlap with network_start, but abstractino just add lines and complexity
function ip_in_subnet() {
	local ip="$1"
	local subnet="$2"
	local network="${subnet%/*}"
	local prefix="${subnet#*/}"

	# Convert IP to 32-bit integer
	IFS=. read -r i1 i2 i3 i4 <<< "$ip"
	local ipint=$(( (i1 << 24) | (i2 << 16) | (i3 << 8) | i4 ))

	# Convert network to 32-bit integer
	IFS=. read -r n1 n2 n3 n4 <<< "$network"
	local netint=$(( (n1 << 24) | (n2 << 16) | (n3 << 8) | n4 ))

	# Compute mask
	local mask=$(( 0xFFFFFFFF << (32 - prefix) & 0xFFFFFFFF ))

	# Apply mask to both IP and network and compare
	if (( (ipint & mask) == (netint & mask) )); then
		return 0
	else
		return 1
	fi
}

# Check that the main directory exists
if [[ ! -d "$BEDFEATHER_DIR" ]]; then
	echl "Error: BEDFEATHER_DIR '$BEDFEATHER_DIR' does not exist. Make sure you are working in the correct directory" error
	exit 1
fi

# Check if config.sh exists and create it if not
# Also make sure the scripts are executable, since this is a first run
if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "This looks like a first run."
	echl "Creating default config.sh at $CONFIG_FILE"
	cat > "$CONFIG_FILE" << EOF
#!/bin/bash

# Base directories
BASE_DIR="$BEDFEATHER_DIR"
SERVER_DIR="\$BASE_DIR/servers"
BACKUP_DIR="\$BASE_DIR/serverbackup"
DOCKER_PREFIX="bedfeather_"
CONFIG_FILES=("server.properties" "permissions.json" "whitelist.json" "allowlist.json")

# Networking / container
MACVLAN_NETWORK="\${DOCKER_PREFIX}macvlan"
NETWORK_IF=""
SUBNET=""
GATEWAY=""

EOF

	echl "Ensuring main suite scripts in $BEDFEATHER_DIR are executable."
	for script in "$BEDFEATHER_DIR"/bp*.sh; do
		[[ -f "$script" ]] && chmod +x "$script"
	done
	echl "Ensuring server and backup directories exists."
	mkdir -p "$BEDFEATHER_DIR/servers"
	mkdir -p "$BEDFEATHER_DIR/serverbackup"
	echo "Initial setup done."
	echo "You should edit $CONFIG_FILE to provide proper values for your setup."
	echo "Network interface, subnet, and gateway should be set manually."
	echo "You can run ./bfconfig.sh again to see autodetected values."
	exit 0
fi

# Source the existing config.sh
source "$CONFIG_FILE"

# Autodetectors will run any time config is missing, regardless if the caller needs the info
# This is fine as it just nags the user about doing proper config

# Autodetect network interface if not specified
if [[ -z "$NETWORK_IF" ]]; then
	echl "No network interface specified, trying to autodetect..." warn
	NETWORK_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1)}}}')
	if [[ -z "$NETWORK_IF" ]]; then
		echl "Error: could not autodetect network interface. Exiting." error
		exit 1
	else
		echo "Autodetected network interface: $NETWORK_IF"
		echl "You should add NETWORK_IF=\"$NETWORK_IF\" to config.sh" warn
	fi
fi

# Autodetect IP range and gateway only if SUBNET or GATEWAY is empty
IF_CIDR=$(ip -o -f inet addr show "$NETWORK_IF" | awk '{print $4}')
if [[ -z "$IF_CIDR" ]]; then
	echl "Error: could not find IP address for $NETWORK_IF. Exiting." error
	exit 1
fi

IP_ADDR=${IF_CIDR%%/*} # host IP
PREFIX=${IF_CIDR##*/}  # CIDR prefix

if [[ -z "$SUBNET" ]]; then
	NETWORK=$(network_start "$IP_ADDR" "$PREFIX")
	SUBNET="$NETWORK/$PREFIX"
	echo "Autodetected subnet: $SUBNET"
	echl "You should add SUBNET=\"$SUBNET\" to config.sh" warn
fi

if [[ -z "$GATEWAY" ]]; then
	GATEWAY=$(ip route | awk '/default/ {print $3}')
	if [[ -z "$GATEWAY" ]]; then
		echl "Error: could not determine default gateway. Exiting." error
		exit 1
	else
		echo "Autodetected gateway: $GATEWAY"
		echl "You should add GATEWAY=\"$GATEWAY\" to config.sh" warn
	fi
fi

