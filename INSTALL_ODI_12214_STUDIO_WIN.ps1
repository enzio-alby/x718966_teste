#Requires -RunAsAdministrator
# =============================================================================
# INSTALACAO ODI Studio 12.2.1.4 STANDALONE - Oraex / Getnet - Windows
#
# Modo    : Standalone Installation (Studio Only)
# Java    : instalado previamente pelo usuario (JDK 8 .exe)
# Bundle  : ODI_SPB_12.2.1.4.260714 (julho/2026) via SPBAT generic
# CVE     : 34809489 (CVE-2021-42575) via opatch apply
# RCU     : NAO necessario na instalacao - equipe configura separado
#
# USO: .\INSTALL_ODI_12214_STUDIO_WIN.ps1
# Executar como Administrador.
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── LOG ─────────────────────────────────────────────────────────────────────

$LogDir  = "$env:TEMP\oraex_logs"
$null    = New-Item -ItemType Directory -Force -Path $LogDir
$LogFile = "$LogDir\install_odi12214_studio_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Level, [string]$Msg, [string]$Color = 'White')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts][$Level] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $line
}
function Log-Info { param([string]$m) Write-Log 'INFO ' $m 'Cyan'   }
function Log-OK   { param([string]$m) Write-Log 'OK   ' $m 'Green'  }
function Log-Warn { param([string]$m) Write-Log 'WARN ' $m 'Yellow' }
function Log-Erro { param([string]$m) Write-Log 'ERRO ' $m 'Red'    }
function Log-Step {
    param([string]$m)
    $sep = '=' * 64
    Write-Host "`n$sep" -ForegroundColor Blue
    Write-Host "  $m"   -ForegroundColor Blue
    Write-Host "$sep`n" -ForegroundColor Blue
    Add-Content -Path $LogFile -Value "`n$sep`n  $m`n$sep"
}

function Ask {
    param([string]$Prompt, [string]$Default = '')
    $hint = if ($Default) { " [$Default]" } else { '' }
    $resp = Read-Host "  $Prompt$hint"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $Default }
    return $resp.Trim()
}

# ─── BANNER ──────────────────────────────────────────────────────────────────

function Show-Banner {
    Clear-Host
    Write-Host @'

  +================================================================+
  |   INSTALACAO ODI Studio 12.2.1.4 STANDALONE - Oraex/Getnet   |
  |   Modo: Studio Only  |  Sem dominio  |  Sem RCU               |
  |   Bundle: ODI_SPB_12.2.1.4.260714  |  CVE: 34809489          |
  +================================================================+

'@ -ForegroundColor Blue
    Write-Host "  Host : $($env:COMPUTERNAME)" -ForegroundColor Cyan
    Write-Host "  Log  : $LogFile`n"           -ForegroundColor Cyan
}

# ─── COLETA ──────────────────────────────────────────────────────────────────

$InstallDir    = ''
$OracleHome    = ''
$JavaHome      = ''
$JarOdiPath    = ''
$OPatchZipPath = ''
$BundleZipPath = ''
$CveInput      = ''
$PatchDir      = ''

