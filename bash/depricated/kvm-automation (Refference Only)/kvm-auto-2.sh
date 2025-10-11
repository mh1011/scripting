#!/bin/bash

# Configuration variables
VM_NAME="k8s-m1"
VM_IP="192.168.22.101"
VM_NETMASK="255.255.255.0"
VM_GATEWAY="192.168.22.1"
VM_NAMESERVERS="8.8.8.8,8.8.4.4"
VM_PASSWORD="admin123"
ADMIN_USERNAME="admink8s"
ISO_PATH="/run/media/mh1011/Storage/Work/Virtualization/Images/ISO/ubuntu-24.04.1-live-server-amd64.iso"
DISK_DIR="/run/media/mh1011/Storage/Work/Virtualization/KVM/k8s"
DISK_PATH="$DISK_DIR/${VM_NAME}.qcow2"
DISK_SIZE="20G"

# Ensure virt-builder is installed
if ! command -v virt-builder &> /dev/null; then
    echo "virt-builder not found. Installing..."
    sudo pacman -S --noconfirm libguestfs
fi

# Clean up existing VM
echo "Cleaning up any existing VM..."
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
rm -f "$DISK_PATH" 2>/dev/null || true

# Ensure directory exists
sudo mkdir -p "$DISK_DIR"
sudo chmod 755 "$DISK_DIR"

# Create network configuration script
cat > /tmp/network-config.sh << EOF
#!/bin/bash
# Configure static IP
cat > /etc/netplan/01-netcfg.yaml << NETPLAN_EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses: [$VM_IP/24]
      gateway4: $VM_GATEWAY
      nameservers:
        addresses: [$VM_NAMESERVERS]
NETPLAN_EOF

# Apply network configuration
netplan apply

# Update hosts file
echo "$VM_IP $VM_NAME" >> /etc/hosts
hostnamectl set-hostname $VM_NAME

# Enable password authentication for SSH
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/#PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
EOF

chmod +x /tmp/network-config.sh

# Create the disk manually first 
#qemu-img create -f qcow2 -o preallocation=off $DISK_PATH $DISK_SIZE

# Build the VM image with virt-builder
echo "Building VM image with virt-builder..."
virt-builder ubuntu-24.04 \
  --format qcow2 \
  --size "$DISK_SIZE" \
  --output "$DISK_PATH" \
  --hostname "$VM_NAME" \
  --password "password:$VM_PASSWORD" \
  --firstboot /tmp/network-config.sh \
  --install openssh-server,vim,curl,tree,net-tools,docker.io \
  --run-command "useradd -m -s /bin/bash -G sudo $ADMIN_USERNAME" \
  --run-command "echo '$ADMIN_USERNAME:$VM_PASSWORD' | chpasswd" \
  --run-command "echo '$ADMIN_USERNAME ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/90-$ADMIN_USERNAME" \
  --run-command "chmod 0440 /etc/sudoers.d/90-$ADMIN_USERNAME" \
  --run-command "systemctl enable docker"

# Create the VM definition
echo "Creating VM definition..."
virt-install \
  --name "$VM_NAME" \
  --memory 4096 \
  --vcpus 2 \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio \
  --import \
  --os-variant ubuntu24.04 \
  --network bridge=virbr0 \
  --graphics none \
  --console pty,target_type=serial \
  --noautoconsole

# Cleanup
rm -f /tmp/network-config.sh

echo "============================================"
echo "VM Provisioning Completed!"
echo "============================================"
echo "VM Name:      $VM_NAME"
echo "IP Address:   $VM_IP"
echo "Username:     $ADMIN_USERNAME"
echo "Password:     $VM_PASSWORD"
echo "SSH Access:   ssh $ADMIN_USERNAME@$VM_IP"
echo "============================================"