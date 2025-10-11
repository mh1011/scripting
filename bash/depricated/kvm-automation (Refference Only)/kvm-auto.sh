#!/bin/bash
set -e

# ========= CONFIG =========
#VM_NAME=${1:-ubuntu2404}             # Pass VM name as first arg, default = ubuntu2404
VM_NAME=k8s-m1
RAM=4096                             # RAM in MB
VCPUS=2                              # CPU cores
DISK_SIZE=20                         # Disk size in GB
VM_PATH="/run/media/mh1011/Storage/Work/Virtualization/KVM/k8s"    # Where VM disks are stored
CLOUD_IMG="noble-server-cloudimg-amd64.img"
CLOUD_IMG_URL="https://cloud-images.ubuntu.com/noble/current/${CLOUD_IMG}"

# Clean up existing VM
if virsh list --all --name | grep -q "^${VM_NAME}$"; then
    echo "Cleaning up existing VM..."
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    sleep 2
fi

# ========= PREPARE =========
echo "[*] Creating VM: $VM_NAME"
mkdir -p "$VM_PATH/$VM_NAME"

# Download cloud image if missing
if [ ! -f "$VM_PATH/$CLOUD_IMG" ]; then
  echo "[*] Downloading Ubuntu 24.04 Cloud Image..."
  wget -O "$VM_PATH/$CLOUD_IMG" "$CLOUD_IMG_URL"
fi

# Create VM disk from base image
echo "[*] Creating QCOW2 disk..."
qemu-img create -f qcow2 -F qcow2 -b "$VM_PATH/$CLOUD_IMG" \
  "$VM_PATH/$VM_NAME/${VM_NAME}.qcow2" ${DISK_SIZE}G

# ========= CLOUD-INIT CONFIG =========
echo "[*] Creating cloud-init config..."

# Generate hashed password: mkpasswd --method=SHA-512
PASSWORD_HASH='$6$rounds=4096$abcxyz$8Imd...replace_me...'

cat > "$VM_PATH/$VM_NAME/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ${VM_NAME}
    username: devops
    password: "${PASSWORD_HASH}"
  ssh:
    install-server: true
  packages:
    - qemu-guest-agent
EOF

cat > "$VM_PATH/$VM_NAME/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

cloud-localds "$VM_PATH/$VM_NAME/seed.iso" \
  "$VM_PATH/$VM_NAME/user-data" "$VM_PATH/$VM_NAME/meta-data"

# genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data


# ========= CREATE VM =========
echo "[*] Installing VM with virt-install..."
virt-install \
  --name "$VM_NAME" \
  --memory $RAM \
  --vcpus $VCPUS \
  --disk path="$VM_PATH/$VM_NAME/${VM_NAME}.qcow2",format=qcow2 \
  --disk path="$VM_PATH/$VM_NAME/seed.iso",device=cdrom \
  --import \
  --os-variant ubuntu24.04 \
  --network bridge=virbr0 \
  --graphics none \
  --noautoconsole

echo "[+] VM $VM_NAME created successfully!"
