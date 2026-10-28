<#
.SYNOPSIS
    Prepara C:\onnx_runtime para el runtime ONNX local de SQL Server 2025.

.DESCRIPTION
    1. Crea la estructura de carpetas que esperan LOCATION y LOCAL_RUNTIME_PATH
       en database\02_modelo_onnx.sql.
    2. Comprueba que están los cuatro archivos necesarios.
    3. Da permisos a la cuenta MSSQLLaunchpad, que es con la que se ejecuta
       AIRuntimeHost (paso 6 del ejemplo oficial de CREATE EXTERNAL MODEL).

    No descarga ni ejecuta nada. onnxruntime.dll y tokenizers_cpp.dll se copian
    a mano (ver README.md) y el modelo se descarga con scripts\descargar_modelo.py.

    Ejecútalo en PowerShell como administrador:
        powershell -ExecutionPolicy Bypass -File scripts\preparar_onnx_runtime.ps1
#>
[CmdletBinding()]
param(
    [string]$RutaRuntime = 'C:\onnx_runtime',
    [string]$CuentaLaunchpad = 'MSSQLLaunchpad'   # instancia por defecto
)

$ErrorActionPreference = 'Stop'
$rutaModelo = Join-Path $RutaRuntime 'model\minilm-sin-padding'   # la que usa LOCATION en 02

# 1. Carpetas
New-Item -ItemType Directory -Force -Path $RutaRuntime | Out-Null
New-Item -ItemType Directory -Force -Path $rutaModelo  | Out-Null
Write-Host "Carpetas preparadas: $RutaRuntime y $rutaModelo"

# 2. Comprobación de archivos
$requeridos = @(
    (Join-Path $RutaRuntime 'onnxruntime.dll'),
    (Join-Path $RutaRuntime 'tokenizers_cpp.dll'),
    (Join-Path $rutaModelo  'model.onnx'),
    (Join-Path $rutaModelo  'tokenizer.json')
)
$faltan = $requeridos | Where-Object { -not (Test-Path $_) }
foreach ($archivo in $requeridos) {
    $estado = if (Test-Path $archivo) { 'OK   ' } else { 'FALTA' }
    Write-Host "  [$estado] $archivo"
}

# 3. Permisos para MSSQLLaunchpad (heredados por subcarpetas y archivos)
#    La documentación oficial usa FullControl.
$acl = Get-Acl -Path $RutaRuntime
$regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $CuentaLaunchpad, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($regla)
Set-Acl -Path $RutaRuntime -AclObject $acl
Write-Host "Permisos concedidos a '$CuentaLaunchpad' sobre $RutaRuntime"

if ($faltan) {
    Write-Warning "Faltan $(@($faltan).Count) archivo(s). Revisa el README antes de ejecutar database\02_modelo_onnx.sql."
    exit 1
}
Write-Host 'Todo listo. Siguiente paso: database\01_configuracion_instancia.sql'
