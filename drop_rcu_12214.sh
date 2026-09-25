#!/bin/bash
# =============================================================================
# drop_rcu_12214.sh - Drop de schemas RCU WebLogic 12.2.1.4
# Suporta: ODI (STB MDS IAU IAU_APPEND IAU_VIEWER OPSS WLS ODI)
#          SOA/OSB (STB MDS IAU IAU_APPEND IAU_VIEWER OPSS WLS UCSUMS SOAINFRA ESS)
#          WCC     (STB MDS IAU IAU_APPEND IAU_VIEWER OPSS WLS WCC IPM CAPTURE)
#
# Metodo primario : RCU -dropRepository (silencioso)
# Metodo fallback : DROP USER ... CASCADE via sqlplus (quando RCU falha ou
#                   schemas foram criados parcialmente sem registro no RCU)
#
# ATENCAO: FMW_HOME (para rcu) e DB_HOME (para sqlplus) sao caminhos distintos.
#          O sqlplus NAO fica no middleware -- fica no Oracle DB Client.
#
# USO: ./drop_rcu_12214.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_erro()  { echo -e "${RED}[ERRO]${NC}  $*"; }
log_step()  { echo -e "\n${BOLD}${BLUE}================================================================${NC}"; \
              echo -e "${BOLD}${BLUE}  $*${NC}"; \
              echo -e "${BOLD}${BLUE}================================================================${NC}\n"; }

# --- COLETA DE PARAMETROS -----------------------------------------------------

log_step "Drop RCU - WebLogic 12.2.1.4"

echo "  FMW_HOME: diretorio do middleware onde o RCU esta instalado"
read -rp "  FMW_HOME [/u01/oracle/middleware]: " inp
FMW_HOME="${inp:-/u01/oracle/middleware}"
RCU="${FMW_HOME}/oracle_common/bin/rcu"

if [ ! -f "$RCU" ]; then
    log_erro "RCU nao encontrado em: $RCU"
    exit 1
fi
log_ok "RCU: $RCU"

# sqlplus nao e usado diretamente — banco pode estar em host separado.
# Se precisar do Metodo 2 ou limpar tablespaces, o script imprime os comandos
# para rodar manualmente no host do banco como SYSDBA.
SQLPLUS_OK=0

echo ""
echo -e "  ${BOLD}Tipo de instalacao:${NC}"
echo "  [1] ODI   (schemas: STB MDS IAU IAU_APPEND IAU_VIEWER OPSS WLS ODI)"
echo "  [2] SOA   (schemas: STB MDS IAU IAU_APPEND IAU_VIEWER OPSS WLS UCSUMS SOAINFRA ESS)"
echo "  [3] OSB   (mesmo que SOA)"
echo "  [4] WCC   (schemas: STB MDS IAU IAU_APPEND IAU_VIEWER OPSS WLS WCC IPM CAPTURE)"
read -rp "  Escolha [1/2/3/4]: " tipo_escolha
case "$tipo_escolha" in
    1) TIPO="odi" ;;
    2) TIPO="soa" ;;
    3) TIPO="osb" ;;
    4) TIPO="wcc" ;;
    *) log_erro "Opcao invalida."; exit 1 ;;
esac

echo ""
read -rp "  Hostname/IP do banco: " DB_HOST
[[ -z "$DB_HOST" ]] && { log_erro "Hostname obrigatorio."; exit 1; }

read -rp "  Porta do listener [1521]: " inp
DB_PORT="${inp:-1521}"

read -rp "  Service name do PDB: " DB_SERVICE
[[ -z "$DB_SERVICE" ]] && { log_erro "Service name obrigatorio."; exit 1; }

read -rp "  Prefixo dos schemas a dropar (ex: ODI12QA): " SCHEMA_PREFIX
[[ -z "$SCHEMA_PREFIX" ]] && { log_erro "Prefixo obrigatorio."; exit 1; }

read -rsp "  Senha do usuario SYS: " SYS_PASS; echo ""
[[ -z "$SYS_PASS" ]] && { log_erro "Senha SYS obrigatoria."; exit 1; }

read -rsp "  Senha dos schemas (usada na criacao original): " SCHEMA_PASS; echo ""
[[ -z "$SCHEMA_PASS" ]] && { log_erro "Senha dos schemas obrigatoria."; exit 1; }