function Coletar-Infos {
    Log-Step "Coleta de Informacoes"

    $script:InstallDir = Ask 'INSTALL_DIR (pasta para response file e resumo)' 'C:\oracle\install'
    $script:OracleHome = Ask 'ORACLE_HOME (destino da instalacao)'              'C:\oracle\middleware'
    $script:JavaHome   = Ask 'JAVA_HOME (JDK 8 ja instalado)'                  'C:\Java\jdk1.8.0_501'

    # Validar JAVA_HOME
    $java = Join-Path $script:JavaHome 'bin\java.exe'
    if (-not (Test-Path $java)) {
        Log-Erro "java.exe nao encontrado: $java"
        Log-Erro "Instale o JDK 8 manualmente e informe o caminho correto."
        exit 1
    }
    $ver = & { $ErrorActionPreference = 'Continue'; & $java -version 2>&1 } | Select-String 'version'
    Log-OK "Java OK: $ver"

    Write-Host ''
    Write-Host '  --- ARQUIVOS DE INSTALACAO ---' -ForegroundColor Yellow
    Write-Host ''

    # JAR ODI — caminho completo, sem auto-deteccao
    $script:JarOdiPath = Ask 'Caminho completo do JAR ODI (fmw_12.2.1.4.0_odi.jar)' 'D:\Oraex\fmw_12.2.1.4.0_odi.jar'
    if (-not (Test-Path $script:JarOdiPath)) {
        Log-Erro "JAR nao encontrado: $($script:JarOdiPath)"
        exit 1
    }
    Log-OK "JAR ODI validado: $($script:JarOdiPath)"

    Write-Host ''
    Write-Host '  --- PATCHES (caminho completo do ZIP ou pasta) ---' -ForegroundColor Yellow
    Write-Host ''

    # OPatch — ZIP ou pasta ja extraida
    $script:OPatchZipPath = Ask 'OPatch: ZIP (p6880880_*.zip) ou pasta descompactada — Enter para pular' ''
    if ($script:OPatchZipPath -and (-not (Test-Path $script:OPatchZipPath))) {
        Log-Erro "OPatch nao encontrado (ZIP ou pasta): $($script:OPatchZipPath)"
        exit 1
    }

    # Bundle ODI — ZIP ou pasta ja extraida
    $script:BundleZipPath = Ask 'Bundle ODI: ZIP (ODI_SPB_*.zip) ou pasta descompactada' ''
    if ($script:BundleZipPath -and (-not (Test-Path $script:BundleZipPath))) {
        Log-Erro "Bundle ODI nao encontrado (ZIP ou pasta): $($script:BundleZipPath)"
        exit 1
    }

    # CVE 34809489 — ZIP ou pasta ja extraida
    $script:CveInput = Ask 'ZIP ou pasta do patch CVE 34809489 — Enter para pular' ''
    if ($script:CveInput -and (-not (Test-Path $script:CveInput))) {
        Log-Erro "Patch CVE nao encontrado: $($script:CveInput)"
        exit 1
    }

    Write-Host ''
    Write-Host '  --- EXTRACAO ---' -ForegroundColor Yellow
    Write-Host ''

    # Pasta onde os patches serao extraidos
    $defaultPatch = Split-Path $script:JarOdiPath -Parent
    $script:PatchDir = Ask "PATCH_DIR (pasta onde extrair os patches)" $defaultPatch

    # Resumo
    Write-Host ''
    Write-Host '  Resumo:' -ForegroundColor White
    Write-Host "  INSTALL_DIR  : $($script:InstallDir)"  -ForegroundColor Cyan
    Write-Host "  ORACLE_HOME  : $($script:OracleHome)"  -ForegroundColor Cyan
    Write-Host "  JAVA_HOME    : $($script:JavaHome)"    -ForegroundColor Cyan
    Write-Host "  JAR ODI      : $($script:JarOdiPath)"  -ForegroundColor Cyan
    Write-Host "  OPatch ZIP   : $(if ($script:OPatchZipPath) { $script:OPatchZipPath } else { '(pulando)' })" -ForegroundColor Cyan
    Write-Host "  Bundle ZIP   : $(if ($script:BundleZipPath) { $script:BundleZipPath } else { '(pulando)' })" -ForegroundColor Cyan
    Write-Host "  CVE 34809489 : $(if ($script:CveInput) { $script:CveInput } else { '(pulando)' })"         -ForegroundColor Cyan
    Write-Host "  PATCH_DIR    : $($script:PatchDir)"    -ForegroundColor Cyan
    Write-Host "  TIPO         : Standalone Installation (Studio Only)" -ForegroundColor Cyan
    Write-Host ''

    $conf = Ask 'Confirma? (s/n)' 's'
    if ($conf -ne 's') {
        Log-Info "Cancelado pelo usuario."
        exit 0
    }
}

# ─── INSTALAR ODI ────────────────────────────────────────────────────────────

