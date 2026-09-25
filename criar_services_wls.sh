#!/bin/bash
# =============================================================================
# criar_services_wls.sh - Criação de services systemd platops para WLS
# Oraex / Getnet
#
# Suporta: 12c, 14c, SOA, OSB, ODI, WCC — qualquer domain existente
#
# O que faz:
#   1. Lê os servidores reais do config.xml do domain
#   2. Para todos os processos em execução
#   3. Gera wrappers .sh em $DOMAIN_HOME/services/
#   4. Gera units .service em /etc/systemd/system/
#   5. Registra, habilita e sobe tudo como service (NM → Admin → MSes)
#
# Services gerados:
#   platops-weblogic-nodemanager-<domain>         (NodeManager)
#   platops-weblogic-admin-<domain>               (AdminServer)
#   platops-weblogic-managed-server-<ms_name>     (cada Managed Server)
#
# USO: ./criar_services_wls.sh
# Deve ser executado como root.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_erro()  { echo -e "${RED}[ERRO]${NC}  $*"; }
log_step()  { echo -e "\n${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"; \
              echo -e "${BOLD}${BLUE}  $*${NC}"; \
              echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}\n"; }

ORACLE_USER="oracle"
ORACLE_GROUP="oinstall"
SYSTEMD_DIR="/etc/systemd/system"

# ─── VALIDAÇÃO ROOT ───────────────────────────────────────────────────────────

if [ "$(id -u)" -ne 0 ]; then
    log_erro "Este script deve ser executado como root."
    exit 1
fi

# ─── COLETA DE INFORMAÇÕES ────────────────────────────────────────────────────

log_step "Criação de Services systemd WLS — Oraex/Getnet"

read -rp "  DOMAIN_HOME (ex: /u01/qualidade/domains/ucm_domain): " DOMAIN_HOME
[[ -z "$DOMAIN_HOME" ]]   && { log_erro "DOMAIN_HOME obrigatório."; exit 1; }
[[ ! -d "$DOMAIN_HOME" ]] && { log_erro "DOMAIN_HOME não encontrado: $DOMAIN_HOME"; exit 1; }

CONFIG_XML="${DOMAIN_HOME}/config/config.xml"
[[ ! -f "$CONFIG_XML" ]] && { log_erro "config.xml não encontrado: $CONFIG_XML"; exit 1; }

DOMAIN_NAME=$(basename "$DOMAIN_HOME")
SERVICES_DIR="${DOMAIN_HOME}/services"

log_ok "Domain     : $DOMAIN_NAME"
log_ok "config.xml : $CONFIG_XML"

# ─── LER SERVIDORES DO CONFIG.XML ─────────────────────────────────────────────

log_step "Lendo servidores do config.xml"

PYTHON_BIN=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")
[[ -z "$PYTHON_BIN" ]] && { log_erro "Python não encontrado no host."; exit 1; }

# Nome do AdminServer
ADMIN_NAME=$("$PYTHON_BIN" - "$CONFIG_XML" << 'PYEOF'
import sys, xml.etree.ElementTree as ET
tree = ET.parse(sys.argv[1])
root = tree.getroot()
ns = ('{' + root.tag.split('}')[0].lstrip('{') + '}') if '}' in root.tag else ''
el = root.find(ns + 'admin-server-name')
print(el.text if el is not None else 'AdminServer')
PYEOF
)

# Todos os servidores: nome:porta
mapfile -t ALL_SERVERS < <("$PYTHON_BIN" - "$CONFIG_XML" << 'PYEOF'
import sys, xml.etree.ElementTree as ET
tree = ET.parse(sys.argv[1])
root = tree.getroot()
ns = ('{' + root.tag.split('}')[0].lstrip('{') + '}') if '}' in root.tag else ''
for srv in root.findall(ns + 'server'):
    name_el = srv.find(ns + 'name')
    port_el = srv.find(ns + 'listen-port')
    if name_el is not None:
        port = port_el.text if port_el is not None else '7001'
        print(name_el.text + ':' + port)
PYEOF
)

# Separar AdminServer dos MSes
ADMIN_PORT="7001"
declare -a MS_NAMES=()
declare -a MS_PORTS=()

