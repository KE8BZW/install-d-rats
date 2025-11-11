# Install-D-RATS

Modern D-RATS deployment on Windows 11 via WSL2 + Ubuntu + venv

## What is D-RATS?

D-RATS (Digital Radio Amateur Text Service) is an open-source communications tool designed for amateur radio operators. It enables text messaging, file transfers, and GPS position reporting over radio frequencies using digital modes. This installer provides a streamlined way to deploy D-RATS on Windows 11 using Windows Subsystem for Linux (WSL2) with Ubuntu, ensuring compatibility and ease of use.

## Prerequisites

- **Windows 11** (or Windows 10 version 22H2+ with 64-bit architecture)
- **Administrator privileges** (required for WSL setup)
- **Internet connection** (for downloading components and fetching active ratflectors)
- **COM ports** configured for your D-STAR radio and TNC (if applicable)
- **Amateur Radio License** (for communicating via the D-RATS software)

### Hardware Requirements (for RF use)
- D-STAR capable radio (e.g., Icom ID-51, ID-31, etc.)
- Terminal Node Controller (TNC) for packet radio (optional)
- Appropriate cables and adapters for COM port connections

## Installation

### Download the Script

Clone this repository or download the `Install-D-RATS.ps1` script:

```powershell
git clone https://github.com/KE8BZW/install-d-star.git
cd install-d-star
```

### Run the Installer

Open PowerShell as Administrator and execute the script with your callsign and name:

```powershell
.\Install-D-RATS.ps1 -Callsign "YOUR_CALLSIGN" -Name "Your Full Name"
```

#### Optional Parameters

- `-InstallPath`: Installation directory (default: `C:\D-RATS`)
- `-DStarComPort`: COM port for D-STAR radio (default: `COM3`)
- `-TncComPort`: COM port for TNC (default: `COM1`)

Example with custom paths:
```powershell
.\Install-D-RATS.ps1 -Callsign "JD0E" -Name "John Doe" -InstallPath "D:\HamRadio\D-RATS" -DStarComPort "COM5" -TncComPort "COM2"
```

### What the Installer Does

1. **System Check**: Verifies Windows version and architecture compatibility
2. **WSL2 Setup**: Enables WSL features and installs the WSL2 kernel if needed
3. **Ubuntu Installation**: Downloads and installs Ubuntu 22.04
4. **D-RATS Deployment**: Clones the D-RATS repository, creates a Python virtual environment, and installs dependencies
5. **Configuration**: Sets up D-RATS with your callsign, location (auto-detected from IP), and active ratflectors
6. **Launchers**: Creates desktop shortcuts and Start Menu entries for easy access
7. **Serial Bridge Setup**: Creates a batch file to bridge Windows COM ports to WSL

## Configuration

The installer automatically configures D-RATS with:

- **User Information**: Your callsign and name
- **Location**: Automatically detected from your IP address (latitude/longitude)
- **Ratflectors**: Active D-RATS servers fetched from groups.io
- **Ports**: Serial ports for D-STAR radio and TNC, plus network connections for ratflectors

Configuration files are stored in `%APPDATA%\D-RATS\`:
- `d_rats.config`: Main configuration
- `repeater.config`: Ratflector settings

## Getting Started

### 1. Start the Serial Bridges

Before launching D-RATS, run the serial bridge to connect your COM ports:

```batch
C:\D-RATS\start-bridges.bat
```

This creates virtual serial ports in WSL that connect to your Windows COM ports.

### 2. Launch D-RATS

Use one of these methods:

- **Desktop Shortcut**: Double-click "D-RATS" on your desktop
- **Start Menu**: Search for "D-RATS" in the Start Menu
- **Command Line**:
  ```powershell
  wsl -d Ubuntu-22.04 -- /opt/d-rats/.venv/bin/python /opt/d-rats/d_rats.py
  ```

### 3. Initial Setup

1. On first run, D-RATS will prompt for initial configuration
2. Verify your callsign and location information
3. Test connectivity to ratflectors
4. Configure your radio settings if needed

### 4. Using D-RATS

- **Messaging**: Send text messages to other stations
- **File Transfer**: Share files over radio
- **GPS**: Share and track positions
- **Ratflector**: Connect to D-RATS servers for wider communication

## Ratflector Mode

To run D-RATS as a ratflector (server) for your local area:

```powershell
wsl -d Ubuntu-22.04 -- /opt/d-rats/.venv/bin/python /opt/d-rats/d_rats_repeater.py
```

Or use the "D-RATS Ratflector" desktop shortcut.

## Troubleshooting

### Common Issues

**WSL Installation Fails**
- Ensure you're running as Administrator
- Check that virtualization is enabled in BIOS
- Restart your computer after WSL feature installation

**Serial Port Not Found**
- Verify COM port numbers in Device Manager
- Ensure radio/TNC is connected and powered on
- Run `start-bridges.bat` as Administrator

**D-RATS Won't Start**
- Check that WSL Ubuntu is running: `wsl -l -v`
- Verify Python environment: `wsl -d Ubuntu-22.04 -- python3 --version`
- Check logs in `C:\D-RATS\install.log`

**No Ratflector Connection**
- Ensure internet connectivity
- Check firewall settings
- Verify ratflector addresses are accessible

### Logs and Debugging

- Installation log: `C:\D-RATS\install.log`
- D-RATS logs: Located in the WSL Ubuntu environment at `/opt/d-rats/`
- WSL logs: Check Windows Event Viewer for WSL-related events

### Manual Verification

Test WSL Ubuntu installation:
```powershell
wsl -d Ubuntu-22.04 -- echo "WSL working"
```

Test D-RATS import:
```powershell
wsl -d Ubuntu-22.04 -- /opt/d-rats/.venv/bin/python -c "import d_rats; print('OK')"
```

## Updating D-RATS

To update to the latest version:

```powershell
wsl -d Ubuntu-22.04 -- bash -c "cd /opt/d-rats && git pull && . .venv/bin/activate && pip install -r requirements.txt"
```

## Uninstalling

To remove D-RATS:

1. Delete the installation directory: `C:\D-RATS`
2. Remove configuration: `rmdir /s %APPDATA%\D-RATS`
3. Uninstall Ubuntu: `wsl --unregister Ubuntu-22.04`
4. Remove WSL if not needed: Disable WSL features in Windows Features

## Contributing

This installer is open source. Contributions are welcome via GitHub issues and pull requests.

## License

See [LICENSE](LICENSE) file for details.

## Support

- D-RATS Documentation: https://github.com/ham-radio-software/D-Rats
- D-RATS Groups.io: https://groups.io/g/d-rats
- Report installer issues: https://github.com/KE8BZW/install-d-star/issues