function Instalar-ODI {
    Log-Step "Instalacao ODI Studio 12.2.1.4"

    $jarPath = $script:JarOdiPath
    if (-not (Test-Path $jarPath)) {
        Log-Erro "JAR nao encontrado: $jarPath"
        exit 1
    }

    # Idempotente: pula se ja instalado
    if (Test-Path (Join-Path $script:OracleHome 'odi\studio\odi.exe')) {
        Log-OK "ODI Studio ja instalado em $($script:OracleHome). Pulando."
        return
    }

    # Response file
    $rspDir  = Join-Path $script:InstallDir 'response'
    $null    = New-Item -ItemType Directory -Force -Path $rspDir
    $rspFile = Join-Path $rspDir 'odi_studio.rsp'

    @"
[ENGINE]
Response File Version=1.0.0.0.0

[GENERIC]
ORACLE_HOME=$($script:OracleHome)
INSTALL_TYPE=Standalone Installation
DECLINE_SECURITY_UPDATES=true
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
MYORACLESUPPORT_USERNAME=
MYORACLESUPPORT_PASSWORD=
PROXY_HOST=
PROXY_PORT=
PROXY_USER=
PROXY_PWD=
COLLECTOR_SUPPORTHUB_URL=
"@ | Out-File -FilePath $rspFile -Encoding ascii

    Log-OK "Response file: $rspFile"
    Log-Info "Instalando ODI Studio (aguarde 5-10 min)..."

    $java   = Join-Path $script:JavaHome 'bin\java.exe'
    $stdOut = "$LogDir\odi_stdout.log"
    $stdErr = "$LogDir\odi_stderr.log"

    $proc = Start-Process -FilePath $java `
        -ArgumentList @(
            '-jar', $jarPath,
            '-silent',
            '-ignoreSysPrereqs',
            '-responseFile', $rspFile
        ) `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdOut `
        -RedirectStandardError  $stdErr

    Get-Content $stdOut -ErrorAction SilentlyContinue | Add-Content -Path $LogFile
    Get-Content $stdErr -ErrorAction SilentlyContinue | Add-Content -Path $LogFile

    if ($proc.ExitCode -ne 0) {
        Log-Erro "Instalador retornou exit code $($proc.ExitCode)."
        Log-Erro "Verifique: $stdErr"
        exit 1
    }

    Log-OK "ODI Studio 12.2.1.4 instalado em $($script:OracleHome)"
}

# ─── ATUALIZAR OPATCH ────────────────────────────────────────────────────────

function Atualizar-OPatch {
    Log-Step "Atualizacao OPatch (6880880)"

    if ([string]::IsNullOrWhiteSpace($script:OPatchZipPath)) {
        Log-Warn "OPatch nao informado — pulando atualizacao de OPatch."
        return
    }

    $java      = Join-Path $script:JavaHome 'bin\java.exe'
    $opatchJar = $null

    if (Test-Path $script:OPatchZipPath -PathType Leaf) {
        # E um ZIP — extrair primeiro
        Log-Info "OPatch ZIP detectado: $($script:OPatchZipPath)"
        Log-Info "Extraindo para $($script:PatchDir)..."
        Expand-Archive -Path $script:OPatchZipPath -DestinationPath $script:PatchDir -Force
        $opatchJar = Join-Path $script:PatchDir '6880880\opatch_generic.jar'
    } elseif (Test-Path $script:OPatchZipPath -PathType Container) {
        # E uma pasta ja extraida — procurar opatch_generic.jar dentro dela
        Log-Info "OPatch pasta detectada: $($script:OPatchZipPath)"
        $found = @(Get-ChildItem -Path $script:OPatchZipPath -Recurse -Filter 'opatch_generic.jar' -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) {
            $opatchJar = $found[0].FullName
        }
    }

    if (-not $opatchJar -or (-not (Test-Path $opatchJar))) {
        Log-Erro "opatch_generic.jar nao encontrado em: $($script:OPatchZipPath)"
        exit 1
    }

    Log-Info "opatch_generic.jar: $opatchJar"
    Log-Info "Instalando OPatch no ORACLE_HOME..."
    $proc = Start-Process -FilePath $java `
        -ArgumentList @('-jar', $opatchJar, '-silent', "oracle_home=$($script:OracleHome)") `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput "$LogDir\opatch_install_stdout.log" `
        -RedirectStandardError  "$LogDir\opatch_install_stderr.log"

    Get-Content "$LogDir\opatch_install_stdout.log" -ErrorAction SilentlyContinue | Add-Content -Path $LogFile
    Get-Content "$LogDir\opatch_install_stderr.log" -ErrorAction SilentlyContinue | Add-Content -Path $LogFile

    if ($proc.ExitCode -ne 0) {
        Log-Erro "Atualizacao OPatch falhou (exit code $($proc.ExitCode))."
        exit 1
    }

    $opatchBat = Join-Path $script:OracleHome 'OPatch\opatch.bat'
    if (Test-Path $opatchBat) {
        Log-OK "OPatch atualizado — $opatchBat"
    } else {
        Log-Erro "opatch.bat nao encontrado em $opatchBat apos atualizacao."
        exit 1
    }
}

