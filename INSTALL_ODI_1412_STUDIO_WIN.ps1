#Requires -RunAsAdministrator
# =============================================================================
# INSTALACAO ODI Studio 14.1.2 STANDALONE - Oraex / Getnet - Windows
#
# Modo    : Standalone Installation (Studio Only)
# Java    : JDK 17 instalado previamente pelo usuario
# RCU     : NAO necessario na instalacao - equipe configura separado
# Binario : V1045400-01.zip -> fmw_14.1.2.0.0_odi.jar
# Bundle  : ODI_SPB_14.1.2.<data> via SPBAT generic
#
# USO: .\INSTALL_ODI_1412_STUDIO_WIN.ps1
# Executar como Administrador.
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- LOG INICIAL (temp ate Coletar-Infos definir LOG_DIR) --------------------

$script:LogDir  = "$env:TEMP\oraex_logs"
$null           = New-Item -ItemType Directory -Force -Path $script:LogDir
$script:LogFile = "$($script:LogDir)\install_odi1412_studio_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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
        Log-Erro "$Nome contem espacos: '$Valor'. SPBAT e OPatch nao suportam paths com espacos."
        exit 1
    }
}

# --- VARIAVEIS GLOBAIS -------------------------------------------------------

$script:InstallDir   = ''
$script:OracleHome   = ''
$script:JavaHome     = ''
$script:JarOdi       = ''
$script:LogDirFinal  = ''
$script:PatchDir     = ''
$script:OpatchSrc    = ''
$script:BundleSrc    = ''
$script:CveSrc       = ''

# --- BANNER ------------------------------------------------------------------

function Show-Banner {
    Clear-Host
    Write-Host @'

  +================================================================+
  |   INSTALACAO ODI Studio 14.1.2 STANDALONE - Oraex/Getnet     |
  |   Modo: Studio Only  |  Sem dominio  |  Sem RCU               |
  |   Bundle: ODI_SPB_14.1.2.0.260714  |  Patch: 39023318          |
  +================================================================+

'@ -ForegroundColor Blue
    Write-Host "  Host : $($env:COMPUTERNAME)" -ForegroundColor Cyan
    Write-Host "  Log  : (sera definido em LOG_DIR apos configuracao)`n" -ForegroundColor Cyan
}

# --- COLETA DE INFORMACOES ---------------------------------------------------

