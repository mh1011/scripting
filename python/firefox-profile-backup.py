#!/usr/bin/env python3

import os
import sys
import subprocess
import platform
import argparse
import shutil
import hashlib
from datetime import datetime
from pathlib import Path
import logging
from typing import List, Tuple
import time
import threading

class FirefoxProfileBackup:
    def __init__(self):
        self.os_type = self.detect_os()
        self.verbose = False
        self.backup_date = datetime.now().strftime("_%d%b%Y-%H:%M")
        self.log_file = Path.home() / "firefox_backup.log"
        self.setup_logging()
        self.setup_directories()
        
    def setup_logging(self):
        """Setup logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(self.log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
    
    def detect_os(self):
        """Detect the operating system"""
        system = platform.system().lower()
        if system == "linux":
            return "linux"
        elif system == "darwin":
            return "macos"
        elif system == "windows":
            return "windows"
        else:
            return "unknown"
    
    def setup_directories(self):
        """Set up OS-specific directories"""
        if self.os_type == "linux":
            self.profile_directory = Path.home() / ".mozilla" / "firefox"
        elif self.os_type == "windows":
            appdata = os.environ.get('APPDATA', '')
            self.profile_directory = Path(appdata) / "Mozilla" / "Firefox" / "Profiles"
        elif self.os_type == "macos":
            self.profile_directory = Path.home() / ".mozilla" / "firefox"
        else:
            raise Exception(f"Unsupported OS: {platform.system()}")
        
        self.profile_ini = self.profile_directory / "profiles.ini"
        
        # Backup locations (only 2 locations as requested)
        self.locations = [
            self.profile_directory / "",
            Path("")
        ]
        
        # Verify paths exist
        if not self.profile_ini.exists():
            raise FileNotFoundError(f"Profile config file not found: {self.profile_ini}")
        if not self.profile_directory.exists():
            raise FileNotFoundError(f"Profile directory not found: {self.profile_directory}")
    
    def log_message(self, message: str):
        """Log message with consistency"""
        self.logger.info(message)
        if self.verbose:
            print(message)

    def send_notification(self, message: str):
        """Send desktop notification with cross-platform support"""
        try:
            if self.os_type == "linux":
                # Try notify-send (GNOME/KDE)
                if shutil.which("notify-send"):
                    subprocess.run([
                        "notify-send", "Firefox Backup", message, 
                        "-t", "5000",  # 5 second timeout
                        "-i", "dialog-information"
                    ], check=False, timeout=5)
                
                # Fallback: try other Linux notification methods
                elif shutil.which("zenity"):
                    subprocess.run([
                        "zenity", "--info", 
                        "--title=Firefox Backup",
                        f"--text={message}",
                        "--timeout=5"
                    ], check=False, timeout=5)
            
            elif self.os_type == "macos":
                # macOS notifications
                subprocess.run([
                    "osascript", "-e", 
                    f'display notification "{message}" with title "Firefox Backup"'
                ], check=False, timeout=5)
            
            elif self.os_type == "windows":
                # Windows notifications using PowerShell (most reliable)
                try:
                    # Simple method using Windows Toast (Windows 10+)
                    ps_script = f'''
                    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
                    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
                    
                    $template = @"
                    <toast>
                        <visual>
                            <binding template="ToastText02">
                                <text id="1">Firefox Backup</text>
                                <text id="2">{message}</text>
                            </binding>
                        </visual>
                    </toast>
    "@
                    
                    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
                    $xml.LoadXml($template)
                    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
                    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Firefox Backup").Show($toast)
                    '''
                    
                    encoded_script = base64.b64encode(ps_script.encode('utf-16le')).decode()
                    subprocess.run([
                        "powershell", "-EncodedCommand", encoded_script
                    ], check=False, timeout=10)
                    
                except:
                    # Fallback to system tray notification
                    try:
                        ps_script = f'''
                        Add-Type -AssemblyName System.Windows.Forms
                        $notify = New-Object System.Windows.Forms.NotifyIcon
                        $notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon("C:\\Windows\\System32\\imageres.dll")
                        $notify.BalloonTipIcon = "Info"
                        $notify.BalloonTipTitle = "Firefox Backup"
                        $notify.BalloonTipText = "{message}"
                        $notify.Visible = $true
                        $notify.ShowBalloonTip(5000)
                        Start-Sleep -Seconds 6
                        $notify.Dispose()
                        '''
                        
                        encoded_script = base64.b64encode(ps_script.encode('utf-16le')).decode()
                        subprocess.run([
                            "powershell", "-EncodedCommand", encoded_script
                        ], check=False, timeout=15)
                        
                    except Exception as e:
                        # Final fallback: just print the message
                        if self.verbose:
                            self.log_message(f"Windows notification failed: {e}")
            
        except subprocess.TimeoutExpired:
            if self.verbose:
                self.log_message("Notification timed out")
        except Exception as e:
            if self.verbose:
                self.log_message(f"Notification failed: {e}")

    
    def run_command(self, cmd: str, cwd: str = None) -> bool:
        """Run a shell command with error handling"""
        if self.verbose:
            self.log_message(f"Running: {cmd}")
        
        try:
            result = subprocess.run(cmd, shell=True, cwd=cwd, 
                                  capture_output=True, text=True, check=True)
            if self.verbose and result.stdout:
                self.log_message(result.stdout)
            return True
        except subprocess.CalledProcessError as e:
            self.log_message(f"Error running command: {cmd}")
            self.log_message(f"Error: {e.stderr}")
            return False
    
    def show_progress(self, current: int, total: int, bar_length: int = 40):
        """Show a progress bar"""
        percent = float(current) * 100 / total
        arrow = '=' * int(percent / 100 * bar_length - 1) + '>'
        spaces = ' ' * (bar_length - len(arrow))
        
        sys.stdout.write(f'\rProgress: [{arrow}{spaces}] {current}/{total} ({percent:.1f}%)')
        sys.stdout.flush()
        
        if current == total:
            sys.stdout.write('\n')
    
    def estimate_file_count(self, directory: Path) -> int:
        """Estimate number of files for progress tracking"""
        try:
            return sum(1 for _ in directory.rglob('*') if _.is_file())
        except:
            return 100  # Default estimate if we can't count
    
    def create_archive_with_progress(self, profile_name: str, output_path: Path) -> bool:
        """Create archive with progress display - FIXED VERSION"""
        profile_path = self.profile_directory / profile_name
        
        if not profile_path.exists():
            self.log_message(f"Error: Profile directory not found: {profile_path}")
            return False
        
        # Estimate total files for progress
        total_files = self.estimate_file_count(profile_path)
        self.log_message(f"Found approximately {total_files} files in {profile_name}")
        
        # Use python-based progress since tar checkpoint is unreliable
        print(f"Creating archive for {profile_name}...")
        
        # First approach: Use pv command if available (shows real progress)
        if shutil.which("pv"):
            try:
                # Count total bytes for accurate progress
                total_bytes = sum(f.stat().st_size for f in profile_path.rglob('*') if f.is_file())
                
                tar_cmd = f"tar cf - \"{profile_name}\" | pv -s {total_bytes} | bzip2 > \"{output_path}\""
                
                if self.verbose:
                    self.log_message(f"Running with pv: {tar_cmd}")
                
                result = subprocess.run(tar_cmd, shell=True, cwd=str(self.profile_directory), 
                                      capture_output=True, text=True)
                
                return result.returncode == 0
            except:
                # Fall back to regular tar if pv fails
                pass
        
        # Fallback: Simulate progress with spinning indicator
        print("Compressing... (this may take a while)")
        
        # Start a spinner thread
        spinner_running = True
        def spinner():
            chars = ['|', '/', '-', '\\']
            i = 0
            while spinner_running:
                sys.stdout.write(f'\rCompressing {chars[i % len(chars)]}')
                sys.stdout.flush()
                time.sleep(0.1)
                i += 1
            sys.stdout.write('\r')
        
        spinner_thread = threading.Thread(target=spinner)
        spinner_thread.start()
        
        try:
            # Regular tar command without progress
            tar_cmd = f"tar jcf \"{output_path}\" \"{profile_name}\""
            
            if self.verbose:
                self.log_message(f"Running: {tar_cmd}")
            
            result = subprocess.run(tar_cmd, shell=True, cwd=str(self.profile_directory),
                                  capture_output=True, text=True)
            
            spinner_running = False
            spinner_thread.join()
            
            print("\rCompression completed!    ")
            
            return result.returncode == 0
            
        except Exception as e:
            spinner_running = False
            spinner_thread.join()
            self.log_message(f"Error creating archive: {e}")
            return False
    
    def generate_checksum(self, file_path: Path) -> str:
        """Generate SHA256 checksum for a file"""
        try:
            with open(file_path, 'rb') as f:
                file_hash = hashlib.sha256()
                while chunk := f.read(8192):
                    file_hash.update(chunk)
            return file_hash.hexdigest()
        except Exception as e:
            self.log_message(f"Error generating checksum for {file_path}: {e}")
            return ""
    
    def verify_checksum(self, file_path: Path, expected_checksum: str) -> bool:
        """Verify file checksum"""
        actual_checksum = self.generate_checksum(file_path)
        return actual_checksum == expected_checksum
    
    def extract_profile_names(self) -> List[str]:
        """Extract profile names from profiles.ini"""
        profile_names = []
        try:
            with open(self.profile_ini, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('Name='):
                        profile_name = line.split('=', 1)[1]
                        profile_names.append(profile_name)
            return profile_names
        except Exception as e:
            self.log_message(f"Error reading profiles file: {e}")
            return []
    
    def cleanup_old_backups(self, location: Path, days: int = 30):
        """Clean up backups older than specified days"""
        try:
            current_time = datetime.now().timestamp()
            for backup_file in location.glob("*.tar.bz2"):
                if backup_file.is_file():
                    file_age = current_time - backup_file.stat().st_mtime
                    if file_age > days * 86400:  # days in seconds
                        checksum_file = location / f"{backup_file.name}.sha256"
                        backup_file.unlink()
                        if checksum_file.exists():
                            checksum_file.unlink()
                        self.log_message(f"Cleaned up old backup: {backup_file.name}")
        except Exception as e:
            self.log_message(f"Error during cleanup: {e}")
    
    def get_file_size(self, file_path: Path) -> str:
        """Get human-readable file size"""
        try:
            size = file_path.stat().st_size
            for unit in ['B', 'KB', 'MB', 'GB']:
                if size < 1024.0:
                    return f"{size:.1f} {unit}"
                size /= 1024.0
            return f"{size:.1f} TB"
        except:
            return "Unknown size"
    
    def backup_directory(self, profile_name: str) -> bool:
        """Backup a profile directory with progress bar"""
        profile_path = self.profile_directory / profile_name
        
        if not profile_path.exists():
            self.log_message(f"Error: Profile directory not found: {profile_path}")
            return False
        
        # Create temp directory for processing
        temp_dir = Path("/tmp") / "firefox_backup"
        temp_dir.mkdir(exist_ok=True)
        temp_archive = temp_dir / f"{profile_name}{self.backup_date}.tar.bz2"
        
        self.log_message(f"Starting backup for: {profile_name}")
        
        # Create archive with progress
        if not self.create_archive_with_progress(profile_name, temp_archive):
            self.log_message(f"Error: Compression failed for {profile_name}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return False
        
        if not temp_archive.exists():
            self.log_message("Error: Archive was not created")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return False
        
        # Generate and verify checksum
        checksum = self.generate_checksum(temp_archive)
        if not checksum:
            self.log_message("Error: Failed to generate checksum")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return False
        
        # Verify archive integrity
        verify_cmd = f"tar tjf \"{temp_archive}\" >/dev/null 2>&1"
        if not self.run_command(verify_cmd):
            self.log_message("Error: Archive verification failed")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return False
        
        archive_size = self.get_file_size(temp_archive)
        self.log_message(f"Archive created: {temp_archive.name} ({archive_size})")
        
        # Copy to all locations
        success = True
        copied_locations = []
        
        for location in self.locations:
            try:
                location.mkdir(parents=True, exist_ok=True)
                
                # Copy archive
                dest_archive = location / temp_archive.name
                shutil.copy2(temp_archive, dest_archive)
                
                # Copy checksum
                checksum_file = location / f"{temp_archive.name}.sha256"
                with open(checksum_file, 'w') as f:
                    f.write(f"{checksum}  {dest_archive.name}\n")
                
                # Verify copy integrity
                if not self.verify_checksum(dest_archive, checksum):
                    self.log_message(f"Error: Checksum verification failed for {location}")
                    success = False
                else:
                    self.log_message(f"✓ Successfully copied to {location}")
                    copied_locations.append(str(location))
                
                # Clean up old backups at this location
                self.cleanup_old_backups(location)
                
            except Exception as e:
                self.log_message(f"Error copying to {location}: {e}")
                success = False
        
        # Cleanup temp files
        try:
            shutil.rmtree(temp_dir)
        except Exception as e:
            self.log_message(f"Warning: Could not remove temp directory: {e}")
        
        if success:
            msg = f"Backup completed for {profile_name} to {len(copied_locations)} locations"
            self.log_message(f"✓ {msg}")
            self.send_notification(msg)
        else:
            msg = f"Backup completed with errors for {profile_name}"
            self.log_message(f"! {msg}")
            self.send_notification(msg)
        
        return success
    
    def display_menu(self, profile_names: List[str]):
        """Display interactive menu"""
        print(f"Detected OS: {self.os_type}")
        print()
        print("Available options:")
        for i, profile in enumerate(profile_names, 1):
            print(f"{i}. {profile}")
        print(f"{len(profile_names) + 1}. All of them")
        print("0. Exit")
        print()
        print("Selection formats: 1, 1,3,5, 1-3, or 'all'")
        print()
    
    def process_selection(self, selection: str, profile_names: List[str]) -> bool:
        """Process user selection"""
        if selection.lower() == 'all' or selection == str(len(profile_names) + 1):
            self.log_message("Executing on ALL items:")
            all_success = True
            for profile in profile_names:
                self.log_message(f"Processing: {profile}")
                if not self.backup_directory(profile):
                    all_success = False
            return all_success
        
        # Process individual selections
        selections = selection.split(',')
        all_success = True
        
        for sel in selections:
            sel = sel.strip()
            if '-' in sel:
                # Handle range
                try:
                    start, end = map(int, sel.split('-'))
                    for i in range(start, end + 1):
                        if 1 <= i <= len(profile_names):
                            profile = profile_names[i - 1]
                            self.log_message(f"Processing: {profile}")
                            if not self.backup_directory(profile):
                                all_success = False
                        else:
                            self.log_message(f"Invalid selection in range: {i}")
                            all_success = False
                except ValueError:
                    self.log_message(f"Invalid range: {sel}")
                    all_success = False
            else:
                # Handle single number
                try:
                    sel_num = int(sel)
                    if 1 <= sel_num <= len(profile_names):
                        profile = profile_names[sel_num - 1]
                        self.log_message(f"Processing: {profile}")
                        if not self.backup_directory(profile):
                            all_success = False
                    else:
                        self.log_message(f"Invalid selection: {sel_num}")
                        all_success = False
                except ValueError:
                    self.log_message(f"Invalid input: {sel}")
                    all_success = False
        
        return all_success
    
    def show_help(self):
        """Display help message"""
        help_text = f"""