# --- LISTA DE COMPONENTES E SCHEMAS -------------------------------------------

if [ "$TIPO" == "odi" ]; then
    COMPONENTS="-component STB -component MDS -component IAU -component IAU_APPEND -component IAU_VIEWER -component OPSS -component WLS -component ODI"
    SCHEMAS="STB MDS IAU IAU_APPEND IAU_VIEWER OPSS WLS ODI_REPO"
    SCHEMAS_DISPLAY="${SCHEMA_PREFIX}_STB  ${SCHEMA_PREFIX}_MDS  ${SCHEMA_PREFIX}_IAU
  ${SCHEMA_PREFIX}_IAU_APPEND  ${SCHEMA_PREFIX}_IAU_VIEWER
  ${SCHEMA_PREFIX}_OPSS  ${SCHEMA_PREFIX}_WLS  ${SCHEMA_PREFIX}_ODI_REPO"
elif [ "$TIPO" == "wcc" ]; then
    COMPONENTS="-component STB -component MDS -component IAU -component IAU_APPEND -component IAU_VIEWER -component OPSS -component WLS -component CONTENT -component CONTENTSEARCH -component IPM -component CAPTURE"
    SCHEMAS="STB MDS IAU IAU_APPEND IAU_VIEWER OPSS WLS OCS OCSSEARCH WLS_RUNTIME IPM CAPTURE"
    SCHEMAS_DISPLAY="${SCHEMA_PREFIX}_STB  ${SCHEMA_PREFIX}_MDS  ${SCHEMA_PREFIX}_IAU
  ${SCHEMA_PREFIX}_IAU_APPEND  ${SCHEMA_PREFIX}_IAU_VIEWER
  ${SCHEMA_PREFIX}_OPSS  ${SCHEMA_PREFIX}_WLS  ${SCHEMA_PREFIX}_WLS_RUNTIME
  ${SCHEMA_PREFIX}_OCS  ${SCHEMA_PREFIX}_OCSSEARCH  ${SCHEMA_PREFIX}_IPM  ${SCHEMA_PREFIX}_CAPTURE"
else
    COMPONENTS="-component STB -component MDS -component IAU -component IAU_APPEND -component IAU_VIEWER -component OPSS -component WLS -component UCSUMS -component SOAINFRA -component ESS"
    SCHEMAS="STB MDS IAU IAU_APPEND IAU_VIEWER OPSS WLS UCSUMS SOAINFRA ESS"
    SCHEMAS_DISPLAY="${SCHEMA_PREFIX}_STB  ${SCHEMA_PREFIX}_MDS  ${SCHEMA_PREFIX}_IAU
  ${SCHEMA_PREFIX}_IAU_APPEND  ${SCHEMA_PREFIX}_IAU_VIEWER
  ${SCHEMA_PREFIX}_OPSS  ${SCHEMA_PREFIX}_WLS
  ${SCHEMA_PREFIX}_UCSUMS  ${SCHEMA_PREFIX}_SOAINFRA  ${SCHEMA_PREFIX}_ESS"
fi

CONNECT_STRING="${DB_HOST}:${DB_PORT}/${DB_SERVICE}"

# --- CONFIRMACAO --------------------------------------------------------------

echo ""
log_warn "ATENCAO: esta operacao vai apagar PERMANENTEMENTE os schemas abaixo:"
echo ""
echo "  $SCHEMAS_DISPLAY"
echo ""
log_warn "Banco   : ${CONNECT_STRING}"
log_warn "Prefixo : ${SCHEMA_PREFIX}"
echo ""
read -rp "  Confirma o drop? (s/n): " confirm
[[ "$confirm" != "s" ]] && { echo "  Cancelado."; exit 0; }

# --- METODO 1: RCU -dropRepository --------------------------------------------

log_step "Metodo 1 -- RCU -dropRepository"

log_info "Executando RCU drop (output em tempo real)..."
log_info "  Banco   : ${CONNECT_STRING}"
log_info "  Prefixo : ${SCHEMA_PREFIX}"
log_info "  Tipo    : ${TIPO}"
echo ""

