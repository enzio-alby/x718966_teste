# -*- coding: utf-8 -*-
#
# exportar_config.py — Exporta configuracoes de dominio WebLogic para JSON
# Autor: gerado para equipe Getnet/Oraex
# Versao: 1.0  Data: 2026-08-27
#
# Uso:
#   $MW_HOME/oracle_common/common/bin/wlst.sh exportar_config.py
#
# Variaveis de ambiente:
#   WLS_ADMIN_URL       URL AdminServer  ex: t3://host:7001   [padrao: t3://localhost:7001]
#   WLS_USER            Usuario admin                          [padrao: weblogic]
#   WLS_PASS            Senha (se vazio, sera pedida)
#   WLS_CONFIG_FILE     Arquivo JSON de saida                  [padrao: config_export.json]
#   WLS_EXPORT_STARTUP  true/false exportar startup servers    [padrao: true]
#   WLS_EXPORT_JDBC     true/false exportar DataSources JDBC   [padrao: true]
#   WLS_EXPORT_JMS_SERVERS  true/false exportar JMS Servers    [padrao: true]
#   WLS_EXPORT_JMS_MODULES  true/false exportar JMS Modules    [padrao: true]

import os
import sys
import re
import datetime

# ─────────────────────────────────────────────────────────────────────────────
# JSON — compativel com Jython 2.5+ (WLS 12c) e Jython 2.7 (WLS 14c)
# ─────────────────────────────────────────────────────────────────────────────
try:
    import json
    def salvar_json(obj, path):
        with open(path, 'w') as fh:
            json.dump(obj, fh, indent=2, ensure_ascii=False)
except ImportError:
    raise SystemExit('[wls-export] ERRO: modulo json nao encontrado. Requer Jython 2.5+')


# ─────────────────────────────────────────────────────────────────────────────
# Utilitarios
# ─────────────────────────────────────────────────────────────────────────────

def log(msg):
    print('[wls-export] ' + str(msg))

def env(var, padrao=''):
    return os.environ.get(var, padrao) or padrao

def env_bool(var, padrao=True):
    val = os.environ.get(var, str(padrao)).strip().lower()
    return val not in ('false', '0', 'no', 'nao')

def str_val(val):
    """Converte valor Java/Jython para string Python ou None."""
    if val is None:
        return None
    s = str(val)
    return s if s not in ('null', 'None', '') else None

def int_val(val):
    """Converte para int ou None."""
    try:
        v = int(val)
        return v
    except Exception:
        return None

def long_val(val):
    """Converte para long ou None (campos de bytes/messages)."""
    try:
        return long(val)
    except Exception:
        try:
            return int(val)
        except Exception:
            return None

def nomes_targets(targets_array):
    """Retorna lista de nomes de targets a partir de array de MBeans."""
    if targets_array is None:
        return []
    result = []
    for t in targets_array:
        try:
            result.append(str(t.getName()))
        except Exception:
            result.append(str(t))
    return result

def extrair_heap(args_str):
    """
    Extrai -Xms, -Xmx e -XX:MaxPermSize dos argumentos JVM.
    Retorna (xms, xmx, perm) — cada um pode ser None.
    """
    if not args_str:
        return None, None, None
    xms  = re.search(r'-Xms(\S+)', args_str)
    xmx  = re.search(r'-Xmx(\S+)', args_str)
    perm = re.search(r'-XX:MaxPermSize[=:](\S+)', args_str)
    return (
        xms.group(1)  if xms  else None,
        xmx.group(1)  if xmx  else None,
        perm.group(1) if perm else None
    )


# ─────────────────────────────────────────────────────────────────────────────
# Leitura de senha (oculta via java.lang.System.console quando disponivel)
# ─────────────────────────────────────────────────────────────────────────────

def pedir_senha(usuario):
    try:
        from java.lang import System as JSystem
        console = JSystem.console()
        if console is not None:
            chars = console.readPassword('\nSenha do WebLogic Console para [%s]: ' % usuario)
            if chars:
                return ''.join([str(c) for c in chars])
    except Exception:
        pass
    # Fallback: raw_input (senha fica visivel — aceitavel em HML)
    log('AVISO: terminal sem suporte a senha oculta — a senha sera exibida em tela.')
    return raw_input('\nSenha para [%s]: ' % usuario)