for entry in "${ALL_SERVERS[@]}"; do
    srv_name="${entry%%:*}"
    srv_port="${entry##*:}"
    if [[ "$srv_name" == "$ADMIN_NAME" ]]; then
        ADMIN_PORT="$srv_port"
    else
        MS_NAMES+=("$srv_name")
        MS_PORTS+=("$srv_port")
    fi
done

log_ok "AdminServer : ${ADMIN_NAME} (porta ${ADMIN_PORT})"
log_info "Managed Servers encontrados: ${#MS_NAMES[@]}"
for i in "${!MS_NAMES[@]}"; do
    log_info "  ${MS_NAMES[$i]} : porta ${MS_PORTS[$i]}"
done

echo ""
log_warn "Atenção: todos os processos WLS serão parados e reiniciados como service."
read -rp "  Confirma? (s/n): " conf
[[ "$conf" != "s" ]] && { log_info "Cancelado."; exit 0; }

# ─── PARAR PROCESSOS EM EXECUÇÃO ──────────────────────────────────────────────

log_step "Parando processos em execução"

for ms_name in "${MS_NAMES[@]}"; do
    log_info "Parando ${ms_name}..."
    sudo -u "$ORACLE_USER" bash -c \
        "'${DOMAIN_HOME}/bin/stopManagedWebLogic.sh' '${ms_name}' 2>/dev/null || true" || true
done

log_info "Parando AdminServer (${ADMIN_NAME})..."
sudo -u "$ORACLE_USER" bash -c \
    "'${DOMAIN_HOME}/bin/stopWebLogic.sh' 2>/dev/null || true" || true

log_info "Parando NodeManager..."
sudo -u "$ORACLE_USER" bash -c \
    "'${DOMAIN_HOME}/bin/stopNodeManager.sh' 2>/dev/null || true" || true

sleep 5
log_ok "Processos parados."

# ─── BOOT.PROPERTIES ──────────────────────────────────────────────────────────
# Necessário antes de subir via service — sem esse arquivo WLS pede credenciais
# no stdin, que não existe em serviço systemd, e o servidor cai imediatamente.
# Cria nos dois caminhos: security/ (startManagedWebLogic.sh) e
# data/nodemanager/ (BootIdentityFile do wrapper de service).

log_step "Criando boot.properties para todos os servidores"

WLS_ADMIN_USER=""
WLS_ADMIN_PASS=""
for f in "/u02/midias/response/wls_admin_pass.txt" \
         "/u01/midias/response/wls_admin_pass.txt" \
         "${DOMAIN_HOME}/../../response/wls_admin_pass.txt"; do
    if [ -f "$f" ]; then
        WLS_ADMIN_USER=$(grep "WLS_ADMIN_USER=" "$f" 2>/dev/null | cut -d= -f2)
        WLS_ADMIN_PASS=$(grep "WLS_ADMIN_PASS=" "$f" 2>/dev/null | cut -d= -f2)
        break
    fi
done
if [ -z "$WLS_ADMIN_USER" ]; then read -rp "  WLS admin user [weblogic]: " WLS_ADMIN_USER; fi
WLS_ADMIN_USER="${WLS_ADMIN_USER:-weblogic}"
if [ -z "$WLS_ADMIN_PASS" ]; then read -rsp "  WLS admin password: " WLS_ADMIN_PASS; echo ""; fi
if [[ -z "$WLS_ADMIN_PASS" ]]; then log_erro "Senha do WLS admin obrigatória."; exit 1; fi

criar_boot_props() {
    local srv="$1"
    sudo -u "$ORACLE_USER" bash -c "
        mkdir -p '${DOMAIN_HOME}/servers/${srv}/security'
        printf 'username=${WLS_ADMIN_USER}\npassword=${WLS_ADMIN_PASS}\n' \
            > '${DOMAIN_HOME}/servers/${srv}/security/boot.properties'
        chmod 600 '${DOMAIN_HOME}/servers/${srv}/security/boot.properties'
        mkdir -p '${DOMAIN_HOME}/servers/${srv}/data/nodemanager'
        printf 'username=${WLS_ADMIN_USER}\npassword=${WLS_ADMIN_PASS}\n' \
            > '${DOMAIN_HOME}/servers/${srv}/data/nodemanager/boot.properties'
        chmod 600 '${DOMAIN_HOME}/servers/${srv}/data/nodemanager/boot.properties'
    "
    log_ok "boot.properties: ${srv}"
}

