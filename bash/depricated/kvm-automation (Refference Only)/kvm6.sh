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
DISK_SIZE="20G"

# Clean up existing VM
echo "Cleaning up any existing VM..."
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -f "$DISK_PATH" 2>/dev/null || true

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

# Create a custom ISO with autoinstall files
CUSTOM_ISO_DIR="/tmp/custom-iso"
mkdir -p "$CUSTOM_ISO_DIR"

# Copy Ubuntu ISO contents (we'll extract them)
echo "Extracting Ubuntu ISO contents..."
sudo mount -o loop "$ISO_PATH" /mnt
cp -r /mnt/* "$CUSTOM_ISO_DIR"/
sudo umount /mnt

# Add autoinstall files to the custom ISO
mkdir -p "$CUSTOM_ISO_DIR/server"
cat > "$CUSTOM_ISO_DIR/server/user-data" << EOF
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
  timezone: Asia/Dhaka
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - openssh-server
    - vim
    - curl
EOF

# Create meta-data
cat > "$CUSTOM_ISO_DIR/server/meta-data" << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# Create custom ISO
CUSTOM_ISO_PATH="/tmp/ubuntu-autoinstall.iso"
genisoimage -o "$CUSTOM_ISO_PATH" -r -J -V "Ubuntu Auto Install" \
  -b isolinux/isolinux.bin -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table "$CUSTOM_ISO_DIR"

# Create the disk
echo "Creating dynamic disk..."
qemu-img create -f qcow2 -o preallocation=off "$DISK_PATH" "$DISK_SIZE"

# Create VM with single custom ISO
virt-install \
  --name "$VM_NAME" \
  --ram 4096 \
  --vcpus 2 \
  --disk "path=$DISK_PATH,size=20,format=qcow2,bus=virtio" \
  --cdrom "$CUSTOM_ISO_PATH" \
  --os-variant ubuntu24.04 \
  --network bridge=virbr0 \
  --graphics none \
  --noautoconsole

echo "============================================"
echo "Autoinstall Provisioning Started!"
echo "============================================"
echo "VM Name:      $VM_NAME"
echo "IP Address:   $VM_IP"
echo "Username:     $ADMIN_USERNAME"
echo "============================================"
echo "Wait 2 minutes, then check:"
echo "  virsh console $VM_NAME"
echo "  qemu-img info $DISK_PATH"