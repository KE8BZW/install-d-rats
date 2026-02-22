# Install-D-RATS.ps1
# Modern D-RATS deployment on Windows 11 via WSL2 + Ubuntu + venv

param (
    [Parameter(Mandatory = $true)]
    [string]$Callsign,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [string]$InstallPath = "C:\D-RATS",

    [Parameter(Mandatory = $false)]
    [string]$DStarComPort = "COM3",

    [Parameter(Mandatory = $false)]
    [string]$TncComPort = "COM1"
)

# Requires elevation for WSL setup
#Requires -RunAsAdministrator

# Constants
$LogPath = Join-Path $InstallPath "install.log"
$UbuntuDistro = "Ubuntu-24.04"
$DRatsRepoUrl = "https://github.com/ham-radio-software/D-Rats.git"
$DRatsPath = "/opt/d-rats"
$ConfigDir = "$env:APPDATA\D-RATS"
$KernelUrl = "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"
$KernelMsi = "$env:TEMP\wsl_kernel.msi"
$GroupsIoTableUrl = "https://groups.io/g/d-rats/table?id=14983"
$IpInfoUrl = "https://ipinfo.io/json"

# Logging
Start-Transcript -Path $LogPath -Append

# Function to write colored output
function Write-ColorOutput {
    param ([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# Function to get location from IP
function Get-LocationFromIP {
    try {
        $response = Invoke-WebRequest -Uri $IpInfoUrl -UseBasicParsing
        $data = $response.Content | ConvertFrom-Json
        if ($data.loc) {
            $loc = $data.loc -split ','
            return @{
                Latitude  = [double]$loc[0]
                Longitude = [double]$loc[1]
            }
        }
    }
    catch {
        Write-ColorOutput "Could not get location from IP: $($_.Exception.Message)" "Yellow"
    }
    return $null
}

# Function to get active ratflectors from groups.io
function Get-ActiveRatflectors {
    try {
        Write-ColorOutput "Fetching active ratflectors from groups.io..." "Cyan"
        $response = Invoke-WebRequest -Uri $GroupsIoTableUrl -UseBasicParsing
        $data = $response.Content | ConvertFrom-Json

        $ratflectors = @()
        foreach ($row in $data.rows) {
            $ip = $row.vals[0].text
            $port = $row.vals[1].text
            $comment = $row.vals[2].text

            # Skip entries with non-standard ports (like 9001)
            if ($port -eq "9000") {
                $ratflectors += @{
                    Host = $ip
                    Port = $port
                    Name = $comment
                }
            }
        }

        # Test connectivity and return only active ones
        $activeRatflectors = @()
        foreach ($rat in $ratflectors) {
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $connectResult = $tcpClient.BeginConnect($rat.Host, [int]$rat.Port, $null, $null)
                $waitResult = $connectResult.AsyncWaitHandle.WaitOne(2000, $false)  # 2 second timeout
                if ($waitResult) {
                    $tcpClient.EndConnect($connectResult)
                    $activeRatflectors += $rat
                    Write-ColorOutput "✓ $($rat.Name) ($($rat.Host))" "Green"
                }
                else {
                    Write-ColorOutput "✗ $($rat.Name) ($($rat.Host)) - timeout" "Gray"
                }
                $tcpClient.Close()
            }
            catch {
                Write-ColorOutput "✗ $($rat.Name) ($($rat.Host)) - error" "Gray"
            }
        }

        Write-ColorOutput "Found $($activeRatflectors.Count) active ratflectors" "Green"
        return $activeRatflectors
    }
    catch {
        Write-ColorOutput "Could not fetch ratflectors from groups.io: $($_.Exception.Message)" "Red"
        Write-ColorOutput "Using fallback ratflectors..." "Yellow"

        # Fallback to known working ratflectors
        return @(
            @{ Host = "ref.d-rats.com"; Port = "9000"; Name = "D-RATS Default" },
            @{ Host = "gaares.ratflector.com"; Port = "9000"; Name = "Georgia Statewide ARES" },
            @{ Host = "gwinnettares.ratflector.com"; Port = "9000"; Name = "Gwinnett Co ARES" },
            @{ Host = "StTammany.ratflector.com"; Port = "9000"; Name = "St. Tammany Parish" },
            @{ Host = "sewx.ratflector.com"; Port = "9000"; Name = "SE WX Net" },
            @{ Host = "d-rats.wa7dre.org"; Port = "9000"; Name = "Spokane WA" },
            @{ Host = "d-rats.pauldingares.com"; Port = "9000"; Name = "Paulding Co. GA ARES" }
        )
    }
}

# Function to check system requirements
function Test-SystemRequirements {
    $os = Get-ComputerInfo
    $buildNumber = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    $isSupported = [int]$buildNumber -ge 19045  # Windows 10 22H2+ or Windows 11
    $is64Bit = $os.OsArchitecture -eq "64-bit"

    if (-not $isSupported -or -not $is64Bit) {
        Write-ColorOutput "This script requires Windows 11 or Windows 10 22H2+ 64-bit (detected build: $buildNumber). Aborting." "Red"
        Stop-Transcript
        exit 1
    }

    Write-ColorOutput "Detected supported Windows version. Proceeding..." "Green"
}

# Function to check if WSL is available
function Test-WSL {
    try {
        wsl --version 2>$null | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# Function to install WSL2
function Install-WSL {
    Write-Progress -Activity "Setting up WSL2" -Status "Enabling WSL features" -PercentComplete 10
    Write-ColorOutput "Enabling WSL2 features..." "Cyan"
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

    # Install WSL2 kernel if needed
    if (-not (Test-Path $KernelMsi)) {
        Invoke-WebRequest -Uri $KernelUrl -OutFile $KernelMsi -UseBasicParsing
    }
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $KernelMsi /quiet /norestart" -Wait
    wsl --set-default-version 2
}

# Function to install Ubuntu
function Install-Ubuntu {
    Write-Progress -Activity "Installing Ubuntu" -Status "Setting up $UbuntuDistro" -PercentComplete 20
    Write-ColorOutput "Installing $UbuntuDistro..." "Cyan"
    wsl --install -d $UbuntuDistro

    # Wait for installation to complete
    Start-Sleep -Seconds 10
}

# Function to install D-RATS
function Install-DRats {
    Write-Progress -Activity "Installing D-RATS" -Status "Setting up packages and cloning repository" -PercentComplete 30
    Write-ColorOutput "Installing system packages and D-RATS..." "Cyan"

    $installScript = @"
apt update && apt upgrade -y
apt install -y python3 python3-venv python3-pip python3-gi python3-gi-cairo \
               gir1.2-gtk-3.0 gir1.2-webkit2-4.0 \
               aspell aspell-en socat git build-essential libgtk-3-dev

cd /opt
git clone $DRatsRepoUrl d-rats
cd d-rats
python3 -m venv --system-site-packages .venv
. .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
# optional spellcheck UI
pip install pygtkspellcheck 2>/dev/null || true
"@

    wsl -d $UbuntuDistro -u root -- bash -c $installScript
}

# Function to create desktop launchers
function Create-Launchers {
    Write-Progress -Activity "Creating Launcher" -Status "Setting up desktop integration" -PercentComplete 40
    Write-ColorOutput "Creating desktop launcher..." "Cyan"

    $desktopScript = @"
cat > /usr/share/applications/d-rats.desktop <<EOF
[Desktop Entry]
Name=D-RATS
Exec=wsl -d $UbuntuDistro $DRatsPath/.venv/bin/python $DRatsPath/d_rats.py
Icon=applications-system
Type=Application
Categories=Network;HamRadio;
Terminal=false
EOF
chmod 644 /usr/share/applications/d-rats.desktop

# Also create ratflector desktop entry
cat > /usr/share/applications/d-rats-ratflector.desktop <<EOF
[Desktop Entry]
Name=D-RATS Ratflector
Exec=wsl -d $UbuntuDistro $DRatsPath/.venv/bin/python $DRatsPath/d_rats_repeater.py
Icon=applications-system
Type=Application
Categories=Network;HamRadio;
Terminal=false
EOF
chmod 644 /usr/share/applications/d-rats-ratflector.desktop
"@

    wsl -d $UbuntuDistro -u root -- bash -c $desktopScript

    # Create Windows shortcuts as backup
    Write-Progress -Activity "Creating Shortcuts" -Status "Creating Windows shortcuts" -PercentComplete 50
    $shell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath("Desktop")

    # D-RATS shortcut
    $shortcut = $shell.CreateShortcut("$desktop\D-RATS.lnk")
    $shortcut.TargetPath = "wsl"
    $shortcut.Arguments = "-d $UbuntuDistro -- $DRatsPath/.venv/bin/python $DRatsPath/d_rats.py"
    $shortcut.WorkingDirectory = "~"
    $shortcut.Save()

    # Ratflector shortcut
    $shortcut = $shell.CreateShortcut("$desktop\D-RATS Ratflector.lnk")
    $shortcut.TargetPath = "wsl"
    $shortcut.Arguments = "-d $UbuntuDistro -- $DRatsPath/.venv/bin/python $DRatsPath/d_rats_repeater.py"
    $shortcut.WorkingDirectory = "~"
    $shortcut.Save()
}

# Function to set INI value
function Set-IniFileValue {
    param ([string]$FilePath, [string]$Section, [string]$Key, [string]$Value)
    $content = Get-Content $FilePath -Raw
    if ($content -match "\[${Section}\]") {
        if ($content -match "${Key}=") {
            $content = $content -replace "(${Key})=.*", "`$1=${Value}"
        }
        else {
            $content = $content -replace "\[${Section}\]", "[${Section}]`n${Key}=${Value}"
        }
    }
    else {
        $content += "`n[${Section}]`n${Key}=${Value}"
    }
    $content | Out-File $FilePath -Encoding UTF8
}

# Function to configure D-RATS
function Configure-DRats {
    param ($Latitude, $Longitude, $ActiveRatflectors)

    Write-Progress -Activity "Configuring D-RATS" -Status "Setting up configuration" -PercentComplete 60

    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir
    }
    $configFile = Join-Path $ConfigDir "d_rats.config"

    # General config
    Set-IniFileValue -FilePath $configFile -Section "user" -Key "callsign" -Value $Callsign
    Set-IniFileValue -FilePath $configFile -Section "user" -Key "name" -Value $Name
    Set-IniFileValue -FilePath $configFile -Section "prefs" -Key "ping_info" -Value "PONG"

    # GPS
    Set-IniFileValue -FilePath $configFile -Section "user" -Key "latitude" -Value $Latitude
    Set-IniFileValue -FilePath $configFile -Section "user" -Key "longitude" -Value $Longitude

    # Appearance
    Set-IniFileValue -FilePath $configFile -Section "prefs" -Key "noticere" -Value "$Callsign(?i)"
    Set-IniFileValue -FilePath $configFile -Section "prefs" -Key "check_spelling" -Value "True"

    # Messages
    Set-IniFileValue -FilePath $configFile -Section "settings" -Key "auto_forward" -Value "1"
    Set-IniFileValue -FilePath $configFile -Section "settings" -Key "queue_flush" -Value "30"
    Set-IniFileValue -FilePath $configFile -Section "settings" -Key "expire_stations" -Value "600"

    # Transfers
    Set-IniFileValue -FilePath $configFile -Section "settings" -Key "remote_files" -Value "1"
    Set-IniFileValue -FilePath $configFile -Section "settings" -Key "warmup_length" -Value "16"
    Set-IniFileValue -FilePath $configFile -Section "settings" -Key "warmup_timeout" -Value "0"

    # Ports - configured for WSL device files
    Set-IniFileValue -FilePath $configFile -Section "ports" -Key "ports_0" -Value "True,serial:/dev/ttyDSTAR:9600,,False,False,D-STAR Radio"
    Set-IniFileValue -FilePath $configFile -Section "ports" -Key "ports_1" -Value "True,tnc:/dev/tnc-kiss:9600,,False,False,PK-232"

    # Add active ratflectors starting from ports_2
    $portIndex = 2
    foreach ($rat in $ActiveRatflectors) {
        $portValue = "True,net:$($rat.Host):$($rat.Port),,False,False,$($rat.Name)"
        Set-IniFileValue -FilePath $configFile -Section "ports" -Key "ports_$portIndex" -Value $portValue
        $portIndex++
    }

    # Ratflector config
    $repeaterConfig = Join-Path $ConfigDir "repeater.config"
    @"
[settings]
acceptnet=True
netport=9000
id=NotSet
idfreq=30
require_auth=False
trust_local=True
gpsport=9500

[tweaks]
allow_gps=

[devices]
devices=[('net:0.0.0.0:9000', ''), ('tnc:/dev/tnc-kiss', '9600')]
"@ | Out-File -FilePath $repeaterConfig -Encoding UTF8

    # Quick setup
    Set-IniFileValue -FilePath $configFile -Section "state" -Key "status_msg" -Value "$Callsign Online (D-RATS)"
}

# Function to create serial bridge script
function Create-SerialBridge {
    $bridgeScript = @"
@echo off
echo Starting D-RATS serial bridges...
echo Bridge Windows $DStarComPort → /dev/ttyDSTAR
wsl -d $UbuntuDistro -- socat pty,link=/dev/ttyDSTAR,raw,echo=0 $DStarComPort &
echo Bridge Windows $TncComPort → /dev/tnc-kiss
wsl -d $UbuntuDistro -- socat pty,link=/dev/tnc-kiss,raw,echo=0 $TncComPort &
echo Bridges started. Press Ctrl+C to stop.
pause
"@

    $bridgePath = Join-Path $InstallPath "start-bridges.bat"
    $bridgeScript | Out-File -FilePath $bridgePath -Encoding ASCII
}

# Function to verify installation
function Verify-Installation {
    Write-Progress -Activity "Finalizing" -Status "Verifying installation" -PercentComplete 80

    try {
        $result = wsl -d $UbuntuDistro -- $DRatsPath/.venv/bin/python -c "import d_rats; print('D-RATS imported successfully')"
        if ($result -match "D-RATS imported successfully") {
            Write-ColorOutput "D-RATS installation successful!" "Green"
        }
        else {
            Write-ColorOutput "Verification failed: Import test did not succeed" "Red"
        }
    }
    catch {
        Write-ColorOutput "Verification failed: $($_.Exception.Message)" "Red"
    }
}

Write-Progress -Activity "Finalizing" -Status "Verifying installation" -PercentComplete 80

# Main script
try {
    Test-SystemRequirements

    # Get location from IP
    Write-ColorOutput "Getting location from IP..." "Cyan"
    $location = Get-LocationFromIP
    if ($location) {
        $Latitude = $location.Latitude
        $Longitude = $location.Longitude
        Write-ColorOutput "Location detected: $Latitude, $Longitude" "Green"
    }
    else {
        Write-ColorOutput "Could not determine location. Using defaults." "Yellow"
        $Latitude = 0.0
        $Longitude = 0.0
    }

    # Get active ratflectors
    $activeRatflectors = Get-ActiveRatflectors

    Install-WSL
    Install-Ubuntu
    Install-DRats
    Create-Launchers
    Configure-DRats -Latitude $Latitude -Longitude $Longitude -ActiveRatflectors $activeRatflectors
    Create-SerialBridge
    Verify-Installation

    Write-Progress -Activity "Complete" -Status "Installation finished" -PercentComplete 100

    Write-ColorOutput "`nD-RATS is ready!`n" "Green"
    Write-ColorOutput "Launch from:" "Cyan"
    Write-ColorOutput "  - Windows Start Menu → 'D-RATS'" "Cyan"
    Write-ColorOutput "  - Desktop shortcuts" "Cyan"
    Write-ColorOutput "  - Or run: wsl -d $UbuntuDistro -- $DRatsPath/.venv/bin/python $DRatsPath/d_rats.py" "Cyan"
    Write-ColorOutput "`nBefore starting D-RATS, run the serial bridge:" "Yellow"
    Write-ColorOutput "  $InstallPath\start-bridges.bat" "Yellow"
    Write-ColorOutput "`nConfigured with $($activeRatflectors.Count) active ratflectors from groups.io" "Green"
    Write-ColorOutput "  - Callsign: $Callsign" "Green"
    Write-ColorOutput "  - Name: $Name" "Green"
    Write-ColorOutput "  - Location: $Latitude, $Longitude" "Green"
    Write-ColorOutput "`nCheck $LogPath for details." "Cyan"
}
catch {
    Write-ColorOutput "Installation failed: $($_.Exception.Message)" "Red"
}
finally {
    Stop-Transcript
}