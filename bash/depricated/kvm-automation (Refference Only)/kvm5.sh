#!/bin/bash

# Configuration variables
VM_NAME="k8s-m1"
VM_IP="192.168.122.101"
VM_NETMASK="255.255.255.0"
VM_GATEWAY="192.168.122.1"
VM_NAMESERVERS="8.8.8.8 8.8.4.4"
VM_PASSWORD="admin123"
ADMIN_USERNAME="admink8s"
ISO_PATH="/Virtualization/Images/ISO/ubuntu-24.04.1-live-server-amd64.iso"
DISK_DIR="/Virtualization/KVM/K8s"
DISK_PATH="$DISK_DIR/${VM_NAME}.qcow2"
DISK_SIZE="20G"

# Clean up existing VM
echo "Cleaning up any existing VM..."
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -f "$DISK_PATH" 2>/dev/null || true
rm -f "/tmp/autoinstall.iso" 2>/dev/null || true

# Ensure directory exists
mkdir -p "$DISK_DIR"
chmod 755 "$DISK_DIR"

# Password encryption
encrypt_password() {
    local password="$1"
    echo "$password" | mkpasswd -s -m sha-512
}

echo "Encrypting password..."
ENCRYPTED_PASSWORD=$(encrypt_password "$VM_PASSWORD")

# Create autoinstall config directory
mkdir -p /tmp/autoinstall-config

# Create user-data
cat > /tmp/autoinstall-config/user-data << EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: $VM_NAME
    username: $ADMIN_USERNAME
    password: "$ENCRYPTED_PASSWORD"
  network:
    network:
      version: 2
      ethernets:
        ens3:
          dhcp4: false
          addresses: [$VM_IP/24]
          gateway4: $VM_GATEWAY
          nameservers:
            addresses: [$VM_NAMESERVERS]
  storage:
    layout:
      name: direct
  locale: en_US.UTF-8
  keyboard:
    layout: us
  timezone: Asia/Almaty
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - openssh-server
    - vim
    - curl
EOF

# Create meta-data
cat > /tmp/autoinstall-config/meta-data << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# Create cloud-init ISO
echo "Creating cloud-init ISO..."
genisoimage -output /tmp/autoinstall.iso -volid cidata -joliet -rock \
  /tmp/autoinstall-config/user-data /tmp/autoinstall-config/meta-data

# Create the disk
echo "Creating dynamic disk..."
qemu-img create -f qcow2 -o preallocation=off "$DISK_PATH" "$DISK_SIZE"

# Method 1: Direct kernel boot with autoinstall (Most reliable)
echo "Starting automated installation..."
virt-install \
  --name "$VM_NAME" \
  --ram 4096 \
  --vcpus 2 \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio \
  --os-type linux \
  --os-variant ubuntu24.04 \
  --network bridge=virbr0 \
  --graphics none \
  --console pty,target_type=serial \
  --location "$ISO_PATH,kernel=casper/vmlinuz,initrd=casper/initrd" \
  --extra-args "ip=dhcp url=$ISO_PATH autoinstall ds=nocloud-net;s=/cdrom/ console=ttyS0,115200n8 serial" \
  --disk path=/tmp/autoinstall.iso,device=cdrom \
  --noautoconsole

echo "============================================"
echo "Autoinstall Provisioning Started!"
echo "============================================"
echo "VM Name:      $VM_NAME"
echo "IP Address:   $VM_IP"
echo "Username:     $ADMIN_USERNAME"
echo "============================================"
echo "Monitor with: virsh console $VM_NAME"
echo "Check disk growth: watch -n 10 'qemu-img info $DISK_PATH'"