# ─── APLICAR BUNDLE ODI ──────────────────────────────────────────────────────

function Aplicar-Bundle-ODI {
    Log-Step "Aplicacao Bundle ODI_SPB_12.2.1.4.260714"

    if ([string]::IsNullOrWhiteSpace($script:BundleZipPath)) {
        Log-Erro "Bundle ODI nao informado. Informe o ZIP ou a pasta do ODI_SPB."
        exit 1
    }

    $searchBase = $null

    if (Test-Path $script:BundleZipPath -PathType Leaf) {
        # E um ZIP — extrair primeiro
        Log-Info "Bundle ZIP detectado: $($script:BundleZipPath)"
        Log-Info "Extraindo para $($script:PatchDir) (aguarde)..."
        Expand-Archive -Path $script:BundleZipPath -DestinationPath $script:PatchDir -Force
        $searchBase = $script:PatchDir
    } elseif (Test-Path $script:BundleZipPath -PathType Container) {
        # E uma pasta ja extraida
        Log-Info "Bundle pasta detectada: $($script:BundleZipPath)"
        $searchBase = $script:BundleZipPath
    } else {
        Log-Erro "Bundle ODI nao encontrado (ZIP ou pasta): $($script:BundleZipPath)"
        exit 1
    }

    $spbat = @(Get-ChildItem -Path $searchBase -Recurse -Filter 'spbat.cmd' -ErrorAction SilentlyContinue)
    if ($spbat.Count -eq 0) {
        Log-Erro "spbat.cmd nao encontrado em: $searchBase"
        exit 1
    }

    $spbatDir = Split-Path $spbat[0].FullName -Parent
    Log-Info "SPBAT: $($spbat[0].FullName)"
    Log-Info "Aplicando Bundle ODI (aguarde, pode demorar varios minutos)..."

    $proc = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList @('/c', "spbat.cmd -phase apply -oracle_home `"$($script:OracleHome)`"") `
        -WorkingDirectory $spbatDir `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput "$LogDir\bundle_odi_stdout.log" `
        -RedirectStandardError  "$LogDir\bundle_odi_stderr.log"

    Get-Content "$LogDir\bundle_odi_stdout.log" -ErrorAction SilentlyContinue | Add-Content -Path $LogFile
    Get-Content "$LogDir\bundle_odi_stderr.log" -ErrorAction SilentlyContinue | Add-Content -Path $LogFile

    if ($proc.ExitCode -ne 0) {
        Log-Erro "Bundle ODI retornou exit code $($proc.ExitCode). Verifique: $LogDir\bundle_odi_stdout.log"
        exit 1
    }

    Log-OK "Bundle ODI_SPB_12.2.1.4.260714 aplicado com sucesso."
}

# ─── APLICAR PATCH CVE-2021-42575 (34809489) ─────────────────────────────────

function Aplicar-Patch-CVE {
    Log-Step "Aplicacao Patch CVE-2021-42575 (34809489)"

    if ([string]::IsNullOrWhiteSpace($script:CveInput)) {
        Log-Warn "Patch CVE 34809489 nao informado — pulando."
        return
    }

    $opatchBat = Join-Path $script:OracleHome 'OPatch\opatch.bat'
    if (-not (Test-Path $opatchBat)) {
        Log-Erro "opatch.bat nao encontrado: $opatchBat"
        exit 1
    }

    $patchDir34 = Join-Path $script:PatchDir '34809489'

    # Se o input for uma pasta ja extraida, usar direto
    if (Test-Path $script:CveInput -PathType Container) {
        $patchDir34 = $script:CveInput
        Log-Info "Pasta do patch CVE: $patchDir34"
    } elseif (Test-Path $script:CveInput -PathType Leaf) {
        # E um ZIP — extrair
        Log-Info "Extraindo patch 34809489 de $($script:CveInput)..."
        Expand-Archive -Path $script:CveInput -DestinationPath $script:PatchDir -Force
        if (-not (Test-Path $patchDir34)) {
            Log-Erro "Pasta 34809489 nao encontrada em $($script:PatchDir) apos extracao."
            Log-Erro "Verifique se o ZIP contem a pasta 34809489 na raiz."
            exit 1
        }
    } else {
        Log-Erro "Caminho do patch CVE nao encontrado: $($script:CveInput)"
        exit 1
    }

    Log-Info "Aplicando patch 34809489 (CVE-2021-42575)..."

    $proc = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList @('/c', "`"$opatchBat`" apply -silent") `
        -WorkingDirectory $patchDir34 `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput "$LogDir\patch_cve_stdout.log" `
        -RedirectStandardError  "$LogDir\patch_cve_stderr.log"

    Get-Content "$LogDir\patch_cve_stdout.log" -ErrorAction SilentlyContinue | Add-Content -Path $LogFile
    Get-Content "$LogDir\patch_cve_stderr.log" -ErrorAction SilentlyContinue | Add-Content -Path $LogFile

    if ($proc.ExitCode -ne 0) {
        Log-Erro "Patch 34809489 retornou exit code $($proc.ExitCode). Verifique: $LogDir\patch_cve_stdout.log"
        exit 1
    }

    Log-OK "Patch 34809489 (CVE-2021-42575) aplicado com sucesso."
}

# ─── RESUMO FINAL ────────────────────────────────────────────────────────────

function Gerar-Resumo {
    Log-Step "Resumo Final"

    $studio  = Join-Path $script:OracleHome 'odi\studio\odi.exe'
    $summary = Join-Path (Join-Path $script:InstallDir 'response') `
               "install_summary_odi12214_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

    $txt = @"
# ============================================================
# RESUMO INSTALACAO ODI Studio 12.2.1.4 STANDALONE
# Data  : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
# Host  : $env:COMPUTERNAME
# ============================================================

INSTALL_DIR   = $($script:InstallDir)
ORACLE_HOME   = $($script:OracleHome)
JAVA_HOME     = $($script:JavaHome)
JAR ODI       = $($script:JarOdiPath)
OPatch ZIP    = $(if ($script:OPatchZipPath) { $script:OPatchZipPath } else { '(nao aplicado)' })
Bundle ZIP    = $(if ($script:BundleZipPath) { $script:BundleZipPath } else { '(nao aplicado)' })
CVE 34809489  = $(if ($script:CveInput) { $script:CveInput } else { '(nao aplicado)' })
PATCH_DIR     = $($script:PatchDir)
TIPO          = Standalone Installation (Studio Only)
BUNDLE        = ODI_SPB_12.2.1.4.260714 (julho/2026)
CVE PATCH     = 34809489 (CVE-2021-42575)

# Como abrir o ODI Studio
Studio EXE    = $studio

# Conexao ao repositorio (feita DENTRO do Studio pela equipe apos RCU)
# File > New ODI Connection
#   URL JDBC Master Repo : jdbc:oracle:thin:@<HOST>:<PORTA>/<SERVICE>
#   Schema               : <PREFIX>_ODI_REPO  (criado via RCU)
#   Work Repository      : definido pela equipe

# Log de instalacao
Log           = $LogFile
"@

    $null = New-Item -ItemType Directory -Force -Path (Split-Path $summary -Parent)
    $txt | Out-File -FilePath $summary -Encoding utf8
    Write-Host $txt -ForegroundColor Cyan
    Log-OK "Resumo salvo: $summary"

    if (Test-Path $studio) {
        Log-OK "ODI Studio pronto — $studio"
    } else {
        Log-Warn "odi.exe nao encontrado em $studio — verifique o log."
    }
}

# ─── MAIN ────────────────────────────────────────────────────────────────────

Show-Banner
Coletar-Infos
Instalar-ODI
Atualizar-OPatch
Aplicar-Bundle-ODI
Aplicar-Patch-CVE
Gerar-Resumo
