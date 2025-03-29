#!/bin/bash
#
# Setup for Control Plane (Master) servers

# This script is located at ~/k8s/kubeadm-scripts/scripts/master.sh
# It sets the following shell options:
# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error and exit immediately.
# -x: Print commands and their arguments as they are executed.
# -o pipefail: Return the exit status of the last command in the pipeline that failed.
set -euxo pipefail

# If you need public access to API server using the servers Public IP adress, change PUBLIC_IP_ACCESS to true.

# This script is used for configuring a Kubernetes master node.
# 
# Variables:
# PUBLIC_IP_ACCESS: A flag to determine if the master node should be accessible via public IP. Default is "false".
# NODENAME: The short hostname of the current machine.
# POD_CIDR: The CIDR range for the Kubernetes pods network. Default is "192.168.0.0/16".
PUBLIC_IP_ACCESS="false"
NODENAME=$(hostname -s)
POD_CIDR="192.168.0.0/16"

# This script pulls the required container images for Kubernetes using kubeadm.
# It ensures that all necessary images are downloaded to the local machine before initializing the Kubernetes cluster.
sudo kubeadm config images pull

# Initialize kubeadm based on PUBLIC_IP_ACCESS

# This script initializes a Kubernetes master node using kubeadm.
# It checks the value of the PUBLIC_IP_ACCESS variable to determine whether to use a private or public IP address for the master node.
#
# If PUBLIC_IP_ACCESS is "false":
# - It retrieves the private IP address of the ens33 network interface.
# - It runs kubeadm init with the private IP address as the apiserver-advertise-address and apiserver-cert-extra-sans.
#
# If PUBLIC_IP_ACCESS is "true":
# - It retrieves the public IP address using the curl command.
# - It runs kubeadm init with the public IP address as the control-plane-endpoint and apiserver-cert-extra-sans.
#
# If PUBLIC_IP_ACCESS has any other value:
# - It prints an error message and exits with a status code of 1.
#
# The script also uses the following variables:
# - POD_CIDR: The CIDR range for the pod network.
# - NODENAME: The name of the node.
#
# Note: The script ignores preflight errors related to Swap.
if [[ "$PUBLIC_IP_ACCESS" == "false" ]]; then
    MASTER_PRIVATE_IP=$(ip addr show ens33 | awk '/inet / {print $2}' | cut -d/ -f1)
    sudo kubeadm init --apiserver-advertise-address="$MASTER_PRIVATE_IP" --apiserver-cert-extra-sans="$MASTER_PRIVATE_IP" --pod-network-cidr="$POD_CIDR" --node-name "$NODENAME" --ignore-preflight-errors Swap
elif [[ "$PUBLIC_IP_ACCESS" == "true" ]]; then
    MASTER_PUBLIC_IP=$(curl ifconfig.me && echo "")
    sudo kubeadm init --control-plane-endpoint="$MASTER_PUBLIC_IP" --apiserver-cert-extra-sans="$MASTER_PUBLIC_IP" --pod-network-cidr="$POD_CIDR" --node-name "$NODENAME" --ignore-preflight-errors Swap
else
    echo "Error: MASTER_PUBLIC_IP has an invalid value: $PUBLIC_IP_ACCESS"
    exit 1
fi

# Configure kubeconfig

mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

# Install Claico Network Plugin Network 

kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml


# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/metallb.yaml

# Configure MetalLB with a Layer 2 configuration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.1.240-192.168.1.250
EOF

# Install Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

# Wait for Nginx Ingress Controller to be fully deployed
echo "Waiting for Nginx Ingress Controller to be fully deployed..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

# Create an Ingress Resource
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
EOF
echo "success."

