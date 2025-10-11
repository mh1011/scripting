#!/bin/bash
set -euo pipefail

# =====================================================================
# Ubuntu Cloud Image VM Provisioning Script | Current task
# Version: 1.3.0
# =====================================================================
#
# CHANGELOG:
# v1.3.0 - Oct 11, 2025
#   - Added file logging with timestamps
#   - Added desktop notifications
#   - Added automatic ISO ejection after installation
#   - Added temporary file cleanup
#   - Improved error handling and resource management
#
# v1.2.0 - Oct 11, 2025
#   - Fixed netplan syntax (routes instead of deprecated gateway4)
#   - Added feature flag system
#   - Improved error handling and logging
#
# v1.1.0 - Oct 10, 2025 
#   - Added Docker installation and user group configuration
#   - Added SSH key support with proper fallback handling
#   - Added MAC address binding for static IP
#
# v1.0.0 - Oct 03, 2025
#   - Initial working version with cloud-init
#   - Basic VM provisioning with static IP
#   - User creation and package installation
#
# FEATURE ROADMAP:
# [ ] TUI for user input configuration
# [ ] Command-line argument parsing
# [ ] Configuration file support
# [ ] Multi-VM cluster creation
# [ ] Health monitoring and alerts
#
# =====================================================================

# =========================
# FEATURE CONFIGURATION
# =========================
readonly SCRIPT_VERSION="1.3.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Feature flags (set to false to disable)
ENABLE_DOCKER=true
ENABLE_EXTRA_PACKAGES=true
ENABLE_QEMU_GUEST_AGENT=true
ENABLE_SECURITY_BASICS=true
ENABLE_MOTD_CUSTOMIZATION=true
ENABLE_NOTIFICATIONS=true
ENABLE_AUTO_CLEANUP=true

# =========================
# CORE CONFIGURATION
# =========================
VM_NAME="k8s-m1"
VM_IP="192.168.122.101"
VM_GATEWAY="192.168.122.1"
VM_NAMESERVERS="8.8.8.8,8.8.4.4"
ADMIN_USERNAME="admink8s"
VM_PASSWORD="admin123"
SSH_PUBKEY="/home/$USER/.ssh/K8s/rondollc.pub"
CLOUD_IMG="$ISO/noble-server-cloudimg-amd64.img"
DISK_DIR="$KVM/K8s"
DISK_PATH="$DISK_DIR/${VM_NAME}.qcow2"
DISK_SIZE="20G"
RAM_MB=4096
VCPUS=2

# =========================
# PATHS AND LOGGING
# =========================
LOG_DIR="$HOME/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${VM_NAME}_installation.log"
CLOUD_INIT_DIR="/tmp/autoinstall-config-${VM_NAME}"
CLOUD_ISO="/tmp/${VM_NAME}-seed.iso"

# =========================
# LOGGING AND NOTIFICATION
# =========================
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

log_error() {
    log_message "ERROR: $1"
    send_notification "error" "VM Provisioning Error" "$1"
}

log_success() {
    log_message "SUCCESS: $1"
    send_notification "success" "VM Provisioning" "$1"
}

log_warning() {
    log_message "WARNING: $1"
    send_notification "warning" "VM Provisioning Warning" "$1"
}

send_notification() {
    local type="$1"
    local title="$2"
    local message="$3"
    
    if [ "$ENABLE_NOTIFICATIONS" = "true" ]; then
        case "$type" in
            "error")
                notify-send -u critical -i dialog-error "$title" "$message" 2>/dev/null || true
                ;;
            "warning")
                notify-send -u normal -i dialog-warning "$title" "$message" 2>/dev/null || true
                ;;
            "success")
                notify-send -u low -i dialog-information "$title" "$message" 2>/dev/null || true
                ;;
            *)
                notify-send -u low "$title" "$message" 2>/dev/null || true
                ;;
        esac
    fi
}

# =========================
# CLEANUP FUNCTIONS
# =========================
cleanup_resources() {
    log_message "Cleaning up temporary resources..."
    
    # Remove cloud-init ISO if it exists
    if [ -f "$CLOUD_ISO" ]; then
        rm -f "$CLOUD_ISO"
        log_message "Removed cloud-init ISO: $CLOUD_ISO"
    fi
    
    # Remove cloud-init config directory
    if [ -d "$CLOUD_INIT_DIR" ]; then
        rm -rf "$CLOUD_INIT_DIR"
        log_message "Removed cloud-init config directory: $CLOUD_INIT_DIR"
    fi
    
    # Clean up any other temporary files
    find "/tmp" -name "*${VM_NAME}*" -type f -delete 2>/dev/null || true
}

eject_seed_iso() {
    log_message "Attempting to eject seed ISO from VM..."
    
    # Wait a bit for cloud-init to complete
    sleep 30
    
    # Try to detach the ISO
    if virsh domstate "$VM_NAME" | grep -q "running"; then
        if virsh domblklist "$VM_NAME" | grep -q "seed.iso"; then
            virsh detach-disk "$VM_NAME" "$CLOUD_ISO" --persistent 2>/dev/null && \
            log_message "Successfully ejected seed ISO from VM" || \
            log_warning "Could not eject seed ISO (may need manual ejection)"
        else
            log_message "Seed ISO not found attached to VM"
        fi
    else
        log_warning "VM is not running, cannot eject ISO"
    fi
}

