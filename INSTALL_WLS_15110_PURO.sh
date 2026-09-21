#!/bin/bash
# =============================================================================
# INSTALAÇÃO WebLogic 15.1.1.0.0 PURO - Standalone (sem SOA/OSB/ODI)
# Oraex / Getnet
#
# Baseado no readme Oracle FMW 15.1.1 e padrões do ambiente Getnet
# Autor: Oraex | Data: Setembro/2026
#
# USO: ./INSTALL_WLS_15110_PURO.sh
# Deve ser executado como root. Operações Oracle rodam como sudo -u oracle.
# =============================================================================

set -euo pipefail

# ─── CORES E LOG ─────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

LOGDIR="/u02/midias/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/install_wls15110_${HOSTNAME}.log"
echo "" >> "$LOGFILE" 2>/dev/null || true
echo "======================================================================" >> "$LOGFILE" 2>/dev/null || true
echo "  NOVA EXECUCAO: $(date '+%d/%m/%Y %H:%M:%S')" >> "$LOGFILE" 2>/dev/null || true
echo "======================================================================" >> "$LOGFILE" 2>/dev/null || true

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*" | tee -a "$LOGFILE"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "$LOGFILE"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOGFILE"; }
log_erro()  { echo -e "${RED}[ERRO]${NC}  $*" | tee -a "$LOGFILE"; }
log_step()  { echo -e "\n${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"; \
              echo -e "${BOLD}${BLUE}  $*${NC}"; \
              echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}\n" | tee -a "$LOGFILE"; }

checar_erro() {
    if [ $? -ne 0 ]; then
        log_erro "$1"
        log_erro "Verifique o log: $LOGFILE"
        exit 1
    fi
}

# ─── REPOSITÓRIOS ────────────────────────────────────────────────────────────

REPO_BASE="https://repository.getnet.com.br"
REPO_JAVA="${REPO_BASE}/binarios/oraex/linux/cpu/middleware/oracle/wls/14.1.2.0.0/puro/latest/java"
REPO_PSU="${REPO_BASE}/binarios/oraex/linux/cpu/middleware/oracle/wls/15.1.1.0.0/puro/latest"
REPO_INSTALADORES="${REPO_BASE}/binarios/oraex/linux/instaladores/15110/instaladores.tar.gz"

JAVA_RPM="jdk-17.0.20_linux-x64_bin.rpm"
JAVA_HOME_17="/usr/java/jdk-17.0.20"

JAR_WLS="fmw_15.1.1.0.0_wls_generic.jar"

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
CLUSTER_NAME_PADRAO="WLS"
WLS_ADMIN_USER="weblogic"

# ─── VARIÁVEIS GLOBAIS (preenchidas interativamente) ─────────────────────────

ORACLE_HOME=""
DOMAIN_HOME=""
DOMAIN_NAME=""
JAVA_HOME_PATH=""
WLS_MEM_MB=""
MS_NOME=""
MS_PORT="7011"
CLUSTER_NAME=""
WLS_ADMIN_PASS=""

HOST_NAME=$(hostname)
HOST_IP=$(hostname -I | awk '{print $1}')
GROUP_NAME="GG_WEBLOGIC_$(echo "$HOST_NAME" | tr '[:lower:]' '[:upper:]')"

# ─── BANNER ──────────────────────────────────────────────────────────────────

banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║     INSTALAÇÃO WebLogic 15.1.1.0.0 PURO - Oraex / Getnet    ║"
    echo "  ║               Standalone - sem SOA/OSB/ODI                  ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  Host    : ${CYAN}${HOST_NAME}${NC}"
    echo -e "  IP      : ${CYAN}${HOST_IP}${NC}"
    echo -e "  Log     : ${CYAN}${LOGFILE}${NC}"
    echo ""
}

# ─── VALIDAÇÕES BÁSICAS ──────────────────────────────────────────────────────

validar_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_erro "Este script deve ser executado como root."
        exit 1
    fi
}

preparar_usuario_oracle() {
    log_step "Verificação / Preparação do Usuário Oracle"

    if ! getent group "$ORACLE_GROUP" &>/dev/null; then
        log_warn "Grupo '$ORACLE_GROUP' não encontrado. Criando..."
        groupadd -g "$ORACLE_GID" "$ORACLE_GROUP"
        log_ok "Grupo $ORACLE_GROUP criado (GID: $ORACLE_GID)."
    else
        log_ok "Grupo $ORACLE_GROUP já existe."
    fi

    if ! id "$ORACLE_USER" &>/dev/null; then
        log_warn "Usuário '$ORACLE_USER' não encontrado. Criando..."
        useradd -u "$ORACLE_UID" \
                -g "$ORACLE_GROUP" \
                -G "$ORACLE_GROUP" \
                -d "$ORACLE_USER_HOME" \
                -s /bin/bash \
                -c "Oracle Software Owner" \
                "$ORACLE_USER"
        log_ok "Usuário oracle criado (UID: $ORACLE_UID | Home: $ORACLE_USER_HOME)."
        echo ""
        log_info "Informe a senha do oracle gerada pelo Playbook/CyberArk para definir no host:"
        read -rsp "  Senha oracle (CyberArk): " ORACLE_OS_PASS; echo ""
        [[ -z "$ORACLE_OS_PASS" ]] && { log_erro "Senha não pode ser vazia."; exit 1; }
        echo "${ORACLE_USER}:${ORACLE_OS_PASS}" | chpasswd
        unset ORACLE_OS_PASS
        log_ok "Senha do oracle definida no host."
    else
        log_ok "Usuário oracle já existe: $(id oracle)"
        echo ""
        read -rp "  Deseja (re)definir a senha do oracle com a do Playbook/CyberArk? (s/n): " redef
        if [[ "$redef" == "s" ]]; then
            log_info "Informe a senha do oracle gerada pelo Playbook/CyberArk:"
            read -rsp "  Senha oracle (CyberArk): " ORACLE_OS_PASS; echo ""
            [[ -z "$ORACLE_OS_PASS" ]] && { log_erro "Senha não pode ser vazia."; exit 1; }
            echo "${ORACLE_USER}:${ORACLE_OS_PASS}" | chpasswd
            unset ORACLE_OS_PASS
            log_ok "Senha do oracle (re)definida no host com sucesso."
        else
            log_info "Senha do oracle mantida. Continuando..."
        fi
    fi

    if [ ! -d "$ORACLE_USER_HOME" ]; then
        mkdir -p "$ORACLE_USER_HOME"
        log_ok "Diretório home criado: $ORACLE_USER_HOME"
    fi
    chown oracle:oinstall "$ORACLE_USER_HOME"
    chmod 750 "$ORACLE_USER_HOME"

    for dir in "$ORACLE_BASE" "$ORACLE_BASE/middleware" "$INVENTORY"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_ok "Diretório criado: $dir"
        fi
        chown -R oracle:oinstall "$dir"
    done

    local profile="${ORACLE_USER_HOME}/.bash_profile"
    if [ ! -f "$profile" ]; then
        cat > "$profile" << EOF
# Oracle bash_profile - gerado por INSTALL_WLS_15110_PURO.sh
export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_HOME=/u01/oracle/middleware
export PATH=\$ORACLE_HOME/bin:\$ORACLE_HOME/OPatch:\$PATH
export JAVA_HOME=/usr/java/latest
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
        chown oracle:oinstall "$profile"
        log_ok ".bash_profile do oracle criado."
    fi

    log_ok "Usuário oracle pronto para instalação."
}

validar_espaco_disco() {
    local path="$1"
    local minimo_gb="$2"
    local disponivel
    disponivel=$(df -BG "$path" 2>/dev/null | awk 'NR==2{gsub("G",""); print $4}')
    if [ -z "$disponivel" ] || [ "$disponivel" -lt "$minimo_gb" ]; then
        log_warn "Espaço disponível em $path: ${disponivel}GB (mínimo recomendado: ${minimo_gb}GB)"
        read -rp "  Deseja continuar mesmo assim? (s/n): " cont
        [[ "$cont" != "s" ]] && exit 1
    else
        log_ok "Espaço em $path: ${disponivel}GB disponível."
    fi
}

# ─── CRIAR oraInst.loc ───────────────────────────────────────────────────────

criar_orainst() {
    log_step "Criando oraInst.loc e inventory"
    if [ -f "$ORAINST" ]; then
        log_warn "$ORAINST já existe. Conteúdo atual:"
        cat "$ORAINST"
        read -rp "  Deseja recriar? (s/n): " recria
        [[ "$recria" != "s" ]] && return 0
    fi

    mkdir -p "$INVENTORY"
    chown -R ${ORACLE_USER}:${ORACLE_GROUP} "$INVENTORY"

    cat > "$ORAINST" << EOF
inventory_loc=${INVENTORY}
inst_group=${ORACLE_GROUP}
EOF
    chmod 644 "$ORAINST"
    log_ok "oraInst.loc criado em $ORAINST"
    log_ok "Inventory: $INVENTORY"
}

# ─── COLETA DE INFORMAÇÕES ───────────────────────────────────────────────────

coletar_infos() {
    log_step "Coleta de Informações - Ambiente WebLogic 15.1.1 PURO"

    echo -e "  Host detectado automaticamente: ${CYAN}${HOST_NAME}${NC} (${HOST_IP})"
    echo -e "  Grupo XACML será configurado:   ${CYAN}${GROUP_NAME}${NC}"
    echo ""

    read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp
    ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
    log_info "ORACLE_HOME: $ORACLE_HOME"

    echo ""
    echo "  Exemplos de path de domain:"
    echo "    /u01/qualidade/domains/wls_domain"
    echo "    /u01/producao/domains/wls_domain"
    read -rp "  Informe o path completo do DOMAIN_HOME: " DOMAIN_HOME
    [[ -z "$DOMAIN_HOME" ]] && { log_erro "DOMAIN_HOME obrigatório."; exit 1; }
    DOMAIN_NAME=$(basename "$DOMAIN_HOME")
    log_info "DOMAIN_HOME: $DOMAIN_HOME"
    log_info "DOMAIN_NAME: $DOMAIN_NAME"

    echo ""
    read -rp "  Nome do Managed Server [wls_server1]: " inp
    MS_NOME="${inp:-wls_server1}"
    log_info "MS: $MS_NOME | Porta: $MS_PORT"

    echo ""
    read -rp "  Nome do Cluster WebLogic [${CLUSTER_NAME_PADRAO}]: " inp
    CLUSTER_NAME="${inp:-$CLUSTER_NAME_PADRAO}"
    log_info "Cluster: $CLUSTER_NAME"

    echo ""
    read -rp "  Memória RAM/Heap para a JVM do Servidor (MB) [4096]: " inp
    WLS_MEM_MB="${inp:-4096}"
    log_info "Heap configurado para: ${WLS_MEM_MB}MB"

    WLS_ADMIN_PASS=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 14 || true)
    WLS_ADMIN_PASS="${WLS_ADMIN_PASS}#1"
    [[ -z "$WLS_ADMIN_PASS" ]] && WLS_ADMIN_PASS="Welcome_$(date +%s | tail -c 6)#1"

    mkdir -p "${MIDIAS}/response"
    local senha_file="${MIDIAS}/response/wls_admin_pass.txt"
    echo "WLS_ADMIN_USER=${WLS_ADMIN_USER}" > "$senha_file"
    echo "WLS_ADMIN_PASS=${WLS_ADMIN_PASS}" >> "$senha_file"
    echo "HOST=${HOST_NAME}" >> "$senha_file"
    echo "GERADO_EM=$(date '+%d/%m/%Y %H:%M:%S')" >> "$senha_file"
    chmod 600 "$senha_file"

    echo ""
    echo -e "  ${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "  ${BOLD}║  SENHA ADMIN WEBLOGIC GERADA                 ║${NC}"
    echo -e "  ${BOLD}║  Usuario : ${WLS_ADMIN_USER}                           ║${NC}"
    echo -e "  ${BOLD}║  Senha   : ${WLS_ADMIN_PASS}                  ║${NC}"
    echo -e "  ${BOLD}║  Salva em: ${senha_file}  ║${NC}"
    echo -e "  ${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

# ─── JAVA ────────────────────────────────────────────────────────────────────

instalar_java() {
    log_step "Fase 0 - Instalação do Java 17"

    echo ""
    echo "  Versoes de Java instaladas atualmente:"
    rpm -qa | grep jdk || echo "  (nenhuma)"
    echo ""

    if rpm -qa | grep -q "jdk-17"; then
        log_ok "Java 17 ja esta instalado no sistema."
        JAVA_HOME_PATH="$JAVA_HOME_17"
        local jsec="${JAVA_HOME_PATH}/conf/security/java.security"
        [ -f "$jsec" ] && sed -i 's|securerandom.source=file:/dev/random|securerandom.source=file:/dev/./urandom|' "$jsec" 2>/dev/null || true
        read -rp "  Deseja reinstalar o Java 17? (s/n): " troca_java
        if [[ "$troca_java" != "s" ]]; then
            log_info "Mantendo Java 17 atual. Continuando..."
            return 0
        fi
    fi

    log_info "Baixando JDK 17 para /u02/midias/java ..."
    mkdir -p "${MIDIAS}/java"
    cd "${MIDIAS}/java"

    wget -q --show-progress "${REPO_JAVA}/${JAVA_RPM}" -O "$JAVA_RPM"
    checar_erro "Falha no download do JDK 17."

    read -rp "  Digite a versao do Java a REMOVER (ou deixe em branco para pular): " java_remove
    if [ -n "$java_remove" ]; then
        if rpm -qa | grep -q "$java_remove"; then
            rpm -e --nodeps "$java_remove"
            log_ok "Java $java_remove removido."
        else
            log_warn "Versao '$java_remove' nao encontrada. Pulando remocao."
        fi
    fi

    log_info "Instalando JDK 17 (${JAVA_RPM})..."
    rpm -i --replacepkgs "${MIDIAS}/java/${JAVA_RPM}" || \
    rpm -U "${MIDIAS}/java/${JAVA_RPM}" || true
    JAVA_HOME_PATH="$JAVA_HOME_17"

    local JAVA_SECURITY="${JAVA_HOME_PATH}/conf/security/java.security"
    if [ -f "$JAVA_SECURITY" ]; then
        sed -i 's|securerandom.source=file:/dev/random|securerandom.source=file:/dev/./urandom|' "$JAVA_SECURITY"
        log_ok "java.security configurado para urandom (${JAVA_SECURITY})."
    else
        log_warn "java.security nao encontrado em ${JAVA_SECURITY}."
    fi

    update-alternatives --config java 2>/dev/null || true

    rm -f "${MIDIAS}/java/${JAVA_RPM}"
    log_ok "Java 17 instalado: $JAVA_HOME_PATH"
}

# ─── DOWNLOAD DOS INSTALADORES ───────────────────────────────────────────────

baixar_instaladores() {
    log_step "Fase 1a - Download dos Instaladores do Repositório"

    log_info "Baixando arquivo tar.gz dos instaladores..."
    log_info "Repositório: $REPO_INSTALADORES"

    mkdir -p "${MIDIAS}/instaladores"
    cd "${MIDIAS}/instaladores"

    wget -q --show-progress "$REPO_INSTALADORES" -O instaladores.tar.gz
    checar_erro "Falha no download do tar.gz de instaladores."

    log_info "Descompactando instaladores..."
    tar -xf instaladores.tar.gz
    checar_erro "Falha ao descompactar instaladores."

    log_info "Ajustando permissões para oracle..."
    chown -R oracle:oinstall "${MIDIAS}/instaladores"
    chmod -R 750 "${MIDIAS}/instaladores"
    log_ok "Permissões ajustadas."

    # Localizar o JAR — pode estar na raiz ou em subdiretório
    local jar_path
    jar_path=$(find "${MIDIAS}/instaladores" -name "$JAR_WLS" 2>/dev/null | head -1)
    if [ -n "$jar_path" ]; then
        log_ok "Instalador localizado: $jar_path"
    else
        log_warn "JAR '${JAR_WLS}' nao localizado em ${MIDIAS}/instaladores."
        log_warn "Conteudo do diretorio:"
        ls -la "${MIDIAS}/instaladores/" 2>/dev/null || true
    fi

    log_ok "Instaladores disponíveis em: ${MIDIAS}/instaladores/"
}

# ─── RESPONSE FILE ───────────────────────────────────────────────────────────

gerar_response_file() {
    local rsp_dir="${MIDIAS}/response"
    mkdir -p "$rsp_dir"
    chown -R ${ORACLE_USER}:${ORACLE_GROUP} "$rsp_dir"

    cat > "${rsp_dir}/wls.rsp" << EOF
[ENGINE]
Response File Version=1.0.0.0.0
[GENERIC]
ORACLE_HOME=${ORACLE_HOME}
INSTALL_TYPE=WebLogic Server
DECLINE_SECURITY_UPDATES=true
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
EOF

    chown ${ORACLE_USER}:${ORACLE_GROUP} "${rsp_dir}/wls.rsp"
    log_ok "Response file gerado em: ${rsp_dir}/wls.rsp"
}

# ─── INSTALAÇÃO DOS BINÁRIOS ─────────────────────────────────────────────────

instalar_binarios() {
    log_step "Fase 1 - Instalação dos Binários WebLogic 15.1.1"

    local rsp_dir="${MIDIAS}/response"
    local java_bin

    java_bin=$(readlink -f /usr/bin/java 2>/dev/null || echo "")
    if [ ! -x "$java_bin" ]; then
        java_bin=$(find /usr/java -name "java" -type f 2>/dev/null | head -1)
    fi
    [[ -z "$java_bin" ]] && { log_erro "Java nao encontrado. Instale o Java primeiro (opcao [2])."; exit 1; }
    log_info "Usando Java: $java_bin"
    export JAVA_HOME=$(dirname $(dirname "$java_bin"))

    criar_orainst
    gerar_response_file

    if [ -f "${ORACLE_HOME}/oracle_common/bin/wlst.sh" ]; then
        log_ok "WebLogic ja detectado em ${ORACLE_HOME}. Pulando instalacao."
        return 0
    fi

    # Localizar JAR
    local jar_path
    jar_path=$(find "${MIDIAS}/instaladores" -name "$JAR_WLS" 2>/dev/null | head -1)
    if [ -z "$jar_path" ]; then
        log_erro "Instalador '${JAR_WLS}' nao encontrado em ${MIDIAS}/instaladores/."
        log_erro "Execute a opcao de download dos instaladores primeiro."
        exit 1
    fi
    log_info "Instalador: $jar_path"

    log_info "Iniciando instalacao silenciosa do WebLogic 15.1.1..."
    mkdir -p "${MIDIAS}/tmp"
    chown oracle:oinstall "${MIDIAS}/tmp"
    sudo -u oracle bash -c "
        export JAVA_HOME=${JAVA_HOME}
        export PATH=\$JAVA_HOME/bin:\$PATH
        '$java_bin' -Djava.io.tmpdir='${MIDIAS}/tmp' -jar '$jar_path' \
            -silent \
            -responseFile '${rsp_dir}/wls.rsp' \
            -invPtrLoc '$ORAINST' \
            -jreLoc '$JAVA_HOME'
    " 2>&1 | tee -a "$LOGFILE"
    checar_erro "Falha na instalacao do WebLogic 15.1.1."

    log_ok "WebLogic 15.1.1.0.0 instalado em: $ORACLE_HOME"
}

# ─── APLICAÇÃO DE PATCHES (PSU) ──────────────────────────────────────────────

aplicar_patches() {
    log_step "Fase 2 - Atualização OPatch e Aplicação do Bundle PSU Jul/2026"

    local BASE_PSU="${MIDIAS}/binarios/oraex/linux/cpu/middleware/oracle/wls/15.1.1.0.0/puro/latest"

    # Localizar java
    local java_bin
    java_bin=$(readlink -f /usr/bin/java 2>/dev/null || echo "")
    if [ ! -x "$java_bin" ]; then
        java_bin=$(find /usr/java -name "java" -type f 2>/dev/null | head -1)
    fi
    [[ -z "$java_bin" ]] && { log_erro "Java nao encontrado."; exit 1; }

    # ── Download dos patches ──
    log_info "Baixando OPatch e bundle PSU do repositório..."
    cd "${MIDIAS}"

    wget -r -nv -np -nH \
        --execute="robots = off" --mirror --convert-links \
        --no-parent --reject "index.html*" \
        "${REPO_PSU}/opatch/" \
        2>&1 | tee -a "$LOGFILE" || true

    wget -r -nv -np -nH \
        --execute="robots = off" --mirror --convert-links \
        --no-parent --reject "index.html*" \
        "${REPO_PSU}/bundle/" \
        2>&1 | tee -a "$LOGFILE" || true

    chown -R oracle:oinstall "${MIDIAS}/binarios" 2>/dev/null || true

    # ── OPatch ──
    log_info "Aplicando OPatch..."
    local opatch_dir="${BASE_PSU}/opatch"
    if [ -d "$opatch_dir" ]; then
        cd "$opatch_dir"
        sudo -u oracle unzip -q -o '*.zip' 2>/dev/null || true
        if [ -d "6880880" ]; then
            cd 6880880/
            sudo -u oracle "$java_bin" -jar opatch_generic.jar -silent oracle_home="$ORACLE_HOME" \
                2>&1 | tee -a "$LOGFILE" || log_warn "Falha ao aplicar OPatch. Continuando..."
            log_ok "OPatch processado."
        else
            log_warn "Diretório 6880880 nao encontrado em ${opatch_dir}. Continuando..."
        fi
    else
        log_warn "Diretório OPatch nao encontrado: ${opatch_dir}. Continuando..."
    fi

    # ── Bundle SPBAT ──
    log_info "Aplicando Bundle Patch via SPBAT (WLS_SPB_15.1.1.0.260703)..."
    local bundle_dir="${BASE_PSU}/bundle"
    if [ -d "$bundle_dir" ]; then
        cd "$bundle_dir"
        sudo -u oracle unzip -q -o '*.zip' 2>/dev/null || true

        local spbat_sh
        spbat_sh=$(find "$bundle_dir" -path "*/WLS_SPB_*/tools/spbat/generic/SPBAT/spbat.sh" 2>/dev/null | head -1)
        if [ -n "$spbat_sh" ]; then
            cd "$(dirname "$spbat_sh")"
            log_info "Executando SPBAT: $(pwd)/spbat.sh"
            sudo -u oracle ./spbat.sh -phase apply -oracle_home "$ORACLE_HOME" \
                2>&1 | tee -a "$LOGFILE" || log_warn "Falha ao aplicar bundle SPBAT. Continuando..."
            log_ok "Bundle Patch SPBAT processado."
        else
            log_warn "spbat.sh nao encontrado em ${bundle_dir}. Verifique o conteudo:"
            ls -la "${bundle_dir}" 2>/dev/null || true
            log_warn "Continuando sem bundle patch..."
        fi
    else
        log_warn "Diretório bundle nao encontrado: ${bundle_dir}. Continuando..."
    fi

    # ── globalEnv.properties (3x com sleep 15 — padrão ambiente Getnet) ──
    log_info "Configurando globalEnv.properties (3x)..."
    sudo -u oracle bash -c "echo -e 'JAVA_HOME=/usr/java/latest\nJAVA_HOME_1_8=/usr/java/latest\nJVM_64=' > ${ORACLE_HOME}/oui/.globalEnv.properties" 2>/dev/null || true
    sleep 15
    sudo -u oracle bash -c "echo -e 'JAVA_HOME=/usr/java/latest\nJAVA_HOME_1_8=/usr/java/latest\nJVM_64=' > ${ORACLE_HOME}/oui/.globalEnv.properties" 2>/dev/null || true
    sleep 15
    sudo -u oracle bash -c "echo -e 'JAVA_HOME=/usr/java/latest\nJAVA_HOME_1_8=/usr/java/latest\nJVM_64=' > ${ORACLE_HOME}/oui/.globalEnv.properties" 2>/dev/null || true
    log_ok "globalEnv.properties configurado."

    # ── Compactar e limpar patch_storage ──
    log_info "Compactando e limpando .patch_storage..."
    sudo -u oracle tar -zcf "${ORACLE_HOME}/patch_storage.tar.gz" \
        -C "$ORACLE_HOME" .patch_storage/ 2>/dev/null || true
    sudo -u oracle rm -rf "${ORACLE_HOME}/.patch_storage/"* 2>/dev/null || true
    log_ok "Patch storage compactado e limpo."

    # ── Verificar patches aplicados ──
    log_info "Patches aplicados no ORACLE_HOME:"
    sudo -u oracle "${ORACLE_HOME}/OPatch/opatch" lspatches 2>/dev/null \
        | tee -a "$LOGFILE" || true

    log_ok "Fase de patches concluída."
}

# ─── GERAR domain.py ─────────────────────────────────────────────────────────

gerar_domain_py() {
    local rsp_dir="${MIDIAS}/response"
    local domain_py="${rsp_dir}/domain.py"

    mkdir -p "$rsp_dir"

    cat > "$domain_py" << 'PYEOF'
# -*- coding: utf-8 -*-
# =============================================================================
# domain.py - Domain WebLogic 15.1.1 PURO
# Jython 2.7.1 — selectTemplate/loadTemplates (padrao Oracle 12.2+)
# =============================================================================

ORACLE_HOME  = '@@ORACLE_HOME@@'
DOMAIN_HOME  = '@@DOMAIN_HOME@@'
DOMAIN_NAME  = '@@DOMAIN_NAME@@'
JAVA_HOME    = '@@JAVA_HOME@@'
ADMIN_USER   = '@@ADMIN_USER@@'
ADMIN_PASS   = '@@ADMIN_PASS@@'
ADMIN_PORT   = @@ADMIN_PORT@@
NM_PORT      = @@NM_PORT@@
MS_NOME      = '@@MS_NOME@@'
MS_PORT      = @@MS_PORT@@
CLUSTER_NAME = '@@CLUSTER_NAME@@'
HOST_NAME    = '@@HOST_NAME@@'
GROUP_NAME   = '@@GROUP_NAME@@'

def createDomain():
    print('Criando domain WebLogic 15.1.1 PURO: ' + DOMAIN_NAME)

    selectTemplate('Basic WebLogic Server Domain')
    loadTemplates()
    print('Template carregado: Basic WebLogic Server Domain')

    setOption('DomainName',      DOMAIN_NAME)
    setOption('JavaHome',        JAVA_HOME)
    setOption('AppDir',          DOMAIN_HOME + '/applications')
    setOption('OverwriteDomain', 'true')
    setOption('ServerStartMode', 'prod')

    print('Configurando senha do admin...')
    cd('/Security/base_domain/User/' + ADMIN_USER)
    cmo.setPassword(ADMIN_PASS)

    print('Configurando Admin Server...')
    cd('/Servers/AdminServer')
    cmo.setListenPort(ADMIN_PORT)
    cmo.setListenAddress('')

    print('Configurando Managed Server: ' + MS_NOME)
    cd('/')
    try:
        cd('/Servers/' + MS_NOME)
        cmo.setListenPort(MS_PORT)
        cmo.setListenAddress('')
        print('MS ' + MS_NOME + ' ja existe — configurado.')
    except:
        print('Criando MS ' + MS_NOME + '...')
        cd('/')
        create(MS_NOME, 'Server')
        cd('/Servers/' + MS_NOME)
        cmo.setListenPort(MS_PORT)
        cmo.setListenAddress('')

    print('Configurando Cluster: ' + CLUSTER_NAME)
    cd('/')
    try:
        create(CLUSTER_NAME, 'Cluster')
    except:
        print('Cluster ja existe.')
    cd('/Clusters/' + CLUSTER_NAME)
    cmo.setClusterMessagingMode('unicast')

    print('Configurando Machine e NodeManager...')
    cd('/')
    try:
        create(HOST_NAME, 'UnixMachine')
    except:
        print('Machine ja existe.')
    cd('/Machines/' + HOST_NAME)
    try:
        create(HOST_NAME, 'NodeManager')
    except:
        print('NodeManager ja existe.')
    cd('/Machines/' + HOST_NAME + '/NodeManager/' + HOST_NAME)
    cmo.setListenAddress(HOST_NAME)
    cmo.setListenPort(int(NM_PORT))
    cmo.setNMType('Plain')

    try:
        cd('/')
        assign('Server', MS_NOME,     'Cluster', CLUSTER_NAME)
        assign('Server', MS_NOME,     'Machine', HOST_NAME)
        assign('Server', 'AdminServer', 'Machine', HOST_NAME)
    except:
        pass

    print('Gravando domain em: ' + DOMAIN_HOME)
    writeDomain(DOMAIN_HOME)
    closeTemplate()
    print('Domain criado com sucesso!')
    print('Remote Console (WRC app): http://' + HOST_NAME + ':' + str(ADMIN_PORT))

createDomain()
PYEOF

    sed -i "s|@@ORACLE_HOME@@|${ORACLE_HOME}|g"       "$domain_py"
    sed -i "s|@@DOMAIN_HOME@@|${DOMAIN_HOME}|g"       "$domain_py"
    sed -i "s|@@DOMAIN_NAME@@|${DOMAIN_NAME}|g"       "$domain_py"
    local _java_home_real
    _java_home_real=$(dirname "$(dirname "$(readlink -f /usr/bin/java 2>/dev/null)")" 2>/dev/null)
    [[ -z "$_java_home_real" || ! -d "$_java_home_real" ]] && _java_home_real="${JAVA_HOME_PATH:-/usr/java/latest}"
    sed -i "s|@@JAVA_HOME@@|${_java_home_real}|g"             "$domain_py"
    sed -i "s|@@ADMIN_USER@@|${WLS_ADMIN_USER}|g"     "$domain_py"
    sed -i "s|@@ADMIN_PASS@@|${WLS_ADMIN_PASS}|g"     "$domain_py"
    sed -i "s|@@ADMIN_PORT@@|${ADMIN_PORT}|g"         "$domain_py"
    sed -i "s|@@NM_PORT@@|${NM_PORT}|g"               "$domain_py"
    sed -i "s|@@MS_NOME@@|${MS_NOME:-wls_server1}|g"  "$domain_py"
    sed -i "s|@@MS_PORT@@|${MS_PORT}|g"               "$domain_py"
    sed -i "s|@@CLUSTER_NAME@@|${CLUSTER_NAME}|g"     "$domain_py"
    sed -i "s|@@HOST_NAME@@|${HOST_NAME}|g"           "$domain_py"
    sed -i "s|@@GROUP_NAME@@|${GROUP_NAME}|g"         "$domain_py"

    chown ${ORACLE_USER}:${ORACLE_GROUP} "$domain_py"
    log_ok "domain.py gerado em: $domain_py"
}

# ─── CRIAR DOMAIN ────────────────────────────────────────────────────────────

criar_domain() {
    log_step "Fase 3 - Criação do Domain WebLogic 15.1.1 PURO"

    gerar_domain_py

    local wlst="${ORACLE_HOME}/oracle_common/common/bin/wlst.sh"
    local domain_py="${MIDIAS}/response/domain.py"

    if [ ! -f "$wlst" ]; then
        log_erro "WLST não encontrado em: $wlst"
        log_erro "Verifique se o WebLogic foi instalado corretamente."
        exit 1
    fi

    mkdir -p "$DOMAIN_HOME"
    chown -R ${ORACLE_USER}:${ORACLE_GROUP} "$(dirname "$DOMAIN_HOME")" 2>/dev/null || true

    if [ -f "${DOMAIN_HOME}/config/config.xml" ]; then
        log_warn "Domain ja existe em ${DOMAIN_HOME}."
        read -rp "  Deseja recriar o domain? ATENCAO: apaga configuracoes atuais (s/n): " recriar_dm
        if [[ "$recriar_dm" != "s" ]]; then
            log_info "Domain mantido. Pulando criacao."
            return 0
        fi
        log_warn "Recriando domain..."
    fi

    log_info "Executando WLST offline para criar o domain..."
    sudo -u oracle bash -c "
        export JAVA_HOME=/usr/java/latest
        export ORACLE_HOME=${ORACLE_HOME}
        '${wlst}' '${domain_py}'
    " 2>&1 | tee -a "$LOGFILE"
    checar_erro "Falha na criação do domain."

    chown -R ${ORACLE_USER}:${ORACLE_GROUP} "$DOMAIN_HOME"
    chmod -R 750 "$DOMAIN_HOME"

    # ── Configurar JAVA_HOME e memória nos scripts do domain ──
    log_info "Configurando JAVA_HOME=/usr/java/latest nos scripts do domain..."

    local set_domain_env="${DOMAIN_HOME}/bin/setDomainEnv.sh"
    if [ -f "$set_domain_env" ]; then
        sudo -u oracle sed -i 's|JAVA_HOME=.*|JAVA_HOME=/usr/java/latest|g' "$set_domain_env"
        sudo -u oracle bash -c "echo 'USER_MEM_ARGS=\"-Xms${WLS_MEM_MB}m -Xmx${WLS_MEM_MB}m\"' >> \"$set_domain_env\""
        sudo -u oracle bash -c "echo 'export USER_MEM_ARGS' >> \"$set_domain_env\""
        log_ok "setDomainEnv.sh atualizado com JAVA_HOME e USER_MEM_ARGS."
    fi

    local set_nm_java="${DOMAIN_HOME}/bin/setNMJavaHome.sh"
    if [ -f "$set_nm_java" ]; then
        sudo -u oracle sed -i 's|JAVA_HOME=.*|JAVA_HOME=/usr/java/latest|g' "$set_nm_java"
        log_ok "setNMJavaHome.sh atualizado."
    fi

    # globalEnv final após criação do domain
    sudo -u oracle bash -c "echo -e 'JAVA_HOME=/usr/java/latest\nJAVA_HOME_1_8=/usr/java/latest\nJVM_64=' > ${ORACLE_HOME}/oui/.globalEnv.properties" 2>/dev/null || true
    log_ok "globalEnv.properties final atualizado."

    log_ok "Domain criado: $DOMAIN_HOME"
    log_ok "Remote Console (WRC app): http://${HOST_NAME}:${ADMIN_PORT}"
}

# ─── INICIAR SERVIDORES ──────────────────────────────────────────────────────

iniciar_servidores() {
    log_step "Fase 4 - Iniciando NodeManager e Admin Server"

    local nm_home="${DOMAIN_HOME}/nodemanager"
    local nm_props="${nm_home}/nodemanager.properties"

    log_info "Configurando NodeManager em ${nm_home}..."
    mkdir -p "$nm_home"
    chown -R oracle:oinstall "$nm_home"

    # Registrar domain no nodemanager.domains para NM reconhecer o domain
    sudo -u oracle bash -c "printf '%s=%s\n' '${DOMAIN_NAME}' '${DOMAIN_HOME}' > ${nm_home}/nodemanager.domains"

    # Pre-criar nodemanager.properties com SecureListener=false e ListenAddress vazio.
    # ListenAddress vazio = escuta em todas as interfaces (o default 'localhost' impede
    # que o Admin Console alcance o NM via hostname).
    sudo -u oracle bash -c "
        printf 'DomainsFile=${nm_home}/nodemanager.domains\n' > ${nm_props}
        printf 'PropertiesVersion=15.1.1\n'          >> ${nm_props}
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
        nohup ${DOMAIN_HOME}/bin/startNodeManager.sh </dev/null > ${nm_home}/nodemanager.out 2>&1 &
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
        sed -i 's/^SecureListener=.*/SecureListener=false/' ${nm_home}/nodemanager.properties
        export JAVA_HOME=/usr/java/latest
        export ORACLE_HOME=${ORACLE_HOME}
        nohup ${DOMAIN_HOME}/bin/startNodeManager.sh </dev/null >> ${nm_home}/nodemanager.out 2>&1 &
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
            log_erro "NodeManager nao respondeu. Verifique: ${nm_home}/nodemanager.out"
        fi
    fi

    # ── Admin Server ──
    log_info "Preparando boot.properties para o Admin Server..."
    local boot_file="${DOMAIN_HOME}/servers/AdminServer/security/boot.properties"
    sudo -u oracle mkdir -p "${DOMAIN_HOME}/servers/AdminServer/security"
    sudo -u oracle mkdir -p "${DOMAIN_HOME}/servers/AdminServer/logs"
    sudo -u oracle mkdir -p "${DOMAIN_HOME}/servers/AdminServer/tmp"

    printf 'username=%s\npassword=%s\n' "${WLS_ADMIN_USER}" "${WLS_ADMIN_PASS}" > "$boot_file"
    chmod 600 "$boot_file"
    chown oracle:oinstall "$boot_file"
    log_ok "boot.properties criado em: $boot_file"
    log_info "  usuario : ${WLS_ADMIN_USER}"
    log_info "  (senha salva no arquivo — será criptografada no primeiro boot)"

    log_info "Iniciando Admin Server como oracle (background)..."
    sudo -u oracle bash -c "
        export JAVA_HOME=/usr/java/latest
        export ORACLE_HOME=${ORACLE_HOME}
        nohup ${DOMAIN_HOME}/bin/startWebLogic.sh </dev/null > ${DOMAIN_HOME}/servers/AdminServer/logs/AdminServer.out 2>&1 &
        disown
        echo \$! > ${DOMAIN_HOME}/servers/AdminServer/tmp/AdminServer.pid
        echo 'Admin Server iniciado com PID '\$!
    "

    log_info "Aguardando Admin Server ficar disponível (pode levar 2-4 minutos)..."
    local tentativas=0
    local max=24
    while [ $tentativas -lt $max ]; do
        if sudo -u oracle bash -c "timeout 3 bash -c 'echo >/dev/tcp/${HOST_NAME}/${ADMIN_PORT}'" 2>/dev/null; then
            log_ok "Admin Server respondendo na porta ${ADMIN_PORT}."
            break
        fi
        tentativas=$((tentativas+1))
        echo -n "."
        sleep 10
    done
    echo ""

    if [ $tentativas -eq $max ]; then
        log_warn "Admin Server nao respondeu em 4 minutos. Verifique o log:"
        log_warn "  tail -f ${DOMAIN_HOME}/servers/AdminServer/logs/AdminServer.out"
        return 1
    fi

    log_ok "NodeManager e Admin Server iniciados com sucesso."

    # ── Managed Server ──
    if [[ -n "${MS_NOME:-}" ]]; then
        log_info "Preparando boot.properties para o Managed Server..."
        local ms_boot="${DOMAIN_HOME}/servers/${MS_NOME}/security/boot.properties"
        sudo -u oracle mkdir -p "${DOMAIN_HOME}/servers/${MS_NOME}/security"
        sudo -u oracle mkdir -p "${DOMAIN_HOME}/servers/${MS_NOME}/logs"
        sudo -u oracle bash -c "printf 'username=%s\npassword=%s\n' '${WLS_ADMIN_USER}' '${WLS_ADMIN_PASS}' > '${ms_boot}'"
        sudo -u oracle chmod 600 "$ms_boot"
        log_ok "boot.properties criado para: ${MS_NOME}"

        log_info "Iniciando Managed Server ${MS_NOME} (porta ${MS_PORT})..."
        local ms_out="${DOMAIN_HOME}/servers/${MS_NOME}/logs/${MS_NOME}.out"
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

    log_ok ""
    log_ok "  NodeManager : tail -f ${DOMAIN_HOME}/nodemanager/nodemanager.out"
    log_ok "  Admin Server: tail -f ${DOMAIN_HOME}/servers/AdminServer/logs/AdminServer.out"
    log_ok "  Remote Console (WRC app): http://${HOST_NAME}:${ADMIN_PORT}"
}

# ─── CONFIGURAR XACML ROLE MAPPER ────────────────────────────────────────────

configurar_xacml() {
    log_step "Fase 5 - Configuração XACMLRoleMapper (Grupo AD na Role Admin)"

    local rsp_dir="${MIDIAS}/response"
    local role_mapper_py="${rsp_dir}/role_mapper.py"
    local wlst="${ORACLE_HOME}/oracle_common/common/bin/wlst.sh"

    if [ ! -f "$wlst" ]; then
        log_erro "WLST não encontrado em: $wlst"
        exit 1
    fi

    # Verificar que Admin Server está respondendo
    if ! sudo -u oracle bash -c "timeout 5 bash -c 'echo >/dev/tcp/${HOST_NAME}/${ADMIN_PORT}'" 2>/dev/null; then
        log_erro "Admin Server nao está respondendo em ${HOST_NAME}:${ADMIN_PORT}."
        log_erro "Inicie o Admin Server antes de configurar o XACML (opcao [5])."
        exit 1
    fi

    log_info "Grupo a ser adicionado na Role Admin: ${GROUP_NAME}"

    # Carregar senha admin se não estiver em memória
    if [ -z "$WLS_ADMIN_PASS" ]; then
        local senha_file="${MIDIAS}/response/wls_admin_pass.txt"
        if [ -f "$senha_file" ]; then
            WLS_ADMIN_PASS=$(grep "WLS_ADMIN_PASS=" "$senha_file" | cut -d= -f2)
            log_info "Senha WebLogic carregada de: $senha_file"
        else
            log_warn "Arquivo de senha nao encontrado. Informe a senha manualmente:"
            read -rsp "  Senha admin WebLogic: " WLS_ADMIN_PASS; echo ""
        fi
    fi

    mkdir -p "$rsp_dir"

    cat > "$role_mapper_py" << PYEOF
# -*- coding: utf-8 -*-
# role_mapper.py - XACMLRoleMapper / WebLogic 15.1.1 / Jython 2.7.x
#
# WLS 15.1.1 exige serverRuntime() para operacoes em security providers.
# O proprio WLS instrui: "use serverRuntime() to switch to the runtime MBean hierarchy".

ADMIN_URL   = 't3://$(hostname -f):${ADMIN_PORT}'
ADMIN_USER  = '${WLS_ADMIN_USER}'
ADMIN_PASS  = '${WLS_ADMIN_PASS}'
DOMAIN_NAME = '${DOMAIN_NAME}'
GROUP_NAME  = '${GROUP_NAME}'

GRUPOS = [
    'Grp("' + GROUP_NAME + '")',
    'Grp("execucaomudancas")',
    'Grp("GG_Acesso_EquipeDBA")',
    'Grp("GG_Acesso_SuporteSistemas_TS")',
    'Grp("Administrators")'
]

print('Conectando em ' + ADMIN_URL + '...')
connect(ADMIN_USER, ADMIN_PASS, ADMIN_URL)

# Obrigatorio em WLS 15.1.1: usar Runtime MBean Server para security providers
serverRuntime()
print('Runtime MBean Server ativo.')

# Navegar ao XACMLRoleMapper no runtime tree
# Paths possiveis dependendo da versao do WLS:
XACML_PATHS = [
    '/SecurityRuntime/myrealm/RoleMappers/XACMLRoleMapper',
    '/SecurityRuntime/RoleMappers/XACMLRoleMapper',
    '/SecurityRuntime/myrealm/XACMLRoleMapper'
]

navegado = False
for xacml_path in XACML_PATHS:
    try:
        cd(xacml_path)
        print('XACMLRoleMapper localizado em: ' + xacml_path)
        navegado = True
        break
    except Exception:
        print('Path nao encontrado: ' + xacml_path)

if not navegado:
    nova_expr_manual = '|'.join(GRUPOS)
    print('')
    print('XACML nao configuravel via WLST nesta versao. Configure manualmente via WRC:')
    print('  Security > Realms > myrealm > Role Mappers > XACMLRoleMapper > Realm Roles > Admin > Edit Role')
    print('  Expressao:')
    print('  ' + nova_expr_manual)
    disconnect()
    raise Exception('XACMLRoleMapper path nao localizado via serverRuntime()')

expr_str = ''
try:
    expr_atual = cmo.getRoleExpression('Admin', None)
    expr_str = str(expr_atual) if expr_atual is not None else ''
    print('Expressao atual: ' + expr_str)
except Exception:
    print('Sem expressao previa (dominio novo). Criando do zero.')

grupos_add = [g for g in GRUPOS if g not in expr_str]
if not grupos_add:
    print('Todos os grupos ja presentes. Nada a fazer.')
    disconnect()
    exit()

nova_expr = (expr_str + '|' if expr_str.strip() else '') + '|'.join(grupos_add)
print('Nova expressao: ' + nova_expr)

cmo.setRoleExpression('Admin', None, nova_expr)
print('XACMLRoleMapper configurado com sucesso!')
print('Grupos adicionados: ' + str(grupos_add))

disconnect()
print('XACML concluido.')
PYEOF

    chmod 600 "$role_mapper_py"
    chown ${ORACLE_USER}:${ORACLE_GROUP} "$role_mapper_py"
    log_info "role_mapper.py gerado em: $role_mapper_py"

    log_info "Executando WLST online para adicionar ${GROUP_NAME} na Role Admin..."
    sudo -u oracle bash -c "
        export JAVA_HOME=/usr/java/latest
        export ORACLE_HOME=${ORACLE_HOME}
        '${wlst}' '${role_mapper_py}'
    " 2>&1 | tee -a "$LOGFILE"
    local exit_code=${PIPESTATUS[0]}

    # Remover o arquivo com a senha após execução
    rm -f "$role_mapper_py"

    if [ $exit_code -ne 0 ]; then
        log_warn "WLST retornou código $exit_code. Verifique o log para detalhes."
        log_warn "Caminho XACMLRoleMapper: Security → Realms → myrealm → Role Mappers → XACMLRoleMapper → Realm Roles → Admin → Edit Role"
    else
        log_ok "Grupo ${GROUP_NAME} configurado na Role Admin com sucesso."
        log_ok "Acesse: Remote Console → Security → Realms → myrealm → Role Mappers → XACMLRoleMapper"
    fi
}

# ─── RESPONSE FILE FINAL ─────────────────────────────────────────────────────

gerar_response_final() {
    log_step "Gerando Response File Final"

    local rsp_dir="${MIDIAS}/response"
    local final="${rsp_dir}/install_summary_$(date +%Y%m%d_%H%M%S).txt"

    mkdir -p "$rsp_dir"

    cat > "$final" << EOF
================================================================================
  RESUMO DE INSTALAÇÃO - WebLogic 15.1.1.0.0 PURO
  Oraex / Getnet
  Gerado em : $(date '+%d/%m/%Y %H:%M:%S')
================================================================================

[HOST]
  Hostname              : ${HOST_NAME}
  IP                    : ${HOST_IP}
  Usuário Oracle        : ${ORACLE_USER} (home: ${ORACLE_USER_HOME})

[INSTALAÇÃO]
  Versao WebLogic       : 15.1.1.0.0 PURO (sem SOA/OSB/ODI)
  ORACLE_HOME           : ${ORACLE_HOME}
  Inventory             : ${INVENTORY}
  oraInst.loc           : ${ORAINST}
  Java utilizado        : ${JAVA_HOME_PATH:-/usr/java/latest} (JDK 17)

[DOMAIN]
  Domain Name           : ${DOMAIN_NAME}
  Domain Home           : ${DOMAIN_HOME}
  Remote Console (WRC)  : http://${HOST_NAME}:${ADMIN_PORT}
  Admin User            : ${WLS_ADMIN_USER}
  Admin Password        : ${WLS_ADMIN_PASS}
  NodeManager Port      : ${NM_PORT}
  Cluster               : ${CLUSTER_NAME}
  Managed Server        : ${MS_NOME:-wls_server1}:${MS_PORT}
  Memoria JVM Injetada  : ${WLS_MEM_MB}MB

[XACML ROLE MAPPER]
  Grupo AD na Role Admin: ${GROUP_NAME}
  Caminho console       : Security > Realms > myrealm > Role Mappers > XACMLRoleMapper > Realm Roles > Admin

[ARQUIVOS GERADOS]
  Log de instalação     : ${LOGFILE}
  domain.py             : ${MIDIAS}/response/domain.py
  Response files        : ${MIDIAS}/response/
  Este resumo           : ${final}

[OBSERVAÇÕES]
  - Para iniciar o Managed Server acesse a Remote Console (WRC):
    Environment -> Servers -> ${MS_NOME:-wls_server1} -> Start
  - Senha do oracle salva APENAS no host (nao registrada aqui por seguranca).
  - PSU aplicado: WLS_SPB_15.1.1.0.260703 (Jul/2026)

================================================================================
EOF

    chmod 644 "$final"
    chown root:root "$final"

    log_ok "Response file final salvo em: $final"
    echo ""
    cat "$final"
}

# ─── MENU PRINCIPAL ──────────────────────────────────────────────────────────

menu_principal() {
    banner
    echo -e "  ${BOLD}O que deseja fazer?${NC}"
    echo ""
    echo "  [1] Instalação completa     (Java → Binários → Patches → Domain → Servidores → XACML online)"
    echo "  [2] Instalar binários       (Java + WLS 15.1.1 + Patches PSU)"
    echo "  [3] Aplicar patches         (OPatch + Bundle SPBAT WLS_SPB_15.1.1.0.260703)"
    echo "  [4] Criar domain            (WLST offline — Basic WebLogic Server Domain)"
    echo "  [5] Iniciar servidores      (NodeManager + Admin Server)"
    echo "  [6] Configurar XACML        (Re-aplicar XACML online (domain pre-existente))"
    echo "  [7] Gerar response file     (Apenas resumo final)"
    echo "  [0] Sair"
    echo ""
    read -rp "  Escolha uma opção: " opcao
    echo ""

    case "$opcao" in
        1)
            coletar_infos
            validar_espaco_disco /u01 20
            validar_espaco_disco /u02 30
            instalar_java
            baixar_instaladores
            instalar_binarios
            aplicar_patches
            criar_domain
            iniciar_servidores
            service qualys-cloud-agent restart 2>/dev/null || true
            gerar_response_final
            ;;
        2)
            coletar_infos
            instalar_java
            baixar_instaladores
            instalar_binarios
            aplicar_patches
            log_ok "Binários e patches instalados. Execute a opção [4] para criar o domain."
            ;;
        3)
            [ -z "$ORACLE_HOME" ] && read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp && ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
            aplicar_patches
            service qualys-cloud-agent restart 2>/dev/null || true
            ;;
        4)
            [ -z "$ORACLE_HOME" ] && read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp && ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
            [ -z "$DOMAIN_HOME" ] && read -rp "  DOMAIN_HOME: " DOMAIN_HOME && DOMAIN_NAME=$(basename "$DOMAIN_HOME")
            [ -z "$MS_NOME" ] && { read -rp "  Nome do Managed Server [wls_server1]: " inp; MS_NOME="${inp:-wls_server1}"; }
            [ -z "$CLUSTER_NAME" ] && { read -rp "  Nome do Cluster [${CLUSTER_NAME_PADRAO}]: " inp; CLUSTER_NAME="${inp:-$CLUSTER_NAME_PADRAO}"; }
            [ -z "$WLS_MEM_MB" ] && { read -rp "  Memória RAM/Heap (MB) [4096]: " inp; WLS_MEM_MB="${inp:-4096}"; }
            if [ -z "$WLS_ADMIN_PASS" ]; then
                local senha_file="${MIDIAS}/response/wls_admin_pass.txt"
                if [ -f "$senha_file" ]; then
                    WLS_ADMIN_PASS=$(grep "WLS_ADMIN_PASS=" "$senha_file" | cut -d= -f2)
                    log_info "Senha WebLogic carregada de: $senha_file"
                    echo -e "  ${BOLD}Senha admin WebLogic: ${WLS_ADMIN_PASS}${NC}"
                else
                    log_warn "Arquivo de senha nao encontrado. Gerando nova senha..."
                    WLS_ADMIN_PASS=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 14 || true)
                    WLS_ADMIN_PASS="${WLS_ADMIN_PASS}#1"
                    mkdir -p "${MIDIAS}/response"
                    echo "WLS_ADMIN_USER=${WLS_ADMIN_USER}" > "$senha_file"
                    echo "WLS_ADMIN_PASS=${WLS_ADMIN_PASS}" >> "$senha_file"
                    echo "HOST=${HOST_NAME}" >> "$senha_file"
                    echo "GERADO_EM=$(date '+%d/%m/%Y %H:%M:%S')" >> "$senha_file"
                    chmod 600 "$senha_file"
                    echo -e "  ${BOLD}Nova senha gerada: ${WLS_ADMIN_PASS}${NC}"
                    echo -e "  ${BOLD}Salva em: ${senha_file}${NC}"
                fi
            fi
            criar_domain
            ;;
        5)
            [ -z "$ORACLE_HOME" ] && read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp && ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
            [ -z "$DOMAIN_HOME" ] && read -rp "  DOMAIN_HOME: " DOMAIN_HOME && DOMAIN_NAME=$(basename "$DOMAIN_HOME")
            [ -z "$MS_NOME" ] && MS_NOME="wls_server1"
            if [ -z "$WLS_ADMIN_PASS" ]; then
                local sf="${MIDIAS}/response/wls_admin_pass.txt"
                [ -f "$sf" ] && WLS_ADMIN_PASS=$(grep "WLS_ADMIN_PASS=" "$sf" | cut -d= -f2)
            fi
            iniciar_servidores
            ;;
        6)
            [ -z "$ORACLE_HOME" ] && read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp && ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
            [ -z "$DOMAIN_HOME" ] && read -rp "  DOMAIN_HOME: " DOMAIN_HOME && DOMAIN_NAME=$(basename "$DOMAIN_HOME")
            configurar_xacml
            ;;
        7)
            [ -z "$ORACLE_HOME" ] && read -rp "  ORACLE_HOME: " ORACLE_HOME
            [ -z "$DOMAIN_HOME" ] && read -rp "  DOMAIN_HOME: " DOMAIN_HOME && DOMAIN_NAME=$(basename "$DOMAIN_HOME")
            gerar_response_final
            ;;
        0) log_info "Saindo."; exit 0 ;;
        *) log_erro "Opção inválida."; menu_principal ;;
    esac

    echo ""
    read -rp "  Deseja executar outra opção? (s/n): " rep
    [[ "$rep" == "s" ]] && menu_principal
}

# ─── INÍCIO ──────────────────────────────────────────────────────────────────

validar_root
preparar_usuario_oracle
mkdir -p "$MIDIAS"
chown -R ${ORACLE_USER}:${ORACLE_GROUP} "$MIDIAS"
chmod -R 777 "$MIDIAS"

menu_principal