# tee exibe o output na tela em tempo real e salva em arquivo para analise
# PIPESTATUS[0] captura o exit code do RCU (nao do tee)
_rcu_log=$(mktemp /tmp/rcu_drop_XXXXXX.log)
set +e
"$RCU" -silent -dropRepository \
    -databaseType ORACLE \
    -connectString "$CONNECT_STRING" \
    -dbUser SYS \
    -dbRole SYSDBA \
    -schemaPrefix "$SCHEMA_PREFIX" \
    $COMPONENTS \
    2>&1 << EOF | tee "$_rcu_log"
${SYS_PASS}
${SCHEMA_PASS}
EOF
RCU_EXIT=${PIPESTATUS[0]}
set -e

RCU_OUTPUT=$(cat "$_rcu_log")
rm -f "$_rcu_log"
echo ""

# RCU-6013 significa que o prefixo nao esta registrado no catalogo do RCU --
# ocorre quando schemas foram criados parcialmente (RCU falhou antes de concluir).
# Neste caso ir direto para o Metodo 2 (DROP USER manual).
if echo "$RCU_OUTPUT" | grep -q "RCU-6013"; then
    log_warn "RCU-6013: schemas nao estao registrados no catalogo do RCU."
    log_warn "Isso ocorre quando a criacao anterior falhou no meio do caminho."
    log_warn "Usando Metodo 2 para dropar os usuarios diretamente no banco."
    DROP_OK=0
elif [ $RCU_EXIT -eq 0 ]; then
    log_ok "RCU drop concluido com sucesso."
    DROP_OK=1
else
    log_warn "RCU retornou exit $RCU_EXIT -- tentando Metodo 2."
    DROP_OK=0
fi

# --- METODO 2: DROP USER ... CASCADE (comandos manuais no host do banco) ------

if [ $DROP_OK -eq 0 ]; then
    log_step "Metodo 2 -- DROP USER ... CASCADE (executar no host do banco)"

    log_warn "O RCU nao conseguiu dropar via catalogo (RCU-6013)."
    log_warn "Execute os comandos abaixo manualmente no host do banco como SYSDBA:"
    echo ""
    echo "  -- Conectar no PDB como SYSDBA:"
    echo "  sqlplus sys/<senha_sys>@${CONNECT_STRING} as sysdba"
    echo ""
    echo "  -- Ou via SQL*Plus local no host do banco:"
    echo "  sqlplus / as sysdba"
    echo "  ALTER SESSION SET CONTAINER = <nome_do_pdb>;"
    echo ""
    echo "  -- Dropar os schemas:"
    echo "  WHENEVER SQLERROR CONTINUE;"
    for s in $SCHEMAS; do
        echo "  DROP USER ${SCHEMA_PREFIX}_${s} CASCADE;"
    done
    echo "  EXIT;"
    echo ""
    log_warn "ORA-01918 (user does not exist) e normal para schemas nao criados."
fi

# --- TABLESPACES --------------------------------------------------------------

log_step "Tablespaces residuais"

if [ "$TIPO" == "wcc" ]; then
    TS_LIST=(
        "${SCHEMA_PREFIX}_IAS_OPSS"
        "${SCHEMA_PREFIX}_WCC_MDS"
        "${SCHEMA_PREFIX}_WCC_TEMP"
        "${SCHEMA_PREFIX}_WCC_USER"
        "${SCHEMA_PREFIX}_IPM_USER"
        "${SCHEMA_PREFIX}_CAPTURE_USER"
    )
elif [ "$TIPO" == "odi" ]; then
    TS_LIST=(
        "${SCHEMA_PREFIX}_IAS_OPSS"
        "${SCHEMA_PREFIX}_ODI_TEMP"
        "${SCHEMA_PREFIX}_ODI_USER"
    )
else
    TS_LIST=(
        "${SCHEMA_PREFIX}_IAS_OPSS"
        "${SCHEMA_PREFIX}_SOAINFRA"
        "${SCHEMA_PREFIX}_MDS"
    )
fi

# Montar bloco SQL de drop das tablespaces
TS_SQL="WHENEVER SQLERROR CONTINUE;\n"
for ts in "${TS_LIST[@]}"; do
    TS_SQL+="DROP TABLESPACE ${ts} INCLUDING CONTENTS AND DATAFILES;\n"
done
TS_SQL+="EXIT;"

