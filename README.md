# Bedfeather

Bedfeather is an ultra-lightweight, scriptable, pure Bash script suite for running and managing multiple Minecraft Bedrock servers on a single host. Each server runs in its own Docker container with a dedicated IPv4 address, allowing all instances to share the default Bedrock port without conflicts. Bedfeather provides scriptable backups, FIFO-based command automation, and deployment/rebuild management, enabling efficient command-line automation for multiple servers simultaneously.

Bedfeather is **NOT AN OFFICIAL MINECRAFT PRODUCT, NOR APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT.**

## Key features
1. **Multi-IP Server Hosting via Docker**

    Run multiple servers concurrently on the same host and port. Each server runs in its own container with a dedicated IP, preventing port conflicts and keeping servers isolated.

2. **Command Automation via FIFO**

    Send console commands to running servers through named pipes (FIFOs), providing a simple and reliable interface compared with docker exec or interactive terminals.

3. **Deployment and Rebuilds**

    Detect file changes, rebuild images, and (re)start server instances automatically.

4. **Scripted Backups**

    Back up worlds and configs with optional notes; servers are stopped and restarted during backups to avoid data corruption. Users are notified.

5. **Cleanup and Maintenance**

    Identify and optionally remove orphaned containers and images.

6. **Pure Bash Utilities**

    Centralized configuration, logging, network autodetection, and helper scripts never extending beyond Bash and coreutils.

7. **World data is stored outside of the container**

    World data is mounted from the server structure on the host filesystem under each server directory

### Limitations

Bedfeather requires Docker and a unique IPv4 per Bedrock server. Commands sent via FIFO pipes are one-way. Live snapshots aren’t supported by Bedrock; backups require briefly stopping or pausing servers. WLAN (Wi-Fi) may be unreliable for multiple IPs. Linux/POSIX only.

## Why Bedfeather Exists

The Minecraft Bedrock server has several architectural limitations that make multi-server hosting awkward on a single host machine. Each server binds its listening port to all network interfaces on the host, not to a specific IP, and uses a fixed UDP port (19132 by default). While the port can technically be changed, many clients, networks, and hosting environments expect or require the default port. This means multiple servers cannot share the same port on a single host without assigning each one a unique IP address isolated from other Bedrock servers on the same host.

In addition, the Bedrock server does not expose a stable stdin-based control channel suitable for automation, and it does not support safe live snapshots of worlds while running. Running multiple instances reliably therefore requires external isolation, explicit IP management, and controlled start/stop and backup mechanisms.

Bedfeather provides tools to work around these limitations, enabling safer, scriptable management of multiple Minecraft Bedrock servers on a single host.

## Scripts

### bfconfig.sh

Common configuration and helper library used by all other scripts.

Loads /opt/bedfeather/config.sh, generates it if missing, and provides shared functions for logging, FIFO command writing, IP/subnet handling, and network autodetection.

### bfrun.sh

Builds, runs, and rebuilds Bedrock server containers.

Tracks critical files, detects changes, rebuilds images when needed, manages container lifecycle, ensures required directories and FIFOs exist, and assigns each server its configured IP.

```bash
./bfrun.sh
./bfrun.sh --force-rebuild
./bfrun.sh --server 192.168.1.50
```

### bfbackup.sh

Performs safe, scripted backups of server data.

Gracefully stops running servers, copies world data and configuration files to timestamped backup directories, optionally adds a note, and restarts servers afterward. Can prune backlog and only keep a given number of copies back in time.


```bash
./bfbackup.sh
./bfbackup.sh --server 192.168.1.50
./bfbackup.sh --note "before upgrading plugins"
./bfbackup.sh --server 192.168.1.50 --prune-old 5
```

### bfcommand.sh

Sends console commands to running servers.

Writes commands into each server’s FIFO command pipe, allowing scripted administration without interactive terminals.

```bash
./bfcommand.sh --command "say Server restart in 5 minutes"
./bfcommand.sh --server 192.168.1.50 --command "save hold"
```

### bfpurge.sh

Identifies and optionally removes orphaned resources.

Finds containers and images that no longer have corresponding server directories and lists or removes them to keep the system clean.

## How to get a server up and running

This section describes the minimal steps required to configure Bedfeather and start one or more Bedrock servers.

