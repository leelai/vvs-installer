# vvs-cli Installation Script for Windows
# Run with elevated privileges:
# powershell -ExecutionPolicy Bypass -File install.ps1 [-Version <specific_version>] [-Uninstall]

param (
    [string]$Version,
    [switch]$Uninstall,
    [switch]$Help
)

# Variables
$InstallDir = "C:\Program Files\VIVERSE CLI"
$BinaryName = "vvs.exe"
$GithubRepo = "VIVERSE/vvs-cli"
$TempDir = Join-Path $env:TEMP "vvs-cli-install"
$BinaryPath = Join-Path $InstallDir $BinaryName

# Colors for output
function Write-ColorOutput {
    param (
        [string]$Text,
        [string]$Color = "White"
    )
    
    $originalColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    Write-Output $Text
    $Host.UI.RawUI.ForegroundColor = $originalColor
}

# Function to show usage
function Show-Usage {
    Write-Output "Usage: .\install.ps1 [options]"
    Write-Output ""
    Write-Output "Options:"
    Write-Output "  -Version <version>    Install specific version (default: latest)"
    Write-Output "  -Uninstall            Uninstall vvs-cli"
    Write-Output "  -Help                 Show this help message"
    
    exit 0
}

# Show help if requested
if ($Help) {
    Show-Usage
}

# Function to check if running as administrator
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $user
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Check administrator rights
if (-not (Test-Administrator)) {
    Write-ColorOutput "This script needs to be run as Administrator. Please restart with elevated privileges." "Red"
    exit 1
}

# Function to clean up temporary files
function Remove-TempFiles {
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Function to check if vvs-cli is installed
function Test-Installed {
    return (Test-Path $BinaryPath)
}

# Function to uninstall vvs-cli
function Uninstall-VvsCli {
    if (Test-Installed) {
        Write-ColorOutput "Uninstalling vvs-cli..." "Yellow"
        
        # Remove binary and installation directory
        Remove-Item -Path $BinaryPath -Force -ErrorAction SilentlyContinue
        if (Test-Path $InstallDir) {
            Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Remove from PATH
        $systemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($systemPath -like "*$InstallDir*") {
            $newPath = ($systemPath -split ';' | Where-Object { $_ -ne $InstallDir }) -join ';'
            [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
            Write-ColorOutput "Removed installation directory from PATH." "Yellow"
        }
        
        Write-ColorOutput "vvs-cli has been uninstalled successfully." "Green"
    } else {
        Write-ColorOutput "vvs-cli is not installed." "Yellow"
    }
    
    exit 0
}

# Uninstall if requested
if ($Uninstall) {
    Uninstall-VvsCli
}

# Function to get the latest release version
function Get-LatestVersion {
    try {
        $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$GithubRepo/releases/latest" -Method Get
        return $releaseInfo.tag_name
    } catch {
        Write-ColorOutput "Error: Unable to determine latest version. $_" "Red"
        exit 1
    }
}

# Function to detect architecture
function Get-Architecture {
    if ([Environment]::Is64BitOperatingSystem) {
        if ([System.Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE") -eq "ARM64") {
            return "arm64"
        } else {
            return "amd64"
        }
    } else {
        return "386"
    }
}

# Set version to install
if (-not $Version) {
    $Version = Get-LatestVersion
    Write-ColorOutput "Installing latest version: $Version" "Cyan"
} else {
    Write-ColorOutput "Installing specified version: $Version" "Cyan"
}

# Detect architecture
$Arch = Get-Architecture
Write-ColorOutput "Detected Architecture: $Arch" "Cyan"

# Create temporary directory
Remove-TempFiles
New-Item -Path $TempDir -ItemType Directory -Force | Out-Null

try {
    # Define file names
    $BinaryFile = "vvs-windows-$Arch.exe"
    $BinaryUrl = "https://github.com/$GithubRepo/releases/download/$Version/$BinaryFile"
    $ChecksumUrl = "https://github.com/$GithubRepo/releases/download/$Version/checksums.txt"
    
    # Download binary
    $TempBinaryPath = Join-Path $TempDir $BinaryFile
    Write-ColorOutput "Downloading from $BinaryUrl" "Cyan"
    Invoke-WebRequest -Uri $BinaryUrl -OutFile $TempBinaryPath
    
    # Download checksum file
    $ChecksumFile = Join-Path $TempDir "checksums.txt"
    Write-ColorOutput "Downloading checksums from $ChecksumUrl" "Cyan"
    Invoke-WebRequest -Uri $ChecksumUrl -OutFile $ChecksumFile
    
    # Extract expected checksum
    $checksumContent = Get-Content $ChecksumFile
    $ExpectedChecksum = ($checksumContent | Where-Object { $_ -like "*$BinaryFile*" }) -split '\s+' | Select-Object -First 1
    
    if (-not $ExpectedChecksum) {
        Write-ColorOutput "Error: Unable to find checksum for $BinaryFile." "Red"
        Remove-TempFiles
        exit 1
    }
    
    # Verify checksum
    Write-ColorOutput "Verifying checksum..." "Cyan"
    $ActualChecksum = (Get-FileHash -Path $TempBinaryPath -Algorithm SHA256).Hash.ToLower()
    
    if ($ActualChecksum -ne $ExpectedChecksum.ToLower()) {
        Write-ColorOutput "Checksum verification failed!" "Red"
        Write-ColorOutput "Expected: $ExpectedChecksum" "Red"
        Write-ColorOutput "Got: $ActualChecksum" "Red"
        Remove-TempFiles
        exit 1
    }
    
    Write-ColorOutput "Checksum verification passed." "Green"
    
    # Create install directory if it doesn't exist
    if (-not (Test-Path $InstallDir)) {
        New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
    }
    
    # Install binary
    Write-ColorOutput "Installing vvs-cli to $InstallDir..." "Cyan"
    Copy-Item -Path $TempBinaryPath -Destination $BinaryPath -Force
    
    # Update PATH if needed
    $systemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($systemPath -notlike "*$InstallDir*") {
        $newPath = "$systemPath;$InstallDir"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
        Write-ColorOutput "Added installation directory to PATH." "Yellow"
        Write-ColorOutput "You may need to restart your terminal or system for the PATH changes to take effect." "Yellow"
    }
    
    # Verify installation
    if (Test-Installed) {
        Write-ColorOutput "vvs-cli has been installed successfully!" "Green"
        Write-ColorOutput "You can now use vvs-cli by running 'vvs' in your terminal." "Green"
    } else {
        Write-ColorOutput "Installation failed. Please check the errors above." "Red"
        exit 1
    }
} catch {
    Write-ColorOutput "An error occurred during installation: $_" "Red"
    exit 1
} finally {
    # Clean up
    Remove-TempFiles
}

exit 0