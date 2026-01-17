$ErrorActionPreference = "Stop"

# =====================================================
# CONFIG
# =====================================================
$RequiredGoVersion = "1.22.1"

$MsysRoot = "C:\msys64"
$MingwBin = "$MsysRoot\mingw64\bin"

$GoRoot = "C:\Go"
$GoBin  = "$GoRoot\bin"
$GoUrl  = "https://go.dev/dl/go$RequiredGoVersion.windows-amd64.msi"
$GoMsi  = "$env:TEMP\go-installer.msi"

# =====================================================
# HELPERS
# =====================================================
function Get-GoVersion {
    if (-not (Get-Command go -ErrorAction SilentlyContinue)) { return $null }
    $v = (& go version) -replace '.*go([0-9\.]+).*', '$1'
    return [version]$v
}

function Force-PrependPath {
    param ($NewPath)
    $Path = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $Parts = $Path -split ';' | Where-Object { $_ -and ($_ -ne $NewPath) }
    $NewPathValue = "$NewPath;" + ($Parts -join ';')
    Write-Host "Forcing $NewPath to front of PATH"
    [Environment]::SetEnvironmentVariable("Path", $NewPathValue, "Machine")
}

function Remove-AllFyne {
    param ($GoodDir)
    Write-Host "Scanning all PATH directories AND Go bin for any fyne.exe..."
    # Scan all PATH directories
    $dirs = $env:Path -split ';'
    $dirs += $GoodDir  # explicitly include Go bin

    foreach ($dir in $dirs | Select-Object -Unique) {
        if (-not (Test-Path $dir)) { continue }
        $file = Join-Path $dir "fyne.exe"
        if (Test-Path $file) {
            Write-Host "Removing existing fyne.exe: $file"
            Remove-Item $file -Force
        }
    }
}

Write-Host "=== Windows Fyne build environment bootstrap ==="

# =====================================================
# MSYS2 + MinGW-w64
# =====================================================
if (-not (Test-Path $MsysRoot)) {
    Write-Host "Installing MSYS2..."
    $msysUrl = "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-x86_64-latest.exe"
    $msysExe = "$env:TEMP\msys2-installer.exe"
    Invoke-WebRequest $msysUrl -OutFile $msysExe
    Start-Process $msysExe -ArgumentList "--confirm-command --accept-messages --root $MsysRoot" -Wait
}

Write-Host "Updating MSYS2..."
& "$MsysRoot\usr\bin\bash.exe" -lc "pacman -Sy --noconfirm pacman"
& "$MsysRoot\usr\bin\bash.exe" -lc "pacman -Su --noconfirm"
& "$MsysRoot\usr\bin\bash.exe" -lc "pacman -S --needed --noconfirm mingw-w64-x86_64-toolchain"

# =====================================================
# GO (VERSION-AWARE)
# =====================================================
$InstalledGo = Get-GoVersion
$Required    = [version]$RequiredGoVersion

if ($InstalledGo -eq $null -or $InstalledGo -lt $Required) {
    Write-Host "Installing / upgrading Go $RequiredGoVersion..."
    Invoke-WebRequest $GoUrl -OutFile $GoMsi
    Start-Process "msiexec.exe" -ArgumentList "/i `"$GoMsi`" /qn /norestart" -Wait
}

# =====================================================
# GO ENV
# =====================================================
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine")

go env -w CGO_ENABLED=1
go env -w CC=x86_64-w64-mingw32-gcc
go env -w CXX=x86_64-w64-mingw32-g++

# =====================================================
# FYNE CLI (FORCE + CLEAN)
# =====================================================
$GoPathBin = (& go env GOPATH) + "\bin"

# 1️⃣ Remove ANY existing fyne.exe including old versions in Go bin
Remove-AllFyne $GoPathBin

# 2️⃣ Install latest Fyne CLI v2
Write-Host "Installing Fyne CLI v2..."
go install fyne.io/tools/cmd/fyne@latest

# 3️⃣ Ensure Go bin is front of PATH
Force-PrependPath $GoPathBin

# Refresh PATH for current session
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine")

# =====================================================
# VERIFICATION
# =====================================================
Write-Host ""
Write-Host "=== Verification ==="
where.exe fyne
fyne version
go version
x86_64-w64-mingw32-gcc --version

Write-Host ""
Write-Host "SUCCESS: Windows Fyne build environment is now CORRECT"
Write-Host "Open a NEW terminal for changes to apply."