criar_boot_props "$ADMIN_NAME"
for ms_name in "${MS_NAMES[@]}"; do
    criar_boot_props "$ms_name"
done

# ─── CRIAR DIRETÓRIO DE SERVICES ──────────────────────────────────────────────

mkdir -p "$SERVICES_DIR"
chown "${ORACLE_USER}:${ORACLE_GROUP}" "$SERVICES_DIR"

# ─── GERAR WRAPPER — NODEMANAGER ──────────────────────────────────────────────

log_step "Gerando service — NodeManager"

NM_SH="${SERVICES_DIR}/platops-weblogic-nodemanager-${DOMAIN_NAME}.sh"
NM_SVC="platops-weblogic-nodemanager-${DOMAIN_NAME}.service"
NM_LOG="${SERVICES_DIR}/nodemanagerservice.log"

cat > "$NM_SH" << SHEOF
#!/bin/bash

SERVICE_COMMAND=\$1
SERVICE_NAME=weblogic-nodemanager

echo \$SERVICE_COMMAND

trap platops_run_stop SIGTERM
trap platops_run_stop SIGINT

platops_run_boot() {
    echo "\$SERVICE_NAME está em Service::ExecStartPre  >> \$(date)"
    if [[ \$(platops_run_status | grep -v grep | grep "running" | wc -l) -eq 1 ]]; then
        echo "\$SERVICE_NAME está executando manualmente... >> \$(date)"
        sleep 10
    else
        echo "\$SERVICE_NAME executando limpeza do cache nodemanager >> \$(date)"
        rm -rf ${DOMAIN_HOME}/nodemanager/nodemanager.*lck*
        sleep 4
    fi
}

platops_run_start() {
    echo "\$SERVICE_NAME está em Service::ExecStart >> \$(date)"
    if [[ \$(platops_run_status | grep -v grep | grep "notok" | wc -l) -eq 1 ]]; then
        echo "\$SERVICE_NAME não esta rodando... então deve iniciar... >> \$(date)"
        nohup ${DOMAIN_HOME}/bin/startNodeManager.sh &
        sleep 10
    fi
    while true; do
        echo "\$SERVICE_NAME está em Service::ExecStart::platops_run_statusx >> \$(date)"
        if [[ \$(platops_run_status | grep -v grep | grep "notok" | wc -l) -eq 1 ]]; then
            exit 1
        fi
        tail -n 4 ${DOMAIN_HOME}/nodemanager/nodemanager.log
        sleep 10
    done
}

platops_run_status() {
    content=\$(netstat -vantup | grep LIST | grep 5556)
    if [ \$(netstat -vantup | grep LIST | grep 5556 | wc -l) -eq 1 ]; then
        echo "\$SERVICE_NAME está em process::status >> \$(date)"
        echo "\$SERVICE_NAME está em process::status::running >> \$(date)"
        echo \$content
    else
        echo "notok"
    fi
}

platops_run_stop() {
    echo "\$SERVICE_NAME está em process::stop >> \$(date)"
    nohup ${DOMAIN_HOME}/bin/stopNodeManager.sh &
    sleep 2
}

platops_run_restart() {
    echo "\$SERVICE_NAME está em process::restart >> \$(date)"
    platops_run_stop
    exit 1
}

case "\$SERVICE_COMMAND" in
    boot)    platops_run_boot ;;
    start)   platops_run_start ;;
    status)  platops_run_status ;;
    stop)    platops_run_stop ;;
    restart) platops_run_restart ;;
    *)       echo "Uso: \$0 {boot|start|status|stop|restart}"; exit 1 ;;
esac
SHEOF

cat > "${SYSTEMD_DIR}/${NM_SVC}" << SVCEOF
[Unit]
Description=platops weblogic - nodemanager - ${DOMAIN_NAME}
After=network.target
StartLimitInterval=240
StartLimitBurst=2