executar_ts_sql() {
    local cmd="$1"
    local log_ts="/tmp/ts_drop_$$.log"
    echo -e "$TS_SQL" | eval "$cmd" 2>&1 | grep -v "^$" | tee "$log_ts"
    local result=0
    if grep -qi "ORA-" "$log_ts" && ! grep -qiE "ORA-00959|ORA-01918|ORA-00942" "$log_ts"; then
        log_warn "Erros ao dropar tablespaces (ORA-00959 = nao existe, e normal)."
        result=1
    else
        log_ok "Tablespaces dropadas (ou nao existiam)."
    fi
    rm -f "$log_ts"
    return $result
}

# Metodo A: sqlplus local
SQLPLUS_BIN=""
for candidate in \
    /u01/app/oracle/product/*/client*/bin/sqlplus \
    /u01/oracle/db/*/bin/sqlplus \
    /u01/oracle/product/*/client*/bin/sqlplus \
    /opt/oracle/product/*/client*/bin/sqlplus \
    "$(which sqlplus 2>/dev/null)"
do
    [ -x "$candidate" ] && { SQLPLUS_BIN="$candidate"; break; }
done

if [ -n "$SQLPLUS_BIN" ]; then
    log_ok "sqlplus local: $SQLPLUS_BIN"
    executar_ts_sql "\"$SQLPLUS_BIN\" sys/${SYS_PASS}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba"

# Metodo B: SSH para o host do banco (oracle@DB_HOST) e roda sqlplus la
elif ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
         "oracle@${DB_HOST}" "which sqlplus" &>/dev/null; then
    log_ok "SSH para oracle@${DB_HOST} disponivel. Rodando sqlplus remotamente..."
    executar_ts_sql "ssh -o BatchMode=yes oracle@${DB_HOST} \
        'sqlplus sys/${SYS_PASS}@//localhost:${DB_PORT}/${DB_SERVICE} as sysdba'"

# Metodo C: SSH como root para o host do banco
elif ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
         "root@${DB_HOST}" "which sqlplus || find /u01 -name sqlplus -type f 2>/dev/null | head -1" &>/dev/null; then
    REMOTE_SQLPLUS=$(ssh -o BatchMode=yes "root@${DB_HOST}" \
        "which sqlplus 2>/dev/null || find /u01 -name sqlplus -type f 2>/dev/null | head -1")
    log_ok "SSH para root@${DB_HOST} disponivel. sqlplus: ${REMOTE_SQLPLUS}"
    executar_ts_sql "ssh -o BatchMode=yes root@${DB_HOST} \
        '${REMOTE_SQLPLUS} sys/${SYS_PASS}@//localhost:${DB_PORT}/${DB_SERVICE} as sysdba'"

# Fallback: imprimir para execucao manual
else
    log_warn "sqlplus nao encontrado localmente e SSH para ${DB_HOST} nao disponivel."
    log_warn "Execute manualmente no host do banco (${DB_HOST}) como SYSDBA:"
    echo ""
    echo "  sqlplus / as sysdba"
    echo "  ALTER SESSION SET CONTAINER = ${DB_SERVICE%%.*};"
    echo "  WHENEVER SQLERROR CONTINUE;"
    for ts in "${TS_LIST[@]}"; do
        echo "  DROP TABLESPACE ${ts} INCLUDING CONTENTS AND DATAFILES;"
    done
    echo "  EXIT;"
    echo ""
    log_warn "Tablespaces residuais travam o proximo RCU. Confirme com o DBA antes de re-executar."
fi
echo ""

# --- RESUMO -------------------------------------------------------------------

log_step "Resumo"
log_ok "Drop RCU concluido."
log_info "Banco   : ${DB_HOST}:${DB_PORT}/${DB_SERVICE}"
log_info "Prefixo : ${SCHEMA_PREFIX}"
log_info "Tipo    : ${TIPO}"
echo ""
log_info "Verificar com check_pdb_editions.sh se o PDB esta limpo."
if [ "$TIPO" == "wcc" ]; then
    log_info "Proximo passo: re-executar o RCU via menu [5] do INSTALL_WCC_12214.sh"
elif [ "$TIPO" == "odi" ]; then
    log_info "Proximo passo: re-executar o RCU via menu [4] do INSTALL_WLS_12214_COMPOSTO.sh (opcao ODI)"
else
    log_info "Proximo passo: re-executar o RCU via menu [4] do INSTALL_WLS_12214_COMPOSTO.sh"
fi
echo ""
