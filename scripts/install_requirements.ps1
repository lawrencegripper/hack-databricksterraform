function Expand-Tar($tarFile, $dest) {
    if (-not (Get-Command Expand-7Zip -ErrorAction Ignore)) {
        Install-Package -Scope CurrentUser -Force 7Zip4PowerShell > $null
    }

    Expand-7Zip $tarFile $dest
}

# Skip if installed already
if ((Get-Command "databricks" -errorAction SilentlyContinue) -and ((Test-Path -Path "./terraform-provider-shell" -errorAction SilentlyContinue))) {
    # Skip as already exists
    exit 0
}

$os = "windows"
if ($PSVersionTable.PSVersion -gt [Version]'6.1.0.0') {
    if ($IsLinux) {
        $os = "linux"
    }
    
    if ($IsWindows) {
        $os = "windows"
    }

    if ($IsMacOS) {
        $os = "darwin"
    }
}

write-host "Downloading shell provider for $os"

$downloadUrl = "https://github.com/scottwinkler/terraform-provider-shell/releases/download/v1.2.0/terraform-provider-shell_v1.2.0_$($os)_amd64.tar.gz"

Invoke-WebRequest -Uri $downloadUrl -OutFile "./terraform-provider-shell.tar.gz"

if ($IsLinux -or $IsMacOS) {
    tar -xvzf ./terraform-provider-shell.tar.gz
    chmod +x "./terraform-provider-shell"
    mkdir -p ~/.terraform.d/plugins
    cp ./terraform-provider-shell ~/.terraform.d/plugins
} else {
    Write-Warning "Untested codepath, only checked in Linux devcontainer may not work on Windows"
    Expand-Tar ./terraform-provider-shell.tar.gz .
    mkdir %APPDATA%\terraform.d\plugins
    cp .\terraform-provider-shell.exe %APPDATA%\terraform.d\plugins
}



write-host "Installing databricks cli"

pip3 install databricks-cli==0.9.1