All of this should be done as root or through `su <command>`. You can make yourself root by doing `sudo -i`, but remember that the system will not tell you if you are doing anything unsmart as root.

1. **Install prerequisites**

    Bedfeather requires:

    * Bash and Coreutils (exists on virtually any standard Linux install)
    * Docker (may have to be installed)
    * A Linux host with a network interface that supports macvlan, which allows each container to have its own unique IP address on the same subnet. Most wired (LAN) interfaces work reliably, while wireless (WLAN) interfaces may not support macvlan or may be unstable for multiple IPs.
    * A subnet where you can assign multiple IPs to the host
    * Root access to the server to run docker properly

   Make sure Docker is installed and working:
   ```bash
   docker info
   ```

3. **Create the base directory**

    Clone or copy Bedfeather into /opt/bedfeather:

    ```bash
    mkdir -p /opt/bedfeather
    cd /opt/bedfeather
    # unpack, copy or clone Bedfeather repository here
    ```

    Make sure the correct scripts are executable
    ```bash
    chmod +x bf*.sh
    # files like config.sh and any files under skel/ remain non-executable
    ```
4. **Run once to generate configuration**

    ```bash
    ./bfconfig.sh
    ```

    On the first run, a configuration file will be created at /opt/bedfeather/config.sh if it does not already exist.

    If the configuration file exists but contains no values for network variables, Bedfeather attempts to autodetect the network interface, subnet, and gateway. Edit the configuration file to provide your specific network settings for reliability.

    ```bash
    nano /opt/bedfeather/config.sh
    ```

