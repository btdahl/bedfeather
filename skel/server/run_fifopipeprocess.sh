#!/bin/bash
# Copyright (c) 2025-2026 apario (www.apario.net)
# Copyright (c) 2025-2026 Bjorn T. Dahl (github.com/btdahl)

CMD_FIFO="/bedrock/command_pipe"
if [[ ! -p "$CMD_FIFO" ]]; then
	>&2 echo "ERROR ($0): command FIFO $CMD_FIFO missing. Not starting."
	exit 1
fi

# Open FIFO for read/write to avoid blocking
# Using exec here changes the file descriptor in this shell
exec 3<> "$CMD_FIFO"

# Start Bedrock reading from fd 3 (non-blocking)
# Using exec here passes process to the server from this shell, leaving it with PID 1
exec /bedrock/bedrock_server <&3

