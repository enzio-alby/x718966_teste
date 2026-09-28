#!/bin/bash
# =============================================================================
# criar_services_ohs.sh - Criação de services systemd platops para OHS
# Oraex / Getnet
#
# Suporta: OHS 12.2.1.4 e 14.1.2 Standalone (qualquer domain, nao so os
#          criados pelo INSTALL_OHS_*_STANDALONE.sh da Oraex)
#
# O que faz:
#   1. Le componentes OHS do config.xml do domain
#   2. Executa storeUserConfig (NM sobe temporariamente, armazena credencial,
#      para) — necessario para startComponent.sh rodar sem prompt de senha
#   3. Para todos os processos em execucao
#   4. Gera wrappers .sh em $DOMAIN_HOME/services/
#   5. Gera units .service em /etc/systemd/system/
#   6. Registra, habilita e sobe tudo (NM -> OHS component)
#
# Services gerados:
#   platops-weblogic-nodemanager-<domain>.service   (NodeManager)
#   platops-weblogic-component-<domain>.service      (cada componente OHS)
#
# Diferenca em relacao ao WLS (criar_services_wls.sh):
#   - Componentes lidos como <system-component>, nao <server>
#   - Start: startComponent.sh <comp>  (nao startManagedWebLogic.sh)
#   - Stop:  stopComponent.sh <comp>
#   - Status: porta HTTP — sem boot.properties
#   - Service OHS tem Requires= apontando pro NM (ordem garantida)
#   - storeUserConfig executado pelo proprio script (compativel com qualquer
#     instalacao, nao so a da Oraex)
#
# USO: ./criar_services_ohs.sh
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

# ─── VALIDACAO ROOT ───────────────────────────────────────────────────────────

if [ "$(id -u)" -ne 0 ]; then
    log_erro "Este script deve ser executado como root."
    exit 1
fi

# ─── COLETA DE INFORMACOES ────────────────────────────────────────────────────

log_step "Criacao de Services systemd OHS — Oraex/Getnet"

read -rp "  DOMAIN_HOME (ex: /u01/qualidade/domains/ohs_domain): " DOMAIN_HOME
if [[ -z "$DOMAIN_HOME" ]]; then log_erro "DOMAIN_HOME obrigatorio."; exit 1; fi
if [[ ! -d "$DOMAIN_HOME" ]]; then log_erro "DOMAIN_HOME nao encontrado: $DOMAIN_HOME"; exit 1; fi

CONFIG_XML="${DOMAIN_HOME}/config/config.xml"
if [[ ! -f "$CONFIG_XML" ]]; then log_erro "config.xml nao encontrado: $CONFIG_XML"; exit 1; fi

DOMAIN_NAME=$(basename "$DOMAIN_HOME")
SERVICES_DIR="${DOMAIN_HOME}/services"

log_ok "Domain     : $DOMAIN_NAME"
log_ok "config.xml : $CONFIG_XML"

# ─── LER COMPONENTES OHS DO CONFIG.XML ───────────────────────────────────────

log_step "Lendo componentes OHS do config.xml"

PYTHON_BIN=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)
if [[ -z "$PYTHON_BIN" ]]; then log_erro "Python nao encontrado no host."; exit 1; fi

# OHS usa <system-component>, WLS usa <server>
mapfile -t OHS_COMPS < <("$PYTHON_BIN" - "$CONFIG_XML" << 'PYEOF'
import sys, xml.etree.ElementTree as ET
tree = ET.parse(sys.argv[1])
root = tree.getroot()
ns = ('{' + root.tag.split('}')[0].lstrip('{') + '}') if '}' in root.tag else ''
for comp in root.findall(ns + 'system-component'):
    name_el = comp.find(ns + 'name')
    if name_el is not None:
        print(name_el.text)
PYEOF
)

if [ "${#OHS_COMPS[@]}" -eq 0 ]; then
    log_erro "Nenhum system-component (OHS) encontrado no config.xml."
    log_info "Verifique se este e um domain OHS standalone (nao WLS)."
    exit 1