# ─────────────────────────────────────────────────────────────────────────────
# 9.1 — Inicializacao de Servidores
# ─────────────────────────────────────────────────────────────────────────────

def exportar_startup(config):
    log('Exportando configuracoes de Inicializacao de Servidores...')
    domainConfig()
    servidores_data = []

    try:
        servidores = cmo.getServers()
    except Exception as e:
        log('ERRO ao listar servidores: ' + str(e))
        config['startup'] = {'servidores': []}
        return

    for srv in servidores:
        nome = str(srv.getName())
        log('  - Servidor: ' + nome)
        try:
            porta    = int_val(srv.getListenPort())
            endereco = str_val(srv.getListenAddress())

            args        = None
            java_vendor = None
            java_home   = None
            classpath   = None

            startup = srv.getServerStart()
            if startup is not None:
                args        = str_val(startup.getArguments())
                java_vendor = str_val(startup.getJavaVendor())
                java_home   = str_val(startup.getJavaHome())
                classpath   = str_val(startup.getClassPath())

            xms, xmx, perm = extrair_heap(args)

            servidores_data.append({
                'nome'          : nome,
                'listen_port'   : porta,
                'listen_address': endereco,
                'java_vendor'   : java_vendor,
                'java_home'     : java_home,
                'classpath'     : classpath,
                'arguments'     : args,
                'min_heap'      : xms,
                'max_heap'      : xmx,
                'max_perm_size' : perm
            })
        except Exception as e:
            log('  AVISO: erro ao ler servidor ' + nome + ': ' + str(e))

    config['startup'] = {'servidores': servidores_data}
    log('  Total: ' + str(len(servidores_data)) + ' servidor(es).')


# ─────────────────────────────────────────────────────────────────────────────
# 9.2 — Origens de Dados JDBC
# ─────────────────────────────────────────────────────────────────────────────

def exportar_jdbc(config):
    log('Exportando DataSources JDBC...')
    domainConfig()
    datasources_data = []

    try:
        recursos = cmo.getJDBCSystemResources()
    except Exception as e:
        log('ERRO ao listar DataSources: ' + str(e))
        config['jdbc'] = {'data_sources': []}
        return

    for recurso in recursos:
        nome = str(recurso.getName())
        log('  - DataSource: ' + nome)
        try:
            targets   = nomes_targets(recurso.getTargets())
            jdbc_res  = recurso.getJDBCResource()

            # Driver
            drv_params = jdbc_res.getJDBCDriverParams()
            url        = str_val(drv_params.getUrl())
            driver     = str_val(drv_params.getDriverName())

            # Senha: exportada como indicador — DEVE ser redefinida no destino
            # (criptografia e especifica do dominio de origem)
            senha_obs = '*** redefinir manualmente no destino ***'

            # Propriedades — busca usuario
            usuario_ds = None
            try:
                props_bean = drv_params.getProperties()
                if props_bean is not None:
                    for prop in props_bean.getProperties():
                        if str(prop.getName()).lower() == 'user':
                            usuario_ds = str_val(prop.getValue())
                            break
            except Exception:
                pass

            # Pool
            pool       = jdbc_res.getJDBCConnectionPoolParams()
            cap_ini    = int_val(pool.getInitialCapacity())
            cap_min    = int_val(pool.getMinCapacity())
            cap_max    = int_val(pool.getMaxCapacity())
            test_table = str_val(pool.getTestTableName())
            reserve_to = int_val(pool.getConnectionReserveTimeoutSeconds())

            # JNDI
            jndi_names = []
            try:
                ds_params = jdbc_res.getJDBCDataSourceParams()
                for j in ds_params.getJNDINames():
                    jndi_names.append(str(j))
            except Exception:
                pass

            datasources_data.append({
                'nome'                    : nome,
                'targets'                 : targets,
                'jndi_names'              : jndi_names,
                'driver'                  : driver,
                'url'                     : url,
                'usuario'                 : usuario_ds,
                'senha'                   : senha_obs,
                'capacidade_inicial'      : cap_ini,
                'capacidade_min'          : cap_min,
                'capacidade_max'          : cap_max,
                'test_table'              : test_table,
                'connection_reserve_timeout': reserve_to
            })
        except Exception as e:
            log('  AVISO: erro ao ler DataSource ' + nome + ': ' + str(e))

    config['jdbc'] = {'data_sources': datasources_data}
    log('  Total: ' + str(len(datasources_data)) + ' DataSource(s).')


