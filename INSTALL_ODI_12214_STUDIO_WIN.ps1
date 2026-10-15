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

# --- LOG ---------------------------------------------------------------------

$script:LogDir  = "$env:TEMP\oraex_logs"
$null           = New-Item -ItemType Directory -Force -Path $script:LogDir
$script:LogFile = "$($script:LogDir)\install_odi12214_studio_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Level, [string]$Msg, [string]$Color = 'White')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts][$Level] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $script:LogFile -Value $line
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
    Add-Content -Path $script:LogFile -Value "`n$sep`n  $m`n$sep"
}

function Ask {
    param([string]$Prompt, [string]$Default = '')
    $hint = if ($Default) { " [$Default]" } else { '' }
    $resp = Read-Host "  $Prompt$hint"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $Default }
    return $resp.Trim()
}

function Validar-SemEspacos {
    param([string]$Nome, [string]$Valor)
    if ($Valor -match '\s') {
        Log-Erro "$Nome contem espacos: '$Valor'. SPBAT e OPatch nao suportam paths com espacos. Informe um caminho sem espacos."
        exit 1
    }
}

# --- BANNER ------------------------------------------------------------------

function Show-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '  +================================================================+' -ForegroundColor Blue
    Write-Host '  |   INSTALACAO ODI Studio 12.2.1.4 STANDALONE - Oraex/Getnet   |' -ForegroundColor Blue
    Write-Host '  |   Modo: Studio Only  |  Sem dominio  |  Sem RCU               |' -ForegroundColor Blue
    Write-Host '  |   Bundle: ODI_SPB_12.2.1.4.260714  |  CVE: 34809489          |' -ForegroundColor Blue
    Write-Host '  +================================================================+' -ForegroundColor Blue
    Write-Host ''
    Write-Host "  Host : $($env:COMPUTERNAME)" -ForegroundColor Cyan
    Write-Host "  Log  : (sera definido em LOG_DIR apos configuracao)`n" -ForegroundColor Cyan
}

# --- COLETA ------------------------------------------------------------------

$script:InstallDir    = ''
$script:OracleHome    = ''
$script:JavaHome      = ''
$script:JarOdiPath    = ''
$script:OPatchZipPath = ''
$script:BundleZipPath = ''
$script:CveInput      = ''
$script:LogDirFinal   = ''
$script:PatchDir      = ''