fi

log_ok "Componentes OHS: ${#OHS_COMPS[@]}"
for comp in "${OHS_COMPS[@]}"; do
    log_info "  $comp"
done

# ─── LER PORTA DO NODEMANAGER ─────────────────────────────────────────────────

NM_PROPS="${DOMAIN_HOME}/nodemanager/nodemanager.properties"
NM_PORT=""
if [ -f "$NM_PROPS" ]; then
    NM_PORT=$(grep "^ListenPort=" "$NM_PROPS" 2>/dev/null | cut -d= -f2 || true)
fi
NM_PORT="${NM_PORT:-5556}"
log_ok "NodeManager porta: ${NM_PORT}"

# ─── DETECTAR PORTAS DO OHS ──────────────────────────────────────────────────

log_step "Detectando portas OHS"

FIRST_COMP="${OHS_COMPS[0]}"
OHS_CONF="${DOMAIN_HOME}/config/fmwconfig/components/OHS/${FIRST_COMP}/httpd.conf"
OHS_HTTP_PORT=""
OHS_HTTPS_PORT=""

if [ -f "$OHS_CONF" ]; then
    log_info "httpd.conf: $OHS_CONF"
    OHS_HTTP_PORT=$(grep -E "^Listen[[:space:]]+[*]?:?[0-9]+" "$OHS_CONF" 2>/dev/null \
        | grep -v "443" | grep -v "^#" | head -1 \
        | grep -oE "[0-9]+" | tail -1 || true)
    OHS_HTTPS_PORT=$(grep -E "^Listen[[:space:]]+[*]?:?443" "$OHS_CONF" 2>/dev/null \
        | grep -v "^#" | head -1 \
        | grep -oE "[0-9]+" | tail -1 || true)
    log_ok "Detectadas — HTTP: ${OHS_HTTP_PORT:-nao encontrada}  HTTPS: ${OHS_HTTPS_PORT:-nao encontrada}"
else
    log_warn "httpd.conf nao encontrado em: $OHS_CONF"
fi

if [ -z "$OHS_HTTP_PORT" ]; then
    read -rp "  Porta HTTP do OHS [80]: " OHS_HTTP_PORT
    OHS_HTTP_PORT="${OHS_HTTP_PORT:-80}"
fi
if [ -z "$OHS_HTTPS_PORT" ]; then
    read -rp "  Porta HTTPS do OHS [443]: " OHS_HTTPS_PORT
    OHS_HTTPS_PORT="${OHS_HTTPS_PORT:-443}"
fi

log_ok "Porta HTTP : ${OHS_HTTP_PORT}"
log_ok "Porta HTTPS: ${OHS_HTTPS_PORT}"

# ─── CONFIRMACAO ─────────────────────────────────────────────────────────────

echo ""
log_warn "Atencao: storeUserConfig sera executado e todos os processos OHS serao"
log_warn "parados e reiniciados como service."
log_info "  Domain     : $DOMAIN_NAME"
log_info "  NM porta   : $NM_PORT"
log_info "  HTTP porta : $OHS_HTTP_PORT"
log_info "  HTTPS porta: $OHS_HTTPS_PORT"
for comp in "${OHS_COMPS[@]}"; do
    log_info "  Componente : $comp"
done
echo ""
read -rp "  Confirma? (s/n): " conf
[[ "$conf" != "s" ]] && { log_info "Cancelado."; exit 0; }

# ─── STOREUSER CONFIG ─────────────────────────────────────────────────────────
# Armazena a credencial do NM em ~/.wlst/nm-cfg-*.props do oracle.
# Necessario para que startComponent.sh inicie o OHS sem prompt de senha.
# Funciona em qualquer domain OHS, independente de quem o criou.

log_step "Configurando credenciais NodeManager (storeUserConfig)"

log_info "A senha do NodeManager e a mesma definida na criacao do domain."
read -rsp "  Senha do NodeManager: " NM_PASS
echo ""
if [[ -z "$NM_PASS" ]]; then log_erro "Senha obrigatoria."; exit 1; fi

