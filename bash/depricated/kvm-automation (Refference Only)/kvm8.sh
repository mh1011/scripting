#!/bin/bash
set -euo pipefail

# =========================
# Ubuntu 24.04 Cloud Image VM (Manjaro Host)
# =========================

# Configuration variables
VM_NAME="k8s-m1"
VM_IP="192.168.122.101"
VM_GATEWAY="192.168.122.1"
VM_NAMESERVERS="8.8.8.8,8.8.4.4"
ADMIN_USERNAME="admink8s"
VM_PASSWORD="admin123"
SSH_PUBKEY="$HOME/.ssh/K8s/rondollc.pub"
CLOUD_IMG="$ISO/noble-server-cloudimg-amd64.img"
DISK_DIR="$KVM/K8s"
DISK_PATH="$DISK_DIR/${VM_NAME}.qcow2"
DISK_SIZE="20G"
RAM_MB=4096
VCPUS=2
CLOUD_ISO="/tmp/autoinstall-config/${VM_NAME}-seed.iso"

# =========================
# Ensure required packages are installed (Manjaro)
# =========================
for pkg in qemu virt-manager virt-install cloud-image-utils whois; do
    if ! pacman -Qi $pkg &>/dev/null; then
        echo "Package $pkg not found. Installing..."
        sudo pacman -S --noconfirm $pkg
    fi
done

# =========================
# Clean up existing VM
# =========================
echo "Cleaning up any existing VM..."
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -f "$DISK_PATH" "$CLOUD_ISO"
rm -rf /tmp/autoinstall-config 2>/dev/null || true

mkdir -p "$DISK_DIR"

# =========================
# Create working QCOW2 disk from cloud image
# =========================
echo "Creating VM disk from cloud image..."
cp "$CLOUD_IMG" "$DISK_PATH"
qemu-img resize "$DISK_PATH" "$DISK_SIZE"

# =========================
# Create cloud-init config
# =========================
CLOUD_INIT_DIR="/tmp/autoinstall-config"
mkdir -p "$CLOUD_INIT_DIR"

# Generate a random MAC address to bind static IP properly
VM_MAC=$(printf '52:54:%02x:%02x:%02x:%02x\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))

# Read public key
PUBKEY=$(cat "$SSH_PUBKEY")

# user-data
cat > "$CLOUD_INIT_DIR/user-data" <<EOF
#cloud-config
hostname: $VM_NAME
manage_etc_hosts: true

users:
  - name: $ADMIN_USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: '$VM_PASSWORD'
    ssh_authorized_keys:
      - $PUBKEY

ssh_pwauth: true
chpasswd: { expire: false }

timezone: Asia/Dhaka

package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - openssh-server
  - vim
  - curl

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "Provisioned successfully" > /home/$ADMIN_USERNAME/READY.txt
EOF

# meta-data
cat > "$CLOUD_INIT_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# network-config (static IP using modern netplan syntax)
cat > "$CLOUD_INIT_DIR/network-config" <<EOF
version: 2
ethernets:
  enp1s0:
    match:
      macaddress: "$VM_MAC"
    dhcp4: false
    addresses: [$VM_IP/24]
    nameservers:
      addresses: [$VM_NAMESERVERS]
    routes:
      - to: 0.0.0.0/0
        via: $VM_GATEWAY
EOF

# Create cloud-init ISO
cloud-localds --network-config="$CLOUD_INIT_DIR/network-config" "$CLOUD_ISO" \
  "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"

# =========================
# Launch the VM
# =========================
echo "Starting VM using cloud image..."
virt-install \
  --connect qemu:///system \
  --name "$VM_NAME" \
  --ram "$RAM_MB" \
  --vcpus "$VCPUS" \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio \
  --disk path="$CLOUD_ISO",device=cdrom,readonly=on \
  --osinfo ubuntu24.04 \
  --network bridge=virbr0,model=virtio,mac="$VM_MAC" \
  --graphics spice \
  --console pty,target_type=serial \
  --import \
  --noautoconsole

# =========================
# Finished
# =========================
echo "============================================"
echo "VM $VM_NAME created successfully!"
echo "Static IP:    $VM_IP"
echo "Username:     $ADMIN_USERNAME"
echo "Password:     $VM_PASSWORD"
echo "SSH Key:      $SSH_PUBKEY"
echo "============================================"
echo "Connect via terminal: virsh console $VM_NAME"
echo "Or SSH after boot: ssh $ADMIN_USERNAME@$VM_IP"
