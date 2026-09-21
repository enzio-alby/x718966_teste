#!/bin/bash
# =============================================================================
# INSTALAÇÃO WebLogic 14.1.1 PURO (Standalone)
# Oraex / Getnet - Ambiente QA
#
# Padrao extraido de WLS_12214_1411_ABR26.sh + INSTALL_WLS_1412_COMPOSTO.sh
# Autor: Oraex | Data: Julho/2026
#
# USO: ./INSTALL_WLS_1411_PURO.sh
# Deve ser executado como root. Operacoes Oracle rodam como sudo -u oracle.
# =============================================================================

set -euo pipefail

# ─── CORES E LOG ─────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

LOGDIR="/u02/midias/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/install_wls1411_${HOSTNAME}.log"
echo "" >> "$LOGFILE" 2>/dev/null || true
echo "======================================================================" >> "$LOGFILE" 2>/dev/null || true
echo "  NOVA EXECUCAO: $(date '+%d/%m/%Y %H:%M:%S')" >> "$LOGFILE" 2>/dev/null || true
echo "======================================================================" >> "$LOGFILE" 2>/dev/null || true

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*" | tee -a "$LOGFILE"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "$LOGFILE"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOGFILE"; }
log_erro()  { echo -e "${RED}[ERRO]${NC}  $*" | tee -a "$LOGFILE"; }
log_step()  {
    echo -e "\n${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}\n" | tee -a "$LOGFILE"
}

checar_erro() {
    if [ $? -ne 0 ]; then
        log_erro "$1"
        log_erro "Verifique o log: $LOGFILE"
        exit 1
    fi
}

# ─── REPOSITÓRIOS ────────────────────────────────────────────────────────────

REPO_BASE="https://repository.getnet.com.br"
REPO_PSU_BASE="${REPO_BASE}/binarios/oraex/linux/cpu/middleware/oracle/wls/14.1.1.0.0/puro/latest"
REPO_JAVA_ZIP="${REPO_BASE}/binarios/oracle/middleware/jdk/jdk_501.zip"
REPO_INSTALADORES="${REPO_BASE}/binarios/oraex/linux/instaladores/14110/instaladores.tar.gz"
# instaladores.tar.gz contem fmw_14.1.1.0.0_wls.jar diretamente (sem ZIP intermediario)

# ─── BINÁRIOS ────────────────────────────────────────────────────────────────

JAVA_ZIP="jdk_501.zip"
JAVA_RPM_8="jdk-8u501-linux-x64.rpm"
JAVA_HOME_8="/usr/java/jdk1.8.0-x64"
JAVA_SECURITY_8="${JAVA_HOME_8}/jre/lib/security/java.security"

JAR_WLS="fmw_14.1.1.0.0_wls.jar"

BUNDLE_DIR="WLS_SPB_14.1.1.0.260703"
BUNDLE_SPBAT="${BUNDLE_DIR}/tools/spbat/generic/SPBAT"

# ─── PADRÕES DO AMBIENTE ─────────────────────────────────────────────────────

ORACLE_HOME_PADRAO="/u01/oracle/middleware"
ORACLE_USER="oracle"
ORACLE_GROUP="oinstall"
ORACLE_BASE="/u01/oracle"
ORACLE_USER_HOME="/home/oracle"
ORACLE_UID="1101"
ORACLE_GID="54321"
MIDIAS="/u02/midias"
INVENTORY="/u01/oracle/oraInventory"
ORAINST="/etc/oraInst.loc"

ADMIN_PORT="7001"
NM_PORT="5556"
WLS_ADMIN_USER="weblogic"
MS_PORT_PADRAO="7011"

# ─── VARIÁVEIS GLOBAIS ───────────────────────────────────────────────────────

ORACLE_HOME=""
DOMAIN_HOME=""
DOMAIN_NAME=""
JAVA_HOME=""
WLS_ADMIN_PASS=""
MS_NOME=""
MS_PORT=""
CLUSTER_NAME="WLS_CLUSTER"
ADMIN_SERVER_NOME="AdminServer"
HOST_NAME=$(hostname)
HOST_IP=$(hostname -I | awk '{print $1}')

# ─── BANNER ──────────────────────────────────────────────────────────────────

banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║       INSTALAÇÃO WebLogic 14.1.1 PURO - Oraex / Getnet      ║"
    echo "  ║       JDK 8u501  |  Bundle WLS_SPB_14.1.1.0.260703          ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  Host    : ${CYAN}${HOST_NAME}${NC} (${HOST_IP})"
    echo -e "  Log     : ${CYAN}${LOGFILE}${NC}"
    echo ""
}

# ─── VALIDAÇÕES ──────────────────────────────────────────────────────────────

validar_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_erro "Este script deve ser executado como root."
        exit 1
    fi
}

validar_espaco_disco() {
    local path="$1" minimo_gb="$2" disponivel
    disponivel=$(df -BG "$path" 2>/dev/null | awk 'NR==2{gsub("G",""); print $4}')
    if [ -z "$disponivel" ] || [ "$disponivel" -lt "$minimo_gb" ]; then
        log_warn "Espaco disponivel em $path: ${disponivel}GB (minimo: ${minimo_gb}GB)"
        read -rp "  Deseja continuar mesmo assim? (s/n): " cont
        [[ "$cont" != "s" ]] && exit 1
    else
        log_ok "Espaco em $path: ${disponivel}GB disponivel."
    fi
}

