#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

# This script sets the following options:
# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error and exit immediately.
# -x: Print commands and their arguments as they are executed.
# -o pipefail: The return value of a pipeline is the status of the last command
#              to exit with a non-zero status, or zero if no command exited with a non-zero status.
set -euxo pipefail

# Kubernetes Variable Declaration
# This script sets the versions for Kubernetes and CRI-O.
# 
# Variables:
#   KUBERNETES_VERSION: The version of Kubernetes to be installed.
#   CRIO_VERSION: The version of CRI-O to be installed.
#   KUBERNETES_INSTALL_VERSION: The specific installation version of Kubernetes.
KUBERNETES_VERSION="v1.32"
CRIO_VERSION="v1.32"
KUBERNETES_INSTALL_VERSION="1.32.2-1.1"

# Disable swap
# This script disables swap on the system.
# Swap is turned off to ensure Kubernetes can function properly,
# as Kubernetes requires swap to be disabled for optimal performance and stability.
sudo swapoff -a

# Keeps the swap off during reboot
# This script performs the following actions:
# 1. Adds a cron job to disable swap on system reboot.
#    - The cron job runs the command `/sbin/swapoff -a` at reboot.
#    - The existing crontab entries are preserved.
# 2. Updates the package list on the system using `apt-get update -y`.
#    - The `-y` option automatically answers 'yes' to prompts during the update process.
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
sudo apt-get update -y

# Create the .conf file to load the modules at bootup
# This script writes a configuration file to load kernel modules required by Kubernetes.
# It uses a here document to create the file /etc/modules-load.d/k8s.conf with the following content:
# - overlay: A kernel module that allows overlaying one filesystem on top of another.
# - br_netfilter: A kernel module that enables bridge network filtering, which is necessary for Kubernetes networking.
# The 'sudo tee' command is used to write the content to the file with elevated privileges.
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# This script loads necessary kernel modules for Kubernetes networking.
# 
# overlay: This module allows the overlay network driver to be used, which is 
#          essential for container networking.
# br_netfilter: This module enables bridge network filtering, which is required 
#               for Kubernetes to manage network traffic between pods.
sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl params required by setup, params persist across reboots
# This script configures sysctl settings for Kubernetes networking.
# It creates a configuration file at /etc/sysctl.d/k8s.conf with the following settings:
# - Enables packet forwarding for IPv4.
# - Ensures that iptables can see bridged traffic for both IPv4 and IPv6.
# The settings are applied using 'sudo tee' to write the configuration file.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
# This script applies system-wide kernel parameter settings from all 
# configuration files located in /etc/sysctl.conf and /etc/sysctl.d/*. 
# It requires superuser privileges to execute.
sudo sysctl --system

# This script updates the package list and installs necessary packages for Kubernetes setup.
# It installs the following packages:
# - apt-transport-https: Allows the use of repositories accessed via the HTTP Secure protocol.
# - ca-certificates: Common CA certificates.
# - curl: Command-line tool for transferring data with URLs.
# - gpg: GNU Privacy Guard, a tool for secure communication and data storage.
sudo apt-get update -y
sudo dpkg --configure -a
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Install CRI-O Runtime
# This script updates the package list and installs necessary packages for adding software repositories and handling HTTPS connections.
# It performs the following actions:
# 1. Updates the package list to ensure the latest versions of packages and their dependencies are available.
# 2. Installs the following packages:
#    - software-properties-common: Provides an abstraction of the used apt repositories.
#    - curl: A tool to transfer data from or to a server.
#    - apt-transport-https: Allows the use of repositories accessed via the HTTP Secure protocol.
#    - ca-certificates: Common CA certificates to ensure secure communication.
sudo apt-get update -y
sudo apt-get install -y software-properties-common curl apt-transport-https ca-certificates

# Downloads the GPG key for the specified CRI-O version from the Kubernetes addons repository
# and saves it as a dearmored GPG keyring file in /etc/apt/keyrings.
# 
# Variables:
#   CRIO_VERSION - The version of CRI-O to be used.
curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

# Adds the CRI-O repository to the APT sources list.
# The repository URL is constructed using the CRIO_VERSION environment variable.
# The repository is signed by the key located at /etc/apt/keyrings/cri-o-apt-keyring.gpg.
# The resulting source list is saved to /etc/apt/sources.list.d/cri-o.list.
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/cri-o.list