# ─────────────────────────────────────────────────────────────────────────────
# 9.3 — JMS Servers
# ─────────────────────────────────────────────────────────────────────────────

def exportar_jms_servers(config):
    log('Exportando JMS Servers...')
    domainConfig()
    servers_data = []

    try:
        jms_servers = cmo.getJMSServers()
    except Exception as e:
        log('ERRO ao listar JMS Servers: ' + str(e))
        config['jms_servers'] = {'servidores': []}
        return

    for jms_srv in jms_servers:
        nome = str(jms_srv.getName())
        log('  - JMS Server: ' + nome)
        try:
            targets     = nomes_targets(jms_srv.getTargets())
            store_nome  = None
            bytes_max   = None
            msgs_max    = None

            try:
                store = jms_srv.getPersistentStore()
                if store is not None:
                    store_nome = str(store.getName())
            except Exception:
                pass

            try:
                bytes_max = long_val(jms_srv.getBytesMaximum())
            except Exception:
                pass

            try:
                msgs_max = long_val(jms_srv.getMessagesMaximum())
            except Exception:
                pass

            servers_data.append({
                'nome'            : nome,
                'targets'         : targets,
                'persistent_store': store_nome,
                'bytes_maximum'   : bytes_max,
                'messages_maximum': msgs_max
            })
        except Exception as e:
            log('  AVISO: erro ao ler JMS Server ' + nome + ': ' + str(e))

    config['jms_servers'] = {'servidores': servers_data}
    log('  Total: ' + str(len(servers_data)) + ' JMS Server(s).')


# ─────────────────────────────────────────────────────────────────────────────
# 9.4 — Modulos JMS (System Resources)
# ─────────────────────────────────────────────────────────────────────────────