[Service]
Type=simple
User=${ORACLE_USER}
Group=${ORACLE_GROUP}
ExecStartPre=${NM_SH} boot
ExecStart=${NM_SH} start
Restart=always
RestartSec=5
StandardOutput=append:${NM_LOG}

[Install]
WantedBy=multi-user.target
SVCEOF

log_ok "NodeManager: $NM_SH"

# ─── GERAR WRAPPER — ADMINSERVER ──────────────────────────────────────────────

log_step "Gerando service — AdminServer (${ADMIN_NAME})"

ADMIN_SH="${SERVICES_DIR}/platops-weblogic-admin-${DOMAIN_NAME}.sh"
ADMIN_SVC="platops-weblogic-admin-${DOMAIN_NAME}.service"
ADMIN_LOG="${SERVICES_DIR}/AdminServerservice.log"

cat > "$ADMIN_SH" << SHEOF
#!/bin/bash

SERVICE_COMMAND=\$1
SERVICE_NAME=weblogic-admin

echo \$SERVICE_COMMAND

trap platops_run_stop SIGTERM
trap platops_run_stop SIGINT

platops_run_boot() {
    echo "\$SERVICE_NAME está em Service::ExecStartPre  >> \$(date)"
    if [[ \$(platops_run_status | grep -v grep | grep "running" | wc -l) -eq 1 ]]; then
        echo "\$SERVICE_NAME está em rodando manual... >> \$(date)"
        sleep 10
    else
        echo "\$SERVICE_NAME add passos para remover cache >> \$(date)"
        rm -rf ${DOMAIN_HOME}/servers/Admin*/cache/*
        rm -rf ${DOMAIN_HOME}/servers/Admin*/tmp/*
        sleep 5
    fi
}

platops_run_start() {
    echo "\$SERVICE_NAME está em Service::ExecStart >> \$(date)"
    if [[ \$(platops_run_status | grep -v grep | grep "notok" | wc -l) -eq 1 ]]; then
        echo "\$SERVICE_NAME não esta rodando... então deve iniciar... >> \$(date)"
        nohup ${DOMAIN_HOME}/bin/startWebLogic.sh
        sleep 20
    fi
    while true; do
        echo "\$SERVICE_NAME está em Service::ExecStart::platops_run_statusx >> \$(date)"
        if [[ \$(platops_run_status | grep -v grep | grep "notok" | wc -l) -eq 1 ]]; then
            exit 1
        fi
        tail -n 4 ${DOMAIN_HOME}/servers/${ADMIN_NAME}/logs/${DOMAIN_NAME}.log
        sleep 10
    done
}

platops_run_status() {
    content=\$(netstat -vantup | grep LIST | grep ${ADMIN_PORT})
    if [ \$(netstat -vantup | grep LIST | grep ${ADMIN_PORT} | wc -l) -eq 1 ]; then
        echo "\$SERVICE_NAME está em process::status >> \$(date)"
        echo "\$SERVICE_NAME está em process::status::running >> \$(date)"
        echo \$content
    else
        echo "notok"
    fi
}

platops_run_stop() {
    echo "\$SERVICE_NAME está em process::stop >> \$(date)"
    sleep 2
    nohup ${DOMAIN_HOME}/bin/stopWebLogic.sh
}

platops_run_restart() {
    echo "\$SERVICE_NAME está em process::restart >> \$(date)"
    sleep 10
    platops_run_stop
    exit 1
}

case "\$SERVICE_COMMAND" in
    boot)    platops_run_boot ;;
    start)   platops_run_start ;;
    status)  platops_run_status ;;
    stop)    platops_run_stop ;;
    restart) platops_run_restart ;;
    *)       echo "Uso: \$0 {boot|start|status|stop|restart}"; exit 1 ;;
esac
SHEOF

cat > "${SYSTEMD_DIR}/${ADMIN_SVC}" << SVCEOF
[Unit]
Description=platops-weblogic-admin-${DOMAIN_NAME}
After=network.target
StartLimitInterval=240
StartLimitBurst=2

[Service]
Type=simple
User=${ORACLE_USER}
Group=${ORACLE_GROUP}
ExecStartPre=${ADMIN_SH} boot
ExecStart=${ADMIN_SH} start
Restart=always
RestartSec=5
StandardOutput=append:${ADMIN_LOG}

[Install]
WantedBy=multi-user.target
SVCEOF

log_ok "AdminServer: $ADMIN_SH"

# ─── GERAR WRAPPERS — MANAGED SERVERS ────────────────────────────────────────

log_step "Gerando services — Managed Servers"

for i in "${!MS_NAMES[@]}"; do
    ms_name="${MS_NAMES[$i]}"
    ms_port="${MS_PORTS[$i]}"

    MS_SH="${SERVICES_DIR}/platops-weblogic-${ms_name}.sh"
    MS_SVC="platops-weblogic-managed-server-${ms_name}.service"
    MS_LOG="${DOMAIN_HOME}/servers/${ms_name}/logs/${ms_name}.out"

    cat > "$MS_SH" << SHEOF
#!/bin/bash

SERVICE_COMMAND=\$1
SERVICE_NAME=weblogic-managed-server-${ms_name}

echo \$SERVICE_COMMAND

trap platops_run_stop SIGTERM
trap platops_run_stop SIGINT

platops_run_boot() {
    echo "\$SERVICE_NAME está em Service::ExecStartPre  >> \$(date)"
    if [[ \$(platops_run_status | grep -v grep | grep "running" | wc -l) -eq 1 ]]; then
        echo "\$SERVICE_NAME está em rodando manual... >> \$(date)"
        sleep 10
    else
        echo "\$SERVICE_NAME add passos para remover cache >> \$(date)"
        rm -rf ${DOMAIN_HOME}/servers/${ms_name}/cache/*
        rm -rf ${DOMAIN_HOME}/servers/${ms_name}/tmp/*
        nohup ${DOMAIN_HOME}/bin/stopNodeManager.sh
        sleep 5
    fi
}

platops_run_start() {
    echo "\$SERVICE_NAME está em Service::ExecStart >> \$(date)"
    if [[ \$(platops_run_status | grep -v grep | grep "notok" | wc -l) -eq 1 ]]; then
        echo "\$SERVICE_NAME não esta executando... então deve iniciar... >> \$(date)"
        CONFIG_ARGS_BOOT="-Dweblogic.system.BootIdentityFile=${DOMAIN_HOME}/servers/${ms_name}/data/nodemanager/boot.properties -Dweblogic.nodemanager.ServiceEnabled=true -Dweblogic.nmservice.RotationEnabled=true"
        CONFIG_ARGS_START=\$(grep -E '<(server|server-start)>' -A50 ${DOMAIN_HOME}/config/config.xml | grep -B50 '<arguments>' | grep '<name>${ms_name}</name>' -A50 | grep '<arguments>' | sed -E 's/.*<arguments>(.*)<\/arguments>.*/\1/')
        CONFIG_ARGS_SSL=\$(cat ${DOMAIN_HOME}/servers/${ms_name}/data/nodemanager/startup.properties 2>/dev/null | grep -E "SSLArguments=" | sed -E 's/SSLArguments=//g')
        export JAVA_OPTIONS="\$JAVA_OPTIONS \$CONFIG_ARGS_BOOT \$CONFIG_ARGS_SSL \$CONFIG_ARGS_START"
        nohup ${DOMAIN_HOME}/bin/startManagedWebLogic.sh ${ms_name}
        sleep 50
    fi
    while true; do
        echo "\$SERVICE_NAME está em Service::ExecStart::platops_run_statusx >> \$(date)"
        if [[ \$(platops_run_status | grep -v grep | grep "notok" | wc -l) -eq 1 ]]; then
            exit 1
        fi
        tail -n 4 ${DOMAIN_HOME}/servers/${ms_name}/logs/${ms_name}.out
        sleep 10
    done
}

