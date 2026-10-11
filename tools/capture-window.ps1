# SPDX-FileCopyrightText: 2026 Anne Jan Brouwer
# SPDX-License-Identifier: GPL-3.0-or-later
# Capture the top-level window of process $ProcessId with Windows' own
# rounded corners and shadow, twice: once on a black and once on a white
# desktop ($Out-black.png, $Out-white.png). tools/alpha-from-pair.sh turns
# the pair into one PNG with real transparency, the way ShareX does.
param([int]$ProcessId, [string]$Out, [int]$Margin = 40)
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SystemParametersInfo(int a, int p, string v, int f);
  [DllImport("user32.dll")] public static extern bool SetSysColors(int n, int[] e, int[] c);
}
"@
[W]::SetProcessDPIAware() | Out-Null

function Set-Desktop([int]$rgb) {
  # A solid colour instead of the wallpaper: no wallpaper, COLOR_DESKTOP.
  Set-ItemProperty "HKCU:\Control Panel\Desktop" Wallpaper ""
  [W]::SystemParametersInfo(20, 0, "", 3) | Out-Null   # SPI_SETDESKWALLPAPER
  [W]::SetSysColors(1, @(1), @($rgb)) | Out-Null       # COLOR_DESKTOP, 0x00BBGGRR
  Start-Sleep -Seconds 2
}

$h = (Get-Process -Id $ProcessId).MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw "process $ProcessId has no main window" }
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(1, 1)
$r = New-Object W+RECT
# DWMWA_EXTENDED_FRAME_BOUNDS: the visible frame; the margin takes in the shadow.
[W]::DwmGetWindowAttribute($h, 9, [ref]$r, 16) | Out-Null
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$L = [Math]::Max($r.L - $Margin, 0); $T = [Math]::Max($r.T - $Margin, 0)
$R = [Math]::Min($r.R + $Margin, $screen.Right); $B = [Math]::Min($r.B + $Margin, $screen.Bottom)
foreach ($pair in @(@("black", 0x000000), @("white", 0xFFFFFF))) {
  Set-Desktop $pair[1]
  [W]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Seconds 2
  $bmp = New-Object System.Drawing.Bitmap ($R - $L), ($B - $T)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($L, $T, 0, 0, $bmp.Size)
  $bmp.Save("$Out-$($pair[0]).png", [System.Drawing.Imaging.ImageFormat]::Png)
}
Write-Output "window $($r.L),$($r.T)-$($r.R),$($r.B); captured $L,$T-$R,$B (working area $screen)"
