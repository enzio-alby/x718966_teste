#!/bin/bash
#
# importar.sh — Wrapper para importar configuracoes WebLogic via WLST
# Uso: ./importar.sh [--dry-run]
#
# Exemplos:
#   ./importar.sh --dry-run    # simula sem aplicar nada
#   ./importar.sh              # importa de verdade

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURAR AQUI (ou exportar antes de chamar o script)
# ─────────────────────────────────────────────────────────────────────────────

# MW_HOME do WebLogic no host DESTINO (ajustar se necessario)
MW_HOME="${MW_HOME:-/u01/oracle/middleware}"

# URL do AdminServer de DESTINO
export WLS_ADMIN_URL="${WLS_ADMIN_URL:-t3://localhost:7001}"

# Usuario admin do WebLogic
export WLS_USER="${WLS_USER:-weblogic}"

# Senha (deixe vazio para pedir interativamente — RECOMENDADO)
# export WLS_PASS="suasenha"

# Arquivo JSON gerado pelo exportar.sh
export WLS_CONFIG_FILE="${WLS_CONFIG_FILE:-config_export.json}"

# O que importar (true/false)
export WLS_EXPORT_STARTUP="${WLS_EXPORT_STARTUP:-true}"
export WLS_EXPORT_JDBC="${WLS_EXPORT_JDBC:-true}"
export WLS_EXPORT_JMS_SERVERS="${WLS_EXPORT_JMS_SERVERS:-true}"
export WLS_EXPORT_JMS_MODULES="${WLS_EXPORT_JMS_MODULES:-true}"

# ─────────────────────────────────────────────────────────────────────────────
# Processar argumento --dry-run
DRY_RUN=false
for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
        DRY_RUN=true
    fi
done
export WLS_DRY_RUN="$DRY_RUN"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WLST="$MW_HOME/oracle_common/common/bin/wlst.sh"

if [ ! -f "$WLST" ]; then
    echo "ERRO: wlst.sh nao encontrado em: $WLST"
    echo "      Ajuste a variavel MW_HOME."
    exit 1
fi

if [ ! -f "$WLS_CONFIG_FILE" ] && [ ! -f "$SCRIPT_DIR/$WLS_CONFIG_FILE" ]; then
    echo "ERRO: arquivo JSON nao encontrado: $WLS_CONFIG_FILE"
    echo "      Execute exportar.sh primeiro."
    exit 1
fi

echo "=========================================="
echo " WebLogic Config Import"
echo "=========================================="
echo " URL destino : $WLS_ADMIN_URL"
echo " Usuario     : $WLS_USER"
echo " Arquivo     : $WLS_CONFIG_FILE"
echo " Startup     : $WLS_EXPORT_STARTUP"
echo " JDBC        : $WLS_EXPORT_JDBC"
echo " JMS Servers : $WLS_EXPORT_JMS_SERVERS"
echo " JMS Modules : $WLS_EXPORT_JMS_MODULES"
if [ "$DRY_RUN" = "true" ]; then
    echo " MODO        : DRY-RUN (nenhuma alteracao sera aplicada)"
else
    echo " MODO        : REAL (alteracoes serao aplicadas)"
fi
echo "=========================================="
echo ""

if [ "$DRY_RUN" = "false" ]; then
    echo "ATENCAO: Este modo APLICA alteracoes no dominio de destino."
    echo "         Recomenda-se executar com --dry-run primeiro."
    echo ""
    read -rp "Confirmar importacao real? [s/N]: " CONFIRM
    if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
        echo "Importacao cancelada pelo usuario."
        exit 0
    fi
    echo ""
fi

"$WLST" "$SCRIPT_DIR/importar_config.py"
STATUS=$?

echo ""
if [ $STATUS -eq 0 ]; then
    if [ "$DRY_RUN" = "true" ]; then
        echo "[OK] Simulacao (dry-run) concluida. Nenhuma alteracao foi aplicada."
        echo "     Para importar de verdade: ./importar.sh"
    else
        echo "[OK] Importacao finalizada."
        echo ""
        echo "PROXIMOS PASSOS:"
        echo "  1. Acesse o console WebLogic"
        echo "  2. Va em Services > Data Sources"
        echo "  3. Redefina a senha de CADA DataSource importado"
        echo "  4. Teste as conexoes (botao Test)"
    fi
else
    echo "[ERRO] Importacao falhou com codigo: $STATUS"
fi

exit $STATUS