cleanup_on_exit() {
    local exit_code=$?
    
    if [ "$ENABLE_AUTO_CLEANUP" = "true" ]; then
        cleanup_resources
    fi
    
    if [ $exit_code -eq 0 ]; then
        log_success "Script completed successfully"
    else
        log_error "Script failed with exit code $exit_code"
    fi
    
    exit $exit_code
}

# Set up cleanup trap
trap cleanup_on_exit EXIT

# =========================
# DEPENDENCY CHECKS
# =========================
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Missing dependency: $1"
        return 1
    fi
}

check_all_dependencies() {
    log_message "Checking system dependencies..."
    
    local deps=("virt-install" "qemu-img" "cloud-localds" "virsh")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! check_dependency "$dep"; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_message "Install with: sudo pacman -S qemu virt-manager cloud-image-utils"
        return 1
    fi
    
    # Check for notify-send if notifications are enabled
    if [ "$ENABLE_NOTIFICATIONS" = "true" ] && ! command -v notify-send &> /dev/null; then
        log_warning "notify-send not found, desktop notifications disabled"
        ENABLE_NOTIFICATIONS=false
    fi
    
    log_success "All dependencies satisfied"
}

# =========================
# VALIDATION FUNCTIONS
# =========================
validate_configuration() {
    log_message "Validating configuration..."
    
    # Check if cloud image exists
    if [ ! -f "$CLOUD_IMG" ]; then
        log_error "Cloud image not found: $CLOUD_IMG"
        return 1
    fi
    
    # Check if SSH key exists (if specified)
    if [ -n "$SSH_PUBKEY" ] && [ ! -f "$SSH_PUBKEY" ]; then
        log_warning "SSH public key not found: $SSH_PUBKEY (will use password only)"
    fi
    
    # Validate IP address format (basic check)
    if ! echo "$VM_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'; then
        log_error "Invalid IP address format: $VM_IP (should be like 192.168.1.100/24)"
        return 1
    fi
    
    log_success "Configuration validation passed"
}

# =========================
# VM MANAGEMENT FUNCTIONS
# =========================
cleanup_existing_vm() {
    log_message "Checking for existing VM..."
    
    if virsh list --all --name | grep -q "^${VM_NAME}$"; then
        log_message "Found existing VM '$VM_NAME', cleaning up..."
        
        # Destroy if running
        if virsh domstate "$VM_NAME" | grep -q "running"; then
            virsh destroy "$VM_NAME"
            log_message "Stopped running VM"
        fi
        
        # Undefine VM
        virsh undefine "$VM_NAME" --remove-all-storage
        log_message "Removed VM definition"
        
        # Remove disk file if it exists
        if [ -f "$DISK_PATH" ]; then
            rm -f "$DISK_PATH"
            log_message "Removed existing disk: $DISK_PATH"
        fi
    else
        log_message "No existing VM found with name: $VM_NAME"
    fi
    
    # Ensure directory exists
    mkdir -p "$DISK_DIR"
}

create_vm_disk() {
    log_message "Creating VM disk from cloud image..."
    
    if ! cp "$CLOUD_IMG" "$DISK_PATH"; then
        log_error "Failed to copy cloud image to $DISK_PATH"
        return 1
    fi
    
    if ! qemu-img resize "$DISK_PATH" "$DISK_SIZE"; then
        log_error "Failed to resize disk to $DISK_SIZE"
        return 1
    fi
    
    log_success "VM disk created: $DISK_PATH ($DISK_SIZE)"
}