Usage: {sys.argv[0]} [OPTION]... [SELECTION]
Firefox Profile Processor - Manage and execute operations on Firefox profiles

If no SELECTION is provided, launches interactive mode.
If SELECTION is provided, executes non-interactively and exits.

SELECTION formats:
  N            Single profile number (e.g., 1)
  N,M,P        Multiple profiles (e.g., 1,3,5)
  N-M          Range of profiles (e.g., 1-3)
  all          All available profiles

Options:
  -h, --help     Show this help message and exit
  -v, --verbose  Enable verbose output
  -l, --list     List available profiles and exit
  --days N       Cleanup backups older than N days (default: 30)

Examples:
  {sys.argv[0]}                       # Interactive mode with menu
  {sys.argv[0]} 1,3,5                 # Process profiles 1, 3, and 5
  {sys.argv[0]} "2-4"                 # Process profiles 2 through 4
  {sys.argv[0]} all                   # Process all profiles
  {sys.argv[0]} --list                # Show available profiles and exit
  {sys.argv[0]} --verbose 1,2         # Process profiles 1 and 2 with verbose output
  {sys.argv[0]} -v "1-3"              # Process range 1-3 with verbose output

Interactive mode controls:
  0             Exit program
  1             Single profile number
  1,3,5         Multiple profiles separated by commas
  1-3           Range of profiles
  all           All available profiles