function Coletar-Infos {
    Log-Step "Coleta de Informacoes"

    $script:InstallDir  = Ask 'INSTALL_DIR (pasta para response file e resumo)' 'C:\oracle\install'
    Validar-SemEspacos 'INSTALL_DIR' $script:InstallDir

    $script:LogDirFinal = Ask 'LOG_DIR (pasta para os logs desta instalacao)' "$($script:InstallDir)\logs"
    Validar-SemEspacos 'LOG_DIR' $script:LogDirFinal

    $script:OracleHome  = Ask 'ORACLE_HOME (destino da instalacao)' 'C:\oracle\middleware'
    Validar-SemEspacos 'ORACLE_HOME' $script:OracleHome

    $script:JavaHome    = Ask 'JAVA_HOME (JDK 8 ja instalado)' 'C:\Java\jdk1.8.0_501'
    Validar-SemEspacos 'JAVA_HOME' $script:JavaHome

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

    $script:JarOdiPath = Ask 'Caminho completo do JAR ODI (fmw_12.2.1.4.0_odi.jar)' 'D:\Oraex\fmw_12.2.1.4.0_odi.jar'
    if (-not (Test-Path $script:JarOdiPath)) {
        Log-Erro "JAR nao encontrado: $($script:JarOdiPath)"
        exit 1
    }
    Log-OK "JAR ODI validado: $($script:JarOdiPath)"

    Write-Host ''
    Write-Host '  --- PATCHES (ZIP ou pasta descompactada) ---' -ForegroundColor Yellow
    Write-Host ''

    $script:OPatchZipPath = Ask 'OPatch: ZIP (p6880880_*.zip) ou pasta descompactada - Enter para pular' ''
    if ($script:OPatchZipPath -and (-not (Test-Path $script:OPatchZipPath))) {
        Log-Erro "OPatch nao encontrado (ZIP ou pasta): $($script:OPatchZipPath)"
        exit 1
    }

    $script:BundleZipPath = Ask 'Bundle ODI: ZIP (ODI_SPB_*.zip) ou pasta descompactada' ''
    if ($script:BundleZipPath -and (-not (Test-Path $script:BundleZipPath))) {
        Log-Erro "Bundle ODI nao encontrado (ZIP ou pasta): $($script:BundleZipPath)"
        exit 1
    }

    $script:CveInput = Ask 'ZIP ou pasta do patch CVE 34809489 - Enter para pular' ''
    if ($script:CveInput -and (-not (Test-Path $script:CveInput))) {
        Log-Erro "Patch CVE nao encontrado: $($script:CveInput)"
        exit 1
    }

    Write-Host ''
    Write-Host '  --- EXTRACAO ---' -ForegroundColor Yellow
    Write-Host ''

    $defaultPatch = Split-Path $script:JarOdiPath -Parent
    $script:PatchDir = Ask 'PATCH_DIR (pasta onde extrair os patches)' $defaultPatch
    Validar-SemEspacos 'PATCH_DIR' $script:PatchDir

    Write-Host ''
    Write-Host '  Resumo:' -ForegroundColor White
    Write-Host "  INSTALL_DIR  : $($script:InstallDir)"  -ForegroundColor Cyan
    Write-Host "  LOG_DIR      : $($script:LogDirFinal)" -ForegroundColor Cyan
    Write-Host "  ORACLE_HOME  : $($script:OracleHome)"  -ForegroundColor Cyan
    Write-Host "  JAVA_HOME    : $($script:JavaHome)"    -ForegroundColor Cyan
    Write-Host "  JAR ODI      : $($script:JarOdiPath)"  -ForegroundColor Cyan

    if ($script:OPatchZipPath) {
        Write-Host "  OPatch       : $($script:OPatchZipPath)" -ForegroundColor Cyan
    } else {
        Write-Host '  OPatch       : (pulando)' -ForegroundColor Cyan
    }

    if ($script:BundleZipPath) {
        Write-Host "  Bundle ODI   : $($script:BundleZipPath)" -ForegroundColor Cyan
    } else {
        Write-Host '  Bundle ODI   : (pulando)' -ForegroundColor Cyan
    }

    if ($script:CveInput) {
        Write-Host "  CVE 34809489 : $($script:CveInput)" -ForegroundColor Cyan
    } else {
        Write-Host '  CVE 34809489 : (pulando)' -ForegroundColor Cyan
    }

    Write-Host "  PATCH_DIR    : $($script:PatchDir)"  -ForegroundColor Cyan
    Write-Host "  TIPO         : Standalone Installation (Studio Only)" -ForegroundColor Cyan
    Write-Host ''

    $conf = Ask 'Confirma? (s/n)' 's'
    if ($conf -ne 's') {
        Log-Info "Cancelado pelo usuario."
        exit 0
    }
}

# --- INSTALAR ODI ------------------------------------------------------------

