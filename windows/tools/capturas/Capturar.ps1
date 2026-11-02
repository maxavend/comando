# Portfolio screenshots of Comando for Windows: Windows 11 at 150 %, only the app window
# (no desktop, no border), in light and dark, on a made-up project folder instead of the
# CI machine's own. Each capture is cut to what Windows draws of the window, minus the
# 1 px border it draws around it (2 px at 150 %).
# Usage: windows/tools/capturas/Capturar.ps1 -App out/Comando/Comando.exe -Output out/portafolio
param(
    [Parameter(Mandatory)] [string] $App,
    [Parameter(Mandatory)] [string] $Output,
    [int] $Scale = 150
)
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'Set-Display.ps1') -Scale $Scale

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ComandoWindow
{
    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool PrintWindow(IntPtr window, IntPtr deviceContext, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr deviceContext);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr deviceContext);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleBitmap(IntPtr deviceContext, int width, int height);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr deviceContext, IntPtr gdiObject);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr deviceContext);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr gdiObject);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out Rect value, int size);

    public static double Scale(IntPtr window) { return GetDpiForWindow(window) / 96.0; }

    /// <summary>Puts the window at the top left, at a logical size, and in front.</summary>
    public static void Place(IntPtr window, int width, int height)
    {
        var scale = Scale(window);
        SetWindowPos(window, IntPtr.Zero, 0, 0, (int)(width * scale), (int)(height * scale), 0x0040 | 0x0004);
        SetForegroundWindow(window);
    }

    /// <summary>The window as Windows draws it, Mica included, even where the taskbar covers it.</summary>
    public static IntPtr Print(IntPtr window)
    {
        Rect rect;
        GetWindowRect(window, out rect);
        var screen = GetDC(IntPtr.Zero);
        var memory = CreateCompatibleDC(screen);
        var bitmap = CreateCompatibleBitmap(screen, rect.Right - rect.Left, rect.Bottom - rect.Top);
        var previous = SelectObject(memory, bitmap);
        PrintWindow(window, memory, 2);
        SelectObject(memory, previous);
        DeleteDC(memory);
        ReleaseDC(IntPtr.Zero, screen);
        return bitmap;
    }

    /// <summary>Left, top, width and height of what is visible: the window rectangle also holds the invisible resize border.</summary>
    public static int[] Visible(IntPtr window)
    {
        Rect rect, frame;
        GetWindowRect(window, out rect);
        var visible = DwmGetWindowAttribute(window, 9, out frame, Marshal.SizeOf(typeof(Rect))) == 0 ? frame : rect;
        return new[] { visible.Left - rect.Left, visible.Top - rect.Top, visible.Right - visible.Left, visible.Bottom - visible.Top };
    }
}
"@

New-Item -ItemType Directory -Force $Output | Out-Null

# The made-up projects. Sizes are what the files would weigh; the bytes are empty.
$projects = 'C:\Proyectos'
$nido = Join-Path $projects 'Nido'
$fotos = Join-Path $projects 'Fotos del viaje'
$tesis = Join-Path $projects 'Tesis'
New-Item -ItemType Directory -Force $nido, $fotos, $tesis, (Join-Path $nido 'fotos') | Out-Null
$files = @{
    'entrevista.mov' = 48MB
    'notas-reunion.md' = 6KB
    'presupuesto.xlsx' = 38KB
    'logo.svg' = 4KB
    'fotos\portada.jpg' = 2MB
    'fotos\equipo.jpg' = 3MB
    'fotos\taller.jpg' = 2MB
}
foreach ($file in $files.GetEnumerator()) {
    $path = Join-Path $nido $file.Key
    $stream = [System.IO.File]::Create($path)
    $stream.SetLength($file.Value)
    $stream.Dispose()
}

$settings = Join-Path $env:LOCALAPPDATA 'Comando'
New-Item -ItemType Directory -Force $settings | Out-Null
$env:COMANDO_DEMO_MODEL = '1'

function Write-Sessions {
    $now = [DateTimeOffset]::Now
    $sessions = @(
        @{ Id = [guid]::NewGuid(); Directory = $nido; RecentDirectories = @($nido); ColorIndex = 0; LastActivity = $now.ToString('o'); Entries = @() }
        @{ Id = [guid]::NewGuid(); Directory = $fotos; RecentDirectories = @($fotos); ColorIndex = 1; LastActivity = $now.AddHours(-20).ToString('o'); LastCommand = 'Get-ChildItem *.jpg | Measure-Object'; Entries = @() }
        @{ Id = [guid]::NewGuid(); Directory = $tesis; RecentDirectories = @($tesis); ColorIndex = 2; Emoji = '📚'; LastActivity = $now.AddDays(-2).ToString('o'); LastCommand = 'git log --oneline'; Entries = @() }
    )
    ConvertTo-Json -InputObject $sessions -Depth 4 | Set-Content (Join-Path $settings 'sessions.json') -Encoding utf8
}