def exportar_jms_modules(config):
    log('Exportando Modulos JMS (System Resources)...')
    domainConfig()
    modulos_data = []

    try:
        recursos = cmo.getJMSSystemResources()
    except Exception as e:
        log('ERRO ao listar JMS System Resources: ' + str(e))
        config['jms_modules'] = {'system_resources': []}
        return

    for recurso in recursos:
        nome = str(recurso.getName())
        log('  - JMS System Resource: ' + nome)
        try:
            targets = nomes_targets(recurso.getTargets())

            # SubDeployments
            subdeployments = []
            try:
                for sub in recurso.getSubDeployments():
                    sub_targets = nomes_targets(sub.getTargets())
                    subdeployments.append({
                        'nome'   : str(sub.getName()),
                        'targets': sub_targets
                    })
            except Exception:
                pass

            jms_res = recurso.getJMSResource()

            # Connection Factories
            cfs = []
            try:
                for cf in jms_res.getConnectionFactories():
                    jndi_cf    = str_val(cf.getJNDIName())
                    sub_dep    = str_val(cf.getSubDeploymentName())
                    tx_timeout = None
                    deliv_mode = None
                    try:
                        tx_timeout = int_val(cf.getTransactionTimeout())
                    except Exception:
                        pass
                    try:
                        dd = cf.getDefaultDeliveryParams()
                        if dd is not None:
                            deliv_mode = str_val(dd.getDefaultDeliveryMode())
                    except Exception:
                        pass
                    cfs.append({
                        'nome'                 : str(cf.getName()),
                        'jndi'                 : jndi_cf,
                        'sub_deployment'       : sub_dep,
                        'transaction_timeout'  : tx_timeout,
                        'default_delivery_mode': deliv_mode
                    })
            except Exception as e_cf:
                log('  AVISO CFs em ' + nome + ': ' + str(e_cf))

            # Queues (simples e distribuidas)
            queues = []
            try:
                for q in jms_res.getQueues():
                    queues.append({
                        'nome'          : str(q.getName()),
                        'jndi'          : str_val(q.getJNDIName()),
                        'sub_deployment': str_val(q.getSubDeploymentName()),
                        'tipo'          : 'queue'
                    })
            except Exception:
                pass
            try:
                for q in jms_res.getDistributedQueues():
                    queues.append({
                        'nome'          : str(q.getName()),
                        'jndi'          : str_val(q.getJNDIName()),
                        'sub_deployment': str_val(q.getSubDeploymentName()),
                        'tipo'          : 'distributed_queue'
                    })
            except Exception:
                pass

            # Topics (simples e distribuidos)
            topics = []
            try:
                for t in jms_res.getTopics():
                    topics.append({
                        'nome'          : str(t.getName()),
                        'jndi'          : str_val(t.getJNDIName()),
                        'sub_deployment': str_val(t.getSubDeploymentName()),
                        'tipo'          : 'topic'
                    })
            except Exception:
                pass
            try:
                for t in jms_res.getDistributedTopics():
                    topics.append({
                        'nome'          : str(t.getName()),
                        'jndi'          : str_val(t.getJNDIName()),
                        'sub_deployment': str_val(t.getSubDeploymentName()),
                        'tipo'          : 'distributed_topic'
                    })
            except Exception:
                pass

            modulos_data.append({
                'nome'               : nome,
                'targets'            : targets,
                'sub_deployments'    : subdeployments,
                'connection_factories': cfs,
                'queues'             : queues,
                'topics'             : topics
            })
        except Exception as e:
            log('  AVISO: erro ao ler JMS Module ' + nome + ': ' + str(e))

    config['jms_modules'] = {'system_resources': modulos_data}
    log('  Total: ' + str(len(modulos_data)) + ' JMS Module(s).')


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    log('=== WebLogic Config Export ===')

    admin_url   = env('WLS_ADMIN_URL', 't3://localhost:7001')
    usuario     = env('WLS_USER', 'weblogic')
    senha       = os.environ.get('WLS_PASS', None)
    config_file = env('WLS_CONFIG_FILE', 'config_export.json')
    exp_startup     = env_bool('WLS_EXPORT_STARTUP', True)
    exp_jdbc        = env_bool('WLS_EXPORT_JDBC', True)
    exp_jms_servers = env_bool('WLS_EXPORT_JMS_SERVERS', True)
    exp_jms_modules = env_bool('WLS_EXPORT_JMS_MODULES', True)

    log('URL AdminServer : ' + admin_url)
    log('Usuario         : ' + usuario)
    log('Arquivo saida   : ' + config_file)
    log('')

    if not senha:
        senha = pedir_senha(usuario)

    log('Conectando em ' + admin_url + ' ...')
    try:
        connect(usuario, senha, admin_url)
    except Exception as e:
        log('ERRO: falha ao conectar. Verifique URL, usuario e senha.')
        log('Detalhe: ' + str(e))
        sys.exit(1)

    log('Conectado com sucesso.')
    domainConfig()
    domain_nome = str(cmo.getName())
    log('Dominio: ' + domain_nome)
    log('')

    config = {
        'timestamp'  : datetime.datetime.now().strftime('%Y%m%d_%H%M%S'),
        'source_url' : admin_url,
        'domain'     : domain_nome
    }

    if exp_startup:
        exportar_startup(config)
    else:
        log('Startup de servidores: IGNORADO (WLS_EXPORT_STARTUP=false)')

    if exp_jdbc:
        exportar_jdbc(config)
    else:
        log('DataSources JDBC: IGNORADO (WLS_EXPORT_JDBC=false)')

    if exp_jms_servers:
        exportar_jms_servers(config)
    else:
        log('JMS Servers: IGNORADO (WLS_EXPORT_JMS_SERVERS=false)')

    if exp_jms_modules:
        exportar_jms_modules(config)
    else:
        log('JMS Modules: IGNORADO (WLS_EXPORT_JMS_MODULES=false)')

    log('')
    log('Salvando em: ' + config_file)
    try:
        salvar_json(config, config_file)
    except Exception as e:
        log('ERRO ao salvar arquivo JSON: ' + str(e))
        disconnect()
        sys.exit(1)

    log('Exportacao concluida com sucesso.')
    log('ATENCAO: senhas de DataSources NAO sao exportadas em texto claro.')
    log('         Redefina as senhas JDBC manualmente no destino apos importar.')
    disconnect()


main()