function Instalar-ODI {
    Log-Step "Instalacao ODI Studio 12.2.1.4"

    if (Test-Path (Join-Path $script:OracleHome 'odi\studio\odi.exe')) {
        Log-OK "ODI Studio ja instalado em $($script:OracleHome). Pulando."
        return
    }

    if (-not (Test-Path $script:JarOdiPath)) {
        Log-Erro "JAR nao encontrado: $($script:JarOdiPath)"
        exit 1
    }

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
    $stdOut = "$($script:LogDir)\odi_stdout.log"
    $stdErr = "$($script:LogDir)\odi_stderr.log"

    $proc = Start-Process -FilePath $java `
        -ArgumentList @('-jar', $script:JarOdiPath, '-silent', '-ignoreSysPrereqs', '-responseFile', $rspFile) `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdOut `
        -RedirectStandardError  $stdErr

    Get-Content $stdOut -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile
    Get-Content $stdErr -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile

    if ($proc.ExitCode -ne 0) {
        Log-Erro "Instalador retornou exit code $($proc.ExitCode). Verifique: $stdErr"
        exit 1
    }

    Log-OK "ODI Studio 12.2.1.4 instalado em $($script:OracleHome)"
}

# --- ATUALIZAR OPATCH --------------------------------------------------------

function Atualizar-OPatch {
    Log-Step "Atualizacao OPatch (6880880)"

    if ([string]::IsNullOrWhiteSpace($script:OPatchZipPath)) {
        Log-Warn "OPatch nao informado - pulando."
        return
    }

    $java      = Join-Path $script:JavaHome 'bin\java.exe'
    $opatchJar = $null

    if (Test-Path $script:OPatchZipPath -PathType Leaf) {
        Log-Info "OPatch ZIP detectado: $($script:OPatchZipPath)"
        Log-Info "Extraindo para $($script:PatchDir)..."
        Expand-Archive -Path $script:OPatchZipPath -DestinationPath $script:PatchDir -Force
        $opatchJar = Join-Path $script:PatchDir '6880880\opatch_generic.jar'
    } elseif (Test-Path $script:OPatchZipPath -PathType Container) {
        Log-Info "OPatch pasta detectada: $($script:OPatchZipPath)"
        $found = @(Get-ChildItem -Path $script:OPatchZipPath -Recurse -Filter 'opatch_generic.jar' -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) {
            $opatchJar = $found[0].FullName
        }
    }

    if ((-not $opatchJar) -or (-not (Test-Path $opatchJar))) {
        Log-Erro "opatch_generic.jar nao encontrado em: $($script:OPatchZipPath)"
        exit 1
    }

    Log-Info "opatch_generic.jar: $opatchJar"
    Log-Info "Instalando OPatch no ORACLE_HOME..."

    $proc = Start-Process -FilePath $java `
        -ArgumentList @('-jar', $opatchJar, '-silent', "oracle_home=$($script:OracleHome)") `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput "$($script:LogDir)\opatch_install_stdout.log" `
        -RedirectStandardError  "$($script:LogDir)\opatch_install_stderr.log"

    Get-Content "$($script:LogDir)\opatch_install_stdout.log" -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile
    Get-Content "$($script:LogDir)\opatch_install_stderr.log" -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile

    if ($proc.ExitCode -ne 0) {
        Log-Erro "Atualizacao OPatch falhou (exit code $($proc.ExitCode))."
        exit 1
    }

    $opatchBat = Join-Path $script:OracleHome 'OPatch\opatch.bat'
    if (Test-Path $opatchBat) {
        Log-OK "OPatch atualizado: $opatchBat"
    } else {
        Log-Erro "opatch.bat nao encontrado em $opatchBat apos atualizacao."
        exit 1
    }
}

# --- APLICAR BUNDLE ODI ------------------------------------------------------