function Coletar-Infos {
    Log-Step "Coleta de Informacoes"

    $script:InstallDir  = Ask 'INSTALL_DIR (pasta com o JAR do ODI)' 'C:\oracle\install'
    $script:LogDirFinal = Ask 'LOG_DIR (pasta para os logs desta instalacao)' "$($script:InstallDir)\logs"
    $script:OracleHome  = Ask 'ORACLE_HOME (destino da instalacao)' 'C:\oracle\middleware_14'
    $script:JavaHome    = Ask 'JAVA_HOME (JDK 17 ja instalado)' 'C:\Java\jdk-17'
    Validar-SemEspacos 'ORACLE_HOME' $script:OracleHome
    Validar-SemEspacos 'JAVA_HOME'   $script:JavaHome

    # Validar Java 17+
    $java = Join-Path $script:JavaHome 'bin\java.exe'
    if (-not (Test-Path $java)) {
        Log-Erro "java.exe nao encontrado: $java"
        exit 1
    }
    $verRaw = & { $ErrorActionPreference = 'Continue'; & $java -version 2>&1 } | Select-String 'version'
    Log-OK "Java OK: $verRaw"
    $verStr = ($verRaw -replace '.*"([^"]+)".*', '$1').Trim()
    $major  = [int]($verStr -split '[._]')[0]
    if ($major -lt 17) {
        Log-Erro "ODI 14.1.2 exige JDK 17 ou superior. Detectado: $verStr"
        exit 1
    }

    Write-Host ''
    Write-Host '  --- ARQUIVO DE INSTALACAO ---' -ForegroundColor White
    Write-Host ''

    # Localizar JAR do ODI 14.1.2 no INSTALL_DIR
    $jars = @(Get-ChildItem -Path $script:InstallDir -Filter 'fmw_*odi*.jar' -ErrorAction SilentlyContinue |
              Select-Object -ExpandProperty FullName)

    if ($jars.Count -eq 0) {
        Log-Warn "Nenhum fmw_*odi*.jar encontrado em $($script:InstallDir)."
        $script:JarOdi = Ask 'Caminho completo do JAR ODI' "$($script:InstallDir)\fmw_14.1.2.0.0_odi.jar"
    } elseif ($jars.Count -eq 1) {
        $script:JarOdi = $jars[0]
        Log-OK "JAR detectado: $($script:JarOdi)"
    } else {
        Write-Host '  JARs encontrados:' -ForegroundColor Yellow
        for ($i = 0; $i -lt $jars.Count; $i++) { Write-Host "    [$i] $($jars[$i])" }
        $idx = [int](Ask 'Numero do JAR a usar' '0')
        $script:JarOdi = $jars[$idx]
    }

    if (-not (Test-Path $script:JarOdi)) {
        Log-Erro "JAR nao encontrado: $($script:JarOdi)"
        exit 1
    }
    Log-OK "JAR ODI validado: $($script:JarOdi)"

    Write-Host ''
    Write-Host '  --- PATCHES (ZIP ou pasta descompactada) ---' -ForegroundColor White
    Write-Host ''

    $script:OpatchSrc = Ask 'OPatch: ZIP (p6880880_*.zip) ou pasta descompactada - Enter para pular' ''
    $script:BundleSrc = Ask 'Bundle ODI 14.1.2: ZIP (ODI_SPB_*.zip) ou pasta descompactada - Enter para pular' ''
    $script:CveSrc    = Ask 'ZIP ou pasta do patch CVE - Enter para pular' ''

    Write-Host ''
    Write-Host '  --- EXTRACAO ---' -ForegroundColor White
    Write-Host ''
    $script:PatchDir = Ask 'PATCH_DIR (pasta onde extrair os patches)' $script:InstallDir

    Write-Host ''
    Write-Host '  Resumo:' -ForegroundColor White
    Write-Host "  INSTALL_DIR  : $($script:InstallDir)"  -ForegroundColor Cyan
    Write-Host "  LOG_DIR      : $($script:LogDirFinal)" -ForegroundColor Cyan
    Write-Host "  ORACLE_HOME  : $($script:OracleHome)"  -ForegroundColor Cyan
    Write-Host "  JAVA_HOME    : $($script:JavaHome)"    -ForegroundColor Cyan
    Write-Host "  JAR ODI      : $($script:JarOdi)"      -ForegroundColor Cyan
    $opatchInfo = if ($script:OpatchSrc) { $script:OpatchSrc } else { '(pular)' }
    $bundleInfo = if ($script:BundleSrc) { $script:BundleSrc } else { '(pular)' }
    $cveInfo    = if ($script:CveSrc)    { $script:CveSrc    } else { '(pular)' }
    Write-Host "  OPatch       : $opatchInfo" -ForegroundColor Cyan
    Write-Host "  Bundle ODI   : $bundleInfo" -ForegroundColor Cyan
    Write-Host "  CVE patch    : $cveInfo"    -ForegroundColor Cyan
    Write-Host "  PATCH_DIR    : $($script:PatchDir)" -ForegroundColor Cyan
    Write-Host "  TIPO         : Standalone Installation (Studio Only)" -ForegroundColor Cyan
    Write-Host ''

    $conf = Ask 'Confirma? (s/n)' 's'
    if ($conf -ne 's' -and $conf -ne 'S') {
        Log-Info "Cancelado pelo usuario."
        exit 0
    }
}

# --- INSTALACAO ODI ----------------------------------------------------------