# ─── USUARIO ORACLE ──────────────────────────────────────────────────────────

preparar_usuario_oracle() {
    log_step "Verificacao / Preparacao do Usuario Oracle"

    if ! getent group "$ORACLE_GROUP" &>/dev/null; then
        groupadd -g "$ORACLE_GID" "$ORACLE_GROUP" && log_ok "Grupo $ORACLE_GROUP criado (GID: $ORACLE_GID)." || \
        { groupadd "$ORACLE_GROUP" && log_ok "Grupo $ORACLE_GROUP criado (GID automatico)."; }
    else
        log_ok "Grupo $ORACLE_GROUP ja existe."
    fi

    if ! id "$ORACLE_USER" &>/dev/null; then
        mkdir -p "$ORACLE_USER_HOME"
        useradd -u "$ORACLE_UID" -g "$ORACLE_GROUP" -d "$ORACLE_USER_HOME" \
                -s /bin/bash -c "Oracle Software Owner" "$ORACLE_USER" || \
        useradd -g "$ORACLE_GROUP" -d "$ORACLE_USER_HOME" \
                -s /bin/bash -c "Oracle Software Owner" "$ORACLE_USER"
        log_ok "Usuario $ORACLE_USER criado."
    else
        log_ok "Usuario $ORACLE_USER ja existe: $(id "$ORACLE_USER")"
    fi

    read -rsp "  Senha $ORACLE_USER (CyberArk): " ORACLE_OS_PASS; echo ""
    [[ -z "$ORACLE_OS_PASS" ]] && { log_erro "Senha nao pode ser vazia."; exit 1; }
    echo "${ORACLE_USER}:${ORACLE_OS_PASS}" | chpasswd
    log_ok "Senha do $ORACLE_USER definida."

    for dir in "$ORACLE_USER_HOME" "$ORACLE_BASE" "$ORACLE_BASE/middleware" "$INVENTORY"; do
        mkdir -p "$dir"
        chown -R oracle:oinstall "$dir"
    done

    local bashrc="${ORACLE_USER_HOME}/.bashrc"
    grep -q "ORACLE_HOME" "$bashrc" 2>/dev/null || cat >> "$bashrc" << BASHEOF

# Oracle Environment
export ORACLE_HOME=${ORACLE_HOME}
export ORACLE_BASE=${ORACLE_BASE}
export PATH=\$PATH:\$ORACLE_HOME/OPatch:\$ORACLE_HOME/oracle_common/common/bin
export PS1='[\[\033[0;32m\]\u\[\033[0m\]@\[\033[0;36m\]\h\[\033[0m\] \w]\$ '
BASHEOF
    chown oracle:oinstall "$bashrc"

    log_ok "Usuario oracle pronto."
}

# ─── oraInst.loc ─────────────────────────────────────────────────────────────

criar_orainst() {
    log_step "Criando oraInst.loc"
    if [ -f "$ORAINST" ]; then
        log_warn "$ORAINST ja existe:"
        cat "$ORAINST"
        read -rp "  Recriar? (s/n): " recria
        [[ "$recria" != "s" ]] && return 0
    fi
    mkdir -p "$INVENTORY"
    chown -R ${ORACLE_USER}:${ORACLE_GROUP} "$INVENTORY"
    printf "inventory_loc=%s\ninst_group=%s\n" "$INVENTORY" "$ORACLE_GROUP" > "$ORAINST"
    chmod 644 "$ORAINST"
    log_ok "oraInst.loc criado em $ORAINST"
}

# ─── COLETA DE INFORMAÇÕES ───────────────────────────────────────────────────