platops_run_status() {
    content=\$(netstat -vantup | grep LIST | grep ${ms_port})
    if [ \$(netstat -vantup | grep LIST | grep ${ms_port} | wc -l) -eq 1 ]; then
        echo "\$SERVICE_NAME está em process::status >> \$(date)"
        echo "\$SERVICE_NAME está em process::status::running >> \$(date)"
        echo \$content
    else
        echo "notok"
    fi
}

platops_run_stop() {
    echo "\$SERVICE_NAME está em process::stop >> \$(date)"
    sleep 2
    ${DOMAIN_HOME}/bin/stopManagedWebLogic.sh ${ms_name}
}

platops_run_restart() {
    echo "\$SERVICE_NAME está em process::restart >> \$(date)"
    sleep 10
    platops_run_stop
    exit 1
}

case "\$SERVICE_COMMAND" in
    boot)    platops_run_boot ;;
    start)   platops_run_start ;;
    status)  platops_run_status ;;
    stop)    platops_run_stop ;;
    restart) platops_run_restart ;;
    *)       echo "Uso: \$0 {boot|start|status|stop|restart}"; exit 1 ;;
esac
SHEOF

    cat > "${SYSTEMD_DIR}/${MS_SVC}" << SVCEOF
[Unit]
Description=platops-weblogic-${ms_name}
After=network.target
StartLimitInterval=240
StartLimitBurst=2

