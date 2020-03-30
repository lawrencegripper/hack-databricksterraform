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

$downloadUrl = "https://github.com/scottwinkler/terraform-provider-shell/releases/download/v1.0.0/terraform-provider-shell_v1.0.0.$($os)_amd64"

Invoke-WebRequest -Uri $downloadUrl -OutFile "./terraform-provider-shell"

if ($IsLinux -or $IsMacOS) {
    chmod +x "./terraform-provider-shell"
}

write-host "Installing databricks cli"

pip3 install databricks-cli==0.9.1
