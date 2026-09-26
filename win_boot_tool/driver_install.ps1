param(
    [Parameter(Mandatory=$true)][string]$InfPath,
    [Parameter(Mandatory=$true)][string]$HardwareId
)
# Force-install a specific INF onto a hardware ID via newdev.dll
# (UpdateDriverForPlugAndPlayDevices, INSTALLFLAG_FORCE=1) - bypasses
# driver ranking so our WinUSB package can replace Apple's signed driver.
# Ported from A7Downgrade WindowsRecoveryDriverBindingService.
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class NativeMethods
{
    [DllImport("newdev.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "UpdateDriverForPlugAndPlayDevicesW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UpdateDriverForPlugAndPlayDevices(
        IntPtr hwndParent, string hardwareId, string fullInfPath, uint installFlags, out bool rebootRequired);
}
"@

$reboot = $false
$ok = [NativeMethods]::UpdateDriverForPlugAndPlayDevices(
    [IntPtr]::Zero, $HardwareId, $InfPath, 1, [ref]$reboot)
$err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

if ($ok) {
    Write-Output "FORCE_INSTALL_OK reboot=$reboot"
    exit 0
}
Write-Output "FORCE_INSTALL_FAIL win32error=$err"
exit 1
