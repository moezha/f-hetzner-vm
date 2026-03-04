# Hetzner VM Bootstrapping

Automated deployment and hardening for Ubuntu 22.04 VMs using Multipass on Windows hosts. This setup includes specific patches for corporate network environments and cross-platform compatibility.

##  Architecture Overview

The infrastructure is built on Ubuntu 22.04 LTS and structured around modular shell scripts.

* **Runtime:** Docker & Docker Compose (running a lightweight Go `http-echo` container).
* **Web Tier:** Nginx acting as a reverse proxy, with automated Let's Encrypt SSL.
* **Security:** UFW (default deny), Fail2ban (SSH protection), and strict OpenSSH hardening.
* **Monitoring:** Prometheus Server, Node Exporter (host metrics), cAdvisor (container metrics), Grafana (visualization), and strict log rotation.

##  Key Architectural Decisions

1.  **Modular & Idempotent Execution**
    Instead of a single monolithic script, the setup is divided into logical modules (`01-system.sh` to `06-monitor.sh`). State checks (e.g., `if ! command -v docker`) ensure scripts can be re-run safely without breaking existing configurations.
2.  **Defense in Depth (Security)**
    * **Root Disabled:** Root SSH login and password authentication are completely disabled. 
    * **Least Privilege:** A dedicated `deploy` user is created. To prevent trivial root escalation via the Docker socket, the user is strictly excluded from the `docker` group. Instead, granular, passwordless `sudo` access is granted specifically for required Docker binaries.
    * **Host-Level Firewall:** UFW is configured directly on the OS. Even if the cloud provider's external firewall is misconfigured, the server remains isolated (only ports 22, 80, and 443 are exposed).
3.  **Preventing Disk Exhaustion (Reliability)**
    Default Docker and Nginx configurations will eventually fill a server's disk with logs. This setup injects a `daemon.json` to limit container logs (max 50MB, 3 files) and enforces aggressive `logrotate` rules for Nginx.
4.  **Configuration Management**
    Environment-specific variables (SSH keys, domains, user names) are isolated in a root-owned, strictly permissioned `config.env` file. The bootstrap script validates the ownership of this file to prevent privilege escalation during execution.

## 🚀 Setup Instructions

### Prerequisites
* A clean Ubuntu 22.04 server (or a local Multipass VM).
* An SSH key pair (`id_ed25519`).

### 1. Configuration
Copy the configuration template and populate it with your environment details:

```bash
    cp config.env.example config.env
```
Ensure `config.env` contains your public SSH key, desired timezone, and domain information.

### 2. Local Testing (Multipass)
To test the deployment locally on Windows, execute the provided PowerShell harness. This spins up an Ubuntu VM, overrides local DNS, sanitizes line endings (CRLF to LF), and executes the bootstrap sequence:
```bash
    .\test-local.ps1
```

### 3. inside vm testing:
```bash
    # Fix Windows line endings and secure the config file
    sed -i 's/\r$//' setup.sh scripts/*.sh config.env Makefile
    chown root:root config.env && chmod 600 config.env
    
    # Run the automated setup via the Makefile entry point
    make install
```

## 🔍 Validation & Health Checks
Once provisioned, verify the following:
* **App Health:** `curl https://<DOMAIN>/health` (Returns HTTP 200 `OK`)
* **Metrics & Dashboards:** Connect via SSH and verify Node Exporter (`curl localhost:9100/metrics`). Grafana is accessible locally on port 3000, and cAdvisor on port 8081.
* **Firewall:** Ensure `curl <IP>:8080` times out (blocked by UFW).
```bash
    chmod +x audit.sh
    ./audit.sh
```