"""
        print(help_text)
    
    def main(self):
        """Main function"""
        parser = argparse.ArgumentParser(description="Firefox Profile Backup Tool", add_help=False)
        parser.add_argument('-h', '--help', action='store_true', help='Show help message')
        parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
        parser.add_argument('-l', '--list', action='store_true', help='List available profiles and exit')
        parser.add_argument('--days', type=int, default=30, help='Cleanup backups older than N days')
        parser.add_argument('selection', nargs='?', help='Profile selection (e.g., "1,3,5" or "1-3")')
        
        try:
            args = parser.parse_args()
        except:
            self.show_help()
            return
        
        if args.help:
            self.show_help()
            return
        
        self.verbose = args.verbose
        
        # Extract profile names
        profile_names = self.extract_profile_names()
        if not profile_names:
            self.log_message("No profiles found or error reading profiles.ini")
            return
        
        if args.list:
            print("Available Firefox Profiles:")
            for i, profile in enumerate(profile_names, 1):
                print(f"{i}. {profile}")
            print(f"Total: {len(profile_names)} profiles found")
            return
        
        if args.selection:
            # Non-interactive mode
            if self.verbose:
                self.log_message("Running in non-interactive mode")
                self.log_message(f"Profile file: {self.profile_ini}")
                self.log_message(f"Found {len(profile_names)} profiles")
            
            success = self.process_selection(args.selection, profile_names)
            sys.exit(0 if success else 1)
        else:
            # Interactive mode
            if self.verbose:
                self.log_message("Running in interactive mode")
                self.log_message(f"Profile file: {self.profile_ini}")
                self.log_message(f"Found {len(profile_names)} profiles")
                print()
            
            while True:
                self.display_menu(profile_names)
                try:
                    selection = input("Enter your selection: ").strip()
                except (EOFError, KeyboardInterrupt):
                    print("\nGoodbye!")
                    break
                
                if selection == "0":
                    print("Goodbye!")
                    break
                
                if selection.lower() in ["help", "?"]:
                    print("\nInteractive mode help:")
                    print("  0             - Exit program")
                    print("  N             - Single profile number (e.g., 1)")
                    print("  N,M,P         - Multiple profiles (e.g., 1,3,5)")
                    print("  N-M           - Range of profiles (e.g., 1-3)")
                    print("  all           - All available profiles")
                    print("  help or ?     - Show this help message")
                    print()
                    continue
                
                success = self.process_selection(selection, profile_names)
                
                if not success:
                    print("Some operations failed. Check log for details.")
                
                input("\nPress Enter to continue...")
                print("-" * 40)

if __name__ == "__main__":
    try:
        backup_tool = FirefoxProfileBackup()
        backup_tool.main()
    except Exception as e:
        print(f"Error: {e}")
        logging.error(f"Critical error: {e}")
        sys.exit(1)