# -*- coding: utf-8 -*-
#
# wlst_config.py -- Exporta ou Importa configuracoes de dominio WebLogic via WLST
# Autor: gerado para equipe Getnet/Oraex
# Versao: 1.3  Data: 2026-09-01
#
# Uso: chamado pelos wrappers exportar.sh e importar.sh (nao executar diretamente)
# Compatibilidade: Jython 2.2.1 (WLS 12.2.1.4) e superior
#
# Variaveis de ambiente comuns:
#   WLS_MODE             export | import           [obrigatorio]
#   WLS_ADMIN_URL        URL AdminServer           [padrao: t3://localhost:7001]
#   WLS_USER             Usuario admin             [padrao: weblogic]
#   WLS_PASS             Senha (se vazio, pedida interativamente)
#   WLS_CONFIG_FILE      Arquivo JSON              [padrao: config_export.json]
#   WLS_EXPORT_STARTUP   true/false startup params [padrao: true]
#   WLS_EXPORT_JDBC      true/false DataSources    [padrao: true]
#   WLS_EXPORT_JMS_SERVERS  true/false             [padrao: true]
#   WLS_EXPORT_JMS_MODULES  true/false             [padrao: true]
#
# Variaveis exclusivas do modo import:
#   WLS_DRY_RUN          true = simular sem aplicar [padrao: false]
#   WLS_DB_OVERRIDE      host:porta/servico para substituir banco em todos DS
#                        ex: qa-db.getnet.local:1521/QAPDB

import os
import sys
import re
from java.text import SimpleDateFormat as _SDF
from java.util import Date as _Date


# -----------------------------------------------------------------------------
# Modo de operacao
# -----------------------------------------------------------------------------

_MODO = os.environ.get('WLS_MODE', 'export').strip().lower()

def log(msg):
    if _MODO == 'import':
        print('[wls-import] ' + str(msg))
    else:
        print('[wls-export] ' + str(msg))


# -----------------------------------------------------------------------------
# Utilitarios compartilhados
# -----------------------------------------------------------------------------

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
    except:
        return None

def long_val(val):
    try:
        return long(val)
    except:
        try:
            return int(val)
        except:
            return None

def nomes_targets(targets_array):
    if targets_array is None:
        return []
    result = []
    for t in targets_array:
        try:
            result.append(str(t.getName()))
        except:
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

def pedir_senha(usuario):
    # readPassword(fmt, args...) exige 0 ou 2+ args no Jython 2.2.1 --
    # imprimir o prompt separadamente resolve sem depender de varargs Java
    try:
        from java.lang import System as JSystem
        console = JSystem.console()
        if console is not None:
            sys.stdout.write('\nSenha do WebLogic Console para [%s]: ' % usuario)
            sys.stdout.flush()
            chars = console.readPassword()
            if chars:
                return ''.join([str(c) for c in chars])
    except:
        pass
    log('AVISO: terminal sem suporte a senha oculta -- sera exibida em tela.')
    return raw_input('\nSenha para [%s]: ' % usuario)


# -----------------------------------------------------------------------------
# JSON -- serializador (export) e leitor (import)
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
    # Jython 2.2.1: bool nao aceita isinstance -- usar identidade
    if obj is True:
        return 'true'
    if obj is False:
        return 'false'
    # Verificar pelo nome do tipo para suportar java.lang.Integer, Long etc
    nome_tipo = type(obj).__name__
    if nome_tipo in ('int', 'Integer'):
        return str(int(obj))
    if nome_tipo in ('long', 'Long'):
        try:
            return str(long(obj))
        except:
            return str(int(obj))
    if nome_tipo in ('float', 'Float', 'Double'):
        return str(float(obj))
    if nome_tipo == 'list' or isinstance(obj, list):
        if not obj:
            return '[]'
        partes = []
        for item in obj:
            partes.append(pad2 + _to_json(item, nivel + 1))
        return '[\n' + ',\n'.join(partes) + '\n' + pad + ']'
    if nome_tipo == 'dict' or isinstance(obj, dict):
        if not obj:
            return '{}'
        partes = []
        for k in obj.keys():
            v_json = _to_json(obj[k], nivel + 1)
            partes.append(pad2 + '"' + str(k) + '": ' + v_json)
        return '{\n' + ',\n'.join(partes) + '\n' + pad + '}'
    return '"' + _json_escape_str(str(obj)) + '"'

