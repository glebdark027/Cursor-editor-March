# ============================================================
#  Cursor Editor — сервер для Windows 10
#  POST /apply  — строка из 1024 цветов через запятую
#  GET  /reset  — возврат системного курсора
# ============================================================

$ErrorActionPreference = "Stop"

try {
    Add-Type -AssemblyName System.Drawing
} catch {
    Write-Host "[!] Не удалось загрузить System.Drawing:" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Нажми Enter, чтобы выйти..."
    Read-Host | Out-Null
    exit
}

try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")] public static extern bool SetSystemCursor(IntPtr h, uint id);
    [DllImport("user32.dll")] public static extern IntPtr CreateIconIndirect(ref ICONINFO p);
    [DllImport("user32.dll", EntryPoint="SystemParametersInfo")] public static extern bool SPI(uint u, uint p, IntPtr pv, uint f);
    public struct ICONINFO { public bool f; public uint x; public uint y; public IntPtr m; public IntPtr c; }
}
"@
} catch {
    Write-Host "[!] Не удалось скомпилировать WinAPI:" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Нажми Enter, чтобы выйти..."
    Read-Host | Out-Null
    exit
}

$PORT = 8080
$URL  = "http://localhost:$PORT/"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  CURSOR EDITOR — SERVER" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Проверка, что порт свободен
try {
    $t = New-Object System.Net.Sockets.TcpClient
    $t.Connect("127.0.0.1", $PORT)
    $t.Close()
    Write-Host "[!] Порт $PORT уже занят." -ForegroundColor Red
    Write-Host "    Закрой старое окно PowerShell с сервером и запусти заново." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Нажми Enter, чтобы выйти..."
    Read-Host | Out-Null
    exit
} catch { }

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($URL)

try {
    $listener.Start()
} catch {
    Write-Host "[!] Не удалось запустить сервер:" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Попробуй запустить PowerShell от имени администратора," -ForegroundColor Yellow
    Write-Host "    либо проверь, не блокирует ли антивирус порт $PORT." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Нажми Enter, чтобы выйти..."
    Read-Host | Out-Null
    exit
}

Write-Host "[OK] Сервер запущен на $URL" -ForegroundColor Green
Write-Host "[OK] Не закрывай это окно! Сверни его." -ForegroundColor Green
Write-Host ""
Write-Host "     Жду команды от HTML-редактора..." -ForegroundColor DarkGray
Write-Host ""

$lastAction = ""

while ($listener.IsListening) {

    $context  = $null
    $request  = $null
    $response = $null

    try {
        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response

        $response.Headers.Add("Access-Control-Allow-Origin",  "*")
        $response.Headers.Add("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")

        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        # ---------- /apply ----------
        if ($request.Url.LocalPath -eq "/apply" -and $request.HttpMethod -eq "POST") {

            $reader    = New-Object System.IO.StreamReader($request.InputStream)
            $colorsStr = $reader.ReadToEnd()
            $reader.Close()

            if ([string]::IsNullOrWhiteSpace($colorsStr)) {
                Write-Host "[!] /apply: пустое тело запроса" -ForegroundColor Yellow
                $response.StatusCode = 400
                $response.Close()
                continue
            }

            $data = $colorsStr.Split(',')

            if ($data.Length -lt 1024) {
                Write-Host "[!] /apply: получено $($data.Length) цветов, нужно 1024" -ForegroundColor Yellow
                $response.StatusCode = 400
                $response.Close()
                continue
            }

            $bc  = New-Object System.Drawing.Bitmap 32,32
            $bm  = New-Object System.Drawing.Bitmap 32,32
            $idx = 0

            for ($y = 0; $y -lt 32; $y++) {
                for ($x = 0; $x -lt 32; $x++) {

                    $c = $data[$idx]
                    $idx++

                    if ($c -and $c -ne "null" -and $c -ne "") {
                        try {
                            $bc.SetPixel($x, $y, [System.Drawing.ColorTranslator]::FromHtml($c))
                        } catch {
                            $bc.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
                        }
                        $bm.SetPixel($x, $y, [System.Drawing.Color]::Black)
                    }
                    else {
                        $bc.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
                        $bm.SetPixel($x, $y, [System.Drawing.Color]::White)
                    }
                }
            }

            $info    = New-Object WinAPI+ICONINFO
            $info.f  = $false
            $info.x  = 0
            $info.y  = 0
            $info.m  = $bm.GetHbitmap()
            $info.c  = $bc.GetHbitmap()
            $h       = [WinAPI]::CreateIconIndirect([ref]$info)
            [WinAPI]::SetSystemCursor($h, 32512) | Out-Null

            $bc.Dispose()
            $bm.Dispose()

            if ($lastAction -ne "apply") {
                Write-Host "[OK] Курсор применён!" -ForegroundColor Green
                $lastAction = "apply"
            }

            $response.StatusCode = 200
            $response.Close()
            continue
        }

        # ---------- /reset ----------
        if ($request.Url.LocalPath -eq "/reset") {

            [WinAPI]::SPI(0x0057, 0, [IntPtr]::Zero, 0x0002) | Out-Null

            if ($lastAction -ne "reset") {
                Write-Host "[OK] Курсор сброшен к системному" -ForegroundColor Green
                $lastAction = "reset"
            }

            $response.StatusCode = 200
            $response.Close()
            continue
        }

        $response.StatusCode = 404
        $response.Close()
    }
    catch {
        Write-Host "[!] Ошибка в цикле сервера: $($_.Exception.Message)" -ForegroundColor Red
        try {
            if ($response) { $response.StatusCode = 500; $response.Close() }
        } catch { }
    }
}
Write-Host ""
Write-Host "Нажми Enter, чтобы закрыть окно..."
Read-Host | Out-Null