# Garantir que o NM esteja parado antes de subir limpo para o storeUserConfig
log_info "Parando NM anterior (se houver)..."
sudo -u "$ORACLE_USER" bash -c \
    "'${DOMAIN_HOME}/bin/stopNodeManager.sh' 2>/dev/null || true" || true
pkill -u "$ORACLE_USER" -f "weblogic.NodeManager" 2>/dev/null || true
sleep 3

# Subir NM temporariamente como oracle
log_info "Iniciando NodeManager temporariamente para storeUserConfig..."
mkdir -p "$SERVICES_DIR"
chown "${ORACLE_USER}:${ORACLE_GROUP}" "$SERVICES_DIR"
sudo -u "$ORACLE_USER" bash -c \
    "nohup '${DOMAIN_HOME}/bin/startNodeManager.sh' </dev/null >>'${SERVICES_DIR}/nm_store_tmp.log' 2>&1 & disown"

# Aguardar NM ficar ativo (max 60s)
log_info "Aguardando NodeManager na porta ${NM_PORT}..."
nm_ok=0
for i in $(seq 1 30); do
    if netstat -vantup 2>/dev/null | grep -q ":${NM_PORT}.*LISTEN"; then
        nm_ok=1
        break
    fi
    sleep 2
done

if [ "$nm_ok" -eq 0 ]; then
    log_erro "NodeManager nao subiu na porta ${NM_PORT} apos 60s."
    log_info "Verifique: tail ${SERVICES_DIR}/nm_store_tmp.log"
    exit 1
fi
log_ok "NodeManager ativo na porta ${NM_PORT}."

# storeUserConfig para cada componente OHS
for comp in "${OHS_COMPS[@]}"; do
    log_info "Executando storeUserConfig para ${comp}..."
    # printf evita problemas com senhas que contem caracteres especiais do shell
    if sudo -u "$ORACLE_USER" bash -c \
        "printf '%s\n' '${NM_PASS}' | '${DOMAIN_HOME}/bin/startComponent.sh' '${comp}' storeUserConfig 2>&1"; then
        log_ok "storeUserConfig: ${comp}"
    else
        log_warn "storeUserConfig pode ter retornado erro para ${comp} (verifique se a senha esta correta)"
    fi
done

# Parar NM — o service vai subi-lo depois de forma controlada
log_info "Parando NodeManager temporario..."
sudo -u "$ORACLE_USER" bash -c \
    "'${DOMAIN_HOME}/bin/stopNodeManager.sh' 2>/dev/null || true" || true
sleep 3
log_ok "storeUserConfig concluido."

# ─── PARAR PROCESSOS ──────────────────────────────────────────────────────────

log_step "Parando processos em execucao"

for comp in "${OHS_COMPS[@]}"; do
    log_info "Parando componente ${comp}..."
    sudo -u "$ORACLE_USER" bash -c \
        "'${DOMAIN_HOME}/bin/stopComponent.sh' '${comp}' 2>/dev/null || true" || true
done

log_info "Parando NodeManager..."
sudo -u "$ORACLE_USER" bash -c \
    "'${DOMAIN_HOME}/bin/stopNodeManager.sh' 2>/dev/null || true" || true

sleep 5

# Encerrar httpd orfao do domain (sobreviventes ao stopComponent)
pkill -f "${DOMAIN_HOME}.*httpd" 2>/dev/null || true
sleep 2
log_ok "Processos parados."

# ─── CRIAR DIRETORIO DE SERVICES ─────────────────────────────────────────────

mkdir -p "$SERVICES_DIR"
chown "${ORACLE_USER}:${ORACLE_GROUP}" "$SERVICES_DIR"