def salvar_json(obj, path):
    conteudo = _to_json(obj, 0) + '\n'
    fh = open(path, 'w')
    try:
        fh.write(conteudo)
    finally:
        fh.close()

def _json_para_python(texto):
    t = texto.strip()
    t = re.sub(r'\bnull\b',  'None',  t)
    t = re.sub(r'\btrue\b',  'True',  t)
    t = re.sub(r'\bfalse\b', 'False', t)
    return eval(t)

def ler_json(path):
    fh = open(path, 'r')
    try:
        conteudo = fh.read()
    finally:
        fh.close()
    return _json_para_python(conteudo)


# -----------------------------------------------------------------------------
# Helpers exclusivos do modo import
# -----------------------------------------------------------------------------

def resolver_target(nome_target):
    mbean = getMBean('/Servers/' + nome_target)
    if mbean is not None:
        return mbean
    mbean = getMBean('/Clusters/' + nome_target)
    if mbean is not None:
        return mbean
    mbean = getMBean('/JMSServers/' + nome_target)
    if mbean is not None:
        return mbean
    log('  AVISO: target "' + nome_target + '" nao encontrado (servidor, cluster ou JMS Server).')
    return None

def resolver_targets(lista_nomes):
    result = []
    for n in lista_nomes:
        mb = resolver_target(n)
        if mb is not None:
            result.append(mb)
    return result

def substituir_banco_url(url, novo_banco):
    """Substitui host:porta/servico na URL JDBC pelo banco de destino."""
    if not url or not novo_banco:
        return url
    nova = re.sub(r'(@//)[^?"]+', r'\g<1>' + novo_banco, url)
    if nova != url:
        return nova
    nova = re.sub(r'(@)[^?"]+', r'\g<1>' + novo_banco, url)
    return nova

def parse_db_map(map_str):
    """Parseia 'origem1|destino1;origem2|destino2' em dict."""
    result = {}
    if not map_str:
        return result
    for par in map_str.split(';'):
        par = par.strip()
        if '|' in par:
            partes = par.split('|', 1)
            result[partes[0].strip()] = partes[1].strip()
    return result

def aplicar_db_map(url, db_map):
    """Retorna (url_substituida, destino_aplicado) usando o mapa de bancos."""
    if not url or not db_map:
        return url, None
    for origem, destino in db_map.items():
        if origem in url:
            return substituir_banco_url(url, destino), destino
    return url, None


# -----------------------------------------------------------------------------
# 9.1 / 1 -- Servidores (export e import)
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


def aplicar_args_map(args_str, args_map):
    if not args_str or not args_map:
        return args_str
    result = args_str
    for origem, destino in args_map.items():
        result = result.replace(origem, destino)
    return result


def importar_startup(servidores, dry_run):
    log('Importando configuracoes de Inicializacao de Servidores...')
    if not servidores:
        log('  Nenhum servidor no JSON.')
        return

    args_map_str = (os.environ.get('WLS_ARGS_MAP', '') or '').strip()
    args_map = parse_db_map(args_map_str)
    if args_map:
        log('  Mapeamento de argumentos JVM:')
        for _orig, _dest in args_map.items():
            log('    ' + _orig + '  ->  ' + _dest)

    for srv_data in servidores:
        nome        = srv_data.get('nome', '')
        args        = srv_data.get('arguments')
        java_vendor = srv_data.get('java_vendor')
        java_home   = srv_data.get('java_home')
        classpath   = srv_data.get('classpath')

        if nome.lower() in ('adminserver', 'adminserver_ucm', 'adminserver_soa', 'adminserver_osb'):
            log('  - Servidor: ' + nome + ' [IGNORADO -- AdminServer nao e alterado]')
            continue

        srv_mbean = getMBean('/Servers/' + nome)
        if srv_mbean is None:
            log('  - Servidor: ' + nome + ' [AVISO] Nao existe no destino -- ignorado')
            continue

        args_final = aplicar_args_map(args, args_map)

        if dry_run:
            log('  - Servidor: ' + nome + ' [DRY-RUN] Seria atualizado startup params')
            if args_final:
                log('      arguments: ' + str(args_final))
            continue

        try:
            cd('/Servers/' + nome + '/ServerStart/' + nome)
            if args_final is not None:
                cmo.setArguments(args_final)
            if java_vendor:
                cmo.setJavaVendor(java_vendor)
            if java_home:
                cmo.setJavaHome(java_home)
            if classpath:
                cmo.setClassPath(classpath)
            log('  - Servidor: ' + nome + ' [OK]')
        except Exception, e:
            log('  - Servidor: ' + nome + ' [ERRO] ' + str(e))


