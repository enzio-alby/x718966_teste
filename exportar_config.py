# -*- coding: utf-8 -*-
#
# exportar_config.py -- Exporta configuracoes de dominio WebLogic para JSON
# Autor: gerado para equipe Getnet/Oraex
# Versao: 1.2  Data: 2026-08-28
#
# Uso:
#   $MW_HOME/oracle_common/common/bin/wlst.sh exportar_config.py
#
# Compatibilidade: Jython 2.2.1 (WLS 12.2.1.4) e superior
#
# Variaveis de ambiente (definidas pelo exportar.sh):
#   WLS_ADMIN_URL           URL AdminServer  [padrao: t3://localhost:7001]
#   WLS_USER                Usuario admin    [padrao: weblogic]
#   WLS_PASS                Senha (se vazio, sera pedida interativamente)
#   WLS_CONFIG_FILE         Arquivo JSON de saida [padrao: config_export.json]
#   WLS_EXPORT_STARTUP      true/false       [padrao: true]
#   WLS_EXPORT_JDBC         true/false       [padrao: true]
#   WLS_EXPORT_JMS_SERVERS  true/false       [padrao: true]
#   WLS_EXPORT_JMS_MODULES  true/false       [padrao: true]

import os
import sys
import re
from java.text import SimpleDateFormat as _SDF
from java.util import Date as _Date


# -----------------------------------------------------------------------------
# Serializador JSON manual -- compativel com Jython 2.2 (sem modulo json)
# -----------------------------------------------------------------------------

def _json_escape_str(s):
    s = s.replace('\\', '\\\\')
    s = s.replace('"',  '\\"')
    s = s.replace('\n', '\\n')
    s = s.replace('\r', '\\r')
    s = s.replace('\t', '\\t')
    return s

def _to_json(obj, nivel):
    pad  = '  ' * nivel
    pad2 = '  ' * (nivel + 1)
    if obj is None:
        return 'null'
    # bool deve vir antes de int (bool e subclasse de int em Python 2)
    if isinstance(obj, bool):
        if obj:
            return 'true'
        return 'false'
    if isinstance(obj, int):
        return str(obj)
    try:
        if isinstance(obj, long):
            return str(obj)
    except NameError:
        pass
    if isinstance(obj, float):
        return str(obj)
    if isinstance(obj, list):
        if not obj:
            return '[]'
        partes = []
        for item in obj:
            partes.append(pad2 + _to_json(item, nivel + 1))
        return '[\n' + ',\n'.join(partes) + '\n' + pad + ']'
    if isinstance(obj, dict):
        if not obj:
            return '{}'
        partes = []
        for k in obj.keys():
            v_json = _to_json(obj[k], nivel + 1)
            partes.append(pad2 + '"' + str(k) + '": ' + v_json)
        return '{\n' + ',\n'.join(partes) + '\n' + pad + '}'
    # string / unicode / java.lang.String -- tudo vira str antes de escapar
    return '"' + _json_escape_str(str(obj)) + '"'

def salvar_json(obj, path):
    conteudo = _to_json(obj, 0) + '\n'
    fh = open(path, 'w')
    try:
        fh.write(conteudo)
    finally:
        fh.close()


# -----------------------------------------------------------------------------
# Utilitarios
# -----------------------------------------------------------------------------

def log(msg):
    print('[wls-export] ' + str(msg))

def env(var, padrao=''):
    val = os.environ.get(var, padrao)
    if val is None or val == '':
        return padrao
    return val

def env_bool(var, padrao=True):
    val = os.environ.get(var, str(padrao)).strip().lower()
    return val not in ('false', '0', 'no', 'nao')

def str_val(val):
    if val is None:
        return None
    s = str(val)
    if s in ('null', 'None', ''):
        return None
    return s

def int_val(val):
    try:
        return int(val)
    except Exception:
        return None

def long_val(val):
    try:
        return long(val)
    except Exception:
        try:
            return int(val)
        except Exception:
            return None

def nomes_targets(targets_array):
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
    if not args_str:
        return None, None, None
    xms  = re.search(r'-Xms(\S+)', args_str)
    xmx  = re.search(r'-Xmx(\S+)', args_str)
    perm = re.search(r'-XX:MaxPermSize[=:](\S+)', args_str)
    if xms:
        xms_val = xms.group(1)
    else:
        xms_val = None
    if xmx:
        xmx_val = xmx.group(1)
    else:
        xmx_val = None
    if perm:
        perm_val = perm.group(1)
    else:
        perm_val = None
    return (xms_val, xmx_val, perm_val)


# -----------------------------------------------------------------------------
# Leitura de senha oculta
# -----------------------------------------------------------------------------

def pedir_senha(usuario):
    try:
        from java.lang import System as JSystem
        console = JSystem.console()
        if console is not None:
            import sys
            sys.stdout.write('\nSenha do WebLogic Console para [%s]: ' % usuario)
            sys.stdout.flush()
            chars = console.readPassword()
            if chars:
                return ''.join([str(c) for c in chars])
    except Exception:
        pass
    log('AVISO: terminal sem suporte a senha oculta -- a senha sera exibida em tela.')
    return raw_input('\nSenha para [%s]: ' % usuario)


# -----------------------------------------------------------------------------
# 9.1 -- Inicializacao de Servidores
# -----------------------------------------------------------------------------

def exportar_startup(config):
    log('Exportando configuracoes de Inicializacao de Servidores...')
    domainConfig()
    servidores_data = []

    try:
        servidores = cmo.getServers()
    except Exception, e:
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
        except Exception, e:
            log('  AVISO: erro ao ler servidor ' + nome + ': ' + str(e))

    config['startup'] = {'servidores': servidores_data}
    log('  Total: ' + str(len(servidores_data)) + ' servidor(es).')