# ─── GERAR WRAPPER — NODEMANAGER ─────────────────────────────────────────────

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
    echo "\$SERVICE_NAME esta em Service::ExecStartPre  >> \$(date)"
    if [[ \$(platops_run_status | grep -v grep | grep "running" | wc -l) -eq 1 ]]; then
        echo "\$SERVICE_NAME esta executando manualmente... >> \$(date)"
        sleep 10
    else
        echo "\$SERVICE_NAME executando limpeza do cache nodemanager >> \$(date)"
        rm -rf ${DOMAIN_HOME}/nodemanager/nodemanager.*lck* 2>/dev/null
        sleep 4
    fi
}

platops_run_start() {
    echo "\$SERVICE_NAME esta em Service::ExecStart >> \$(date)"
    if [[ \$(platops_run_status | grep -v grep | grep "notok" | wc -l) -eq 1 ]]; then
        echo "\$SERVICE_NAME nao esta rodando... iniciando... >> \$(date)"
        nohup ${DOMAIN_HOME}/bin/startNodeManager.sh &
        sleep 15
    fi
    while true; do
        echo "\$SERVICE_NAME esta em Service::ExecStart::platops_run_statusx >> \$(date)"
        if [[ \$(platops_run_status | grep -v grep | grep "notok" | wc -l) -eq 1 ]]; then
            exit 1
        fi
        tail -n 4 ${DOMAIN_HOME}/nodemanager/nodemanager.log 2>/dev/null
        sleep 10
    done
}

platops_run_status() {
    if [ \$(netstat -vantup 2>/dev/null | grep LIST | grep ${NM_PORT} | wc -l) -eq 1 ]; then
        echo "\$SERVICE_NAME esta em process::status::running >> \$(date)"
    else
        echo "notok"
    fi
}

platops_run_stop() {
    echo "\$SERVICE_NAME esta em process::stop >> \$(date)"
    nohup ${DOMAIN_HOME}/bin/stopNodeManager.sh &
    sleep 2
}

