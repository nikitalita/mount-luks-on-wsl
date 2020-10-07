#requires -version 5

<#
.SYNOPSIS
  Detects and mounts LUKS partition on WSL Instance
.DESCRIPTION
  Given a physical drive path, it will mount it on WSL, automatically find the LUKS partition, ask the user for the password to unlock it, then mount it.
  It's read-only.
.NOTES
  Version:        0.1
.EXAMPLE
    luksmount -Drive \\.\PHYSICALDRIVE2
#>

[CmdletBinding()]
param (
    [Parameter()]   
    # Absolute path to physical disk to use \n(use "wmic diskdrives list brief" for the path, e.g. "\\.\PHYSICALDRIVE2").
    [String]$Drive = '\\.\PHYSICALDRIVE2',
    [Parameter()]
    # Distro to mount the drive on, defaults to WSL default distro
    [String]$Distro,
    [Parameter()]
    # Mount point on linux for luks drive.
    [Alias("M")]
    [String]$Mount = '/mnt/luks-drive',
    [Parameter()]
    # Unmount luks partition and unmount drive from WSL.
    [Alias("U")]
    [Switch]$Unmount
)


$wslPath = (Get-Command 'wsl')[0].Source
if (! $wslPath){
    $wslPath = "C:\Windows\System32\wsl.exe"
}

# Do some trickery to get the output
function Invoke-Wsl-Admin
{
    Process{
        echo "haldo"
        $argstring = $args -join ' '
        $wslPath = (Get-Command 'wsl')[0].Source
        $outputFile = '{0}\wsl_error.txt' -f $env:TEMP
        $command = '[System.Console]::OutputEncoding = [System.Text.Encoding]::Unicode; {0} {1} >{2}' -f $wslPath, $argstring, $outputFile
        $process = Start-Process powershell -Wait -PassThru -ArgumentList $command -Verb RunAs;
        $process.WaitForExit()
        $output=Get-Content $outputFile -Encoding unicode
        rm $outputFile

        [hashtable]$Return = @{}
        $Return.ReturnCode = $process.ExitCode
        $Return.Output = $output
        return $return
    }
}
function Get-Default-Distro
{
    try {
        $oldOutputEncoding = [System.Console]::OutputEncoding
        [System.Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $output = &$wslPath --list --verbose
        if ($LASTEXITCODE -ne 0) {
            throw "Wsl.exe failed: $output"
            $hasError = $true
        }
    } finally {
        [System.Console]::OutputEncoding = $oldOutputEncoding
    }
    $output | Select-Object -Skip 1 | ForEach-Object {
        $fields = $_.Split(@(" "), [System.StringSplitOptions]::RemoveEmptyEntries)
        if ($fields.Count -eq 4) {
            $fields = $fields | Select-Object -Skip 1
            return $fields[0]
        }
    }
    return
}
function Get-Path-On-WSL
{
    param(
        [Parameter(
            Mandatory=$true)]
        [String]$Distro,
        [Parameter(
            Mandatory=$true)]
        [String]$Path
    )
    $thing = & $wslPath -d $Distro --exec wslpath "$Path"
    return $thing
}
function Mount-Drive-Wsl
{
    param(
        [Parameter(
            Mandatory=$true)]
        [String]$Drive,
        [Parameter(
            Mandatory=$true)]
        [String]$Distro
    )
    $result = Invoke-Wsl-Admin -d $distro --mount $Drive --bare
    $output = $result.Output
    if ( $result.ReturnCode -ne 0) {
        if ($output -match "That disk is already attached"){
            echo $output
        } else {
            throw "Failed to mount on WSL: $output"
        }
    }
}
function Unmount
{
    Write-Host -Foreground Cyan "***** Unmounting... *****"
    Write-Host "Distro:       $Distro"
    Write-Host "Drive:        $Drive"
    Write-Host "Mount Point:  $Mount"
    param(
        [Parameter(
            Mandatory=$true)]
        [String]$Drive,
        [Parameter(
            Mandatory=$true)]
        [String]$Distro,
        [Parameter(
            Mandatory=$true)]
        [String]$Mount
    )
    $path_to_here = Get-Path-On-WSL -Distro $Distro -Path "$PWD"
    $bash_script_path = '{0}/mount-luks-partition.sh' -f $path_to_here
    & $wslPath -d $Distro --user root -- bash $bash_script_path --unmount --mount-point $Mount
    if (! $?){
        throw "Failed to umount the partition on Linux! Refusing to unmount drive from WSL"
    }
    &$wslPath --unmount $Drive
    Write-Host -Foreground Green "***** Successfully unmounted! *****"

}

try{
    if (! $Distro){
        $Distro = Get-Default-Distro
    }
    if ($Unmount){
        Unmount -Drive $Drive -Distro $Distro -Mount $Mount
        return
    }
    Write-Host -Foreground Cyan "***** Mounting... *****"
    Write-Host "Distro:       $Distro"
    Write-Host "Drive:        $Drive"
    Write-Host "Mount Point:  $Mount"
    Write-Host -Foreground Cyan "***** Attempting to mount drive on WSL instance... *****"

    Mount-Drive-Wsl -Distro $Distro -Drive $Drive
    Write-Host -Foreground Green "***** Successfully mounted drive on WSL instance *****"
    $path_to_here = Get-Path-On-WSL -Distro $Distro -Path "$PWD"

    &$wslPath -d $Distro --user root -- bash $path_to_here/mount-luks-partition.sh --mount-point $Mount
    Write-Host -Foreground Green "***** Successfully mounted! *****"

} catch {
    Write-Host -Foreground Red -Background Black  $_.Exception.Message
}