coletar_infos() {
    log_step "Coleta de Informacoes - Ambiente"

    echo -e "  Host: ${CYAN}${HOST_NAME}${NC} (${HOST_IP})"
    echo ""

    read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp
    ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
    log_info "ORACLE_HOME: $ORACLE_HOME"

    echo ""
    echo -e "  ${BOLD}Usuario Oracle do SO:${NC}"
    read -rp "  ORACLE_USER      [${ORACLE_USER}]: " inp
    ORACLE_USER="${inp:-$ORACLE_USER}"
    read -rp "  ORACLE_USER_HOME [${ORACLE_USER_HOME}]: " inp
    ORACLE_USER_HOME="${inp:-$ORACLE_USER_HOME}"
    read -rp "  ORACLE_BASE      [${ORACLE_BASE}]: " inp
    ORACLE_BASE="${inp:-$ORACLE_BASE}"
    log_info "Oracle OS: user=$ORACLE_USER | home=$ORACLE_USER_HOME | base=$ORACLE_BASE"

    echo ""
    echo "  Exemplo: /u01/QA/projects/domains/wls_puro_domain"
    read -rp "  DOMAIN_HOME: " DOMAIN_HOME
    [[ -z "$DOMAIN_HOME" ]] && { log_erro "DOMAIN_HOME obrigatorio."; exit 1; }
    DOMAIN_NAME=$(basename "$DOMAIN_HOME")
    log_info "DOMAIN_HOME: $DOMAIN_HOME | DOMAIN_NAME: $DOMAIN_NAME"

    JAVA_HOME="/usr/java/latest"
    log_info "JAVA_HOME: $JAVA_HOME (via update-alternatives apos instalacao JDK 8)"

    echo ""
    read -rp "  Nome do Admin Server [AdminServer]: " inp
    ADMIN_SERVER_NOME="${inp:-AdminServer}"

    echo ""
    read -rp "  Criar Managed Server? (s/n): " cria_ms
    if [[ "$cria_ms" == "s" ]]; then
        read -rp "  Nome do Managed Server [wls_server1]: " inp
        MS_NOME="${inp:-wls_server1}"
        read -rp "  Porta do Managed Server [${MS_PORT_PADRAO}]: " inp
        MS_PORT="${inp:-$MS_PORT_PADRAO}"
        read -rp "  Nome do Cluster [${CLUSTER_NAME}]: " inp
        CLUSTER_NAME="${inp:-$CLUSTER_NAME}"
        log_info "MS: $MS_NOME:$MS_PORT | Cluster: $CLUSTER_NAME"
    else
        MS_NOME=""
        MS_PORT=""
        log_info "Domain sem Managed Server."
    fi

    echo ""
    read -rsp "  Senha weblogic: " WLS_ADMIN_PASS; echo ""
    read -rsp "  Confirme a senha: " WLS_ADMIN_PASS2; echo ""
    if [[ "$WLS_ADMIN_PASS" != "$WLS_ADMIN_PASS2" ]]; then
        log_erro "Senhas nao conferem."
        exit 1
    fi
    if [[ ${#WLS_ADMIN_PASS} -lt 8 ]]; then
        log_erro "Senha deve ter ao menos 8 caracteres."
        exit 1
    fi

    echo ""
    echo -e "  ${BOLD}Resumo:${NC}"
    echo -e "  ORACLE_HOME  : ${CYAN}$ORACLE_HOME${NC}"
    echo -e "  DOMAIN_HOME  : ${CYAN}$DOMAIN_HOME${NC}"
    echo -e "  JAVA_HOME    : ${CYAN}$JAVA_HOME${NC} (JDK 8u501)"
    echo -e "  BUNDLE       : ${CYAN}${BUNDLE_DIR}${NC}"
    [[ -n "$MS_NOME" ]] && echo -e "  MS           : ${CYAN}$MS_NOME:$MS_PORT (Cluster: $CLUSTER_NAME)${NC}"
    echo ""
    read -rp "  Confirma? (s/n): " conf
    if [[ "$conf" != "s" ]]; then
        log_info "Cancelado."
        exit 0
    fi
}

# ─── PRÉ-REQUISITOS ──────────────────────────────────────────────────────────

instalar_prereqs() {
    log_step "Fase 0 - Pre-requisitos do Sistema"

    validar_espaco_disco "/u01" 10
    validar_espaco_disco "/u02" 5

    local pkgs="binutils gcc gcc-c++ glibc-devel libstdc++-devel libaio-devel sysstat ksh"
    log_info "Instalando pacotes: $pkgs"
    dnf install -y $pkgs 2>&1 | tee -a "$LOGFILE" || true
    log_ok "Pacotes verificados."

    cat > /etc/security/limits.d/99-oracle.conf << 'EOF'
oracle soft nofile 4096
oracle hard nofile 65536
oracle soft nproc  2047
oracle hard nproc  16384
oracle soft stack  10240
oracle hard stack  32768
EOF

    cat > /etc/sysctl.d/99-oracle-wls.conf << 'EOF'
kernel.shmall = 2097152
kernel.shmmax = 1073741824
kernel.shmmni = 4096
fs.file-max = 6815744
net.core.rmem_max = 4194304
net.core.wmem_max = 1048576
EOF
    sysctl -p /etc/sysctl.d/99-oracle-wls.conf 2>&1 | tee -a "$LOGFILE" || true
    log_ok "Limites e parametros de kernel configurados."
}

# ─── JAVA 8 ──────────────────────────────────────────────────────────────────

instalar_java() {
    log_step "Fase 1a - Instalacao JDK 8u501"

    if java -version 2>&1 | grep -q '"1\.8\.'; then
        log_ok "JDK 8 ja detectado. Pulando instalacao."
        return 0
    fi

    mkdir -p "${MIDIAS}/java"
    chown -R oracle:oinstall "${MIDIAS}"

    log_info "Baixando ${JAVA_ZIP}..."
    wget -nv -O "${MIDIAS}/java/${JAVA_ZIP}" "${REPO_JAVA_ZIP}" \
        2>&1 | tee -a "$LOGFILE"
    checar_erro "Falha no download do ${JAVA_ZIP}."

    log_info "Extraindo ${JAVA_ZIP}..."
    cd "${MIDIAS}/java"
    unzip -q "$JAVA_ZIP"
    checar_erro "Falha ao extrair ${JAVA_ZIP}."

    log_info "Instalando ${JAVA_RPM_8}..."
    rpm -i "${MIDIAS}/java/${JAVA_RPM_8}" 2>&1 | tee -a "$LOGFILE"
    checar_erro "Falha na instalacao do JDK 8."

    log_info "Configurando update-alternatives..."
    update-alternatives --install /usr/bin/java java "${JAVA_HOME_8}/bin/java" 1 2>/dev/null || true
    update-alternatives --set java "${JAVA_HOME_8}/bin/java" 2>/dev/null || true
    ln -sfn "$JAVA_HOME_8" /usr/java/latest 2>/dev/null || true

    log_info "Ajustando java.security (urandom)..."
    if [ -f "$JAVA_SECURITY_8" ]; then
        sed -i 's|securerandom.source=file:/dev/random|securerandom.source=file:/dev/./urandom|' \
            "$JAVA_SECURITY_8"
        log_ok "java.security atualizado."
    else
        log_warn "java.security nao encontrado em $JAVA_SECURITY_8 — ajuste manual se necessario."
    fi

    cd /
    rm -rf "${MIDIAS}/java"
    log_ok "JDK 8u501 instalado:"
    java -version 2>&1 | tee -a "$LOGFILE" || true

    service qualys-cloud-agent restart 2>/dev/null || true
}

# ─── BINÁRIOS WLS ────────────────────────────────────────────────────────────

instalar_binarios() {
    log_step "Fase 1b - Download e Instalacao dos Binarios WLS 14.1.1"

    local java_bin="/usr/java/latest/bin/java"
    [[ ! -f "$java_bin" ]] && java_bin="${JAVA_HOME_8}/bin/java"
    [[ ! -f "$java_bin" ]] && { log_erro "Java nao encontrado. Execute opcao [3] primeiro."; exit 1; }

    local dir_inst="${MIDIAS}/instaladores/wls1411"
    local rsp_dir="${MIDIAS}/response"
    mkdir -p "$dir_inst" "$rsp_dir"
    chown -R oracle:oinstall "${MIDIAS}"

    log_info "Baixando instaladores.tar.gz (14111)..."
    wget -nv -O "${MIDIAS}/instaladores.tar.gz" "$REPO_INSTALADORES" \
        2>&1 | tee -a "$LOGFILE"
    checar_erro "Falha no download do pacote de instaladores."

    log_info "Extraindo instaladores..."
    sudo -u oracle tar -xzf "${MIDIAS}/instaladores.tar.gz" -C "$dir_inst" \
        2>&1 | tee -a "$LOGFILE"
    chown -R oracle:oinstall "$dir_inst"

    # Localizar o JAR dentro do tar.gz (pode estar em subpasta ou na raiz)
    local jar_path
    jar_path=$(find "$dir_inst" -name "$JAR_WLS" 2>/dev/null | head -1)
    if [ -z "$jar_path" ]; then
        log_erro "JAR nao encontrado: $JAR_WLS em $dir_inst"
        log_info "Conteudo de $dir_inst:"
        find "$dir_inst" -maxdepth 3 -name "*.jar" 2>/dev/null | tee -a "$LOGFILE"
        exit 1
    fi
    log_ok "JAR localizado: $jar_path"

    local rsp_wls="${rsp_dir}/wls.rsp"
    cat > "$rsp_wls" << EOF
[ENGINE]
Response File Version=1.0.0.0.0

[GENERIC]
ORACLE_HOME=${ORACLE_HOME}
INSTALL_TYPE=WebLogic Server
MYORACLESUPPORT_USERNAME=
MYORACLESUPPORT_PASSWORD=
DECLINE_SECURITY_UPDATES=true
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
PROXY_HOST=
PROXY_PORT=
PROXY_USER=
PROXY_PWD=
COLLECTOR_SUPPORTHUB_URL=
EOF
    chown oracle:oinstall "$rsp_wls"

    if [ -d "${ORACLE_HOME}/wlserver" ]; then
        log_ok "WLS ja detectado em ${ORACLE_HOME}/wlserver. Pulando instalacao."
    else
        log_info "Instalando WLS 14.1.1 (modo silencioso)..."
        sudo -u oracle "$java_bin" -jar "$jar_path" \
            -silent \
            -ignoreSysPrereqs \
            -responseFile "${rsp_wls}" \
            -invPtrLoc "$ORAINST" \
            -jreLoc "/usr/java/latest" \
            2>&1 | tee -a "$LOGFILE"
        checar_erro "Falha na instalacao do WLS 14.1.1."
        log_ok "WebLogic 14.1.1 instalado em $ORACLE_HOME"
    fi
}

# ─── PSU ─────────────────────────────────────────────────────────────────────

aplicar_patches() {
    log_step "Fase 2 - OPatch + WLS Bundle Patch (${BUNDLE_DIR})"

    mkdir -p "${MIDIAS}"
    chown -R oracle:oinstall "${MIDIAS}"

    # Download completo do repo PSU 14.1.1 puro (opatch + bundle)
    log_info "Baixando binarios PSU do repositorio Getnet..."
    cd "${MIDIAS}"
    sudo -u oracle wget -r -nv -np -nH \
        --execute="robots = off" --mirror --convert-links \
        --no-parent --reject "index.html*" \
        "${REPO_PSU_BASE}/" \
        2>&1 | tee -a "$LOGFILE" || true
    chown -R oracle:oinstall "${MIDIAS}/binarios" 2>/dev/null || true

    local BASE_PSU="${MIDIAS}/binarios/oraex/linux/cpu/middleware/oracle/wls/14.1.1.0.0/puro/latest"

    # ── OPatch ──
    log_info "Atualizando OPatch..."
    cd "${BASE_PSU}/opatch"
    sudo -u oracle unzip -q '*.zip' 2>/dev/null || true
    cd 6880880/
    sudo -u oracle java -jar opatch_generic.jar -silent oracle_home="$ORACLE_HOME" \
        2>&1 | tee -a "$LOGFILE" || log_warn "OPatch retornou erro. Continuando..."
    log_ok "OPatch processado."

    # ── WLS Bundle Patch (SPBAT) ──
    log_info "Aplicando ${BUNDLE_DIR}..."
    cd "${BASE_PSU}/bundle"
    sudo -u oracle unzip -q '*.zip' 2>/dev/null || true
    cd "${BUNDLE_SPBAT}"
    sudo -u oracle ./spbat.sh -phase apply -oracle_home "$ORACLE_HOME" \
        2>&1 | tee -a "$LOGFILE"
    checar_erro "Falha ao aplicar WLS Bundle Patch."
    log_ok "WLS Bundle Patch aplicado."

    # ── globalEnv.properties (mesmo padrao do WLS_12214_1411_ABR26.sh: 3x com sleep) ──
    log_info "Atualizando globalEnv.properties..."
    local props
    props="JAVA_HOME=/usr/java/latest\nJAVA_HOME_1_8=/usr/java/latest\nJVM_64="
    sudo -u oracle bash -c "mkdir -p ${ORACLE_HOME}/oui && printf '${props}' > ${ORACLE_HOME}/oui/.globalEnv.properties"
    sleep 15
    sudo -u oracle bash -c "printf '${props}' > ${ORACLE_HOME}/oui/.globalEnv.properties"
    sleep 15
    sudo -u oracle bash -c "printf '${props}' > ${ORACLE_HOME}/oui/.globalEnv.properties"
    log_ok "globalEnv.properties atualizado."

    # ── Patch Storage ──
    log_info "Compactando .patch_storage..."
    sudo -u oracle tar -zcf "${ORACLE_HOME}/patch_storage.tar.gz" \
        -C "$ORACLE_HOME" .patch_storage/ 2>/dev/null || true
    sudo -u oracle rm -rf "${ORACLE_HOME}/.patch_storage/"* 2>/dev/null || true
    log_ok "Patch storage compactado e limpo."

    log_info "Patches instalados:"
    sudo -u oracle "${ORACLE_HOME}/OPatch/opatch" lspatches 2>/dev/null | tee -a "$LOGFILE" || true

    service qualys-cloud-agent restart 2>/dev/null || true
    log_ok "Fase de patches concluida."
}

# ─── DOMAIN ──────────────────────────────────────────────────────────────────

gerar_domain_py() {
    local rsp_dir="${MIDIAS}/response"
    local domain_py="${rsp_dir}/domain.py"
    mkdir -p "$rsp_dir"

    local has_ms_py="False"
    local ms_port_py="0"
    [[ -n "$MS_NOME" ]] && { has_ms_py="True"; ms_port_py="$MS_PORT"; }

    cat > "$domain_py" << PYEOF
# -*- coding: utf-8 -*-
# domain.py - WLS 14.1.1 PURO
# Template: Basic WebLogic Server Domain (identico ao 12.2.1.4)
# Gerado por INSTALL_WLS_1411_PURO.sh

ORACLE_HOME  = '${ORACLE_HOME}'
DOMAIN_HOME  = '${DOMAIN_HOME}'
DOMAIN_NAME  = '${DOMAIN_NAME}'
JAVA_HOME    = '/usr/java/latest'
ADMIN_USER   = '${WLS_ADMIN_USER}'
ADMIN_PASS   = '${WLS_ADMIN_PASS}'
ADMIN_NOME   = '${ADMIN_SERVER_NOME}'
ADMIN_PORT   = ${ADMIN_PORT}
NM_PORT      = ${NM_PORT}
MS_NOME      = '${MS_NOME}'
MS_PORT      = ${ms_port_py}
CLUSTER_NAME = '${CLUSTER_NAME}'
HOST_NAME    = '${HOST_NAME}'
HAS_MS       = ${has_ms_py}

def createDomain():
    print('Criando domain WLS 14.1.1 PURO...')

    selectTemplate('Basic WebLogic Server Domain')
    loadTemplates()
    print('Template carregado: Basic WebLogic Server Domain')

    setOption('DomainName',      DOMAIN_NAME)
    setOption('JavaHome',        JAVA_HOME)
    setOption('AppDir',          DOMAIN_HOME + '/applications')
    setOption('OverwriteDomain', 'true')
    setOption('ServerStartMode', 'prod')

    cd('/Security/base_domain/User/weblogic')
    cmo.setPassword(ADMIN_PASS)

    cd('/Servers/AdminServer')
    cmo.setListenPort(ADMIN_PORT)
    cmo.setListenAddress('')
    print('Admin Server configurado na porta ' + str(ADMIN_PORT))

    if HAS_MS and MS_NOME:
        cd('/')
        try:
            cd('/Servers/' + MS_NOME)
        except:
            cd('/')
            create(MS_NOME, 'Server')
            cd('/Servers/' + MS_NOME)
        cmo.setListenPort(MS_PORT)
        cmo.setListenAddress('')
        print('MS ' + MS_NOME + ' na porta ' + str(MS_PORT))

        cd('/')
        try:
            create(CLUSTER_NAME, 'Cluster')
        except:
            pass
        # assign() e a API offline correta para associacoes — nao depende de getMBean
        assign('Server', MS_NOME, 'Cluster', CLUSTER_NAME)

    cd('/')
    try:
        create(HOST_NAME, 'UnixMachine')
    except:
        pass
    cd('/Machines/' + HOST_NAME)
    try:
        create(HOST_NAME, 'NodeManager')
    except:
        pass
    cd('/Machines/' + HOST_NAME + '/NodeManager/' + HOST_NAME)
    cmo.setListenAddress(HOST_NAME)
    cmo.setListenPort(NM_PORT)
    cmo.setNMType('Plain')

    assign('Server', ADMIN_NOME, 'Machine', HOST_NAME)
    if HAS_MS and MS_NOME:
        assign('Server', MS_NOME, 'Machine', HOST_NAME)

    setOption('OverwriteDomain', 'true')
    writeDomain(DOMAIN_HOME)
    closeTemplate()
    print('Domain gravado em: ' + DOMAIN_HOME)

createDomain()
PYEOF

    chown oracle:oinstall "$domain_py"
    log_ok "domain.py gerado em $domain_py"
}

criar_domain() {
    log_step "Fase 3 - Criacao do Domain WLS 14.1.1 PURO"

    gerar_domain_py

    log_info "Preparando diretorio do domain..."
    mkdir -p "$DOMAIN_HOME"
    chown -R oracle:oinstall "$(dirname "$DOMAIN_HOME")"
    log_ok "DOMAIN_HOME pronto: $DOMAIN_HOME"


    log_info "Rodando WLST..."
    sudo -u oracle "${ORACLE_HOME}/oracle_common/common/bin/wlst.sh" \
        "${MIDIAS}/response/domain.py" \
        2>&1 | tee -a "$LOGFILE"
    checar_erro "Falha na criacao do domain via WLST."

    # boot.properties Admin Server
    local boots_dir="${DOMAIN_HOME}/servers/${ADMIN_SERVER_NOME}/security"
    sudo -u oracle mkdir -p "$boots_dir"
    sudo -u oracle bash -c "printf 'username=${WLS_ADMIN_USER}\npassword=${WLS_ADMIN_PASS}\n' > ${boots_dir}/boot.properties"
    sudo -u oracle chmod 600 "${boots_dir}/boot.properties"
    log_ok "boot.properties Admin Server criado."

    if [[ -n "$MS_NOME" ]]; then
        local bootms_dir="${DOMAIN_HOME}/servers/${MS_NOME}/security"
        sudo -u oracle mkdir -p "$bootms_dir"
        sudo -u oracle bash -c "printf 'username=${WLS_ADMIN_USER}\npassword=${WLS_ADMIN_PASS}\n' > ${bootms_dir}/boot.properties"
        sudo -u oracle chmod 600 "${bootms_dir}/boot.properties"
        log_ok "boot.properties Managed Server ($MS_NOME) criado."
    fi

    log_ok "Domain $DOMAIN_NAME criado em $DOMAIN_HOME"
}

# ─── INICIAR SERVIÇOS ────────────────────────────────────────────────────────

iniciar_servicos() {
    log_step "Fase 4 - Inicializacao dos Servicos"

    local start_admin="${DOMAIN_HOME}/bin/startWebLogic.sh"
    if [[ ! -f "$start_admin" ]]; then
        log_erro "startWebLogic.sh nao encontrado. Domain criado?"
        exit 1
    fi

    # Logs de servidor ficam dentro do domain, nao em /u02/midias
    local nm_home="${DOMAIN_HOME}/nodemanager"
    local nm_props="${nm_home}/nodemanager.properties"
    local nm_out="${nm_home}/nodemanager.out"
    local admin_out="${DOMAIN_HOME}/servers/${ADMIN_SERVER_NOME}/logs/${ADMIN_SERVER_NOME}.out"

    sudo -u oracle mkdir -p "$nm_home"
    sudo -u oracle mkdir -p "${DOMAIN_HOME}/servers/${ADMIN_SERVER_NOME}/logs"

    # Registrar domain no nodemanager.domains para NM reconhecer o domain
    sudo -u oracle bash -c "printf '%s=%s\n' '${DOMAIN_NAME}' '${DOMAIN_HOME}' > ${nm_home}/nodemanager.domains"

    # Pre-criar nodemanager.properties com SecureListener=false e ListenAddress vazio.
    # ListenAddress vazio = escuta em todas as interfaces (o default 'localhost' impede
    # que o Admin Console alcance o NM via hostname).
    sudo -u oracle bash -c "
        printf 'DomainsFile=${nm_home}/nodemanager.domains\n' > ${nm_props}
        printf 'PropertiesVersion=14.1.1\n'          >> ${nm_props}
        printf 'AuthenticationEnabled=true\n'        >> ${nm_props}
        printf 'NodeManagerHome=${nm_home}\n'        >> ${nm_props}
        printf 'JavaHome=/usr/java/latest\n'         >> ${nm_props}
        printf 'LogLevel=INFO\n'                     >> ${nm_props}
        printf 'DomainsFileEnabled=true\n'           >> ${nm_props}
        printf 'StartScriptEnabled=false\n'          >> ${nm_props}
        printf 'ListenAddress=\n'                    >> ${nm_props}
        printf 'ListenPort=${NM_PORT}\n'             >> ${nm_props}
        printf 'NativeVersionEnabled=true\n'         >> ${nm_props}
        printf 'SecureListener=false\n'              >> ${nm_props}
        printf 'ListenBacklog=50\n'                  >> ${nm_props}
        printf 'CrashRecoveryEnabled=false\n'        >> ${nm_props}
        printf 'StartScriptName=startWebLogic.sh\n'  >> ${nm_props}
    "
    chown oracle:oinstall "$nm_props"

    log_info "Iniciando NodeManager como oracle (background)..."
    sudo -u oracle bash -c "
        export JAVA_HOME=/usr/java/latest
        export ORACLE_HOME=${ORACLE_HOME}
        nohup ${DOMAIN_HOME}/bin/startNodeManager.sh </dev/null > ${nm_out} 2>&1 &
        disown
        echo \$! > ${nm_home}/nodemanager.pid
        echo 'NodeManager iniciado com PID '\$!
    "
    sleep 20

    # WLS NM regenera nodemanager.properties no boot restaurando SecureListener=true.
    # Domain usa NMType=Plain — matar NM, forcar false e reiniciar.
    log_info "Corrigindo SecureListener=false e reiniciando NodeManager..."
    sudo -u oracle bash -c "
        kill \$(cat ${nm_home}/nodemanager.pid 2>/dev/null) 2>/dev/null || true
        sleep 5
        sed -i 's/^SecureListener=.*/SecureListener=false/' ${nm_props}
        export JAVA_HOME=/usr/java/latest
        export ORACLE_HOME=${ORACLE_HOME}
        nohup ${DOMAIN_HOME}/bin/startNodeManager.sh </dev/null >> ${nm_out} 2>&1 &
        disown
        echo \$! > ${nm_home}/nodemanager.pid
        echo 'NodeManager reiniciado com PID '\$!
    "
    sleep 10

    if sudo -u oracle bash -c "timeout 5 bash -c 'echo >/dev/tcp/${HOST_NAME}/${NM_PORT}'" 2>/dev/null; then
        log_ok "NodeManager ativo na porta ${NM_PORT}."
    else
        log_warn "NodeManager pode estar iniciando ainda. Aguardando 15s..."
        sleep 15
        if ! sudo -u oracle bash -c "timeout 5 bash -c 'echo >/dev/tcp/${HOST_NAME}/${NM_PORT}'" 2>/dev/null; then
            log_erro "NodeManager nao respondeu. Verifique: $nm_out"
        fi
    fi

    log_info "Iniciando Admin Server (porta ${ADMIN_PORT})..."
    sudo -u oracle bash -c "
        export JAVA_HOME=/usr/java/latest
        export ORACLE_HOME=${ORACLE_HOME}
        nohup ${start_admin} </dev/null >> ${admin_out} 2>&1 &
        disown
    "
    # (variavel start_admin ja definida acima)

    log_info "Aguardando Admin Server RUNNING (max 5 min)..."
    local t=0
    until grep -q "RUNNING" "$admin_out" 2>/dev/null || [[ $t -ge 30 ]]; do
        sleep 10; t=$((t+1)); echo -n "."
    done
    echo ""

    if ! grep -q "RUNNING" "$admin_out" 2>/dev/null; then
        log_erro "Timeout aguardando Admin Server. Verifique: $admin_out"
        tail -20 "$admin_out" 2>/dev/null || true
        exit 1
    fi
    log_ok "Admin Server RUNNING — http://${HOST_IP}:${ADMIN_PORT}/console"

    # Iniciar Managed Server se configurado
    if [[ -n "$MS_NOME" ]]; then
        local ms_out="${DOMAIN_HOME}/servers/${MS_NOME}/logs/${MS_NOME}.out"
        sudo -u oracle mkdir -p "${DOMAIN_HOME}/servers/${MS_NOME}/logs"

        log_info "Iniciando Managed Server ${MS_NOME} (porta ${MS_PORT})..."
        sudo -u oracle bash -c "
            export JAVA_HOME=/usr/java/latest
            export ORACLE_HOME=${ORACLE_HOME}
            nohup ${DOMAIN_HOME}/bin/startManagedWebLogic.sh \
                '${MS_NOME}' 't3://${HOST_NAME}:${ADMIN_PORT}' \
                </dev/null >> ${ms_out} 2>&1 &
            disown
        "

        log_info "Aguardando ${MS_NOME} RUNNING (max 5 min)..."
        local tm=0
        until grep -q "RUNNING" "$ms_out" 2>/dev/null || [[ $tm -ge 30 ]]; do
            sleep 10; tm=$((tm+1)); echo -n "."
        done
        echo ""

        if grep -q "RUNNING" "$ms_out" 2>/dev/null; then
            log_ok "${MS_NOME} RUNNING na porta ${MS_PORT}"
        else
            log_warn "Timeout aguardando ${MS_NOME}. Verifique: $ms_out"
            tail -20 "$ms_out" 2>/dev/null || true
        fi
    fi
}

# ─── RESPONSE FINAL ──────────────────────────────────────────────────────────

gerar_response_final() {
    local summary="${MIDIAS}/response/install_summary_wls1411_$(date '+%Y%m%d_%H%M%S').txt"
    mkdir -p "${MIDIAS}/response"

    cat > "$summary" << EOF
# ============================================================
# RESUMO INSTALACAO WLS 14.1.1 PURO
# Data: $(date '+%d/%m/%Y %H:%M:%S')
# Host: ${HOST_NAME} (${HOST_IP})
# ============================================================

ORACLE_HOME   = ${ORACLE_HOME}
DOMAIN_HOME   = ${DOMAIN_HOME}
DOMAIN_NAME   = ${DOMAIN_NAME}
JAVA_HOME     = /usr/java/latest  (JDK 8u501)
ADMIN_PORT    = ${ADMIN_PORT}
NM_PORT       = ${NM_PORT}
MS_NOME       = ${MS_NOME:-N/A}
MS_PORT       = ${MS_PORT:-N/A}
CLUSTER       = ${CLUSTER_NAME}
BUNDLE        = ${BUNDLE_DIR}

Console       = http://${HOST_IP}:${ADMIN_PORT}/console
Log install   = ${LOGFILE}
Log NM        = ${DOMAIN_HOME}/nodemanager/nodemanager.out
Log admin     = ${DOMAIN_HOME}/servers/${ADMIN_SERVER_NOME}/logs/${ADMIN_SERVER_NOME}.out
Log MS        = ${DOMAIN_HOME}/servers/${MS_NOME:-N/A}/logs/${MS_NOME:-N/A}.out

# Comandos uteis
startWebLogic : ${DOMAIN_HOME}/bin/startWebLogic.sh
stopWebLogic  : ${DOMAIN_HOME}/bin/stopWebLogic.sh
startNM       : ${DOMAIN_HOME}/bin/startNodeManager.sh
startMS       : ${DOMAIN_HOME}/bin/startManagedWebLogic.sh ${MS_NOME:-<MS>} t3://${HOST_NAME}:${ADMIN_PORT}
opatch check  : sudo -u oracle ${ORACLE_HOME}/OPatch/opatch lspatches
EOF

    chown oracle:oinstall "$summary" 2>/dev/null || true
    log_ok "Resumo salvo em: $summary"
    cat "$summary"
}


# ─── MENU PRINCIPAL ──────────────────────────────────────────────────────────

menu() {
    banner
    echo -e "  ${BOLD}Selecione a opcao:${NC}"
    echo ""
    echo "  [1] Instalacao COMPLETA (prereqs + JDK + binarios + PSU + domain + servidores)"
    echo "  [2] Somente pre-requisitos do sistema"
    echo "  [3] Somente JDK 8u501"
    echo "  [4] Somente binarios WLS 14.1.1"
    echo "  [5] Somente PSU (OPatch + ${BUNDLE_DIR})"
    echo "  [6] Somente criar domain"
    echo "  [7] Somente iniciar servicos"
    echo "  [8] Gerar response/resumo"
    echo "  [0] Sair"
    echo ""
    read -rp "  Opcao: " opcao

    validar_root

    case "$opcao" in
        1)
            coletar_infos
            preparar_usuario_oracle
            criar_orainst
            instalar_prereqs
            instalar_java
            instalar_binarios
            aplicar_patches
            criar_domain
            iniciar_servicos
            gerar_response_final
            ;;
        2)
            coletar_infos
            preparar_usuario_oracle
            criar_orainst
            instalar_prereqs
            ;;
        3)
            instalar_java
            ;;
        4)
            coletar_infos
            instalar_binarios
            ;;
        5)
            read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp
            ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
            aplicar_patches
            ;;
        6)
            coletar_infos
            criar_domain
            ;;
        7)
            coletar_infos
            iniciar_servicos
            ;;
        8)
            coletar_infos
            gerar_response_final
            ;;
        0)
            log_info "Saindo."
            exit 0
            ;;
        *)
            log_erro "Opcao invalida."
            exit 1
            ;;
    esac
}

menu