platops_run_restart() {
    echo "\$SERVICE_NAME esta em process::restart >> \$(date)"
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

# ─── GERAR WRAPPERS — COMPONENTES OHS ────────────────────────────────────────

log_step "Gerando services — Componentes OHS"

for comp in "${OHS_COMPS[@]}"; do

    OHS_SH="${SERVICES_DIR}/platops-weblogic-component-${DOMAIN_NAME}.sh"
    OHS_SVC="platops-weblogic-component-${DOMAIN_NAME}.service"
    OHS_LOG="${SERVICES_DIR}/${comp}service.log"

    cat > "$OHS_SH" << SHEOF
#!/bin/bash

SERVICE_COMMAND=\$1
SERVICE_NAME=ohs-${comp}

echo \$SERVICE_COMMAND

trap platops_run_stop SIGTERM
trap platops_run_stop SIGINT

platops_run_boot() {
    echo "\$SERVICE_NAME esta em Service::ExecStartPre >> \$(date)"
    if [[ \$(platops_run_status | grep "running" | wc -l) -eq 1 ]]; then
        echo "\$SERVICE_NAME esta rodando manualmente... >> \$(date)"
        sleep 10
    else
        echo "\$SERVICE_NAME limpando cache >> \$(date)"
        rm -rf ${DOMAIN_HOME}/servers/${comp}/cache/* 2>/dev/null
        rm -rf ${DOMAIN_HOME}/servers/${comp}/tmp/* 2>/dev/null
        sleep 4
    fi
}

platops_run_start() {
    echo "\$SERVICE_NAME esta em Service::ExecStart >> \$(date)"
    if [[ \$(platops_run_status | grep "notok" | wc -l) -eq 1 ]]; then
        echo "\$SERVICE_NAME nao esta rodando... iniciando... >> \$(date)"
        nohup ${DOMAIN_HOME}/bin/startComponent.sh ${comp}
        sleep 30
    fi
    while true; do
        echo "\$SERVICE_NAME esta em Service::ExecStart::platops_run_statusx >> \$(date)"
        if [[ \$(platops_run_status | grep "notok" | wc -l) -eq 1 ]]; then
            exit 1
        fi
        sleep 10
    done
}

platops_run_status() {
    if [ \$(netstat -vantup 2>/dev/null | grep LIST | grep ${OHS_HTTP_PORT} | wc -l) -ge 1 ]; then
        echo "\$SERVICE_NAME esta em process::status::running >> \$(date)"
    else
        echo "notok"
    fi
}

platops_run_stop() {
    echo "\$SERVICE_NAME esta em process::stop >> \$(date)"
    nohup ${DOMAIN_HOME}/bin/stopComponent.sh ${comp} &
    sleep 5
}

platops_run_restart() {
    echo "\$SERVICE_NAME esta em process::restart >> \$(date)"
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

    # OHS depende do NM — systemd garante que NM sobe antes do componente
    cat > "${SYSTEMD_DIR}/${OHS_SVC}" << SVCEOF
[Unit]
Description=platops-weblogic-component-${DOMAIN_NAME}
After=network.target ${NM_SVC}
Requires=${NM_SVC}
StartLimitInterval=240
StartLimitBurst=2

[Service]
Type=simple
User=${ORACLE_USER}
Group=${ORACLE_GROUP}
ExecStartPre=${OHS_SH} boot
ExecStart=${OHS_SH} start
Restart=always
RestartSec=10
StandardOutput=append:${OHS_LOG}

[Install]
WantedBy=multi-user.target
SVCEOF

    log_ok "OHS ${comp}: $OHS_SH"
done

# ─── PERMISSOES ───────────────────────────────────────────────────────────────

log_step "Ajustando permissoes"

chmod +x "${SERVICES_DIR}"/platops-weblogic-*.sh
chown -R "${ORACLE_USER}:${ORACLE_GROUP}" "$SERVICES_DIR"
log_ok "chmod +x e chown oracle:oinstall aplicados."

# ─── SYSTEMCTL — REGISTRAR E SUBIR ───────────────────────────────────────────

log_step "Registrando e iniciando services — NM -> OHS"

systemctl daemon-reload
log_ok "daemon-reload concluido."

# NodeManager primeiro
log_info "Habilitando e iniciando NodeManager..."
systemctl enable "${NM_SVC}"
systemctl start  "${NM_SVC}"
sleep 20
log_ok "NodeManager iniciado."

# Componentes OHS (dependem do NM via Requires=)
for comp in "${OHS_COMPS[@]}"; do
    SVC="platops-weblogic-component-${DOMAIN_NAME}.service"
    log_info "Habilitando e iniciando ${comp}..."
    systemctl enable "$SVC"
    systemctl start  "$SVC"
    sleep 15
done

# ─── RESUMO ───────────────────────────────────────────────────────────────────

log_step "Resumo — Services OHS criados para domain: ${DOMAIN_NAME}"

echo ""
log_info "Status atual:"
systemctl status "${NM_SVC}" --no-pager -l 2>/dev/null | grep -E "Active:|●" || true
for comp in "${OHS_COMPS[@]}"; do
    systemctl status "platops-weblogic-component-${DOMAIN_NAME}.service" \
        --no-pager -l 2>/dev/null | grep -E "Active:|●" || true
done

echo ""
log_info "Comandos uteis:"
log_info "  systemctl status  platops-weblogic-nodemanager-${DOMAIN_NAME}"
for comp in "${OHS_COMPS[@]}"; do
    log_info "  systemctl status  platops-weblogic-component-${DOMAIN_NAME}"
    log_info "  systemctl restart platops-weblogic-component-${DOMAIN_NAME}"
done

echo ""
log_info "Verificar OHS respondendo:"
log_info "  curl -sk http://localhost:${OHS_HTTP_PORT}/  | head -3"
log_info "  curl -sk https://localhost:${OHS_HTTPS_PORT}/ | head -3"

echo ""
log_info "Logs:"
log_info "  tail -f ${SERVICES_DIR}/nodemanagerservice.log"
for comp in "${OHS_COMPS[@]}"; do
    log_info "  tail -f ${SERVICES_DIR}/${comp}service.log"
done
echo ""