# -----------------------------------------------------------------------------
# 9.2 / 2 -- DataSources JDBC (export e import)
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
            usuario_ds = None
            try:
                props_bean = drv_params.getProperties()
                if props_bean is not None:
                    for prop in props_bean.getProperties():
                        if str(prop.getName()).lower() == 'user':
                            usuario_ds = str_val(prop.getValue())
                            break
            except:
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
            except:
                pass
            datasources_data.append({
                'nome'                      : nome,
                'targets'                   : targets,
                'jndi_names'                : jndi_names,
                'driver'                    : driver,
                'url'                       : url,
                'usuario'                   : usuario_ds,
                'senha'                     : '*** redefinir manualmente no destino ***',
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


def _pedir_senha_ds(nome_ds):
    try:
        from java.lang import System as JSystem
        console = JSystem.console()
        if console is not None:
            sys.stdout.write('  Senha para [' + nome_ds + ']: ')
            sys.stdout.flush()
            chars = console.readPassword()
            if chars:
                return ''.join([str(c) for c in chars])
            return ''
    except:
        pass
    return raw_input('  Senha para [' + nome_ds + ']: ')


def importar_jdbc(datasources, dry_run, db_override):
    log('Importando DataSources JDBC...')
    if db_override:
        log('  Banco de destino: ' + db_override + ' (substituindo URLs do JSON)')

    ds_senha_padrao = (os.environ.get('WLS_DS_SENHA', '') or '').strip()
    ds_senha_por_ds = env_bool('WLS_DS_SENHA_POR_DS', False)

    db_map_str = (os.environ.get('WLS_DB_MAP', '') or '').strip()
    db_map = parse_db_map(db_map_str)
    if db_map:
        log('  Mapeamento multi-banco:')
        for _orig, _dest in db_map.items():
            log('    ' + _orig + '  ->  ' + _dest)

    if not dry_run:
        if ds_senha_por_ds:
            log('  Senhas: serao pedidas individualmente por DataSource.')
        elif ds_senha_padrao:
            log('  Senhas: senha unica aplicada em todos os DataSources.')
        else:
            log('  Senhas: em branco -- redefina no console WebLogic apos importar.')

    if not datasources:
        log('  Nenhum DataSource no JSON.')
        return

    for ds in datasources:
        nome       = ds.get('nome', '')
        targets    = ds.get('targets', [])
        jndi_names = ds.get('jndi_names', [])
        driver     = ds.get('driver', '')
        url        = ds.get('url', '')
        usuario    = ds.get('usuario', '')
        cap_ini    = ds.get('capacidade_inicial', 1)
        cap_min    = ds.get('capacidade_min', 1)
        cap_max    = ds.get('capacidade_max', 10)
        test_table = ds.get('test_table', '')
        reserve_to = ds.get('connection_reserve_timeout', 10)

        if db_map:
            url_final, _banco_aplicado = aplicar_db_map(url, db_map)
        elif db_override:
            url_final = substituir_banco_url(url, db_override)
            if url_final != url:
                _banco_aplicado = db_override
            else:
                _banco_aplicado = None
        else:
            url_final = url
            _banco_aplicado = None

        ja_existe = (getMBean('/JDBCSystemResources/' + nome) is not None)

        if dry_run:
            if ja_existe:
                log('  - DataSource: ' + nome + ' [DRY-RUN] Ja existe -- seria ignorado')
            else:
                log('  - DataSource: ' + nome + ' [DRY-RUN] Seria criado')
                log('      driver : ' + str(driver))
                log('      url    : ' + str(url_final))
                if db_override and url_final != url:
                    log('      url orig: ' + str(url) + ' --> substituida')
                if _banco_aplicado:
                    log('      url orig : ' + str(url) + ' -> mapeado')
                log('      usuario: ' + str(usuario))
                log('      targets: ' + str(targets))
                log('      pool   : ini=%s min=%s max=%s' % (cap_ini, cap_min, cap_max))
            continue

        if ja_existe:
            log('  - DataSource: ' + nome + ' [AVISO] Ja existe -- ignorado')
            continue

        try:
            cd('/')
            cmo.createJDBCSystemResource(nome)
            cd('/JDBCSystemResources/' + nome)
            jr = cmo.getJDBCResource()
            jr.setName(nome)

            dp = jr.getJDBCDriverParams()
            dp.setUrl(url_final)
            dp.setDriverName(driver)
            if ds_senha_por_ds:
                senha_ds = _pedir_senha_ds(nome)
            else:
                senha_ds = ds_senha_padrao
            dp.setPassword(senha_ds)

            if usuario:
                pp_props = dp.getProperties()
                pp_props.createProperty('user')
                for p in pp_props.getProperties():
                    if str(p.getName()) == 'user':
                        p.setValue(usuario)
                        break

            pool = jr.getJDBCConnectionPoolParams()
            pool.setInitialCapacity(int(cap_ini or 1))
            pool.setMinCapacity(int(cap_min or 1))
            pool.setMaxCapacity(int(cap_max or 10))
            if test_table:
                pool.setTestTableName(test_table)
            if reserve_to is not None:
                pool.setConnectionReserveTimeoutSeconds(int(reserve_to))

            if jndi_names:
                dsp = jr.getJDBCDataSourceParams()
                from java.lang import String
                dsp.setJNDINames([String(j) for j in jndi_names])

            target_mbeans = resolver_targets(targets)
            if target_mbeans:
                cmo.setTargets(target_mbeans)

            log('  - DataSource: ' + nome + ' [OK] -- REDEFINIR SENHA no console')
        except Exception, e:
            log('  - DataSource: ' + nome + ' [ERRO] ' + str(e))


# -----------------------------------------------------------------------------
# 9.3 / 3 -- JMS Servers (export e import)
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
            except:
                pass
            try:
                bytes_max = long_val(jms_srv.getBytesMaximum())
            except:
                pass
            try:
                msgs_max = long_val(jms_srv.getMessagesMaximum())
            except:
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


def importar_jms_servers(servidores, dry_run):
    log('Importando JMS Servers...')
    if not servidores:
        log('  Nenhum JMS Server no JSON.')
        return

    for srv in servidores:
        nome       = srv.get('nome', '')
        targets    = srv.get('targets', [])
        store_nome = srv.get('persistent_store')
        bytes_max  = srv.get('bytes_maximum')
        msgs_max   = srv.get('messages_maximum')

        ja_existe = (getMBean('/JMSServers/' + nome) is not None)

        if dry_run:
            if ja_existe:
                log('  - JMS Server: ' + nome + ' [DRY-RUN] Ja existe -- seria ignorado')
            else:
                log('  - JMS Server: ' + nome + ' [DRY-RUN] Seria criado')
                log('      targets         : ' + str(targets))
                log('      persistent_store: ' + str(store_nome))
                log('      bytes_maximum   : ' + str(bytes_max))
            continue

        if ja_existe:
            log('  - JMS Server: ' + nome + ' [AVISO] Ja existe -- ignorado')
            continue

        try:
            cd('/')
            cmo.createJMSServer(nome)
            cd('/JMSServers/' + nome)
            if bytes_max is not None:
                try:
                    cmo.setBytesMaximum(long(bytes_max))
                except:
                    pass
            if msgs_max is not None:
                try:
                    cmo.setMessagesMaximum(long(msgs_max))
                except:
                    pass
            if store_nome:
                store_mbean = getMBean('/FileStores/' + store_nome)
                if store_mbean is None:
                    store_mbean = getMBean('/JDBCStores/' + store_nome)
                if store_mbean is not None:
                    cmo.setPersistentStore(store_mbean)
                else:
                    log('    AVISO: persistent store "' + store_nome + '" nao encontrado')
            target_mbeans = resolver_targets(targets)
            if target_mbeans:
                cmo.setTargets(target_mbeans)
            log('  - JMS Server: ' + nome + ' [OK]')
        except Exception, e:
            log('  - JMS Server: ' + nome + ' [ERRO] ' + str(e))


# -----------------------------------------------------------------------------
# 9.4 / 4 -- JMS Modules (export e import)
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
            except:
                pass

            # Lista de nomes validos de SubDeployments -- usada para validar CFs/queues/topics.
            # getSubDeploymentName() nas CFs pode retornar o nome da propria CF em dominios
            # onde o campo nao foi preenchido corretamente; nesse caso substituimos pelo
            # unico SubDeployment existente (comportamento identico ao do console WebLogic).
            sub_nomes_validos = [s['nome'] for s in subdeployments]

            jms_res = recurso.getJMSResource()
            cfs = []
            try:
                for cf in jms_res.getConnectionFactories():
                    jndi_cf = str_val(cf.getJNDIName())
                    sub_dep = str_val(cf.getSubDeploymentName())
                    if sub_dep is not None and sub_nomes_validos and sub_dep not in sub_nomes_validos:
                        if len(sub_nomes_validos) == 1:
                            sub_dep = sub_nomes_validos[0]
                        else:
                            sub_dep = None
                    tx_timeout = None
                    deliv_mode = None
                    try:
                        tx_timeout = int_val(cf.getTransactionTimeout())
                    except:
                        pass
                    try:
                        dd = cf.getDefaultDeliveryParams()
                        if dd is not None:
                            deliv_mode = str_val(dd.getDefaultDeliveryMode())
                    except:
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
                    q_sub = str_val(q.getSubDeploymentName())
                    if q_sub is not None and sub_nomes_validos and q_sub not in sub_nomes_validos:
                        if len(sub_nomes_validos) == 1:
                            q_sub = sub_nomes_validos[0]
                        else:
                            q_sub = None
                    queues.append({
                        'nome'          : str(q.getName()),
                        'jndi'          : str_val(q.getJNDIName()),
                        'sub_deployment': q_sub,
                        'tipo'          : 'queue'
                    })
            except:
                pass
            try:
                for q in jms_res.getDistributedQueues():
                    q_sub = str_val(q.getSubDeploymentName())
                    if q_sub is not None and sub_nomes_validos and q_sub not in sub_nomes_validos:
                        if len(sub_nomes_validos) == 1:
                            q_sub = sub_nomes_validos[0]
                        else:
                            q_sub = None
                    queues.append({
                        'nome'          : str(q.getName()),
                        'jndi'          : str_val(q.getJNDIName()),
                        'sub_deployment': q_sub,
                        'tipo'          : 'distributed_queue'
                    })
            except:
                pass
            topics = []
            try:
                for t in jms_res.getTopics():
                    t_sub = str_val(t.getSubDeploymentName())
                    if t_sub is not None and sub_nomes_validos and t_sub not in sub_nomes_validos:
                        if len(sub_nomes_validos) == 1:
                            t_sub = sub_nomes_validos[0]
                        else:
                            t_sub = None
                    topics.append({
                        'nome'          : str(t.getName()),
                        'jndi'          : str_val(t.getJNDIName()),
                        'sub_deployment': t_sub,
                        'tipo'          : 'topic'
                    })
            except:
                pass
            try:
                for t in jms_res.getDistributedTopics():
                    t_sub = str_val(t.getSubDeploymentName())
                    if t_sub is not None and sub_nomes_validos and t_sub not in sub_nomes_validos:
                        if len(sub_nomes_validos) == 1:
                            t_sub = sub_nomes_validos[0]
                        else:
                            t_sub = None
                    topics.append({
                        'nome'          : str(t.getName()),
                        'jndi'          : str_val(t.getJNDIName()),
                        'sub_deployment': t_sub,
                        'tipo'          : 'distributed_topic'
                    })
            except:
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


def importar_jms_modules(modulos, dry_run):
    log('Importando Modulos JMS (System Resources)...')
    if not modulos:
        log('  Nenhum JMS Module no JSON.')
        return

    for mod in modulos:
        nome           = mod.get('nome', '')
        targets        = mod.get('targets', [])
        subdeployments = mod.get('sub_deployments', [])
        cfs            = mod.get('connection_factories', [])
        queues         = mod.get('queues', [])
        topics         = mod.get('topics', [])

        ja_existe = (getMBean('/JMSSystemResources/' + nome) is not None)

        if dry_run:
            if ja_existe:
                log('  - JMS Module: ' + nome + ' [DRY-RUN] Ja existe -- seria ignorado')
            else:
                log('  - JMS Module: ' + nome + ' [DRY-RUN] Seria criado')
                log('      targets             : ' + str(targets))
                log('      sub_deployments     : ' + str([s['nome'] for s in subdeployments]))
                log('      connection_factories: ' + str([c['nome'] for c in cfs]))
                log('      queues              : ' + str([q['nome'] for q in queues]))
                log('      topics              : ' + str([t['nome'] for t in topics]))
            continue

        if ja_existe:
            log('  - JMS Module: ' + nome + ' [AVISO] Ja existe -- ignorado')
            continue

        try:
            cd('/')
            cmo.createJMSSystemResource(nome)
            cd('/JMSSystemResources/' + nome)
            target_mbeans = resolver_targets(targets)
            if target_mbeans:
                cmo.setTargets(target_mbeans)
            for sub in subdeployments:
                sub_nome = sub.get('nome', '')
                cd('/JMSSystemResources/' + nome)
                cmo.createSubDeployment(sub_nome)
                cd('/JMSSystemResources/%s/SubDeployments/%s' % (nome, sub_nome))
                sub_targets = resolver_targets(sub.get('targets', []))
                if sub_targets:
                    cmo.setTargets(sub_targets)
            for cf_data in cfs:
                cf_nome = cf_data.get('nome', '')
                try:
                    cd('/JMSSystemResources/%s/JMSResource/%s' % (nome, nome))
                    cmo.createConnectionFactory(cf_nome)
                    cd('/JMSSystemResources/%s/JMSResource/%s/ConnectionFactories/%s' % (nome, nome, cf_nome))
                    if cf_data.get('jndi'):
                        cmo.setJNDIName(cf_data['jndi'])
                    if cf_data.get('sub_deployment'):
                        cmo.setSubDeploymentName(cf_data['sub_deployment'])
                    if cf_data.get('transaction_timeout') is not None:
                        cmo.setTransactionTimeout(int(cf_data['transaction_timeout']))
                    if cf_data.get('default_delivery_mode'):
                        try:
                            dd = cmo.getDefaultDeliveryParams()
                            if dd is not None:
                                dd.setDefaultDeliveryMode(cf_data['default_delivery_mode'])
                        except:
                            pass
                except Exception, e_cf:
                    log('    AVISO CF ' + cf_nome + ': ' + str(e_cf))
            for q_data in queues:
                q_nome = q_data.get('nome', '')
                try:
                    cd('/JMSSystemResources/%s/JMSResource/%s' % (nome, nome))
                    if q_data.get('tipo') == 'distributed_queue':
                        cmo.createDistributedQueue(q_nome)
                        cd('/JMSSystemResources/%s/JMSResource/%s/DistributedQueues/%s' % (nome, nome, q_nome))
                    else:
                        cmo.createQueue(q_nome)
                        cd('/JMSSystemResources/%s/JMSResource/%s/Queues/%s' % (nome, nome, q_nome))
                    if q_data.get('jndi'):
                        cmo.setJNDIName(q_data['jndi'])
                    if q_data.get('sub_deployment'):
                        cmo.setSubDeploymentName(q_data['sub_deployment'])
                except Exception, e_q:
                    log('    AVISO Queue ' + q_nome + ': ' + str(e_q))
            for t_data in topics:
                t_nome = t_data.get('nome', '')
                try:
                    cd('/JMSSystemResources/%s/JMSResource/%s' % (nome, nome))
                    if t_data.get('tipo') == 'distributed_topic':
                        cmo.createDistributedTopic(t_nome)
                        cd('/JMSSystemResources/%s/JMSResource/%s/DistributedTopics/%s' % (nome, nome, t_nome))
                    else:
                        cmo.createTopic(t_nome)
                        cd('/JMSSystemResources/%s/JMSResource/%s/Topics/%s' % (nome, nome, t_nome))
                    if t_data.get('jndi'):
                        cmo.setJNDIName(t_data['jndi'])
                    if t_data.get('sub_deployment'):
                        cmo.setSubDeploymentName(t_data['sub_deployment'])
                except Exception, e_t:
                    log('    AVISO Topic ' + t_nome + ': ' + str(e_t))
            log('  - JMS Module: ' + nome + ' [OK]')
        except Exception, e:
            log('  - JMS Module: ' + nome + ' [ERRO] ' + str(e))


# -----------------------------------------------------------------------------
# Main Export
# -----------------------------------------------------------------------------

def main_export():
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


# -----------------------------------------------------------------------------
# Main Import
# -----------------------------------------------------------------------------

def main_import():
    log('=== WebLogic Config Import ===')

    admin_url       = env('WLS_ADMIN_URL', 't3://localhost:7001')
    usuario         = env('WLS_USER', 'weblogic')
    senha           = os.environ.get('WLS_PASS', None)
    config_file     = env('WLS_CONFIG_FILE', 'config_export.json')
    imp_startup     = env_bool('WLS_EXPORT_STARTUP', True)
    imp_jdbc        = env_bool('WLS_EXPORT_JDBC', True)
    imp_jms_servers = env_bool('WLS_EXPORT_JMS_SERVERS', True)
    imp_jms_modules = env_bool('WLS_EXPORT_JMS_MODULES', True)
    dry_run         = env_bool('WLS_DRY_RUN', False)
    db_override     = os.environ.get('WLS_DB_OVERRIDE', '') or ''
    db_override     = db_override.strip()

    log('URL destino : ' + admin_url)
    log('Usuario     : ' + usuario)
    log('Arquivo     : ' + config_file)
    if db_override:
        log('Banco dest. : ' + db_override)
    if dry_run:
        log('MODO        : DRY-RUN -- nenhuma alteracao sera aplicada')
    else:
        log('MODO        : REAL -- alteracoes serao aplicadas')
    log('')

    if not os.path.exists(config_file):
        log('ERRO: arquivo nao encontrado: ' + config_file)
        sys.exit(1)

    try:
        config = ler_json(config_file)
    except Exception, e:
        log('ERRO ao ler JSON: ' + str(e))
        sys.exit(1)

    log('Arquivo carregado:')
    log('  Origem    : ' + str(config.get('source_url', '?')))
    log('  Dominio   : ' + str(config.get('domain', '?')))
    log('  Timestamp : ' + str(config.get('timestamp', '?')))
    log('')

    if not senha:
        senha = pedir_senha(usuario)

    log('Conectando em ' + admin_url + ' ...')
    try:
        connect(usuario, senha, admin_url)
    except Exception, e:
        log('ERRO: falha ao conectar.')
        log('Detalhe: ' + str(e))
        sys.exit(1)
    log('Conectado com sucesso.')
    log('')

    if not dry_run:
        try:
            edit()
            startEdit()
        except Exception, e:
            log('ERRO ao iniciar edicao: ' + str(e))
            disconnect()
            sys.exit(1)

    try:
        if imp_startup:
            importar_startup(config.get('startup', {}).get('servidores', []), dry_run)
        else:
            log('Startup: IGNORADO')

        if imp_jdbc:
            importar_jdbc(config.get('jdbc', {}).get('data_sources', []), dry_run, db_override)
        else:
            log('JDBC: IGNORADO')

        if imp_jms_servers:
            importar_jms_servers(config.get('jms_servers', {}).get('servidores', []), dry_run)
        else:
            log('JMS Servers: IGNORADO')

        if imp_jms_modules:
            importar_jms_modules(config.get('jms_modules', {}).get('system_resources', []), dry_run)
        else:
            log('JMS Modules: IGNORADO')

    except Exception, e_geral:
        log('ERRO inesperado: ' + str(e_geral))
        if not dry_run:
            try:
                cancelEdit('y')
                log('Edicao cancelada (rollback).')
            except:
                pass
        disconnect()
        sys.exit(1)

    if dry_run:
        log('')
        log('DRY-RUN concluido. Nenhuma alteracao foi aplicada.')
    else:
        try:
            activate()
            log('')
            log('Importacao concluida e ativada com sucesso.')
            log('')
            log('PROXIMOS PASSOS OBRIGATORIOS:')
            log('  1. Console WebLogic > Services > Data Sources')
            log('  2. Redefina a senha de cada DataSource importado')
            log('  3. Teste as conexoes (botao Test)')
            log('  4. Reinicie Managed Servers se startup params foram alterados')
        except Exception, e:
            log('ERRO ao ativar: ' + str(e))
            try:
                cancelEdit('y')
                log('Rollback executado.')
            except:
                pass
            disconnect()
            sys.exit(1)

    disconnect()


# -----------------------------------------------------------------------------
# Dispatch por WLS_MODE
# -----------------------------------------------------------------------------

if _MODO == 'import':
    main_import()
else:
    main_export()
