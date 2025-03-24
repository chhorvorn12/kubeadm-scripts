# Run Script

### 1. Allow permission for run script 

 * This script elevates the user to superuser (root) and changes the permissions
 * of all files and directories recursively in the current directory to 775.
 * 
 * Usage:
 * 1. Run the script with superuser privileges.
 * 2. The script will modify permissions for all files and directories in the current path.
 * 
 * Note:
 * - Ensure you have the necessary permissions to execute these commands.
 * - Be cautious when changing permissions, as it can affect the security and accessibility of files.

```
sudo su
chmod -R 775 .
```

### 2. Install on Master node
```
 ./common.sh
 ./master.sh
 ```
 
### 3. Install on Worker node 1

```
./common.sh
```
* Connect Worker node 1 to Master node


```
kubeadm token create --print-join-command
```
8Show
```
kubeadm join <your-server-master-node>:6443 <--token token-name> --discovery-token-ca-cert-hash ********
```

### 3. Install on Worker node 3

```
./common.sh
```
* Connect Worker node 1 to Master node


```
kubeadm token create --print-join-command
```
* Show
```
kubeadm join <your-server-master-node>:6443 <--token token-name> --discovery-token-ca-cert-hash ********
```