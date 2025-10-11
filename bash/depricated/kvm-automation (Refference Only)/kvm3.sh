#!/bin/bash

# Configuration variables
VM_NAME="k8s-m1"
VM_IP="192.168.122.101"
VM_NETMASK="255.255.255.0"
VM_GATEWAY="192.168.122.1"
VM_NAMESERVERS="8.8.8.8 8.8.4.4"
ADMIN_USERNAME="rondollc"
VM_PASSWORD="Rondo@123#"
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

# Generate encrypted password
encrypt_password() {
    local password="$1"
    if command -v mkpasswd >/dev/null 2>&1; then
        echo "$password" | mkpasswd -s -m sha-512
    else
        echo "WARNING: Password encryption failed, using plaintext" >&2
        echo "$password"
    fi
}

ENCRYPTED_PASSWORD=$(encrypt_password "$VM_PASSWORD")

# Create autoinstall user-data file
cat > /tmp/user-data << EOF
#cloud-config
autoinstall:
  version: 1
  
  # Identity and user configuration
  identity:
    hostname: $VM_NAME
    username: $ADMIN_USERNAME
    password: "$ENCRYPTED_PASSWORD"
  
  # Network configuration
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
  
  # Storage configuration
  storage:
    layout:
      name: direct
  
  # Localization
  locale: en_US.UTF-8
  keyboard:
    layout: us
  timezone: Asia/Almaty
  
  # SSH configuration
  ssh:
    install-server: true
    allow-pw: true
  
  # Packages to install
  packages:
    - openssh-server
    - vim
    - curl
    - tree
    - net-tools
    - docker.io
  
  # User setup (additional user configuration)
  user-data:
    users:
      - name: $ADMIN_USERNAME
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        groups: [adm, cdrom, sudo, dip, plugdev, docker]
  
  # Late commands (run after installation)
  late-commands:
    - |
        cat > /target/etc/motd << MOTD_EOF
        ============================================
        =           Kubernetes Node               =
        = Hostname: $VM_NAME                     =
        = IP: $VM_IP                             =
        = User: $ADMIN_USERNAME                   =
        ============================================
MOTD_EOF
    - curtin in-target --target /target -- systemctl enable docker
    - curtin in-target --target /target -- usermod -aG docker $ADMIN_USERNAME
    - curtin in-target --target /target -- hostnamectl set-hostname $VM_NAME
    - curtin in-target --target /target -- sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
EOF

# Create meta-data file
cat > /tmp/meta-data << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# Create the disk
echo "Creating dynamic disk..."
qemu-img create -f qcow2 -o preallocation=off "$DISK_PATH" "$DISK_SIZE"

# Create the VM with autoinstall
echo "Starting automated installation..."
virt-install \
  --name "$VM_NAME" \
  --ram 4096 \
  --vcpus 2 \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio \
  --os-variant ubuntu24.04 \
  --location "$ISO_PATH,kernel=casper/vmlinuz,initrd=casper/initrd" \
  --network bridge=virbr0 \
  --graphics none \
  --console pty,target_type=serial \
  --initrd-inject /tmp/user-data \
  --initrd-inject /tmp/meta-data \
  --extra-args "autoinstall ds=nocloud-net;s=/cdrom/ console=ttyS0,115200n8 serial"

echo "============================================"
echo "Autoinstall Provisioning Started!"
echo "============================================"
echo "VM Name:      $VM_NAME"
echo "IP Address:   $VM_IP"
echo "Gateway:      $VM_GATEWAY"
echo "DNS:          $VM_NAMESERVERS"
echo "Username:     $ADMIN_USERNAME"
echo "Password:     $VM_PASSWORD"
echo "============================================"