5. **Create a server directory**

    Each server is represented by a directory named after its IPv4 address:

    ```bash
    mkdir -p /opt/bedfeather/servers/192.168.1.50
    ```

    Download and extract the official Bedrock server from Microsoft’s website (https://www.minecraft.net/en-us/download/server/bedrock) into this directory, or copy your existing server files here in their entirety (not including any existing Docker files). Make sure permissions are retained properly, especially if you copy existing files.

    On the first run of bfrun.sh, Bedfeather will automatically copy all necessary management files, including Docker setup and scripts, into the server directory. This ensures the server is ready to build and run with minimal manual setup.

6. **Start the server**

    ```bash
    cd /opt/bedfeather
    ./bfrun.sh
    ```

    This will:

    1. Create the macvlan network if needed
    2. Build the container image
    3. Create required FIFOs and directories
    4. Start the server bound to its IP

7. **Verify**

    Check that the container is running:

    ```bash
    docker ps
    ```

    You should see a container named like:

    ```text
    bedfeather_192_168_1_50
    ```

    Verify that the server is reachable by connecting from a Bedrock client to:

    ```text
    192.168.1.50:19132
    ```

   You should now also be able to discover the server automatically on LAN with a minecraft client since it is on standard port.

8. **Managing the server**

    Send commands:
    ```bash
    cd /opt/bedfeather
    ./bfcommand.sh --server 192.168.1.50 --command "say hello"
    ```

    Back up:
    ```bash
    cd /opt/bedfeather
    ./bfbackup.sh --server 192.168.1.50
    ```

    Rebuild after changing files:
    ```bash
    cd /opt/bedfeather
    ./bfrun.sh --server 192.168.1.50
    ```

9. **Adding more servers**

    Repeat step 5 for each additional server, using a different IP:
    ```bash
    mkdir -p /opt/bedfeather/servers/192.168.1.51
    # copy relevant server files or unzip new ones
    ```

    Then run:
    ```bash
    ./bfrun.sh
    ```

## Automatic startup and shutdown with systemd

Bedfeather can be started automatically at boot and stopped cleanly using a systemd service.

systemd is the service manager used by most modern Linux distributions. It handles starting and stopping services at boot and shutdown, and provides logging, dependency management, and centralized service control.

Enable the Bedfeather service

```bash
# Create a symlink to the systemd directory
sudo ln -s /opt/bedfeather/systemd/bedfeather.service /etc/systemd/system/bedfeather.service

# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable bedfeather.service

# Optional: Start the service immediately
# Note: This will build and start all servers, if any
sudo systemctl start bedfeather.service

# Optional: Follow logs to monitor startup
sudo journalctl -u bedfeather.service -f
```

## Advanced Options

### Using a non-standard installation directory

By default, Bedfeather should be installed under `/opt/bedfeather`. If you want to install it somewhere else:

1. **Set `BEDFEATHER_DIR` before first run** in `bfconfig.sh`:

    ```bash
    (...)
    # Change BEDFEATHER_DIR before running bfconfig.sh if you want Bedfeather to live elsewhere
    # Changing this requires knowledge of what you are doing. Systemd will not work without update
    # You will also have to change the sourcing in the other script files
    BEDFEATHER_DIR="/your/custom/path"
    CONFIG_FILE="$BEDFEATHER_DIR/config.sh"
    (...)
    ```
    Make sure the Bedfeather files are in this directory.

    **Warning:** If you copy a new version of Bedfeather, `bfconfig.sh` will be overwritten, make sure to update it.

2. **Systemd integration:**
    If you are using the systemd service to start Bedfeather automatically, you must update the symlink in `/etc/systemd/system/bedfeather.service` to point to the new path, and also update all paths in the systemd file itself.

## Limitations/requirements

Bedfeather addresses many of the challenges of running multiple Minecraft Bedrock servers, but there are some inherent limitations to be aware of:

* **Network requirements:** Each server requires an available IP within the host’s subnet. Using macvlan may require specific configuration on the host and router. Macvlan works reliably on wired Ethernet interfaces, but may not function on Wi-Fi or certain virtual/bridged interfaces.
* **No live snapshots:** While backups are automated, Bedrock does not support live snapshots of worlds. Backups require stopping or pausing the server to ensure data integrity.
* **One way command interface:** Commands are sent one-way through a named pipe (FIFO); no automatic response or output is returned. For feedback, monitor the server logs:
`docker logs -f bedfeather_192_168_1_50`
* **Docker dependency:** Bedfeather uses Docker containers to isolate each server’s IP, so Docker must be installed and running on the host.
* **Resource usage:** While Bedfeather itself is extremely lightweight, each server runs in a separate container that consumes CPU and memory. Host resources will limit the number of concurrent servers.
* **POSIX / Linux only:** The FIFO-based control mechanism relies on POSIX kernel FIFOs and mounting behavior. This means Bedfeather cannot run natively on Windows, though it works on Linux and other POSIX-compliant systems
* **IPv4 only:** Bedfeather currently requires IPv4 addresses for server directories and container assignment. (Albeit, if you are using IPv6 in Docker, you likely don’t need this explanation and are mainly here for a deeper look at the FIFO command pipe.)


## The FIFO command pipe (technical deep dive)

Bedfeather solves the challenge of scripting commands to a Bedrock server in Docker using a FIFO mounted into the container and a small wrapper script. Here’s how the full flow works:

1. **Host writes to the FIFO**

    On the host, each server has a FIFO file:
    ```bash
    /opt/bedfeather/servers/192.168.1.50/command_pipe
    ```

    Commands can be written directly to the FIFO from the host shell/command line:

    ```bash
    # Send a single command
    echo "say Hello world" > /opt/bedfeather/servers/192.168.1.50/command_pipe

    # Pipe multiple commands from a file
    cat commands.txt > /opt/bedfeather/servers/192.168.1.50/command_pipe
    ```

    The kernel buffers writes to the FIFO until the container reads them, ensuring atomic delivery per line.

2. **FIFO is mounted into the container**

    When the container starts, the host FIFO is mounted inside the container at:

    ```bash
    /bedrock/command_pipe
    ```

    This means the container sees the same FIFO file as the host and anything written from the host is immediately available inside the container.

3. **Wrapper script reads from the FIFO**

    Inside the container, the server is started via the wrapper script `run_fifopipeprocess.sh`:

    ```bash
    #!/bin/bash

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
    ```

    Key points:

    * The FIFO is opened for read/write on custom file descriptor 3 to prevent blocking.
    * The Bedrock server’s stdin is redirected from the FIFO.
    * Every line read from the FIFO is delivered to the server exactly as console input, in order.

4. **Server executes commands**

    Commands are executed sequentially, preserving order.

    Multiple writers can write safely to the FIFO, as long as each command fits within the pipe buffer, which is system-dependent, but typically 4096 bytes on Linux. The kernel guarantees that writes up to PIPE_BUF are atomic.

    The FIFO is one-way only: output is not returned through the pipe.

5. **Monitoring output**

    Because PID 1 inside the container is the server itself:

    * Attaching a shell directly isn’t available by default.
    * To see command results, use the container logs: `docker logs -f bedfeather_192_168_1_50`
    * The FIFO ensures commands are executed in order, while logs give a reliable way to monitor server activity without interfering with stdin.

### Why the shared FIFO approach is more robust

* **Kernel-mediated communication:** The FIFO enables direct communication between host and container without extra daemons, network sockets, or intermediary processes.
* **Scriptable automation:** Mounting the FIFO from the host allows standard shell piping and redirection directly into the container.
* **Avoids common Docker issues:** Unlike docker exec or PTY-based solutions, this approach prevents deadlocks, stdin problems, and partial writes.
* **Per-container isolation:** Each container has its own FIFO, enabling strict per-container isolation while still supporting centralized orchestration.

### Why the sharedFIFO approach is faster and more resource efficient

* **Direct kernel I/O:** Using a FIFO avoids TCP/IP stack overhead or additional sockets, letting commands pass directly from host to container with minimal system calls.
* **No extra processes:** Commands are written straight to the FIFO without spawning intermediary shells or multiplexers, reducing CPU usage and memory footprint.
* **Low-latency delivery:** Writes to the FIFO are atomic per line, ensuring commands reach the server immediately without buffering delays outside of the kernel.
* **Concurrent-safe writes:** Multiple scripts or processes can write to the FIFO simultaneously without requiring locks or coordination, preventing contention bottlenecks.

### Why the shared FIFO approach is both fast and robust

* **Minimal shell overhead:** The server runs as PID 1 with the FIFO opened directly, avoiding extra wrapper processes or bloated multiplexers inside the container.
* **Atomic line semantics / low-latency writes:** Commands are delivered intact and sequentially, even with concurrent writers, without requiring locks, ensuring predictable behavior.
* **Zero-translation input:** Redirecting stdin directly from the FIFO makes the Bedrock server see input exactly as if typed on stdin, preserving command integrity and efficiency.

### Code references summary

This setup transforms a simple UNIX FIFO into a robust, atomic, scriptable console channel, providing predictable, low-latency, per-container command execution in a containerized environment without unnecessary overhead.

* **bfbackup.sh:** mounting FIFO into container `-v "$CMD_FIFO:/bedrock/command_pipe"`, sending shutdown messages via `fifo_write()`
* **bfcommand.sh:** sending commands to `$CMD_FIFO` for all or targeted servers
* **bfrun.sh:** creating FIFO `mkfifo "$CMD_FIFO"`, opening it as FD 3 `exec 3<> "$CMD_FIFO"`, running server as PID 1
* **bfconfig.sh:** `fifo_write()` implementation, including timeout and atomic line semantics
* **skel/server/run_fifopipeprocess.sh:** FD 3 redirected to server (exec /bedrock/bedrock_server <&3)

## FIFO-based command pipe (General Use)

Bedfeather introduces a shared FIFO approach for per-container, scriptable command execution. While originally designed for Minecraft Bedrock servers, this FIFO-based approach works for any containerized process that reads from stdin and benefits from line-atomic input.

If you adapt or reuse this FIFO-based stdin approach in your own projects, we encourage you to acknowledge where it originated.

## License & Reuse

Bedfeather is licensed under the MIT License. You are free to copy, modify, redistribute, or integrate the scripts, Docker setup, and documentation into your own projects, as long as the required notices are included.

The techniques described here—including the per-container FIFO command system for robust, atomic, scriptable command input, and the approach to managing multiple Bedrock servers on unique IP addresses—are methods developed in Bedfeather. While the MIT license covers the code and documentation as written, the ideas themselves are free to study, adapt, and implement in your own projects.

You are encouraged to learn from the implementation, experiment with your own adaptations, and integrate these methods into new tools.

If you incorporate any of these methods or are inspired by them, a simple reference is appreciated:

```text
Method inspired by Bedfeather (https://github.com/btdahl/bedfeather)
by apario (https://www.apario.net/) and Bjørn T. Dahl (https://github.com/btdahl)
```

---
Copyright (c) 2025,2026 apario (www.apario.net)  
Copyright (c) 2025,2026 Bjørn T. Dahl (github.com/btdahl)