function Aplicar-Bundle-ODI {
    Log-Step "Aplicacao Bundle ODI_SPB_12.2.1.4.260714"

    if ([string]::IsNullOrWhiteSpace($script:BundleZipPath)) {
        Log-Erro "Bundle ODI nao informado. Informe o ZIP ou a pasta do ODI_SPB."
        exit 1
    }

    $searchBase = $null

    if (Test-Path $script:BundleZipPath -PathType Leaf) {
        Log-Info "Bundle ZIP detectado: $($script:BundleZipPath)"
        Log-Info "Extraindo para $($script:PatchDir) (aguarde)..."
        Expand-Archive -Path $script:BundleZipPath -DestinationPath $script:PatchDir -Force
        $searchBase = $script:PatchDir
    } elseif (Test-Path $script:BundleZipPath -PathType Container) {
        Log-Info "Bundle pasta detectada: $($script:BundleZipPath)"
        $searchBase = $script:BundleZipPath
    } else {
        Log-Erro "Bundle ODI nao encontrado (ZIP ou pasta): $($script:BundleZipPath)"
        exit 1
    }

    $spbat = @(Get-ChildItem -Path $searchBase -Recurse -Include 'spbat.bat','spbat.cmd' -ErrorAction SilentlyContinue)
    if ($spbat.Count -eq 0) {
        Log-Erro "spbat.bat / spbat.cmd nao encontrado em: $searchBase"
        exit 1
    }

    $spbatDir  = Split-Path $spbat[0].FullName -Parent
    $spbatName = $spbat[0].Name
    Log-Info "SPBAT: $($spbat[0].FullName)"

    # SPBAT 2.25 Windows: o batch escreve MW_HOME com aspas no propfile
    # e o Python le as aspas como parte do path. Patch cirurgico em preReqCheck.py
    # para strip das aspas antes de qualquer uso do valor.
    $preReqPy = Get-ChildItem -Path $spbatDir -Recurse -Filter 'preReqCheck.py' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($preReqPy) {
        $pyContent = [System.IO.File]::ReadAllText($preReqPy.FullName)
        $pyTarget  = '    validateOraInventory(MW_HOME)'
        $pyFixed   = "    MW_HOME = MW_HOME.strip(chr(34)).strip(chr(39))`n    validateOraInventory(MW_HOME)"
        if ($pyContent.Contains($pyTarget) -and -not $pyContent.Contains('MW_HOME.strip')) {
            Copy-Item $preReqPy.FullName "$($preReqPy.FullName).bak" -Force
            $pyContent = $pyContent.Replace($pyTarget, $pyFixed)
            [System.IO.File]::WriteAllText($preReqPy.FullName, $pyContent, [System.Text.Encoding]::UTF8)
            Log-OK "preReqCheck.py: fix aplicado (strip aspas em MW_HOME)"
        } else {
            Log-Info "preReqCheck.py: fix ja aplicado ou padrao nao encontrado"
        }
    } else {
        Log-Warn "preReqCheck.py nao encontrado - prosseguindo sem patch"
    }

    Log-Info "Aplicando Bundle ODI (aguarde, pode demorar varios minutos)..."

    $env:ORACLE_HOME = $script:OracleHome
    $env:MW_HOME     = $script:OracleHome
    $env:JAVA_HOME   = $script:JavaHome

    $proc = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList @('/c', "$spbatName -phase apply -oracle_home $($script:OracleHome)") `
        -WorkingDirectory $spbatDir `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput "$($script:LogDir)\bundle_odi_stdout.log" `
        -RedirectStandardError  "$($script:LogDir)\bundle_odi_stderr.log"

    Get-Content "$($script:LogDir)\bundle_odi_stdout.log" -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile
    Get-Content "$($script:LogDir)\bundle_odi_stderr.log" -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile

    if ($proc.ExitCode -ne 0) {
        Log-Erro "Bundle ODI retornou exit code $($proc.ExitCode). Verifique: $($script:LogDir)\bundle_odi_stdout.log"
        exit 1
    }

    Log-OK "Bundle ODI_SPB_12.2.1.4.260714 aplicado com sucesso."
}

# --- APLICAR PATCH CVE-2021-42575 (34809489) ---------------------------------

function Aplicar-Patch-CVE {
    Log-Step "Aplicacao Patch CVE-2021-42575 (34809489)"

    if ([string]::IsNullOrWhiteSpace($script:CveInput)) {
        Log-Warn "Patch CVE 34809489 nao informado - pulando."
        return
    }

    $opatchBat = Join-Path $script:OracleHome 'OPatch\opatch.bat'
    if (-not (Test-Path $opatchBat)) {
        Log-Erro "opatch.bat nao encontrado: $opatchBat"
        exit 1
    }

    $patchDir34 = Join-Path $script:PatchDir '34809489'

    if (Test-Path $script:CveInput -PathType Container) {
        $patchDir34 = $script:CveInput
        Log-Info "Pasta do patch CVE: $patchDir34"
    } elseif (Test-Path $script:CveInput -PathType Leaf) {
        Log-Info "Extraindo patch 34809489 de $($script:CveInput)..."
        Expand-Archive -Path $script:CveInput -DestinationPath $script:PatchDir -Force
        if (-not (Test-Path $patchDir34)) {
            Log-Erro "Pasta 34809489 nao encontrada em $($script:PatchDir) apos extracao."
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
        -RedirectStandardOutput "$($script:LogDir)\patch_cve_stdout.log" `
        -RedirectStandardError  "$($script:LogDir)\patch_cve_stderr.log"

    Get-Content "$($script:LogDir)\patch_cve_stdout.log" -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile
    Get-Content "$($script:LogDir)\patch_cve_stderr.log" -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile

    if ($proc.ExitCode -ne 0) {
        Log-Erro "Patch 34809489 retornou exit code $($proc.ExitCode). Verifique: $($script:LogDir)\patch_cve_stdout.log"
        exit 1
    }

    Log-OK "Patch 34809489 (CVE-2021-42575) aplicado com sucesso."
}