function Instalar-ODI {
    Log-Step "Instalacao ODI Studio 14.1.2"

    if (-not (Test-Path $script:JarOdi)) {
        Log-Erro "JAR nao encontrado: $($script:JarOdi)"
        exit 1
    }

    if (Test-Path (Join-Path $script:OracleHome 'odi\studio\odi.exe')) {
        Log-OK "ODI Studio ja instalado em $($script:OracleHome). Pulando."
        return
    }

    $rspDir  = Join-Path $script:InstallDir 'response'
    $null    = New-Item -ItemType Directory -Force -Path $rspDir
    $rspFile = Join-Path $rspDir 'odi1412_studio.rsp'

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
    Log-Info "Instalando ODI Studio 14.1.2 (aguarde 5-15 min)..."

    $java   = Join-Path $script:JavaHome 'bin\java.exe'
    $stdOut = "$($script:LogDir)\odi1412_stdout.log"
    $stdErr = "$($script:LogDir)\odi1412_stderr.log"

    $proc = Start-Process -FilePath $java `
        -ArgumentList @(
            '-jar', $script:JarOdi,
            '-silent',
            '-ignoreSysPrereqs',
            '-responseFile', $rspFile
        ) `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdOut `
        -RedirectStandardError  $stdErr

    Get-Content $stdOut -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile
    Get-Content $stdErr -ErrorAction SilentlyContinue | Add-Content -Path $script:LogFile

    if ($proc.ExitCode -ne 0) {
        Log-Erro "Instalador retornou exit code $($proc.ExitCode). Verifique: $stdErr"
        exit 1
    }

    Log-OK "ODI Studio 14.1.2 instalado em $($script:OracleHome)"
}

# --- ATUALIZAR OPATCH --------------------------------------------------------

function Atualizar-OPatch {
    if (-not $script:OpatchSrc) {
        Log-Info "OPatch: ignorado (nenhum path informado)."
        return
    }

    Log-Step "Atualizacao OPatch (6880880)"

    $opatchDir = $script:OpatchSrc

    # Se for ZIP, extrair
    if ($opatchDir -match '\.zip$') {
        Log-Info "OPatch ZIP detectado: $opatchDir"
        $dest = Join-Path $script:PatchDir 'opatch_extracted'
        Expand-Archive -Path $opatchDir -DestinationPath $dest -Force
        $opatchDir = $dest
        Log-OK "OPatch extraido em: $opatchDir"
    } else {
        Log-Info "OPatch pasta detectada: $opatchDir"
    }

    $opatchJar = Get-ChildItem -Path $opatchDir -Recurse -Filter 'opatch_generic.jar' -ErrorAction SilentlyContinue |
                 Select-Object -First 1
    if (-not $opatchJar) {
        Log-Erro "opatch_generic.jar nao encontrado em $opatchDir"
        exit 1
    }
    Log-Info "opatch_generic.jar: $($opatchJar.FullName)"
    Log-Info "Instalando OPatch no ORACLE_HOME..."

    $java = Join-Path $script:JavaHome 'bin\java.exe'
    $proc = Start-Process -FilePath $java `
        -ArgumentList @('-jar', $opatchJar.FullName, '-silent', "oracle_home=$($script:OracleHome)") `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput "$($script:LogDir)\opatch_update_stdout.log" `
        -RedirectStandardError  "$($script:LogDir)\opatch_update_stderr.log"

    $opatchBat = Join-Path $script:OracleHome 'OPatch\opatch.bat'
    if (Test-Path $opatchBat) {
        Log-OK "OPatch atualizado: $opatchBat"
    } else {
        Log-Warn "opatch.bat nao encontrado apos update — exit code: $($proc.ExitCode)"
    }
}

# --- APLICAR BUNDLE ODI ------------------------------------------------------