function Send([string] $keys, [int] $wait) {
    $script:composer.SetFocus()
    [System.Windows.Forms.SendKeys]::SendWait($keys)
    Start-Sleep -Seconds $wait
}

function Save-Window([string] $name) {
    Start-Sleep -Milliseconds 900
    $handle = [ComandoWindow]::Print($script:window)
    $full = [System.Drawing.Image]::FromHbitmap($handle)
    try {
        $visible = [ComandoWindow]::Visible($script:window)
        $border = [math]::Ceiling([ComandoWindow]::Scale($script:window))
        $area = [System.Drawing.Rectangle]::new($visible[0] + $border, $visible[1] + $border, $visible[2] - 2 * $border, $visible[3] - 2 * $border)
        $cut = $full.Clone($area, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $cut.Save((Join-Path $Output "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        "$name $($cut.Width)x$($cut.Height)"
        $cut.Dispose()
    }
    finally {
        $full.Dispose()
        [ComandoWindow]::DeleteObject($handle) | Out-Null
    }
    if ($script:process.HasExited) { Write-Error "Comando se cerró antes de $name" }
}

foreach ($theme in @(@{ Name = 'claro'; Value = 1; Light = 1 }, @{ Name = 'oscuro'; Value = 2; Light = 0 })) {
    $suffix = $theme.Name
    "{`"HasSeenWelcome`":true,`"Theme`":$($theme.Value)}" | Set-Content (Join-Path $settings 'settings.json')
    Write-Sessions
    # Mica and the title bar buttons follow Windows' own mode too.
    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    New-Item -Force $personalize -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty $personalize AppsUseLightTheme $theme.Light -Type DWord
    Set-ItemProperty $personalize SystemUsesLightTheme $theme.Light -Type DWord

    $script:process = Start-Process -FilePath $App -WorkingDirectory $nido -PassThru
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        $process.Refresh()
        if ($process.HasExited -or $process.MainWindowHandle -ne [IntPtr]::Zero) { break }
    }
    if ($process.HasExited) {
        Get-Content (Join-Path $settings 'sessions.json')
        Get-WinEvent -LogName Application -MaxEvents 6 | Format-List TimeCreated, ProviderName, Message
        Write-Error "Comando se cerró al abrir (código $($process.ExitCode))"
    }
    $script:window = $process.MainWindowHandle
    if ($window -eq [IntPtr]::Zero) { Write-Error 'Comando no abrió su ventana' }
    Start-Sleep -Seconds 10
    # Logical 1260 x 700, the size of Bardo's captures: about 1868 x 1037 at 150 %.
    [ComandoWindow]::Place($window, 1260, 700)
    "Escala $([ComandoWindow]::Scale($window))" | Tee-Object -FilePath (Join-Path $Output 'pantalla.txt')

    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $byProcess = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
    $element = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $byProcess)
    $byName = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Comando')
    $isEdit = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
    $script:composer = $element.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.AndCondition($byName, $isEdit)))
    if ($null -eq $composer) { Write-Error 'No encontré el campo de texto' }

    Send 'Get-ChildItem{ENTER}' 6
    Send 'convierte entrevista.mov a mp4{ENTER}' 12
    Save-Window "01-propuesta-$suffix"

    Send 'gti status{ENTER}' 5
    Save-Window "02-pista-$suffix"

    Send 'para que sirve Comando{ENTER}' 5
    Save-Window "03-asistente-$suffix"

    Send '^k' 3
    Save-Window "04-recetas-$suffix"
    [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
    Start-Sleep -Seconds 1

    # A nested PowerShell opens the embedded terminal.
    Send 'pwsh -NoLogo{ENTER}' 12
    [System.Windows.Forms.SendKeys]::SendWait('Get-ChildItem fotos{ENTER}')
    Start-Sleep -Seconds 4
    Save-Window "05-terminal-$suffix"
    [System.Windows.Forms.SendKeys]::SendWait('exit{ENTER}')
    Start-Sleep -Seconds 4

    Send '^+i' 15
    Save-Window "06-herramientas-$suffix"
    [System.Windows.Forms.SendKeys]::SendWait('^,')
    Start-Sleep -Seconds 3
    Save-Window "07-ajustes-$suffix"

    Stop-Process -Id $process.Id -Force
    Start-Sleep -Seconds 3
}

Get-ChildItem $Output -Filter *.png | ForEach-Object { "$($_.Name) $($_.Length)" }