[Service]
Type=simple
User=${ORACLE_USER}
Group=${ORACLE_GROUP}
ExecStartPre=${MS_SH} boot
ExecStart=${MS_SH} start
Restart=always
RestartSec=5
StandardOutput=append:${MS_LOG}

[Install]
WantedBy=multi-user.target
SVCEOF

    log_ok "MS ${ms_name} (porta ${ms_port}): $MS_SH"
done

# ─── PERMISSÕES ───────────────────────────────────────────────────────────────

log_step "Ajustando permissões"

chmod +x "${SERVICES_DIR}"/platops-weblogic-*.sh
chown -R "${ORACLE_USER}:${ORACLE_GROUP}" "$SERVICES_DIR"
log_ok "chmod +x e chown oracle:oinstall aplicados."

# ─── SYSTEMCTL — REGISTRAR E SUBIR ────────────────────────────────────────────

log_step "Registrando e iniciando services — NM → Admin → MSes"

systemctl daemon-reload
log_ok "daemon-reload concluído."

# NodeManager
log_info "Habilitando e iniciando NodeManager..."
systemctl enable "${NM_SVC}"
systemctl start  "${NM_SVC}"
sleep 15
log_ok "NodeManager iniciado."

# AdminServer
log_info "Habilitando e iniciando AdminServer (${ADMIN_NAME})..."
systemctl enable "${ADMIN_SVC}"
systemctl start  "${ADMIN_SVC}"
sleep 30
log_ok "AdminServer iniciado."

# Managed Servers
for ms_name in "${MS_NAMES[@]}"; do
    SVC="platops-weblogic-managed-server-${ms_name}.service"
    log_info "Habilitando e iniciando ${ms_name}..."
    systemctl enable "$SVC"
    systemctl start  "$SVC"
    sleep 5
done

# ─── RESUMO ───────────────────────────────────────────────────────────────────

log_step "Resumo — Services criados para domain: ${DOMAIN_NAME}"

echo ""
log_info "Status atual:"
systemctl status "${NM_SVC}"    --no-pager -l 2>/dev/null | grep -E "Active:|●" || true
systemctl status "${ADMIN_SVC}" --no-pager -l 2>/dev/null | grep -E "Active:|●" || true
for ms_name in "${MS_NAMES[@]}"; do
    systemctl status "platops-weblogic-managed-server-${ms_name}.service" \
        --no-pager -l 2>/dev/null | grep -E "Active:|●" || true
done

echo ""
log_info "Comandos úteis:"
log_info "  systemctl status  platops-weblogic-nodemanager-${DOMAIN_NAME}"
log_info "  systemctl status  platops-weblogic-admin-${DOMAIN_NAME}"
for ms_name in "${MS_NAMES[@]}"; do
    log_info "  systemctl status  platops-weblogic-managed-server-${ms_name}"
done

echo ""
log_info "Logs dos services:"
log_info "  tail -f ${SERVICES_DIR}/nodemanagerservice.log"
log_info "  tail -f ${SERVICES_DIR}/AdminServerservice.log"
for ms_name in "${MS_NAMES[@]}"; do
    log_info "  tail -f ${DOMAIN_HOME}/servers/${ms_name}/logs/${ms_name}.out"
done
echo ""