function Aplicar-Bundle-ODI {
    if (-not $script:BundleSrc) {
        Log-Info "Bundle ODI: ignorado (nenhum path informado)."
        return
    }

    Log-Step "Aplicacao Bundle ODI 14.1.2"

    $bundleDir = $script:BundleSrc

    # Se for ZIP, extrair
    if ($bundleDir -match '\.zip$') {
        Log-Info "Bundle ZIP detectado: $bundleDir"
        $dest = Join-Path $script:PatchDir 'bundle_odi_extracted'
        Expand-Archive -Path $bundleDir -DestinationPath $dest -Force
        $bundleDir = $dest
        Log-OK "Bundle extraido em: $bundleDir"
    } else {
        Log-Info "Bundle pasta detectada: $bundleDir"
    }

    $spbat = Get-ChildItem -Path $bundleDir -Recurse -Include 'spbat.bat','spbat.cmd' -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if (-not $spbat) {
        Log-Erro "spbat.bat nao encontrado em $bundleDir"
        exit 1
    }

    $spbatDir  = Split-Path $spbat.FullName -Parent
    $spbatName = $spbat.Name
    Log-Info "SPBAT: $($spbat.FullName)"

    # SPBAT 2.25 Windows: batch escreve MW_HOME com aspas no propfile;
    # Python le as aspas como parte do path. Patch cirurgico em preReqCheck.py.
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

    if ($proc.ExitCode -eq 0) {
        Log-OK "Bundle ODI 14.1.2 aplicado com sucesso."
    } else {
        Log-Erro "SPBAT retornou exit code $($proc.ExitCode)."
        Log-Erro "Verifique: $($script:LogDir)\bundle_odi_stdout.log"
        exit 1
    }
}

# --- APLICAR PATCH CVE -------------------------------------------------------

