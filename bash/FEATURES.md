# Script: kvm-vm-provisioning.sh | Feature Tracker

## Backlog
- [ ] Add TUI for user input
- [ ] Add command-line argument parsing
- [ ] Add configuration file support

## In Progress
- [ ] Eject seed ISO after installation
- [ ] Clean up /tmp resources
- [ ] Enhanced logging system
- [ ] Desktop notifications

## Completed
- [x] Basic cloud-init VM provisioning
- [x] Static IP configuration
- [ ] Docker installation
- [x] Feature flag system

## Feature Details

### High Priority
1. **Eject seed ISO** - Remove cloud-init ISO after first boot
2. **Cleanup /tmp** - Auto-clean temporary files
3. **Enhanced logging** - File logging with timestamps
4. **Desktop notifications** - User notifications

### Medium Priority  
5. **User input** - Interactive TUI for configuration
6. **Config file** - External configuration file support
7. **CLI arguments** - Command-line option parsing

### Low Priority
8. **Multiple VMs** - Batch VM creation
9. **Health checks** - Post-installation verification
10. **Backup/restore** - VM snapshot functionality