# --- RESUMO FINAL ------------------------------------------------------------

function Gerar-Resumo {
    Log-Step "Resumo Final"

    $studio  = Join-Path $script:OracleHome 'odi\studio\odi.exe'
    $summary = Join-Path (Join-Path $script:InstallDir 'response') `
               "install_summary_odi12214_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

    $opatchInfo = if ($script:OPatchZipPath) { $script:OPatchZipPath } else { '(nao aplicado)' }
    $bundleInfo = if ($script:BundleZipPath) { $script:BundleZipPath } else { '(nao aplicado)' }
    $cveInfo    = if ($script:CveInput)      { $script:CveInput }      else { '(nao aplicado)' }

    $txt = @"
# ============================================================
# RESUMO INSTALACAO ODI Studio 12.2.1.4 STANDALONE
# Data  : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
# Host  : $env:COMPUTERNAME
# ============================================================

INSTALL_DIR   = $($script:InstallDir)
LOG_DIR       = $($script:LogDirFinal)
ORACLE_HOME   = $($script:OracleHome)
JAVA_HOME     = $($script:JavaHome)
JAR ODI       = $($script:JarOdiPath)
OPatch        = $opatchInfo
Bundle ODI    = $bundleInfo
CVE 34809489  = $cveInfo
PATCH_DIR     = $($script:PatchDir)
TIPO          = Standalone Installation (Studio Only)

Studio EXE    = $studio
Log           = $($script:LogFile)
"@

    $null = New-Item -ItemType Directory -Force -Path (Split-Path $summary -Parent)
    $txt | Out-File -FilePath $summary -Encoding utf8
    Write-Host $txt -ForegroundColor Cyan
    Log-OK "Resumo salvo: $summary"

    if (Test-Path $studio) {
        Log-OK "ODI Studio pronto: $studio"
    } else {
        Log-Warn "odi.exe nao encontrado em $studio - verifique o log."
    }
}

# --- MAIN --------------------------------------------------------------------

Show-Banner
Coletar-Infos

$_tempLog       = $script:LogFile
$script:LogDir  = $script:LogDirFinal
$null           = New-Item -ItemType Directory -Force -Path $script:LogDir
$script:LogFile = "$($script:LogDir)\install_odi12214_studio_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
if (Test-Path $_tempLog) {
    Get-Content $_tempLog -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile
    Remove-Item $_tempLog -ErrorAction SilentlyContinue
}
Log-Info "Log: $($script:LogFile)"

Instalar-ODI
Atualizar-OPatch
Aplicar-Bundle-ODI
Aplicar-Patch-CVE
Gerar-Resumo
