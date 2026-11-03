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
Add-Type -AssemblyName System.Drawing

# Запуск локального мини-сервера для приема команд от HTML
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8080/")
try { $listener.Start() } catch { Exit }

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
    
    # Разрешаем HTML отправлять запросы (CORS)
    $response.Headers.Add("Access-Control-Allow-Origin", "*")
    $response.Headers.Add("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
    $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    
    if ($request.HttpMethod -eq "OPTIONS") {
        $response.StatusCode = 200
        $response.Close()
        continue
    }

    if ($request.Url.LocalPath -eq "/apply" -and $request.HttpMethod -eq "POST") {
        $reader = New-Object System.IO.StreamReader($request.InputStream)
        $colorsStr = $reader.ReadToEnd()
        $data = $colorsStr.Split(',')
        
        $bc = New-Object System.Drawing.Bitmap 32,32
        $bm = New-Object System.Drawing.Bitmap 32,32
        $idx = 0
        for($y=0;$y-lt32;$y++){
            for($x=0;$x-lt32;$x++){
                $c = $data[$idx]; $idx++
                if ($c -and $c -ne "null") {
                    $bc.SetPixel($x, $y, [System.Drawing.ColorTranslator]::FromHtml($c))
                    $bm.SetPixel($x, $y, [System.Drawing.Color]::Black)
                } else {
                    $bc.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
                    $bm.SetPixel($x, $y, [System.Drawing.Color]::White)
                }
            }
        }
        $info = New-Object WinAPI+ICONINFO
        $info.f = $false; $info.x = 0; $info.y = 0
        $info.m = $bm.GetHbitmap(); $info.c = $bc.GetHbitmap()
        $h = [WinAPI]::CreateIconIndirect([ref]$info)
        [WinAPI]::SetSystemCursor($h, 32512)
    } 
    elseif ($request.Url.LocalPath -eq "/reset") {
        [WinAPI]::SPI(0x0057, 0, [IntPtr]::Zero, 0x0002)
    }

    $response.StatusCode = 200
    $response.Close()
}
