#!/bin/bash
#
# importar.sh — Importa configuracoes de dominio WebLogic a partir de JSON via WLST
# Uso: ./importar.sh
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
echo " WebLogic Config Import — WLST"
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

# URL do AdminServer de destino
read -rp "URL AdminServer DESTINO [t3://localhost:7001]: " INPUT_URL
export WLS_ADMIN_URL="${INPUT_URL:-t3://localhost:7001}"

# Usuario
read -rp "Usuario WebLogic [weblogic]: " INPUT_USER
export WLS_USER="${INPUT_USER:-weblogic}"

# Arquivo JSON de entrada
read -rp "Arquivo JSON de entrada [config_export.json]: " INPUT_FILE
export WLS_CONFIG_FILE="${INPUT_FILE:-config_export.json}"

if [ ! -f "$WLS_CONFIG_FILE" ] && [ ! -f "$SCRIPT_DIR/$WLS_CONFIG_FILE" ]; then
    echo ""
    echo "ERRO: arquivo JSON nao encontrado: $WLS_CONFIG_FILE"
    echo "      Execute exportar.sh no host de origem primeiro."
    exit 1
fi

# O que importar
echo ""
echo "O que importar? (Enter = sim para todos)"
read -rp "  Startup params dos servidores? [S/n]: " IMP_STARTUP
read -rp "  DataSources JDBC?             [S/n]: " IMP_JDBC
read -rp "  JMS Servers?                  [S/n]: " IMP_JMS_SRV
read -rp "  JMS Modules (queues/topics)?  [S/n]: " IMP_JMS_MOD

[[ "${IMP_STARTUP,,}" == "n" ]] && export WLS_EXPORT_STARTUP=false  || export WLS_EXPORT_STARTUP=true
[[ "${IMP_JDBC,,}"    == "n" ]] && export WLS_EXPORT_JDBC=false     || export WLS_EXPORT_JDBC=true
[[ "${IMP_JMS_SRV,,}" == "n" ]] && export WLS_EXPORT_JMS_SERVERS=false || export WLS_EXPORT_JMS_SERVERS=true
[[ "${IMP_JMS_MOD,,}" == "n" ]] && export WLS_EXPORT_JMS_MODULES=false || export WLS_EXPORT_JMS_MODULES=true

# Substituicao de banco nos DataSources (para importar em ambiente diferente)
export WLS_DB_OVERRIDE=""
if [[ "${IMP_JDBC,,}" != "n" ]]; then
    echo ""
    echo "Os DataSources exportados tem URLs de banco do ambiente de ORIGEM."
    read -rp "Substituir banco nos DataSources? [s/N]: " OVERRIDE_DB
    if [[ "${OVERRIDE_DB,,}" == "s" ]]; then
        echo "  Informe o novo host:porta/servico do banco de DESTINO."
        echo "  Exemplos:"
        echo "    qa-db-host.getnet.local:1521/QAPDB"
        echo "    10.x.x.x:1521/QAPDB"
        read -rp "  Novo banco [host:porta/servico]: " INPUT_DB
        export WLS_DB_OVERRIDE="$INPUT_DB"
    fi
fi

# Dry-run
echo ""
read -rp "Executar em DRY-RUN (simular sem aplicar)? [s/N]: " INPUT_DRY
if [[ "${INPUT_DRY,,}" == "s" ]]; then
    export WLS_DRY_RUN=true
else
    export WLS_DRY_RUN=false
fi

# ─────────────────────────────────────────────────────────────────────────────
# Resumo
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "------------------------------------------"
echo " Resumo"
echo "------------------------------------------"
echo " MW_HOME     : $MW_HOME"
echo " URL destino : $WLS_ADMIN_URL"
echo " Usuario     : $WLS_USER"
echo " Arquivo     : $WLS_CONFIG_FILE"
echo " Startup     : $WLS_EXPORT_STARTUP"
echo " JDBC        : $WLS_EXPORT_JDBC"
echo " JMS Servers : $WLS_EXPORT_JMS_SERVERS"
echo " JMS Modules : $WLS_EXPORT_JMS_MODULES"
if [ -n "$WLS_DB_OVERRIDE" ]; then
    echo " Banco dest. : $WLS_DB_OVERRIDE"
else
    echo " Banco dest. : (mantido do JSON)"
fi
if [ "$WLS_DRY_RUN" = "true" ]; then
    echo " MODO        : DRY-RUN (nenhuma alteracao sera aplicada)"
else
    echo " MODO        : REAL (alteracoes serao aplicadas)"
fi
echo "------------------------------------------"
echo ""

# Confirmacao extra no modo real
if [ "$WLS_DRY_RUN" = "false" ]; then
    echo "ATENCAO: alteracoes serao aplicadas no dominio de destino."
    read -rp "Confirmar? [s/N]: " CONFIRM
    if [[ "${CONFIRM,,}" != "s" ]]; then
        echo "Importacao cancelada."
        exit 0
    fi
    echo ""
fi

echo "A senha sera pedida a seguir pelo WLST (oculta)."
echo ""

"$WLST" "$SCRIPT_DIR/importar_config.py"
STATUS=$?

echo ""
if [ $STATUS -eq 0 ]; then
    if [ "$WLS_DRY_RUN" = "true" ]; then
        echo "[OK] Simulacao (dry-run) concluida. Nenhuma alteracao foi aplicada."
        echo "     Para importar de verdade: execute novamente e responda N no dry-run."
    else
        echo "[OK] Importacao finalizada."
        echo ""
        echo "PROXIMOS PASSOS:"
        echo "  1. Acesse o console WebLogic: http://<host>:7001/console"
        echo "  2. Va em Services > Data Sources"
        echo "  3. Redefina a senha de CADA DataSource importado"
        echo "  4. Teste as conexoes (botao Test)"
    fi
else
    echo "[ERRO] Importacao falhou com codigo: $STATUS"
fi

exit $STATUS
