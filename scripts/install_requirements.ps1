
# Skip if installed already
if ((Get-Command "databricks" -errorAction SilentlyContinue) -and ((Test-Path -Path "./terraform-provider-shell" -errorAction SilentlyContinue))) {
    # Skip as already exists
    exit 0
}

$fileEx = ""
if ($PSVersionTable.PSVersion -gt [Version]'6.1.0.0') {
    if ($IsLinux) {
        $fileEx = "_linux_amd64.zip"
    }
    
    if ($IsWindows) {
        $fileEx = ".exe_windows_amd64.zip"
    }

    if ($IsMacOS) {
        $fileEx = "-darwin_amd64.zip"
    }
}

write-output "Downloading shell provider $fileEx"

$downloadUrl = "https://github.com/scottwinkler/terraform-provider-shell/releases/download/v1.3.1/terraform-provider-shell_v1.3.1$($fileEx)"

write-output $downloadUrl


Invoke-WebRequest -Uri $downloadUrl -OutFile "terraform-provider-shell.zip"

if ($IsLinux -or $IsMacOS) {
    unzip terraform-provider-shell.zip
    chmod +x "terraform-provider-shell_v1.3.1"
    mkdir -p ~/.terraform.d/plugins
    cp ./terraform-provider-shell_v1.3.1 ~/.terraform.d/plugins
}
else {
    Expand-Archive .\terraform-provider-shell.zip
    New-Item $env:APPDATA\terraform.d\plugins -ItemType Directory -ErrorAction SilentlyContinue
    Copy-Item terraform-provider-shell\terraform-provider-shell_v1.3.1.exe $env:APPDATA\terraform.d\plugins
}


write-output "Installing databricks cli"

pip3 install databricks-cli==0.9.1