generate_cloud_init_config() {
    log_message "Generating cloud-init configuration..."
    
    mkdir -p "$CLOUD_INIT_DIR"
    
    # Generate MAC address
    local VM_MAC=$(printf '52:54:%02x:%02x:%02x:%02x\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    
    # Read SSH public key
    local PUBKEY=""
    if [ -f "$SSH_PUBKEY" ]; then
        PUBKEY=$(cat "$SSH_PUBKEY")
        log_message "Using SSH key: $SSH_PUBKEY"
    else
        log_warning "SSH public key not found at $SSH_PUBKEY (using password authentication only)"
    fi

    # Generate user-data
    cat > "$CLOUD_INIT_DIR/user-data" <<EOF
#cloud-config
# Generated by ${SCRIPT_NAME} v${SCRIPT_VERSION}
hostname: $VM_NAME
manage_etc_hosts: true

users:
  - name: $ADMIN_USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: '$VM_PASSWORD'
$([ -n "$PUBKEY" ] && echo "    ssh_authorized_keys:" && echo "      - $PUBKEY")

ssh_pwauth: true
chpasswd: { expire: false }

timezone: Asia/Dhaka

package_update: true
package_upgrade: true
packages:
  - openssh-server
  - vim
  - curl
$([ "$ENABLE_QEMU_GUEST_AGENT" = "true" ] && echo "  - qemu-guest-agent")
$([ "$ENABLE_DOCKER" = "true" ] && echo "  - docker.io")
$([ "$ENABLE_EXTRA_PACKAGES" = "true" ] && echo "  - net-tools" && echo "  - htop" && echo "  - tree")

runcmd:
$([ "$ENABLE_QEMU_GUEST_AGENT" = "true" ] && echo "  - systemctl enable qemu-guest-agent" && echo "  - systemctl start qemu-guest-agent")
$([ "$ENABLE_DOCKER" = "true" ] && echo "  - systemctl enable docker" && echo "  - usermod -aG docker $ADMIN_USERNAME")
$([ "$ENABLE_MOTD_CUSTOMIZATION" = "true" ] && echo "  - echo 'Kubernetes Node: $VM_NAME ($VM_IP)' > /etc/motd")
  - echo "Provisioned by ${SCRIPT_NAME} v${SCRIPT_VERSION} on $(date)" > /home/$ADMIN_USERNAME/PROVISIONED.txt

final_message: "VM $VM_NAME v${SCRIPT_VERSION} is ready! Connect: ssh $ADMIN_USERNAME@${VM_IP%%/*}"
EOF

    # Generate meta-data
    cat > "$CLOUD_INIT_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

    # Generate network-config
    cat > "$CLOUD_INIT_DIR/network-config" <<EOF
version: 2
ethernets:
  enp1s0:
    match:
      macaddress: "$VM_MAC"
    dhcp4: false
    addresses: [$VM_IP]
    routes:
      - to: default
        via: $VM_GATEWAY
    nameservers:
      addresses: [$VM_NAMESERVERS]
EOF
}

create_cloud_init_iso() {
    log_message "Creating cloud-init ISO..."
    
    if ! cloud-localds --network-config="$CLOUD_INIT_DIR/network-config" \
        "$CLOUD_ISO" \
        "$CLOUD_INIT_DIR/user-data" \
        "$CLOUD_INIT_DIR/meta-data"; then
        log_error "Failed to create cloud-init ISO"
        return 1
    fi
    
    log_success "Cloud-init ISO created: $CLOUD_ISO"
}

launch_vm() {
    log_message "Launching VM..."
    
    # Get MAC address from network config
    local VM_MAC=$(grep "macaddress" "$CLOUD_INIT_DIR/network-config" | cut -d'"' -f2)
    
    if ! virt-install \
        --connect qemu:///system \
        --name "$VM_NAME" \
        --ram "$RAM_MB" \
        --vcpus "$VCPUS" \
        --disk path="$DISK_PATH",format=qcow2,bus=virtio \
        --disk path="$CLOUD_ISO",device=cdrom,readonly=on \
        --osinfo ubuntu24.04 \
        --network bridge=virbr0,model=virtio,mac="$VM_MAC" \
        --graphics none \
        --console pty,target_type=serial \
        --import \
        --noautoconsole; then
        log_error "Failed to launch VM"
        return 1
    fi
    
    log_success "VM launched successfully"
}

wait_for_vm_boot() {
    log_message "Waiting for VM to boot and cloud-init to complete..."
    log_message "This may take 2-3 minutes..."
    
    # Start ISO ejection in background
    if [ "$ENABLE_AUTO_CLEANUP" = "true" ]; then
        eject_seed_iso &
    fi
    
    log_message "VM is starting up. Check progress with: virsh console $VM_NAME"
    log_message "Or wait for cloud-init to complete and connect via SSH"
}

display_success_message() {
    local ip_without_cidr="${VM_IP%%/*}"
    
    log_success "VM provisioning process completed!"
    echo "============================================"
    echo "PROVISIONING SUMMARY"
    echo "============================================"
    echo "VM Name:          $VM_NAME"
    echo "IP Address:       $ip_without_cidr"
    echo "Username:         $ADMIN_USERNAME"
    echo "Script Version:   v$SCRIPT_VERSION"
    echo "Log File:         $LOG_FILE"
    echo "============================================"
    echo "NEXT STEPS:"
    echo "1. Wait for cloud-init to complete (2-3 minutes)"
    echo "2. Connect via SSH: ssh $ADMIN_USERNAME@$ip_without_cidr"
    echo "3. Check console: virsh console $VM_NAME"
    echo "4. View logs: tail -f $LOG_FILE"
    echo "============================================"
}

# =========================
# MAIN EXECUTION
# =========================
main() {
    log_message "=== Starting VM Provisioning (v${SCRIPT_VERSION}) ==="
    
    # Log configuration
    log_message "Configuration:"
    log_message "  VM Name: $VM_NAME"
    log_message "  VM IP: $VM_IP"
    log_message "  Username: $ADMIN_USERNAME"
    log_message "  Disk: $DISK_PATH ($DISK_SIZE)"
    
    # Run provisioning steps
    check_all_dependencies || exit 1
    validate_configuration || exit 1
    cleanup_existing_vm
    create_vm_disk || exit 1
    generate_cloud_init_config || exit 1
    create_cloud_init_iso || exit 1
    launch_vm || exit 1
    wait_for_vm_boot
    display_success_message
}

# Run main function
main "$@"