function Aplicar-Patch-CVE {
    if (-not $script:CveSrc) {
        Log-Info "Patch CVE: ignorado (nenhum path informado)."
        return
    }

    Log-Step "Aplicacao Patch CVE"

    $patchDir = $script:CveSrc

    # Se for ZIP, extrair
    if ($patchDir -match '\.zip$') {
        Log-Info "Patch CVE ZIP detectado: $patchDir"
        $dest = Join-Path $script:PatchDir 'cve_extracted'
        Expand-Archive -Path $patchDir -DestinationPath $dest -Force
        $patchDir = $dest
        Log-OK "Patch CVE extraido em: $patchDir"
    } else {
        Log-Info "Pasta do patch CVE: $patchDir"
    }

    $opatchBat = Join-Path $script:OracleHome 'OPatch\opatch.bat'
    if (-not (Test-Path $opatchBat)) {
        Log-Erro "opatch.bat nao encontrado: $opatchBat"
        exit 1
    }

    # Detectar numero do patch pelo nome da pasta
    $patchNum = Split-Path $patchDir -Leaf
    Log-Info "Aplicando patch $patchNum via OPatch..."

    $proc = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList @('/c', "`"$opatchBat`" apply -silent -oh `"$($script:OracleHome)`"") `
        -WorkingDirectory $patchDir `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput "$($script:LogDir)\cve_${patchNum}_stdout.log" `
        -RedirectStandardError  "$($script:LogDir)\cve_${patchNum}_stderr.log"

    if ($proc.ExitCode -eq 0) {
        Log-OK "Patch $patchNum aplicado com sucesso."
    } else {
        Log-Erro "OPatch retornou exit code $($proc.ExitCode). Verifique: $($script:LogDir)\cve_${patchNum}_stdout.log"
        exit 1
    }
}

# --- CONFIGURAR ACESSO GLOBAL ------------------------------------------------

function Configurar-Acesso-Global {
    Log-Step "Configuracao de Acesso Global"

    $oracleHome = $script:OracleHome
    $javaHome   = $script:JavaHome
    $javaBin    = "$javaHome\bin"
    $studioExe  = "$oracleHome\odi\studio\odi.exe"
    $studioDir  = "$oracleHome\odi\studio"
    $atalho     = "C:\Users\Public\Desktop\ODI Studio 14.1.2.lnk"

    Write-Host ''
    Write-Host "  Configuracao de acesso global para todos os usuarios do host:" -ForegroundColor Cyan
    Write-Host "    ORACLE_HOME : $oracleHome" -ForegroundColor White
    Write-Host "    JAVA_HOME   : $javaHome"   -ForegroundColor White
    Write-Host "    Studio EXE  : $studioExe"  -ForegroundColor White
    Write-Host ''
    Write-Host "  Acoes que serao executadas:" -ForegroundColor Cyan
    Write-Host "    [1] icacls: Authenticated Users com RX recursivo em ORACLE_HOME" -ForegroundColor White
    Write-Host "    [2] Variavel de sistema JAVA_HOME = $javaHome" -ForegroundColor White
    Write-Host "    [3] $javaBin adicionado ao PATH de sistema" -ForegroundColor White
    Write-Host "    [4] Atalho ODI Studio em C:\Users\Public\Desktop\" -ForegroundColor White
    Write-Host ''

    $resp = Ask 'Aplicar configuracao global? (s/n)' 's'
    if ($resp -ne 's' -and $resp -ne 'S') {
        Log-Info "Configuracao global ignorada pelo usuario."
        return
    }

    # 1 - Permissoes
    Log-Info "Aplicando permissoes icacls em $oracleHome ..."
    $proc = Start-Process -FilePath 'icacls.exe' `
        -ArgumentList @($oracleHome, '/grant', 'Authenticated Users:(OI)(CI)(RX)', '/T', '/C', '/Q') `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput "$($script:LogDir)\icacls_stdout.log" `
        -RedirectStandardError  "$($script:LogDir)\icacls_stderr.log"
    if ($proc.ExitCode -eq 0) {
        Log-OK "icacls: permissoes aplicadas em $oracleHome"
    } else {
        Log-Warn "icacls saiu com codigo $($proc.ExitCode) - verifique $($script:LogDir)\icacls_stderr.log"
    }

    # 2 - JAVA_HOME de sistema
    $javaAtual = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if ($javaAtual -ne $javaHome) {
        [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "Machine")
        Log-OK "JAVA_HOME sistema: $javaHome"
    } else {
        Log-Info "JAVA_HOME sistema ja configurado: $javaAtual"
    }

    # 3 - java\bin no PATH de sistema
    $sysPath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($sysPath -notlike "*$javaBin*") {
        [System.Environment]::SetEnvironmentVariable("PATH", "$sysPath;$javaBin", "Machine")
        Log-OK "PATH sistema: $javaBin adicionado"
    } else {
        Log-Info "PATH sistema: $javaBin ja presente"
    }

    # 4 - Atalho publico
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $sc  = $wsh.CreateShortcut($atalho)
        $sc.TargetPath       = $studioExe
        $sc.WorkingDirectory = $studioDir
        $sc.Description      = "ODI Studio 14.1.2"
        $sc.Save()
        Log-OK "Atalho criado: $atalho"
    } catch {
        Log-Warn "Falha ao criar atalho: $_"
    }

    Log-OK "Configuracao global concluida."
}

# --- RESUMO FINAL ------------------------------------------------------------

function Gerar-Resumo {
    Log-Step "Resumo Final"

    $studio  = Join-Path $script:OracleHome 'odi\studio\odi.exe'
    $rspDir  = Join-Path $script:InstallDir 'response'
    $null    = New-Item -ItemType Directory -Force -Path $rspDir
    $summary = Join-Path $rspDir "install_summary_odi1412_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

    $opatchInfo = if ($script:OpatchSrc) { $script:OpatchSrc } else { '(ignorado)' }
    $bundleInfo = if ($script:BundleSrc) { $script:BundleSrc } else { '(ignorado)' }
    $cveInfo    = if ($script:CveSrc)    { $script:CveSrc    } else { '(ignorado)' }

    $txt = @"
# ============================================================
# RESUMO INSTALACAO ODI Studio 14.1.2 STANDALONE
# Data  : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
# Host  : $env:COMPUTERNAME
# ============================================================

INSTALL_DIR   = $($script:InstallDir)
LOG_DIR       = $($script:LogDirFinal)
ORACLE_HOME   = $($script:OracleHome)
JAVA_HOME     = $($script:JavaHome)  (JDK 17+)
JAR ODI       = $($script:JarOdi)
OPatch        = $opatchInfo
Bundle ODI    = $bundleInfo
CVE patch     = $cveInfo
PATCH_DIR     = $($script:PatchDir)
TIPO          = Standalone Installation (Studio Only)

Studio EXE    = $studio
Log           = $($script:LogFile)
"@

    $txt | Out-File -FilePath $summary -Encoding utf8
    Write-Host $txt -ForegroundColor Cyan
    Log-OK "Resumo salvo: $summary"

    if (Test-Path $studio) {
        Log-OK "ODI Studio 14.1.2 pronto: $studio"
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
$script:LogFile = "$($script:LogDir)\install_odi1412_studio_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
Configurar-Acesso-Global
