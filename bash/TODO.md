# Script: kvm-vm-provisioning.sh | Next Implementation

## High Priority (Next Session)
- [ ] Add TUI for user input (using `dialog` or `whiptail`)
- [ ] Add command-line argument parsing
- [ ] Add configuration file support

## Implementation Notes

### TUI Implementation
- Use `dialog` for interactive menus
- Provide defaults for all values
- Allow skipping interactive mode with env vars

### CLI Arguments
- Support `--name`, `--ip`, `--username` etc.
- Support `--config-file` for batch operations
- Support `--non-interactive` for automation

### Configuration File
- YAML format for readability
- Support multiple VM profiles
- Environment variable substitution