# -----------------------------------------------------------------------------
# 9.2 -- Origens de Dados JDBC
# -----------------------------------------------------------------------------

def exportar_jdbc(config):
    log('Exportando DataSources JDBC...')
    domainConfig()
    datasources_data = []

    try:
        recursos = cmo.getJDBCSystemResources()
    except Exception, e:
        log('ERRO ao listar DataSources: ' + str(e))
        config['jdbc'] = {'data_sources': []}
        return

    for recurso in recursos:
        nome = str(recurso.getName())
        log('  - DataSource: ' + nome)
        try:
            targets  = nomes_targets(recurso.getTargets())
            jdbc_res = recurso.getJDBCResource()

            drv_params = jdbc_res.getJDBCDriverParams()
            url        = str_val(drv_params.getUrl())
            driver     = str_val(drv_params.getDriverName())

            senha_obs = '*** redefinir manualmente no destino ***'

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

            pool       = jdbc_res.getJDBCConnectionPoolParams()
            cap_ini    = int_val(pool.getInitialCapacity())
            cap_min    = int_val(pool.getMinCapacity())
            cap_max    = int_val(pool.getMaxCapacity())
            test_table = str_val(pool.getTestTableName())
            reserve_to = int_val(pool.getConnectionReserveTimeoutSeconds())

            jndi_names = []
            try:
                ds_params = jdbc_res.getJDBCDataSourceParams()
                for j in ds_params.getJNDINames():
                    jndi_names.append(str(j))
            except Exception:
                pass

            datasources_data.append({
                'nome'                      : nome,
                'targets'                   : targets,
                'jndi_names'                : jndi_names,
                'driver'                    : driver,
                'url'                       : url,
                'usuario'                   : usuario_ds,
                'senha'                     : senha_obs,
                'capacidade_inicial'        : cap_ini,
                'capacidade_min'            : cap_min,
                'capacidade_max'            : cap_max,
                'test_table'                : test_table,
                'connection_reserve_timeout': reserve_to
            })
        except Exception, e:
            log('  AVISO: erro ao ler DataSource ' + nome + ': ' + str(e))

    config['jdbc'] = {'data_sources': datasources_data}
    log('  Total: ' + str(len(datasources_data)) + ' DataSource(s).')


# -----------------------------------------------------------------------------
# 9.3 -- JMS Servers
# -----------------------------------------------------------------------------

def exportar_jms_servers(config):
    log('Exportando JMS Servers...')
    domainConfig()
    servers_data = []

    try:
        jms_servers = cmo.getJMSServers()
    except Exception, e:
        log('ERRO ao listar JMS Servers: ' + str(e))
        config['jms_servers'] = {'servidores': []}
        return

    for jms_srv in jms_servers:
        nome = str(jms_srv.getName())
        log('  - JMS Server: ' + nome)
        try:
            targets    = nomes_targets(jms_srv.getTargets())
            store_nome = None
            bytes_max  = None
            msgs_max   = None

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
        except Exception, e:
            log('  AVISO: erro ao ler JMS Server ' + nome + ': ' + str(e))

    config['jms_servers'] = {'servidores': servers_data}
    log('  Total: ' + str(len(servers_data)) + ' JMS Server(s).')


# -----------------------------------------------------------------------------
# 9.4 -- Modulos JMS (System Resources)
# -----------------------------------------------------------------------------

def exportar_jms_modules(config):
    log('Exportando Modulos JMS (System Resources)...')
    domainConfig()
    modulos_data = []

    try:
        recursos = cmo.getJMSSystemResources()
    except Exception, e:
        log('ERRO ao listar JMS System Resources: ' + str(e))
        config['jms_modules'] = {'system_resources': []}
        return

    for recurso in recursos:
        nome = str(recurso.getName())
        log('  - JMS System Resource: ' + nome)
        try:
            targets = nomes_targets(recurso.getTargets())

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
            except Exception, e_cf:
                log('  AVISO CFs em ' + nome + ': ' + str(e_cf))

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
                'nome'                : nome,
                'targets'             : targets,
                'sub_deployments'     : subdeployments,
                'connection_factories': cfs,
                'queues'              : queues,
                'topics'              : topics
            })
        except Exception, e:
            log('  AVISO: erro ao ler JMS Module ' + nome + ': ' + str(e))

    config['jms_modules'] = {'system_resources': modulos_data}
    log('  Total: ' + str(len(modulos_data)) + ' JMS Module(s).')


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def main():
    log('=== WebLogic Config Export ===')

    admin_url       = env('WLS_ADMIN_URL', 't3://localhost:7001')
    usuario         = env('WLS_USER', 'weblogic')
    senha           = os.environ.get('WLS_PASS', None)
    config_file     = env('WLS_CONFIG_FILE', 'config_export.json')
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
    except Exception, e:
        log('ERRO: falha ao conectar. Verifique URL, usuario e senha.')
        log('Detalhe: ' + str(e))
        sys.exit(1)

    log('Conectado com sucesso.')
    domainConfig()
    domain_nome = str(cmo.getName())
    log('Dominio: ' + domain_nome)
    log('')

    config = {
        'timestamp'  : _SDF('yyyyMMdd_HHmmss').format(_Date()),
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
    except Exception, e:
        log('ERRO ao salvar arquivo JSON: ' + str(e))
        disconnect()
        sys.exit(1)

    log('Exportacao concluida com sucesso.')
    log('ATENCAO: senhas de DataSources NAO sao exportadas.')
    log('         Redefina as senhas JDBC manualmente no destino apos importar.')
    disconnect()


main()
