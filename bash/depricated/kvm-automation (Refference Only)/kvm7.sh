#!/bin/bash

# Configuration variables
VM_NAME="k8s-m1"
VM_IP="192.168.122.101"
VM_NETMASK="255.255.255.0"
VM_GATEWAY="192.168.122.1"
VM_NAMESERVERS="8.8.8.8 8.8.4.4"
VM_PASSWORD="admin123"
ADMIN_USERNAME="admink8s"
ISO_PATH="/run/media/mh1011/Storage/Work/Virtualization/Images/ISO/ubuntu-24.04.1-live-server-amd64.iso"
DISK_DIR="/run/media/mh1011/Storage/Work/Virtualization/KVM/K8s"
DISK_PATH="$DISK_DIR/${VM_NAME}.qcow2"

# Clean up existing VM
echo "Cleaning up any existing VM..."
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -f "$DISK_PATH" 2>/dev/null || true
rm -f "/tmp/cloud-init.iso" 2>/dev/null || true

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

# Create cloud-init config directory
CLOUD_INIT_DIR="/tmp/cloud-init"
mkdir -p "$CLOUD_INIT_DIR"

# Create user-data
cat > "$CLOUD_INIT_DIR/user-data" << EOF
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
cat > "$CLOUD_INIT_DIR/meta-data" << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# Create cloud-init ISO
echo "Creating cloud-init ISO..."
genisoimage -output "/tmp/cloud-init.iso" -volid cidata -joliet -rock \
  "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"

echo "Cloud-init ISO created successfully"

# Create the disk
echo "Creating dynamic disk..."
qemu-img create -f qcow2 -o preallocation=off "$DISK_PATH" 20G

# Extract kernel and initrd from ISO
echo "Extracting kernel and initrd from ISO..."
mkdir -p /tmp/iso-mount
sudo mount -o loop "$UBUNTU_ISO" /tmp/iso-mount
cp /tmp/iso-mount/casper/vmlinuz /tmp/vmlinuz
cp /tmp/iso-mount/casper/initrd /tmp/initrd
sudo umount /tmp/iso-mount

# Create the VM with direct kernel boot
echo "Starting installation with direct kernel boot..."
virt-install \
  --name "$VM_NAME" \
  --ram 4096 \
  --vcpus 2 \
  --disk "path=$DISK_PATH,format=qcow2,bus=virtio" \
  --initrd-inject "$CLOUD_INIT_DIR/user-data" \
  --initrd-inject "$CLOUD_INIT_DIR/meta-data" \
  --os-variant ubuntu24.04 \
  --network bridge=virbr0 \
  --graphics none \
  --kernel /tmp/vmlinuz \
  --initrd /tmp/initrd \
  --extra-args "autoinstall ds=nocloud-net;s=/cdrom/ console=ttyS0,115200n8 serial" \
  --noautoconsole

echo "============================================"
echo "Installation Started!"
echo "============================================"
echo "VM Name:    $VM_NAME"
echo "VM IP:      $VM_IP"
echo "Username:   $ADMIN_USERNAME"
echo "============================================"