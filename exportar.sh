#!/bin/bash
#
# exportar.sh — Exporta configuracoes de dominio WebLogic para JSON via WLST
# Uso: ./exportar.sh
#
# Faz perguntas interativas com valores default.
# A senha do WebLogic e pedida de forma segura (oculta) pelo proprio WLST.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─────────────────────────────────────────────────────────────────────────────
# Auto-detectar MW_HOME
# ─────────────────────────────────────────────────────────────────────────────
detectar_mw_home() {
    if [ -n "$ORACLE_HOME" ] && [ -f "$ORACLE_HOME/oracle_common/common/bin/wlst.sh" ]; then
        echo "$ORACLE_HOME"; return
    fi
    for dir in /u01/oracle/middleware /u01/app/oracle/middleware /oracle/middleware; do
        if [ -f "$dir/oracle_common/common/bin/wlst.sh" ]; then
            echo "$dir"; return
        fi
    done
    echo ""
}

MW_DETECTADO="$(detectar_mw_home)"

# ─────────────────────────────────────────────────────────────────────────────
# Perguntas interativas
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " WebLogic Config Export — WLST"
echo "=========================================="
echo ""

# MW_HOME
if [ -n "$MW_DETECTADO" ]; then
    read -rp "MW_HOME [$MW_DETECTADO]: " INPUT_MW
    MW_HOME="${INPUT_MW:-$MW_DETECTADO}"
else
    read -rp "MW_HOME (ex: /u01/oracle/middleware): " INPUT_MW
    MW_HOME="$INPUT_MW"
fi

WLST="$MW_HOME/oracle_common/common/bin/wlst.sh"
if [ ! -f "$WLST" ]; then
    echo ""
    echo "ERRO: wlst.sh nao encontrado em: $WLST"
    echo "      Verifique o MW_HOME informado."
    exit 1
fi

# URL do AdminServer
read -rp "URL AdminServer [t3://localhost:7001]: " INPUT_URL
export WLS_ADMIN_URL="${INPUT_URL:-t3://localhost:7001}"

# Usuario
read -rp "Usuario WebLogic [weblogic]: " INPUT_USER
export WLS_USER="${INPUT_USER:-weblogic}"

# Arquivo de saida
read -rp "Arquivo JSON de saida [config_export.json]: " INPUT_FILE
export WLS_CONFIG_FILE="${INPUT_FILE:-config_export.json}"

# O que exportar
echo ""
echo "O que exportar? (Enter = sim para todos)"
read -rp "  Startup params dos servidores? [S/n]: " EXP_STARTUP
read -rp "  DataSources JDBC?             [S/n]: " EXP_JDBC
read -rp "  JMS Servers?                  [S/n]: " EXP_JMS_SRV
read -rp "  JMS Modules (queues/topics)?  [S/n]: " EXP_JMS_MOD

[[ "${EXP_STARTUP,,}" == "n" ]] && export WLS_EXPORT_STARTUP=false  || export WLS_EXPORT_STARTUP=true
[[ "${EXP_JDBC,,}"    == "n" ]] && export WLS_EXPORT_JDBC=false     || export WLS_EXPORT_JDBC=true
[[ "${EXP_JMS_SRV,,}" == "n" ]] && export WLS_EXPORT_JMS_SERVERS=false || export WLS_EXPORT_JMS_SERVERS=true
[[ "${EXP_JMS_MOD,,}" == "n" ]] && export WLS_EXPORT_JMS_MODULES=false || export WLS_EXPORT_JMS_MODULES=true

# ─────────────────────────────────────────────────────────────────────────────
# Resumo e execucao
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "------------------------------------------"
echo " Resumo"
echo "------------------------------------------"
echo " MW_HOME     : $MW_HOME"
echo " URL         : $WLS_ADMIN_URL"
echo " Usuario     : $WLS_USER"
echo " Saida       : $WLS_CONFIG_FILE"
echo " Startup     : $WLS_EXPORT_STARTUP"
echo " JDBC        : $WLS_EXPORT_JDBC"
echo " JMS Servers : $WLS_EXPORT_JMS_SERVERS"
echo " JMS Modules : $WLS_EXPORT_JMS_MODULES"
echo "------------------------------------------"
echo ""
echo "A senha sera pedida a seguir pelo WLST (oculta)."
echo ""

"$WLST" "$SCRIPT_DIR/exportar_config.py"
STATUS=$?

echo ""
if [ $STATUS -eq 0 ]; then
    echo "[OK] Exportacao finalizada: $WLS_CONFIG_FILE"
else
    echo "[ERRO] Exportacao falhou com codigo: $STATUS"
fi
exit $STATUS