# This script updates the package lists for upgrades and new package installations,
# and then installs the CRI-O container runtime on a Debian-based system.
#
# Commands:
# 1. sudo apt-get update -y
#    - Updates the package lists for upgrades and new package installations.
#    - The '-y' flag automatically answers 'yes' to prompts.
#
# 2. sudo apt-get install -y cri-o
#    - Installs the CRI-O container runtime.
#    - The '-y' flag automatically answers 'yes' to prompts.
sudo apt-get update -y
sudo apt-get install -y cri-o

# This script reloads the systemd manager configuration, enables the CRI-O service to start on boot,
# and starts the CRI-O service immediately.
#
# Commands:
# 1. sudo systemctl daemon-reload
#    - Reloads the systemd manager configuration. This is necessary after making changes to unit files.
#
# 2. sudo systemctl enable crio --now
#    - Enables the CRI-O service to start on boot and starts the service immediately.
#
# 3. sudo systemctl start crio.service
#    - Starts the CRI-O service. This command is redundant if the previous command is used with the '--now' option.
sudo systemctl daemon-reload
sudo systemctl enable crio --now
sudo systemctl start crio.service

echo "CRI runtime installed successfully"

# Install kubelet, kubectl, and kubeadm
# This script downloads the Kubernetes APT repository GPG key and saves it to the specified location.
# 
# The `curl` command fetches the GPG key from the Kubernetes package repository.
# - `-fsSL` options ensure that curl fails silently on server errors and follows redirects.
# 
# The `gpg --dearmor` command converts the ASCII-armored GPG key to binary format.
# - The output is saved to `/etc/apt/keyrings/kubernetes-apt-keyring.gpg`.
# 
# Environment Variables:
# - `KUBERNETES_VERSION`: Specifies the version of Kubernetes to be used in the URL.
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Adds the Kubernetes APT repository to the system's sources list.
# The repository URL includes the Kubernetes version specified by the $KUBERNETES_VERSION environment variable.
# The repository is signed by the key located at /etc/apt/keyrings/kubernetes-apt-keyring.gpg.
# The output is written to /etc/apt/sources.list.d/kubernetes.list.
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/kubernetes.list

# This script updates the package list and installs specific versions of Kubernetes components (kubelet, kubectl, and kubeadm).
# The versions of the components to be installed are specified by the environment variable KUBERNETES_INSTALL_VERSION.
#
# Usage:
#   Ensure the environment variable KUBERNETES_INSTALL_VERSION is set to the desired version before running this script.
#
# Example:
#   export KUBERNETES_INSTALL_VERSION=1.21.0
#   ./common.sh
sudo apt-get update -y
sudo apt-get install -y kubelet="$KUBERNETES_INSTALL_VERSION" kubectl="$KUBERNETES_INSTALL_VERSION" kubeadm="$KUBERNETES_INSTALL_VERSION"

# This script prevents automatic updates for the Kubernetes components:
# kubelet, kubeadm, and kubectl by placing them on hold using the apt-mark command.
# Prevent automatic updates for kubelet, kubeadm, and kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# This script updates the package lists for upgrades and new package installations
# using the apt-get package manager. The -y option automatically answers 'yes' to
# any prompts, allowing the update to proceed without user intervention.
sudo apt-get update -y

# This script installs jq, a lightweight and flexible command-line JSON processor.
# jq is used for parsing, manipulating, and working with JSON data in shell scripts.
# The script uses apt-get to install jq with the -y flag to automatically confirm the installation.
# Install jq, a command-line JSON processor
sudo apt-get install -y jq

# Retrieves the local IP address of the ens33 interface and assigns it to the local_ip variable.
# This IP address is then used to configure the kubelet.
# 
# The command uses 'ip' to get the JSON representation of the network interfaces,
# 'jq' to parse the JSON and extract the IP address of the 'inet' family for the 'ens33' interface.
# Retrieve the local IP address of the eth0 interface and set it for kubelet
local_ip="$(ip --json addr show ens33 | jq -r '.[0].addr_info[] | select(.family == "inet") | .local')"

# This script writes the local IP address to the kubelet default configuration file.
# It uses a here document to create or overwrite the /etc/default/kubelet file with the
# KUBELET_EXTRA_ARGS environment variable set to the local IP address.
# The local IP address is expected to be stored in the variable $local_ip.
# Write the local IP address to the kubelet default configuration file
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF
