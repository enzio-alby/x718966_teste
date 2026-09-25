#!/bin/bash
# =============================================================================
# INSTALAÇÃO Oracle WebCenter Content 12.2.1.4.0 - COMPOSTO
# Oraex / Getnet - Ambiente QA
#
# Stack: JDK 8 + FMW Infrastructure 12.2.1.4 + WebCenter Content 12.2.1.4
#        (UCM + IBR + IPM + Capture + WCCADF)
#        + OPatch + 3x Bundle Patches + RCU + Domain + NodeManager
#
# Servidores criados:
#   AdminServer (7001), UCM_server1 (16200), IBR_server1 (16250),
#   IPM_server1 (16000), capture_server1 (16400), WCCADF_server1 (16225)
#
# USO: ./INSTALL_WCC_12214.sh
# Deve ser executado como root. Operações Oracle rodam como sudo -u oracle.
# =============================================================================

set -euo pipefail

# ─── CORES E LOG ─────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

LOGDIR="/u02/midias/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/install_wcc_${HOSTNAME}.log"
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

# Instaladores — mesma estrutura do COMPOSTO 12214
REPO_INSTALADORES="${REPO_BASE}/binarios/oraex/linux/instaladores/12214/instaladores.tar.gz"
REPO_WCC_ZIP="${REPO_BASE}/binarios/oraex/linux/instaladores/12214/instaladores/wcc/V983399-01.zip"

# PSU WCC — estrutura dedicada wccontent
REPO_PSU_WCC="${REPO_BASE}/binarios/oraex/linux/cpu/middleware/oracle/wls/12.2.1.4.0/wccontent/latest"

# JDK 8 — vem como RPM direto no repo WCC (sem ZIP wrapper)
JAVA_RPM="jdk-8u501-linux-x64.rpm"
JAVA_HOME_8="/usr/java/jdk1.8.0-x64"

# Identificadores dos artefatos no repo (nomes dos ZIPs 12214)
ZIP_FMW="V983368-01.zip"           # FMW Infrastructure 12.2.1.4 (extraido do tar.gz)
ZIP_WCC="V983399-01.zip"           # WCC 12.2.1.4 (download separado)
JAR_FMW="fmw_12.2.1.4.0_infrastructure.jar"
JAR_WCC="fmw_12.2.1.4.0_wccontent.jar"

# OPatch — versao especifica para WCC
OPATCH_ZIP="p28186730_1394224_Generic.zip"

# Bundle patches WCC — aplicados em ordem
BUNDLE1_ZIP="p39838420_122140_Generic.zip"    # 1o: WC_SPB_12.2.1.4.260805 (SPBAT)
BUNDLE1_DIR="WC_SPB_12.2.1.4.260805"         # pasta raiz dentro do zip
BUNDLE2_ZIP="p39702395_122140_Generic.zip"    # 2o: opatch direto (patch 39702395)
BUNDLE2_ID="39702395"
BUNDLE3_ZIP="p39673201_122140_Linux-x86-64.zip"  # 3o: opatch direto (patch 39673201)
BUNDLE3_ID="39673201"

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
SCHEMA_PREFIX_PADRAO="QA"

# Portas default de cada MS (Oracle WCC 12.2.1.4 standard)
PORT_UCM="16200"
PORT_IBR="16250"
PORT_IPM="16000"
PORT_CAP="16400"
PORT_ADF="16225"

# ─── VARIÁVEIS GLOBAIS ───────────────────────────────────────────────────────

ORACLE_HOME=""
DOMAIN_HOME=""
DOMAIN_NAME=""
JAVA_HOME_PATH=""
WLS_ADMIN_PASS=""
DB_HOST=""
DB_PORT="1521"
DB_PDB=""
DB_SCHEMA_PREFIX=""
DB_SYS_PASS=""
DB_SCHEMA_PASS=""

HOST_NAME=$(hostname)
HOST_IP=$(hostname -I | awk '{print $1}')

# ─── BANNER ──────────────────────────────────────────────────────────────────

banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║   INSTALAÇÃO Oracle WebCenter Content 12.2.1.4 - Oraex/Getnet   ║"
    echo "  ║   FMW Infra + UCM + IBR + IPM + Capture + WCCADF + RCU         ║"
    echo "  ╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  Host    : ${CYAN}${HOST_NAME}${NC}"
    echo -e "  IP      : ${CYAN}${HOST_IP}${NC}"
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

testar_conectividade_banco() {
    log_info "Testando conectividade com o banco ${DB_HOST}:${DB_PORT} ..."
    if timeout 5 bash -c "echo >/dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then
        log_ok "Banco alcançável em ${DB_HOST}:${DB_PORT}"
    else
        log_warn "Banco NÃO alcançável em ${DB_HOST}:${DB_PORT}"
        log_warn "Verifique se o PDB está ativo e o firewall liberado."
        read -rp "  Deseja continuar mesmo assim? (s/n): " cont
        [[ "$cont" != "s" ]] && return 1
    fi
}

# ─── USUÁRIO ORACLE ──────────────────────────────────────────────────────────

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
        useradd -u "$ORACLE_UID" -g "$ORACLE_GROUP" -G "$ORACLE_GROUP" \
                -d "$ORACLE_USER_HOME" -s /bin/bash \
                -c "Oracle Software Owner" "$ORACLE_USER"
        log_ok "Usuário oracle criado (UID: $ORACLE_UID)."
        echo ""
        log_info "Informe a senha do oracle gerada pelo Playbook/CyberArk:"
        read -rsp "  Senha oracle (CyberArk): " ORACLE_OS_PASS; echo ""
        if [[ -z "$ORACLE_OS_PASS" ]]; then log_erro "Senha não pode ser vazia."; exit 1; fi
        echo "${ORACLE_USER}:${ORACLE_OS_PASS}" | chpasswd
        unset ORACLE_OS_PASS
        log_ok "Senha do oracle definida."
    else
        log_ok "Usuário oracle já existe: $(id oracle)"
        echo ""
        read -rp "  Deseja (re)definir a senha do oracle? (s/n): " redef
        if [[ "$redef" == "s" ]]; then
            read -rsp "  Senha oracle (CyberArk): " ORACLE_OS_PASS; echo ""
            echo "${ORACLE_USER}:${ORACLE_OS_PASS}" | chpasswd
            unset ORACLE_OS_PASS
            log_ok "Senha do oracle redefinida."
        fi
    fi

    [ ! -d "$ORACLE_USER_HOME" ] && mkdir -p "$ORACLE_USER_HOME"
    chown oracle:oinstall "$ORACLE_USER_HOME"
    chmod 750 "$ORACLE_USER_HOME"

    for dir in "$ORACLE_BASE" "$ORACLE_BASE/middleware" "$INVENTORY"; do
        mkdir -p "$dir"
        chown -R oracle:oinstall "$dir"
    done

    local profile="${ORACLE_USER_HOME}/.bash_profile"
    if [ ! -f "$profile" ]; then
        cat > "$profile" << EOF
export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_HOME=/u01/oracle/middleware
export MW_HOME=\$ORACLE_HOME
export PATH=\$ORACLE_HOME/bin:\$ORACLE_HOME/OPatch:\$PATH
export JAVA_HOME=/usr/java/latest
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
        chown oracle:oinstall "$profile"
        log_ok ".bash_profile do oracle criado."
    fi

    log_ok "Usuário oracle pronto."
}

criar_orainst() {
    if [ ! -f "$ORAINST" ]; then
        cat > "$ORAINST" << EOF
inventory_loc=${INVENTORY}
inst_group=${ORACLE_GROUP}
EOF
        chown root:${ORACLE_GROUP} "$ORAINST"
        chmod 644 "$ORAINST"
        log_ok "oraInst.loc criado."
    else
        log_ok "oraInst.loc já existe."
    fi
}

# ─── COLETAR INFORMAÇÕES ─────────────────────────────────────────────────────

coletar_infos() {
    log_step "Coleta de Informações do Ambiente"

    # Gerar senha WebLogic antes de qualquer prompt — anote agora para registrar no HAS
    WLS_ADMIN_PASS=$(tr -dc 'A-Za-z0-9!@#$%' < /dev/urandom | head -c 16 || true)
    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║   SENHA WEBLOGIC GERADA — ANOTE AGORA           ║"
    echo "  ║                                                  ║"
    echo "  ║   Usuário : weblogic                            ║"
    echo "  ║   Senha   : ${WLS_ADMIN_PASS}                  ║"
    echo "  ║                                                  ║"
    echo "  ║   Abrir REQ para CyberArk após instalação       ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    read -rp "  Anotou a senha? Pressione Enter para continuar..." _

    echo -e "  Host detectado: ${CYAN}${HOST_NAME}${NC} (${HOST_IP})"
    echo ""

    read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp
    ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"

    read -rp "  DOMAIN_HOME (ex: /u01/qualidade/domains/ucm_domain): " DOMAIN_HOME
    if [[ -z "$DOMAIN_HOME" ]]; then log_erro "DOMAIN_HOME obrigatório."; exit 1; fi
    DOMAIN_NAME=$(basename "$DOMAIN_HOME")

    echo ""
    log_info "--- Banco de Dados (para RCU e JDBC) ---"
    log_warn "Você poderá pular o RCU agora e executá-lo depois pelo menu."
    echo ""

    read -rp "  Hostname/IP do banco Oracle (pmon): " DB_HOST
    if [[ -z "$DB_HOST" ]]; then log_erro "Hostname do banco obrigatório."; exit 1; fi

    read -rp "  Porta do listener [${DB_PORT}]: " inp
    DB_PORT="${inp:-$DB_PORT}"

    read -rp "  Service name do PDB (ex: WCCQASRV): " DB_PDB
    if [[ -z "$DB_PDB" ]]; then log_erro "PDB obrigatório."; exit 1; fi

    read -rp "  Prefixo dos schemas RCU [${SCHEMA_PREFIX_PADRAO}]: " inp
    DB_SCHEMA_PREFIX="${inp:-$SCHEMA_PREFIX_PADRAO}"
    DB_SCHEMA_PREFIX=$(echo "$DB_SCHEMA_PREFIX" | tr '[:lower:]' '[:upper:]')

    echo ""
    log_info "--- Senhas ---"

    read -rsp "  Senha do usuário SYS (DBA): " DB_SYS_PASS; echo ""
    if [[ -z "$DB_SYS_PASS" ]]; then log_erro "Senha SYS obrigatória."; exit 1; fi

    read -rsp "  Senha padrão para os schemas criados: " DB_SCHEMA_PASS; echo ""
    if [[ -z "$DB_SCHEMA_PASS" ]]; then log_erro "Senha dos schemas obrigatória."; exit 1; fi

    # Salvar senha admin para uso em iniciar_servidores
    local rsp_dir="${MIDIAS}/response"
    mkdir -p "$rsp_dir"
    printf 'WLS_ADMIN_PASS=%s\n' "$WLS_ADMIN_PASS" > "${rsp_dir}/wls_admin_pass.txt"
    chmod 600 "${rsp_dir}/wls_admin_pass.txt"
    chown ${ORACLE_USER}:${ORACLE_GROUP} "${rsp_dir}/wls_admin_pass.txt"

    echo ""
    log_ok "Configurações coletadas:"
    log_info "  ORACLE_HOME  : ${ORACLE_HOME}"
    log_info "  DOMAIN_HOME  : ${DOMAIN_HOME} (${DOMAIN_NAME})"
    log_info "  Banco        : ${DB_HOST}:${DB_PORT}/${DB_PDB}"
    log_info "  Prefixo RCU  : ${DB_SCHEMA_PREFIX}"
    echo ""
    read -rp "  Confirma? (s/n): " conf
    if [[ "$conf" != "s" ]]; then log_info "Cancelado."; exit 0; fi
}

# ─── JAVA ────────────────────────────────────────────────────────────────────

instalar_java() {
    log_step "Fase 0 - Instalação / Atualização do Java (JDK 8)"

    echo ""
    echo "  Versões de Java instaladas atualmente:"
    rpm -qa | grep -i jdk || echo "  (nenhuma)"
    echo ""

    if rpm -qa | grep -qi "jdk1.8\|jdk-1.8\|jdk-8"; then
        log_ok "Um JDK 8 já está instalado no sistema."
        rpm -qa | grep -i "jdk1.8\|jdk-1.8\|jdk-8"
        read -rp "  Deseja reinstalar ou trocar a versão? (s/n): " troca_java
        if [[ "$troca_java" != "s" ]]; then
            if [ -d "$JAVA_HOME_8" ]; then
                JAVA_HOME_PATH="$JAVA_HOME_8"
            else
                JAVA_HOME_PATH=$(ls -d /usr/java/jdk1.8* 2>/dev/null | head -1)
            fi
            log_info "Mantendo Java atual: $JAVA_HOME_PATH"
            local jsec="${JAVA_HOME_PATH}/jre/lib/security/java.security"
            [ -f "$jsec" ] && sed -i 's|securerandom.source=file:/dev/random|securerandom.source=file:/dev/./urandom|' "$jsec" 2>/dev/null || true
            return 0
        fi
    fi

    log_info "Baixando JDK 8 para ${MIDIAS}/java ..."
    mkdir -p "${MIDIAS}/java"

    # Para WCC: Java vem como RPM direto no repo (sem ZIP wrapper)
    wget -q --show-progress "${REPO_PSU_WCC}/java/${JAVA_RPM}" \
        -O "${MIDIAS}/java/${JAVA_RPM}"
    checar_erro "Falha no download do JDK."

    read -rp "  Digite a versão do Java a REMOVER (ou deixe em branco para pular): " java_remove
    if [ -n "$java_remove" ]; then
        rpm -qa | grep -q "$java_remove" && rpm -e --nodeps "$java_remove" && \
            log_ok "Java $java_remove removido." || \
            log_warn "Versão '$java_remove' não encontrada. Pulando remoção."
    fi

    log_info "Instalando ${JAVA_RPM}..."
    rpm -i --replacepkgs "${MIDIAS}/java/${JAVA_RPM}" || \
    rpm -U "${MIDIAS}/java/${JAVA_RPM}" || true
    JAVA_HOME_PATH="$JAVA_HOME_8"

    local jsec="${JAVA_HOME_PATH}/jre/lib/security/java.security"
    if [ -f "$jsec" ]; then
        sed -i 's|securerandom.source=file:/dev/random|securerandom.source=file:/dev/./urandom|' "$jsec"
        log_ok "java.security configurado para urandom."
    fi

    update-alternatives --config java 2>/dev/null || true
    rm -f "${MIDIAS}/java/${JAVA_RPM}"
    log_ok "Java instalado: $JAVA_HOME_PATH"
}

# ─── DOWNLOAD DOS INSTALADORES ───────────────────────────────────────────────

baixar_instaladores() {
    log_step "Fase 1a - Download dos Instaladores do Repositório"

    mkdir -p "${MIDIAS}/instaladores"

    # ── FMW Infrastructure — mesma estrutura do COMPOSTO 12214 ──
    if [ -f "${MIDIAS}/instaladores/instaladores/weblogic/${ZIP_FMW}" ]; then
        log_ok "tar.gz de instaladores já extraído — FMW Infrastructure presente."
    else
        log_info "Baixando instaladores.tar.gz (FMW Infrastructure 12.2.1.4)..."
        log_info "Repositório: $REPO_INSTALADORES"
        cd "${MIDIAS}/instaladores"
        wget -q --show-progress "$REPO_INSTALADORES" -O instaladores.tar.gz
        checar_erro "Falha no download do tar.gz de instaladores."

        log_info "Descompactando instaladores.tar.gz..."
        tar -xf instaladores.tar.gz
        checar_erro "Falha ao descompactar instaladores.tar.gz."

        chown -R oracle:oinstall "${MIDIAS}/instaladores"
        chmod -R 750 "${MIDIAS}/instaladores"
        log_ok "Instaladores FMW Infrastructure disponíveis em: ${MIDIAS}/instaladores/instaladores/"
    fi

    # ── WCC — download separado do ZIP ──
    if [ -f "${MIDIAS}/instaladores/wcc/${ZIP_WCC}" ]; then
        log_ok "WCC ZIP já presente — pulando download."
    else
        log_info "Baixando WCC 12.2.1.4 (${ZIP_WCC})..."
        mkdir -p "${MIDIAS}/instaladores/wcc"
        wget -q --show-progress "$REPO_WCC_ZIP" \
            -O "${MIDIAS}/instaladores/wcc/${ZIP_WCC}"
        checar_erro "Falha no download do WCC ZIP."
        chown -R oracle:oinstall "${MIDIAS}/instaladores/wcc"
        log_ok "WCC ZIP baixado: ${MIDIAS}/instaladores/wcc/${ZIP_WCC}"
    fi
}

# ─── RESPONSE FILES ──────────────────────────────────────────────────────────

gerar_response_files() {
    local rsp_dir="${MIDIAS}/response"
    mkdir -p "$rsp_dir"

    cat > "${rsp_dir}/infra.rsp" << EOF
[ENGINE]
Response File Version=1.0.0.0.0
[GENERIC]
ORACLE_HOME=${ORACLE_HOME}
INSTALL_TYPE=Fusion Middleware Infrastructure
DECLINE_SECURITY_UPDATES=true
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
EOF

    # WCC — Complete Install para instalar todos os componentes
    # (UCM + IBR + IPM + Capture + WCCADF + Records)
    cat > "${rsp_dir}/wcc.rsp" << EOF
[ENGINE]
Response File Version=1.0.0.0.0
[GENERIC]
ORACLE_HOME=${ORACLE_HOME}
INSTALL_TYPE=Complete Install
DECLINE_SECURITY_UPDATES=true
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
EOF

    chown -R ${ORACLE_USER}:${ORACLE_GROUP} "$rsp_dir"
    log_ok "Response files gerados em: $rsp_dir"
}

# ─── INSTALAÇÃO DOS BINÁRIOS ─────────────────────────────────────────────────

instalar_binarios() {
    log_step "Fase 1 - Instalação dos Binários (FMW Infrastructure + WCC)"

    local dir_inst="${MIDIAS}/instaladores/instaladores"
    local dir_wcc="${MIDIAS}/instaladores/wcc"
    local rsp_dir="${MIDIAS}/response"
    local java_bin

    java_bin=$(readlink -f /usr/bin/java 2>/dev/null || echo "")
    [ ! -x "$java_bin" ] && java_bin=$(find /usr/java -name "java" -type f 2>/dev/null | head -1)
    if [[ -z "$java_bin" ]]; then log_erro "Java não encontrado. Instale o Java primeiro."; exit 1; fi
    log_info "Usando Java: $java_bin"
    export JAVA_HOME=$(dirname $(dirname "$java_bin"))

    criar_orainst
    gerar_response_files

    # ── FMW Infrastructure ──
    if [ -f "${ORACLE_HOME}/oracle_common/bin/wlst.sh" ]; then
        log_ok "FMW Infrastructure já detectado em ${ORACLE_HOME}. Pulando instalação."
    else
        log_step "Instalando FMW Infrastructure 12.2.1.4"
        log_info "Descompactando ${ZIP_FMW}..."
        cd "${dir_inst}/weblogic"
        sudo -u oracle unzip -q "$ZIP_FMW" 2>/dev/null || true

        log_info "Iniciando instalação silenciosa do FMW Infrastructure..."
        sudo -u oracle "$java_bin" -jar "${dir_inst}/weblogic/${JAR_FMW}" \
            -silent \
            -responseFile "${rsp_dir}/infra.rsp" \
            -invPtrLoc "$ORAINST" \
            -jreLoc "$JAVA_HOME" \
            2>&1 | tee -a "$LOGFILE"
        checar_erro "Falha na instalação do FMW Infrastructure."
        log_ok "FMW Infrastructure instalado com sucesso em ${ORACLE_HOME}."
    fi

    # ── WebCenter Content ──
    if [ -d "${ORACLE_HOME}/wccontent" ]; then
        log_ok "WebCenter Content já detectado em ${ORACLE_HOME}/wccontent. Pulando instalação."
    else
        log_step "Instalando WebCenter Content 12.2.1.4 (Complete Install)"
        log_info "Descompactando ${ZIP_WCC}..."
        cd "$dir_wcc"
        sudo -u oracle unzip -q "$ZIP_WCC" 2>/dev/null || true

        log_info "Iniciando instalação silenciosa do WebCenter Content..."
        sudo -u oracle "$java_bin" -jar "${dir_wcc}/${JAR_WCC}" \
            -silent \
            -responseFile "${rsp_dir}/wcc.rsp" \
            -invPtrLoc "$ORAINST" \
            -jreLoc "$JAVA_HOME" \
            2>&1 | tee -a "$LOGFILE"
        checar_erro "Falha na instalação do WebCenter Content."
        log_ok "WebCenter Content instalado com sucesso em ${ORACLE_HOME}/wccontent."
    fi

    log_ok "Binários verificados em: $ORACLE_HOME"
}

# ─── APLICAÇÃO DE PATCHES (PSU) ──────────────────────────────────────────────

aplicar_patches() {
    log_step "Fase 2 - Atualização OPatch + 3 Bundle Patches WCC"

    local BASE_WCC="${MIDIAS}/binarios/oraex/linux/cpu/middleware/oracle/wls/12.2.1.4.0/wccontent/latest"

    # ── globalEnv.properties — obrigatório ANTES do SPBAT ──
    sudo -u oracle bash -c "echo -e 'JAVA_HOME=/usr/java/latest\nJAVA_HOME_1_8=/usr/java/latest\nJVM_64=' > ${ORACLE_HOME}/oui/.globalEnv.properties"
    log_ok "globalEnv.properties criado em ${ORACLE_HOME}/oui/.globalEnv.properties"

    # ── Baixar OPatch e bundles individualmente ──
    log_info "Baixando OPatch e bundles do repositório WCC..."
    mkdir -p "${BASE_WCC}/opatch" "${BASE_WCC}/bundle"
    chown -R oracle:oinstall "${MIDIAS}/binarios"

    log_info "  OPatch: ${OPATCH_ZIP}"
    sudo -u oracle wget -q --show-progress \
        "${REPO_PSU_WCC}/opatch/${OPATCH_ZIP}" \
        -O "${BASE_WCC}/opatch/${OPATCH_ZIP}"
    checar_erro "Falha no download do OPatch."

    log_info "  Bundle 1: ${BUNDLE1_ZIP}"
    sudo -u oracle wget -q --show-progress \
        "${REPO_PSU_WCC}/bundle/${BUNDLE1_ZIP}" \
        -O "${BASE_WCC}/bundle/${BUNDLE1_ZIP}"
    checar_erro "Falha no download do Bundle 1."

    log_info "  Bundle 2: ${BUNDLE2_ZIP}"
    sudo -u oracle wget -q --show-progress \
        "${REPO_PSU_WCC}/bundle/${BUNDLE2_ZIP}" \
        -O "${BASE_WCC}/bundle/${BUNDLE2_ZIP}"
    checar_erro "Falha no download do Bundle 2."

    log_info "  Bundle 3: ${BUNDLE3_ZIP}"
    sudo -u oracle wget -q --show-progress \
        "${REPO_PSU_WCC}/bundle/${BUNDLE3_ZIP}" \
        -O "${BASE_WCC}/bundle/${BUNDLE3_ZIP}"
    checar_erro "Falha no download do Bundle 3."

    # ── OPatch — p28186730 extrai como OPatch/ direto ──
    log_info "Atualizando OPatch (${OPATCH_ZIP})..."
    cd "${BASE_WCC}/opatch"
    sudo -u oracle unzip -qo "$OPATCH_ZIP" -d opatch_update
    local opatch_jar
    opatch_jar=$(find opatch_update -name "opatch_generic.jar" | head -1)
    if [[ -z "$opatch_jar" ]]; then log_erro "opatch_generic.jar não encontrado após extração."; exit 1; fi
    sudo -u oracle java -jar "$opatch_jar" -silent oracle_home="${ORACLE_HOME}" \
        2>&1 | tee -a "$LOGFILE"
    checar_erro "Falha ao atualizar OPatch."
    log_ok "OPatch atualizado."
    sudo -u oracle "${ORACLE_HOME}/OPatch/opatch" version 2>/dev/null | tee -a "$LOGFILE" || true

    # ── Bundle 1 — WC_SPB_12.2.1.4.260805 via SPBAT (maior, aplicar primeiro) ──
    log_info "Aplicando Bundle 1 — SPBAT WCC (${BUNDLE1_ZIP})..."
    cd "${BASE_WCC}/bundle"
    sudo -u oracle unzip -q "$BUNDLE1_ZIP" 2>/dev/null || true
    cd "${BASE_WCC}/bundle/${BUNDLE1_DIR}/tools/spbat/generic/SPBAT"
    sudo -u oracle ./spbat.sh -phase apply -oracle_home "$ORACLE_HOME" \
        2>&1 | tee -a "$LOGFILE"
    log_ok "Bundle 1 WCC processado: ${BUNDLE1_DIR}"

    # ── Bundle 2 — opatch direto ──
    log_info "Aplicando Bundle 2 — OPatch direto (${BUNDLE2_ZIP} / patch ${BUNDLE2_ID})..."
    cd "${BASE_WCC}/bundle"
    sudo -u oracle unzip -q "$BUNDLE2_ZIP" 2>/dev/null || true
    cd "${BASE_WCC}/bundle/${BUNDLE2_ID}"
    sudo -u oracle "${ORACLE_HOME}/OPatch/opatch" apply -silent \
        2>&1 | tee -a "$LOGFILE"
    log_ok "Bundle 2 processado: patch ${BUNDLE2_ID}"

    # ── Bundle 3 — opatch direto ──
    log_info "Aplicando Bundle 3 — OPatch direto (${BUNDLE3_ZIP} / patch ${BUNDLE3_ID})..."
    cd "${BASE_WCC}/bundle"
    sudo -u oracle unzip -q "$BUNDLE3_ZIP" 2>/dev/null || true
    cd "${BASE_WCC}/bundle/${BUNDLE3_ID}"
    sudo -u oracle "${ORACLE_HOME}/OPatch/opatch" apply -silent \
        2>&1 | tee -a "$LOGFILE"
    log_ok "Bundle 3 processado: patch ${BUNDLE3_ID}"

    # ── globalEnv.properties — reescrever após patches ──
    sudo -u oracle bash -c "echo -e 'JAVA_HOME=/usr/java/latest\nJAVA_HOME_1_8=/usr/java/latest\nJVM_64=' > ${ORACLE_HOME}/oui/.globalEnv.properties"
    log_ok "globalEnv.properties atualizado após patches."

    # ── Patch Storage ──
    log_info "Realizando patch_storage..."
    sudo -u oracle tar -zcf "${ORACLE_HOME}/patch_storage.tar.gz" -C "$ORACLE_HOME" .patch_storage/
    sudo -u oracle rm -rf "${ORACLE_HOME}/.patch_storage/"*
    log_ok "Patch storage compactado e limpo."

    log_info "Patches aplicados no ORACLE_HOME:"
    sudo -u oracle "${ORACLE_HOME}/OPatch/opatch" lspatches 2>/dev/null \
        | tee -a "$LOGFILE" || true

    log_ok "Fase de patches concluída."
}

# ─── CONECTIVIDADE BANCO ─────────────────────────────────────────────────────

testar_conectividade_banco() {
    log_info "Testando conectividade com o banco ${DB_HOST}:${DB_PORT} ..."
    if timeout 5 bash -c "echo >/dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then
        log_ok "Banco alcançável em ${DB_HOST}:${DB_PORT}"
    else
        log_warn "Banco NÃO alcançável em ${DB_HOST}:${DB_PORT}"
        log_warn "Verifique se o PDB está ativo e o firewall liberado."
        read -rp "  Deseja continuar mesmo assim? (s/n): " cont
        if [[ "$cont" != "s" ]]; then return 1; fi
    fi
}

# ─── RCU ─────────────────────────────────────────────────────────────────────

executar_rcu() {
    log_step "Fase 3 - RCU (Repository Creation Utility)"

    if [ ! -f "${ORACLE_HOME}/oracle_common/bin/rcu" ]; then
        log_erro "RCU não encontrado. Verifique se o FMW Infrastructure foi instalado."
        exit 1
    fi

    # Coletar banco se chamado isoladamente
    if [ -z "$DB_HOST" ]; then
        read -rp "  Hostname/IP do banco: " DB_HOST
        read -rp "  Porta [1521]: " inp; DB_PORT="${inp:-1521}"
        read -rp "  Service name (PDB): " DB_PDB
        read -rp "  Prefixo schemas [QA]: " inp; DB_SCHEMA_PREFIX="${inp:-QA}"
        DB_SCHEMA_PREFIX=$(echo "$DB_SCHEMA_PREFIX" | tr '[:lower:]' '[:upper:]')
        read -rsp "  Senha SYS: " DB_SYS_PASS; echo ""
        read -rsp "  Senha schemas: " DB_SCHEMA_PASS; echo ""
    fi

    testar_conectividade_banco

    log_warn "Lembrete: senha dos schemas deve conter apenas letras, números, \$, # ou _ e não pode começar com número."
    log_info "Schemas a criar: STB, MDS, IAU, IAU_APPEND, IAU_VIEWER, OPSS, WLS, CONTENT, CONTENTSEARCH, IPM, CAPTURE"
    log_warn "Se os schemas já existirem no banco, o RCU vai falhar — use prefixo diferente."
    read -rp "  Confirma execução do RCU? (s/n): " conf_rcu
    if [[ "$conf_rcu" != "s" ]]; then log_info "RCU cancelado pelo usuário."; return 0; fi

    local rcu_pass_file="${MIDIAS}/response/.rcu_pass.tmp"
    printf '%s\n%s\n' "$DB_SYS_PASS" "$DB_SCHEMA_PASS" > "$rcu_pass_file"
    chmod 600 "$rcu_pass_file"
    chown ${ORACLE_USER}:${ORACLE_GROUP} "$rcu_pass_file"

    # TMPDIR no ORACLE_HOME — evita problemas com noexec/nosuid em /tmp
    local rcu_tmpdir="/u02/midias/rcu_tmp"
    mkdir -p "$rcu_tmpdir"
    chown "${ORACLE_USER}:${ORACLE_GROUP}" "$rcu_tmpdir"
    chmod 755 "$rcu_tmpdir"

    sudo -u oracle env TMPDIR="$rcu_tmpdir" _JAVA_OPTIONS="-Djava.io.tmpdir=${rcu_tmpdir}" \
        "${ORACLE_HOME}/oracle_common/bin/rcu" \
        -silent \
        -createRepository \
        -databaseType ORACLE \
        -connectString "${DB_HOST}:${DB_PORT}/${DB_PDB}" \
        -dbUser SYS \
        -dbRole SYSDBA \
        -schemaPrefix "${DB_SCHEMA_PREFIX}" \
        -useSamePasswordForAllSchemaUsers true \
        -component STB \
        -component MDS \
        -component IAU \
        -component IAU_APPEND \
        -component IAU_VIEWER \
        -component OPSS \
        -component WLS \
        -component CONTENT \
        -component CONTENTSEARCH \
        -component IPM \
        -component CAPTURE \
        -f < "$rcu_pass_file" \
        2>&1 | tee -a "$LOGFILE"
    local rcu_exit=${PIPESTATUS[0]}

    rm -f "$rcu_pass_file"

    [ $rcu_exit -ne 0 ] && {
        log_erro "RCU falhou com código $rcu_exit. Verifique: /u02/midias/rcu_tmp/RCU*/logs/rcu.log"
        return 1
    }
    log_ok "Schemas criados com prefixo: ${DB_SCHEMA_PREFIX}"
}

# ─── DOMAIN ──────────────────────────────────────────────────────────────────

criar_domain() {
    log_step "Fase 4 - Criação do Domain WebCenter Content"

    # Coletar se chamado isoladamente
    if [ -z "$ORACLE_HOME" ]; then
        read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp
        ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
    fi
    if [ -z "$DOMAIN_HOME" ]; then
        read -rp "  DOMAIN_HOME: " DOMAIN_HOME
        DOMAIN_NAME=$(basename "$DOMAIN_HOME")
    fi
    if [ -z "$WLS_ADMIN_PASS" ]; then
        local sf="${MIDIAS}/response/wls_admin_pass.txt"
        [ -f "$sf" ] && WLS_ADMIN_PASS=$(grep "WLS_ADMIN_PASS=" "$sf" | cut -d= -f2)
        [ -z "$WLS_ADMIN_PASS" ] && { read -rsp "  Senha admin: " WLS_ADMIN_PASS; echo ""; }
    fi
    if [ -z "$DB_SCHEMA_PASS" ]; then
        read -rsp "  Senha dos schemas JDBC: " DB_SCHEMA_PASS; echo ""
    fi
    if [ -z "$DB_HOST" ]; then
        read -rp "  Hostname/IP do banco: " DB_HOST
        if [[ -z "$DB_HOST" ]]; then log_erro "Hostname do banco obrigatório."; exit 1; fi
        read -rp "  Porta do listener [${DB_PORT}]: " inp
        DB_PORT="${inp:-$DB_PORT}"
        read -rp "  Service name do PDB (ex: WCCQASRV): " DB_PDB
        if [[ -z "$DB_PDB" ]]; then log_erro "PDB obrigatório."; exit 1; fi
    fi
    if [ -z "$DB_SCHEMA_PREFIX" ]; then
        read -rp "  Prefixo dos schemas RCU [${SCHEMA_PREFIX_PADRAO}]: " inp
        DB_SCHEMA_PREFIX="${inp:-$SCHEMA_PREFIX_PADRAO}"
        DB_SCHEMA_PREFIX=$(echo "$DB_SCHEMA_PREFIX" | tr '[:lower:]' '[:upper:]')
    fi

    local rsp_dir="${MIDIAS}/response"
    local domain_py="${rsp_dir}/domain_wcc.py"
    local wlst="${ORACLE_HOME}/oracle_common/common/bin/wlst.sh"

    [ ! -f "$wlst" ] && { log_erro "WLST não encontrado: $wlst"; exit 1; }
    mkdir -p "$rsp_dir"

    local java_bin
    java_bin=$(readlink -f /usr/bin/java 2>/dev/null || find /usr/java -name "java" -type f 2>/dev/null | head -1)
    export JAVA_HOME=$(dirname $(dirname "$java_bin"))

    cat > "$domain_py" << 'PYEOF'
# -*- coding: utf-8 -*-
# =============================================================================
# domain_wcc.py - Domain Oracle WebCenter Content 12.2.1.4 COMPLETO
# Servidores: UCM_server1, IBR_server1, IPM_server1, capture_server1, WCCADF_server1
# Abordagem 2 fases:
#   Fase 1 - basic WLS domain (writeDomain/closeTemplate)
#   Fase 2 - addTemplate JRF+WCC + getDatabaseDefaults + updateDomain
# getDatabaseDefaults() SOMENTE funciona em contexto readDomain (dominio ja no disco)
# =============================================================================

ORACLE_HOME  = '@@ORACLE_HOME@@'
DOMAIN_HOME  = '@@DOMAIN_HOME@@'
DOMAIN_NAME  = '@@DOMAIN_NAME@@'
JAVA_HOME    = '@@JAVA_HOME@@'
ADMIN_USER   = '@@ADMIN_USER@@'
ADMIN_PASS   = '@@ADMIN_PASS@@'
ADMIN_PORT   = @@ADMIN_PORT@@
NM_PORT      = @@NM_PORT@@
HOST_NAME    = '@@HOST_NAME@@'
DB_HOST      = '@@DB_HOST@@'
DB_PORT      = '@@DB_PORT@@'
DB_PDB       = '@@DB_PDB@@'
SCHEMA_PFX   = '@@SCHEMA_PFX@@'
SCHEMA_PASS  = '@@SCHEMA_PASS@@'

PORT_UCM = @@PORT_UCM@@
PORT_IBR = @@PORT_IBR@@
PORT_IPM = @@PORT_IPM@@
PORT_CAP = @@PORT_CAP@@
PORT_ADF = @@PORT_ADF@@

jdbc_url = 'jdbc:oracle:thin:@//' + DB_HOST + ':' + DB_PORT + '/' + DB_PDB

# =============================================================================
# FASE 1: Basic WLS domain — escreve estrutura minima no disco
# =============================================================================
print('')
print('=== FASE 1: Basic WLS domain ===')
selectTemplate('Basic WebLogic Server Domain')
loadTemplates()

setOption('DomainName',      DOMAIN_NAME)
setOption('JavaHome',        JAVA_HOME)
setOption('AppDir',          DOMAIN_HOME + '/applications')
setOption('OverwriteDomain', 'true')
setOption('ServerStartMode', 'prod')

cd('/Security/base_domain/User/' + ADMIN_USER)
cmo.setPassword(ADMIN_PASS)
cd('/Servers/AdminServer')
cmo.setListenPort(ADMIN_PORT)
cmo.setListenAddress('')
print('AdminServer configurado: porta ' + str(ADMIN_PORT))

writeDomain(DOMAIN_HOME)
closeTemplate()
print('Fase 1 concluida: basic domain gravado em ' + DOMAIN_HOME)

# =============================================================================
# FASE 2: Estender com JRF + WCC — usa readDomain (dominio ja existe no disco)
# =============================================================================
print('')
print('=== FASE 2: Extender domain com JRF + WCC ===')
readDomain(DOMAIN_HOME)
setOption('AppDir', DOMAIN_HOME + '/applications')

addTemplate(ORACLE_HOME + '/oracle_common/common/templates/wls/oracle.jrf_template.jar')
addTemplate(ORACLE_HOME + '/wccontent/common/templates/wls/oracle.ucm.cs_template.jar')
addTemplate(ORACLE_HOME + '/wccontent/common/templates/wls/oracle.ucm.ibr_template.jar')
addTemplate(ORACLE_HOME + '/wccontent/common/templates/wls/oracle.ipm_template.jar')
addTemplate(ORACLE_HOME + '/wccontent/common/templates/wls/oracle.wcc.adf.rui_template.jar')
print('Templates adicionados ao domain.')

# ── Managed Servers ──
ms_map = [
    ('UCM_server1',     PORT_UCM),
    ('IBR_server1',     PORT_IBR),
    ('IPM_server1',     PORT_IPM),
    ('capture_server1', PORT_CAP),
    ('WCCADF_server1',  PORT_ADF),
]
for ms_nome, ms_port in ms_map:
    try:
        cd('/Servers/' + ms_nome)
        cmo.setListenPort(ms_port)
        cmo.setListenAddress('')
        print('MS configurado: ' + ms_nome + ':' + str(ms_port))
    except Exception, e:
        try:
            cd('/')
            create(ms_nome, 'Server')
            cd('/Servers/' + ms_nome)
            cmo.setListenPort(ms_port)
            cmo.setListenAddress('')
            print('MS criado manualmente: ' + ms_nome + ':' + str(ms_port))
        except Exception, e2:
            print('ERRO MS ' + ms_nome + ': ' + str(e2)[:80])

# ── Machine (UnixMachine para Linux) ──
print('Configurando Machine: ' + HOST_NAME)
cd('/')
try:
    create(HOST_NAME, 'UnixMachine')
except Exception, e:
    print('Machine ja existe: ' + str(e)[:60])
try:
    cd('/Machines/' + HOST_NAME)
    try:
        create(HOST_NAME, 'NodeManager')
    except Exception, enm:
        pass
    cd('/Machines/' + HOST_NAME + '/NodeManager/' + HOST_NAME)
    cmo.setListenAddress(HOST_NAME)
    cmo.setListenPort(NM_PORT)
    cmo.setNMType('Plain')
except Exception, e:
    print('Erro NM machine (ignorado): ' + str(e)[:60])

cd('/')
servidores = ['AdminServer', 'UCM_server1', 'IBR_server1',
              'IPM_server1', 'capture_server1', 'WCCADF_server1']
for srv in servidores:
    try:
        assign('Server', srv, 'Machine', HOST_NAME)
        print('Assigned: ' + srv + ' -> ' + HOST_NAME)
    except Exception, e:
        print('Assign ignorado ' + srv + ': ' + str(e)[:60])

# ── STB datasource: URL + DriverName + senha + user (SCHEMA_PFX + '_STB')
# getDatabaseDefaults() le o STB e configura todos os schemas JRF automaticamente
print('Configurando STB: ' + jdbc_url)
try:
    cd('/JDBCSystemResource/LocalSvcTblDataSource/JdbcResource/LocalSvcTblDataSource/JDBCDriverParams/NO_NAME_0')
    set('DriverName', 'oracle.jdbc.OracleDriver')
    set('URL', jdbc_url)
    set('PasswordEncrypted', SCHEMA_PASS)
    cd('Properties/NO_NAME_0/Property/user')
    set('Value', SCHEMA_PFX + '_STB')
    print('STB datasource configurado.')
except Exception, e:
    print('ERRO STB datasource: ' + str(e)[:120])

# ── getDatabaseDefaults: funciona em contexto readDomain ──
# Configura automaticamente: mds-owsm, opss-data-source, opss-audit-*, WLSSchemaDataSource
print('Executando getDatabaseDefaults (OPSS/MDS bootstrap)...')
cd('/')
getDatabaseDefaults()
print('getDatabaseDefaults concluido.')

# Re-forcar senha em cleartext nos datasources OPSS/MDS
# getDatabaseDefaults pode gravar PasswordEncrypted em formato incompativel com updateDomain offline
print('Re-aplicando senhas OPSS em cleartext...')
ds_opss = ['opss-data-source', 'opss-audit-DBDS', 'opss-audit-viewDS',
           'mds-owsm', 'WLSSchemaDataSource', 'LocalSvcTblDataSource']
for ds in ds_opss:
    try:
        cd('/JDBCSystemResource/' + ds + '/JdbcResource/' + ds + '/JDBCDriverParams/NO_NAME_0')
        set('PasswordEncrypted', SCHEMA_PASS)
        print('  Senha re-aplicada: ' + ds)
    except Exception, e:
        print('  Ignorado: ' + ds + ' | ' + str(e)[:60])
cd('/')

# ── Datasources de produto (nao gerenciados pelo getDatabaseDefaults) ──
print('Configurando datasources de produto...')
ds_produto = [
    ('CSDS',           SCHEMA_PFX + '_WCC'),
    ('IPMDS',          SCHEMA_PFX + '_IPM'),
    ('capture-ds',     SCHEMA_PFX + '_CAPTURE'),
    ('capture-mds-ds', SCHEMA_PFX + '_MDS'),
]
for ds_name, schema in ds_produto:
    try:
        cd('/JDBCSystemResource/' + ds_name + '/JdbcResource/' + ds_name + '/JDBCDriverParams')
        try:
            cd('NO_NAME_0')
        except Exception:
            cd('NO_NAME')
        set('URL', jdbc_url)
        set('PasswordEncrypted', SCHEMA_PASS)
        cd('Properties/NO_NAME_0/Property/user')
        set('Value', schema)
        print('  DS ok: ' + ds_name + ' -> ' + schema)
    except Exception, e:
        print('  DS ignorado: ' + ds_name + ' | ' + str(e)[:80])

# ── Gravar domain ──
print('Gravando domain (updateDomain)...')
updateDomain()
closeDomain()

print('')
print('=============================================================')
print('  Domain WCC criado com sucesso!')
print('  Admin Console  : http://' + HOST_NAME + ':' + str(ADMIN_PORT))
print('  UCM_server1    : http://' + HOST_NAME + ':' + str(PORT_UCM) + '/cs')
print('  IBR_server1    : http://' + HOST_NAME + ':' + str(PORT_IBR))
print('  IPM_server1    : http://' + HOST_NAME + ':' + str(PORT_IPM) + '/imaging')
print('  capture_server1: http://' + HOST_NAME + ':' + str(PORT_CAP))
print('  WCCADF_server1 : http://' + HOST_NAME + ':' + str(PORT_ADF) + '/wcc')
print('=============================================================')
PYEOF

    # Substituir placeholders
    declare -A ph=(
        ["@@ORACLE_HOME@@"]="$ORACLE_HOME"
        ["@@DOMAIN_HOME@@"]="$DOMAIN_HOME"
        ["@@DOMAIN_NAME@@"]="$DOMAIN_NAME"
        ["@@JAVA_HOME@@"]="$JAVA_HOME"
        ["@@ADMIN_USER@@"]="$WLS_ADMIN_USER"
        ["@@ADMIN_PASS@@"]="$WLS_ADMIN_PASS"
        ["@@ADMIN_PORT@@"]="$ADMIN_PORT"
        ["@@NM_PORT@@"]="$NM_PORT"
        ["@@HOST_NAME@@"]="$HOST_NAME"
        ["@@DB_HOST@@"]="$DB_HOST"
        ["@@DB_PORT@@"]="$DB_PORT"
        ["@@DB_PDB@@"]="$DB_PDB"
        ["@@SCHEMA_PFX@@"]="$DB_SCHEMA_PREFIX"
        ["@@SCHEMA_PASS@@"]="$DB_SCHEMA_PASS"
        ["@@PORT_UCM@@"]="$PORT_UCM"
        ["@@PORT_IBR@@"]="$PORT_IBR"
        ["@@PORT_IPM@@"]="$PORT_IPM"
        ["@@PORT_CAP@@"]="$PORT_CAP"
        ["@@PORT_ADF@@"]="$PORT_ADF"
    )
    for k in "${!ph[@]}"; do
        sed -i "s|${k}|${ph[$k]}|g" "$domain_py"
    done

    chmod 600 "$domain_py"
    chown ${ORACLE_USER}:${ORACLE_GROUP} "$domain_py"
    log_info "domain_wcc.py gerado em: $domain_py"

    log_info "Criando diretório do domain e ajustando permissões..."
    mkdir -p "$DOMAIN_HOME"
    chown ${ORACLE_USER}:${ORACLE_GROUP} "$(dirname "$DOMAIN_HOME")"
    chown -R ${ORACLE_USER}:${ORACLE_GROUP} "$DOMAIN_HOME"

    log_info "Executando WLST para criar domain..."
    sudo -u oracle bash -c "
        export JAVA_HOME=${JAVA_HOME}
        export ORACLE_HOME=${ORACLE_HOME}
        export WLST_PROPERTIES='-Djps.policystore.migration=OFF'
        cd '${DOMAIN_HOME}'
        '${wlst}' '${domain_py}'
    " 2>&1 | tee -a "$LOGFILE"
    local wlst_exit=${PIPESTATUS[0]}

    rm -f "$domain_py"

    [ $wlst_exit -ne 0 ] && { log_erro "WLST falhou na criação do domain."; exit 1; }
    log_ok "Domain ${DOMAIN_NAME} criado em: ${DOMAIN_HOME}"
}

# ─── NODEMANAGER + SERVIDORES ─────────────────────────────────────────────────

iniciar_servidores() {
    log_step "Fase 5 - NodeManager + Admin Server + Managed Servers"

    if [ -z "$DOMAIN_HOME" ]; then
        read -rp "  DOMAIN_HOME: " DOMAIN_HOME
        DOMAIN_NAME=$(basename "$DOMAIN_HOME")
    fi
    if [ -z "$WLS_ADMIN_PASS" ]; then
        local sf="${MIDIAS}/response/wls_admin_pass.txt"
        [ -f "$sf" ] && WLS_ADMIN_PASS=$(grep "WLS_ADMIN_PASS=" "$sf" | cut -d= -f2)
        [ -z "$WLS_ADMIN_PASS" ] && { read -rsp "  Senha admin: " WLS_ADMIN_PASS; echo ""; }
    fi
    if [ -z "$ORACLE_HOME" ]; then
        read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp
        ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
    fi

    # boot.properties — AdminServer + todos os MSes
    local bp_servers=(AdminServer UCM_server1 IBR_server1 IPM_server1 capture_server1 WCCADF_server1)
    for srv in "${bp_servers[@]}"; do
        sudo -u oracle bash -c "
            mkdir -p '${DOMAIN_HOME}/servers/${srv}/security'
            printf 'username=${WLS_ADMIN_USER}\npassword=${WLS_ADMIN_PASS}\n' \
                > '${DOMAIN_HOME}/servers/${srv}/security/boot.properties'
            chmod 600 '${DOMAIN_HOME}/servers/${srv}/security/boot.properties'
        "
    done
    log_ok "boot.properties criado para: ${bp_servers[*]}"

    # nodemanager.domains
    sudo -u oracle bash -c "
        mkdir -p '${ORACLE_HOME}/oracle_common/nodemanager'
        printf '${DOMAIN_NAME}=${DOMAIN_HOME}\n' > '${ORACLE_HOME}/oracle_common/nodemanager/nodemanager.domains'
    "

    # nodemanager.properties
    local nm_props="${DOMAIN_HOME}/nodemanager/nodemanager.properties"
    sudo -u oracle bash -c "
        mkdir -p '$(dirname ${nm_props})'
        cat > '${nm_props}' << NMEOF
#NodeManager Properties
NodeManagerHome=${DOMAIN_HOME}/nodemanager
ListenAddress=${HOST_NAME}
ListenPort=${NM_PORT}
NativeVersionEnabled=true
StartScriptEnabled=true
StartScriptName=startWebLogic.sh
StopScriptEnabled=false
QuitEnabled=false
LogCount=5
LogLevel=INFO
LogToStderr=true
SecureListener=false
DomainsFile=${ORACLE_HOME}/oracle_common/nodemanager/nodemanager.domains
DomainsFileEnabled=true
NMEOF
        chmod 600 '${nm_props}'
    "

    local java_bin
    java_bin=$(readlink -f /usr/bin/java 2>/dev/null || find /usr/java -name "java" -type f 2>/dev/null | head -1)
    export JAVA_HOME=$(dirname $(dirname "$java_bin"))

    local nm_log="${DOMAIN_HOME}/nodemanager/nodemanager.log"
    local admin_log="${DOMAIN_HOME}/servers/AdminServer/logs/AdminServer_console.log"

    # Iniciar NodeManager
    log_info "Iniciando NodeManager..."
    sudo -u oracle bash -c "
        mkdir -p '$(dirname ${nm_log})'
        export JAVA_HOME=${JAVA_HOME}
        export ORACLE_HOME=${ORACLE_HOME}
        nohup '${DOMAIN_HOME}/bin/startNodeManager.sh' \
            > '${nm_log}' 2>&1 &
        disown
    "
    sleep 20

    # Fix SecureListener (NM pode regenerar com true)
    local nm_pid
    nm_pid=$(pgrep -f "NodeManager" | head -1 || true)
    if [ -n "$nm_pid" ]; then
        kill "$nm_pid" 2>/dev/null || true
        sleep 3
        sed -i 's/^SecureListener=true/SecureListener=false/' "$nm_props" 2>/dev/null || true
        sudo -u oracle bash -c "
            export JAVA_HOME=${JAVA_HOME}
            export ORACLE_HOME=${ORACLE_HOME}
            nohup '${DOMAIN_HOME}/bin/startNodeManager.sh' \
                > '${nm_log}' 2>&1 &
            disown
        "
        sleep 15
        log_ok "NodeManager reiniciado com SecureListener=false."
    fi

    # Iniciar Admin Server
    log_info "Iniciando Admin Server..."
    sudo -u oracle bash -c "
        mkdir -p '$(dirname ${admin_log})'
        export JAVA_HOME=${JAVA_HOME}
        export ORACLE_HOME=${ORACLE_HOME}
        nohup '${DOMAIN_HOME}/bin/startWebLogic.sh' \
            > '${admin_log}' 2>&1 &
        disown
    "
    log_info "Aguardando Admin Server (60s)..."
    sleep 60

    if sudo -u oracle bash -c "timeout 5 bash -c 'echo >/dev/tcp/${HOST_NAME}/${ADMIN_PORT}'" 2>/dev/null; then
        log_ok "Admin Server RUNNING em ${HOST_NAME}:${ADMIN_PORT}"
    else
        log_warn "Admin Server não respondeu ainda. Acompanhe: tail -f '${admin_log}'"
    fi

    # ── Iniciar Managed Servers ──
    echo ""
    log_info "Managed Servers disponíveis para iniciar:"
    echo "  [1] UCM_server1     (porta ${PORT_UCM})"
    echo "  [2] IBR_server1     (porta ${PORT_IBR})"
    echo "  [3] IPM_server1     (porta ${PORT_IPM})"
    echo "  [4] capture_server1 (porta ${PORT_CAP})"
    echo "  [5] WCCADF_server1  (porta ${PORT_ADF})"
    echo "  [a] Todos"
    echo "  [n] Nenhum (iniciar manualmente depois)"
    echo ""
    read -rp "  Quais servidores iniciar agora? [a]: " choice
    choice="${choice:-a}"

    iniciar_ms() {
        local nome="$1"
        local ms_log="${DOMAIN_HOME}/servers/${nome}/logs/${nome}_console.log"
        log_info "Iniciando ${nome}..."
        sudo -u oracle bash -c "
            mkdir -p '$(dirname ${ms_log})'
            export JAVA_HOME=${JAVA_HOME}
            export ORACLE_HOME=${ORACLE_HOME}
            nohup '${DOMAIN_HOME}/bin/startManagedWebLogic.sh' \
                '${nome}' \
                't3://${HOST_NAME}:${ADMIN_PORT}' \
                > '${ms_log}' 2>&1 &
            disown
        "
        log_ok "${nome} iniciado. Log: ${ms_log}"
    }

    case "$choice" in
        1) iniciar_ms "UCM_server1" ;;
        2) iniciar_ms "IBR_server1" ;;
        3) iniciar_ms "IPM_server1" ;;
        4) iniciar_ms "capture_server1" ;;
        5) iniciar_ms "WCCADF_server1" ;;
        a|A)
            iniciar_ms "UCM_server1"
            iniciar_ms "IBR_server1"
            iniciar_ms "IPM_server1"
            iniciar_ms "capture_server1"
            iniciar_ms "WCCADF_server1"
            ;;
        n|N) log_info "Managed Servers não iniciados. Inicie manualmente via startManagedWebLogic.sh" ;;
        *)   log_warn "Opção inválida. Nenhum MS iniciado." ;;
    esac

    echo ""
    log_ok "=== URLs de acesso (quando servidores estiverem RUNNING) ==="
    log_info "  Admin Console  : http://${HOST_NAME}:${ADMIN_PORT}/console"
    log_info "  UCM (Content)  : http://${HOST_NAME}:${PORT_UCM}/cs"
    log_info "  IBR            : http://${HOST_NAME}:${PORT_IBR}"
    log_info "  IPM (Imaging)  : http://${HOST_NAME}:${PORT_IPM}/imaging"
    log_info "  Capture        : http://${HOST_NAME}:${PORT_CAP}"
    log_info "  WCCADF         : http://${HOST_NAME}:${PORT_ADF}/wcc"
}

# ─── RESPONSE FILE FINAL ─────────────────────────────────────────────────────

gerar_response_final() {
    log_step "Gerando Response File Final"

    local rsp_dir="${MIDIAS}/response"
    local final="${rsp_dir}/install_wcc_${HOST_NAME}_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$rsp_dir"

    cat > "$final" << EOF
================================================================================
  RESUMO DE INSTALAÇÃO - Oracle WebCenter Content 12.2.1.4.0 COMPLETO
  Oraex / Getnet
  Gerado em : $(date '+%d/%m/%Y %H:%M:%S')
================================================================================

[HOST]
  Hostname              : ${HOST_NAME}
  IP                    : ${HOST_IP}

[BINÁRIOS INSTALADOS]
  FMW Infrastructure    : 12.2.1.4.0 (Fusion Middleware Infrastructure)
  WebCenter Content     : 12.2.1.4.0 (Complete Install)
  ORACLE_HOME           : ${ORACLE_HOME}
  Inventory             : ${INVENTORY}
  Java                  : ${JAVA_HOME_8} (${JAVA_RPM})

[PATCHES APLICADOS - EM ORDEM]
  OPatch                : ${OPATCH_ZIP}
  Bundle 1 (SPBAT)      : ${BUNDLE1_ZIP} -> ${BUNDLE1_DIR}
  Bundle 2 (OPatch)     : ${BUNDLE2_ZIP} -> patch ${BUNDLE2_ID}
  Bundle 3 (OPatch)     : ${BUNDLE3_ZIP} -> patch ${BUNDLE3_ID}

[DOMAIN]
  Domain Name           : ${DOMAIN_NAME}
  Domain Home           : ${DOMAIN_HOME}
  Admin User            : ${WLS_ADMIN_USER}
  Admin Password        : ${WLS_ADMIN_PASS}   ← ABRIR REQ CYBERARK
  Admin Port            : ${ADMIN_PORT}
  NM Port               : ${NM_PORT}

[MANAGED SERVERS]
  UCM_server1           : ${HOST_NAME}:${PORT_UCM}   -> /cs
  IBR_server1           : ${HOST_NAME}:${PORT_IBR}
  IPM_server1           : ${HOST_NAME}:${PORT_IPM}   -> /imaging
  capture_server1       : ${HOST_NAME}:${PORT_CAP}
  WCCADF_server1        : ${HOST_NAME}:${PORT_ADF}   -> /wcc

[BANCO DE DADOS]
  Host:Port/PDB         : ${DB_HOST}:${DB_PORT}/${DB_PDB}
  Prefixo Schemas       : ${DB_SCHEMA_PREFIX}
  Schemas               : _STB, _MDS, _OPSS, _IAU*, _WCC, _IPM, _CAPTURE

[LOGS]
  Install               : ${LOGFILE}
  NodeManager           : /u02/midias/logs/nm_wcc.log
  Admin Server          : /u02/midias/logs/admin_wcc.log
  UCM_server1           : /u02/midias/logs/UCM_server1.log
  IBR_server1           : /u02/midias/logs/IBR_server1.log
  IPM_server1           : /u02/midias/logs/IPM_server1.log
  capture_server1       : /u02/midias/logs/capture_server1.log
  WCCADF_server1        : /u02/midias/logs/WCCADF_server1.log
================================================================================
EOF

    log_ok "Response file gerado: $final"
    cat "$final"
}

# ─── MENU PRINCIPAL ──────────────────────────────────────────────────────────

menu_principal() {
    banner
    echo -e "  ${BOLD}O que deseja fazer?${NC}"
    echo ""
    echo "  [1] Instalação completa"
    echo "       Java -> FMW Infra -> WCC -> OPatch + 3 Bundles -> RCU -> Domain -> Servidores"
    echo ""
    echo "  [2] Instalar Java (JDK 8)"
    echo "  [3] Download e instalação dos binários (FMW Infra + WCC)"
    echo "  [4] Aplicar patches (OPatch + Bundle 1+2+3)"
    echo "  [5] Executar RCU (criar schemas no banco)"
    echo "  [6] Criar domain WebCenter Content"
    echo "  [7] Iniciar servidores (NM + Admin + Managed)"
    echo "  [8] Gerar response file final"
    echo "  [0] Sair"
    echo ""
    read -rp "  Escolha uma opção: " opcao
    echo ""

    case "$opcao" in
        1)
            preparar_usuario_oracle
            coletar_infos
            instalar_java
            baixar_instaladores
            instalar_binarios
            aplicar_patches
            echo ""
            log_warn "O banco (pmon) e PDB precisam estar prontos para continuar."
            read -rp "  O banco já está provisionado e acessível? (s/n): " banco_pronto
            if [[ "$banco_pronto" == "s" ]]; then
                executar_rcu
                criar_domain
                iniciar_servidores
                gerar_response_final
            else
                log_warn "RCU e Domain pulados. Execute as opções [5] e [6] quando o banco estiver pronto."
            fi
            ;;
        2) instalar_java ;;
        3)
            read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp; ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
            preparar_usuario_oracle
            baixar_instaladores
            instalar_binarios
            ;;
        4)
            read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp; ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
            aplicar_patches
            ;;
        5)
            read -rp "  ORACLE_HOME [${ORACLE_HOME_PADRAO}]: " inp; ORACLE_HOME="${inp:-$ORACLE_HOME_PADRAO}"
            executar_rcu
            ;;
        6) criar_domain ;;
        7) iniciar_servidores ;;
        8) gerar_response_final ;;
        0) log_info "Saindo."; exit 0 ;;
        *) log_erro "Opção inválida."; menu_principal ;;
    esac
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────

validar_root
while true; do
    menu_principal
    echo ""
    read -rp "  Voltar ao menu? (s/n): " voltar
    [[ "$voltar" != "s" ]] && break
done
log_info "Encerrando."
