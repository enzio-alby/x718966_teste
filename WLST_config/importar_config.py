# -*- coding: utf-8 -*-
#
# importar_config.py — Importa configuracoes de dominio WebLogic a partir de JSON
# Autor: gerado para equipe Getnet/Oraex
# Versao: 1.0  Data: 2026-08-27
#
# Uso:
#   $MW_HOME/oracle_common/common/bin/wlst.sh importar_config.py
#
# Variaveis de ambiente:
#   WLS_ADMIN_URL       URL AdminServer destino  ex: t3://host:7001  [padrao: t3://localhost:7001]
#   WLS_USER            Usuario admin                                  [padrao: weblogic]
#   WLS_PASS            Senha (se vazio, sera pedida)
#   WLS_CONFIG_FILE     Arquivo JSON gerado pelo exportar_config.py   [padrao: config_export.json]
#   WLS_EXPORT_STARTUP  true/false importar startup servers            [padrao: true]
#   WLS_EXPORT_JDBC     true/false importar DataSources JDBC           [padrao: true]
#   WLS_EXPORT_JMS_SERVERS  true/false importar JMS Servers            [padrao: true]
#   WLS_EXPORT_JMS_MODULES  true/false importar JMS Modules            [padrao: true]
#   WLS_DRY_RUN         true = simular sem aplicar alteracoes          [padrao: false]
#
# ATENCAO: senhas de DataSources sao especificas do dominio de origem.
#          O script cria o DataSource com senha em branco — redefina manualmente.

import os
import sys
import datetime

# ─────────────────────────────────────────────────────────────────────────────
# JSON
# ─────────────────────────────────────────────────────────────────────────────
try:
    import json
    def ler_json(path):
        with open(path, 'r') as fh:
            return json.load(fh)
except ImportError:
    raise SystemExit('[wls-import] ERRO: modulo json nao encontrado. Requer Jython 2.5+')


# ─────────────────────────────────────────────────────────────────────────────
# Utilitarios
# ─────────────────────────────────────────────────────────────────────────────

def log(msg):
    print('[wls-import] ' + str(msg))

def env(var, padrao=''):
    return os.environ.get(var, padrao) or padrao

def env_bool(var, padrao=False):
    val = os.environ.get(var, str(padrao)).strip().lower()
    return val not in ('false', '0', 'no', 'nao')

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
    log('AVISO: terminal sem suporte a senha oculta — a senha sera exibida em tela.')
    return raw_input('\nSenha para [%s]: ' % usuario)

def resolver_target(nome_target):
    """Tenta resolver target como Server, depois como Cluster."""
    mbean = getMBean('/Servers/' + nome_target)
    if mbean is not None:
        return mbean
    mbean = getMBean('/Clusters/' + nome_target)
    if mbean is not None:
        return mbean
    log('  AVISO: target "' + nome_target + '" nao encontrado (servidor nem cluster).')
    return None

def resolver_targets(lista_nomes):
    """Retorna lista de MBeans de targets a partir de lista de nomes."""
    result = []
    for n in lista_nomes:
        mb = resolver_target(n)
        if mb is not None:
            result.append(mb)
    return result


# ─────────────────────────────────────────────────────────────────────────────
# 1 — Startup de Servidores
# Atualiza parametros JVM de servidores JA existentes no dominio destino.
# Nao cria servidores novos.
# ─────────────────────────────────────────────────────────────────────────────

def importar_startup(servidores, dry_run):
    log('Importando configuracoes de Inicializacao de Servidores...')
    if not servidores:
        log('  Nenhum servidor no JSON.')
        return

    for srv_data in servidores:
        nome = srv_data.get('nome', '')
        args = srv_data.get('arguments')
        java_vendor = srv_data.get('java_vendor')
        java_home   = srv_data.get('java_home')
        classpath   = srv_data.get('classpath')

        # Nao atualizar AdminServer por seguranca — apenas Managed Servers
        # (AdminServer geralmente tem configuracoes proprias do dominio)
        if nome.lower() in ('adminserver',):
            log('  - Servidor: ' + nome + ' [IGNORADO — AdminServer nao e alterado]')
            continue

        srv_mbean = getMBean('/Servers/' + nome)
        if srv_mbean is None:
            log('  - Servidor: ' + nome + ' [AVISO: nao existe no destino — ignorado]')
            continue

        if dry_run:
            log('  - Servidor: ' + nome + ' [DRY-RUN] Seria atualizado startup params')
            if args:
                log('      arguments: ' + str(args))
            continue

        try:
            cd('/Servers/' + nome + '/ServerStart/' + nome)
            if args is not None:
                cmo.setArguments(args)
            if java_vendor:
                cmo.setJavaVendor(java_vendor)
            if java_home:
                cmo.setJavaHome(java_home)
            if classpath:
                cmo.setClassPath(classpath)
            log('  - Servidor: ' + nome + ' [OK] startup params atualizados')
        except Exception as e:
            log('  - Servidor: ' + nome + ' [ERRO] ' + str(e))


# ─────────────────────────────────────────────────────────────────────────────
# 2 — DataSources JDBC
# ─────────────────────────────────────────────────────────────────────────────

def importar_jdbc(datasources, dry_run):
    log('Importando DataSources JDBC...')
    if not datasources:
        log('  Nenhum DataSource no JSON.')
        return

    for ds in datasources:
        nome    = ds.get('nome', '')
        targets = ds.get('targets', [])
        jndi_names = ds.get('jndi_names', [])
        driver  = ds.get('driver', '')
        url     = ds.get('url', '')
        usuario = ds.get('usuario', '')
        cap_ini = ds.get('capacidade_inicial', 1)
        cap_min = ds.get('capacidade_min', 1)
        cap_max = ds.get('capacidade_max', 10)
        test_table = ds.get('test_table', '')
        reserve_to = ds.get('connection_reserve_timeout', 10)

        # Verificar se ja existe
        ja_existe = (getMBean('/JDBCSystemResources/' + nome) is not None)

        if dry_run:
            if ja_existe:
                log('  - DataSource: ' + nome + ' [DRY-RUN] Ja existe — seria ignorado (use console para atualizar)')
            else:
                log('  - DataSource: ' + nome + ' [DRY-RUN] Seria criado')
                log('      driver: ' + str(driver))
                log('      url: ' + str(url))
                log('      usuario: ' + str(usuario))
                log('      targets: ' + str(targets))
                log('      pool: ini=' + str(cap_ini) + ' min=' + str(cap_min) + ' max=' + str(cap_max))
            continue

        if ja_existe:
            log('  - DataSource: ' + nome + ' [AVISO] Ja existe — ignorado (remova pelo console se quiser recriar)')
            continue

        try:
            # Criar JDBCSystemResource
            cd('/')
            cmo.createJDBCSystemResource(nome)

            # Driver params
            cd('/JDBCSystemResources/%s/JDBCResource/%s/JDBCDriverParams/NO_NAME_0' % (nome, nome))
            cmo.setUrl(url)
            cmo.setDriverName(driver)
            # Senha em branco — DEVE ser redefinida manualmente no console apos importar
            cmo.setPassword('')

            # Propriedade user
            if usuario:
                cd('/JDBCSystemResources/%s/JDBCResource/%s/JDBCDriverParams/NO_NAME_0/Properties/NO_NAME_0' % (nome, nome))
                cmo.createProperty('user')
                cd('Properties/user')
                cmo.setValue(usuario)

            # Pool params
            cd('/JDBCSystemResources/%s/JDBCResource/%s/JDBCConnectionPoolParams/NO_NAME_0' % (nome, nome))
            cmo.setInitialCapacity(int(cap_ini or 1))
            cmo.setMinCapacity(int(cap_min or 1))
            cmo.setMaxCapacity(int(cap_max or 10))
            if test_table:
                cmo.setTestTableName(test_table)
            if reserve_to is not None:
                cmo.setConnectionReserveTimeoutSeconds(int(reserve_to))

            # JNDI names
            if jndi_names:
                cd('/JDBCSystemResources/%s/JDBCResource/%s/JDBCDataSourceParams/NO_NAME_0' % (nome, nome))
                from java.lang import String
                cmo.setJNDINames([String(j) for j in jndi_names])

            # Targets
            cd('/JDBCSystemResources/' + nome)
            target_mbeans = resolver_targets(targets)
            if target_mbeans:
                cmo.setTargets(target_mbeans)

            log('  - DataSource: ' + nome + ' [OK] criado')
            log('    !! REDEFINIR SENHA no console apos importar !!')

        except Exception as e:
            log('  - DataSource: ' + nome + ' [ERRO] ' + str(e))


# ─────────────────────────────────────────────────────────────────────────────
# 3 — JMS Servers
# ─────────────────────────────────────────────────────────────────────────────

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
                log('  - JMS Server: ' + nome + ' [DRY-RUN] Ja existe — seria ignorado')
            else:
                log('  - JMS Server: ' + nome + ' [DRY-RUN] Seria criado')
                log('      targets: ' + str(targets))
                log('      persistent_store: ' + str(store_nome))
                log('      bytes_maximum: ' + str(bytes_max))
            continue

        if ja_existe:
            log('  - JMS Server: ' + nome + ' [AVISO] Ja existe — ignorado')
            continue

        try:
            cd('/')
            cmo.createJMSServer(nome)
            cd('/JMSServers/' + nome)

            if bytes_max is not None:
                try:
                    cmo.setBytesMaximum(long(bytes_max))
                except Exception:
                    pass

            if msgs_max is not None:
                try:
                    cmo.setMessagesMaximum(long(msgs_max))
                except Exception:
                    pass

            # Persistent store
            if store_nome:
                store_mbean = getMBean('/FileStores/' + store_nome)
                if store_mbean is None:
                    store_mbean = getMBean('/JDBCStores/' + store_nome)
                if store_mbean is not None:
                    cmo.setPersistentStore(store_mbean)
                else:
                    log('    AVISO: persistent store "' + store_nome + '" nao encontrado — JMS Server criado sem store')

            # Target (JMS Server tem apenas 1 target normalmente)
            target_mbeans = resolver_targets(targets)
            if target_mbeans:
                cmo.setTargets(target_mbeans)

            log('  - JMS Server: ' + nome + ' [OK] criado')

        except Exception as e:
            log('  - JMS Server: ' + nome + ' [ERRO] ' + str(e))


# ─────────────────────────────────────────────────────────────────────────────
# 4 — JMS Modules (System Resources)
# ─────────────────────────────────────────────────────────────────────────────

def importar_jms_modules(modulos, dry_run):
    log('Importando Modulos JMS (System Resources)...')
    if not modulos:
        log('  Nenhum JMS Module no JSON.')
        return

    for mod in modulos:
        nome         = mod.get('nome', '')
        targets      = mod.get('targets', [])
        subdeployments = mod.get('sub_deployments', [])
        cfs          = mod.get('connection_factories', [])
        queues       = mod.get('queues', [])
        topics       = mod.get('topics', [])

        ja_existe = (getMBean('/JMSSystemResources/' + nome) is not None)

        if dry_run:
            if ja_existe:
                log('  - JMS Module: ' + nome + ' [DRY-RUN] Ja existe — seria ignorado')
            else:
                log('  - JMS Module: ' + nome + ' [DRY-RUN] Seria criado')
                log('      targets: ' + str(targets))
                log('      sub_deployments: ' + str([s['nome'] for s in subdeployments]))
                log('      connection_factories: ' + str([c['nome'] for c in cfs]))
                log('      queues: ' + str([q['nome'] for q in queues]))
                log('      topics: ' + str([t['nome'] for t in topics]))
            continue

        if ja_existe:
            log('  - JMS Module: ' + nome + ' [AVISO] Ja existe — ignorado')
            continue

        try:
            cd('/')
            cmo.createJMSSystemResource(nome)

            # Targets do modulo
            cd('/JMSSystemResources/' + nome)
            target_mbeans = resolver_targets(targets)
            if target_mbeans:
                cmo.setTargets(target_mbeans)

            # SubDeployments
            for sub in subdeployments:
                sub_nome = sub.get('nome', '')
                cd('/JMSSystemResources/' + nome)
                cmo.createSubDeployment(sub_nome)
                cd('/JMSSystemResources/%s/SubDeployments/%s' % (nome, sub_nome))
                sub_targets = resolver_targets(sub.get('targets', []))
                if sub_targets:
                    cmo.setTargets(sub_targets)

            # Connection Factories
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
                        except Exception:
                            pass
                except Exception as e_cf:
                    log('    AVISO CF ' + cf_nome + ': ' + str(e_cf))

            # Queues e Distributed Queues
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
                except Exception as e_q:
                    log('    AVISO Queue ' + q_nome + ': ' + str(e_q))

            # Topics e Distributed Topics
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
                except Exception as e_t:
                    log('    AVISO Topic ' + t_nome + ': ' + str(e_t))

            log('  - JMS Module: ' + nome + ' [OK] criado')

        except Exception as e:
            log('  - JMS Module: ' + nome + ' [ERRO] ' + str(e))


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    log('=== WebLogic Config Import ===')

    admin_url   = env('WLS_ADMIN_URL', 't3://localhost:7001')
    usuario     = env('WLS_USER', 'weblogic')
    senha       = os.environ.get('WLS_PASS', None)
    config_file = env('WLS_CONFIG_FILE', 'config_export.json')
    imp_startup     = env_bool('WLS_EXPORT_STARTUP', True)
    imp_jdbc        = env_bool('WLS_EXPORT_JDBC', True)
    imp_jms_servers = env_bool('WLS_EXPORT_JMS_SERVERS', True)
    imp_jms_modules = env_bool('WLS_EXPORT_JMS_MODULES', True)
    dry_run         = env_bool('WLS_DRY_RUN', False)

    log('URL AdminServer : ' + admin_url)
    log('Usuario         : ' + usuario)
    log('Arquivo entrada : ' + config_file)
    if dry_run:
        log('MODO            : DRY-RUN — nenhuma alteracao sera aplicada')
    else:
        log('MODO            : REAL — alteracoes serao aplicadas no dominio')
    log('')

    # Ler JSON
    if not os.path.exists(config_file):
        log('ERRO: arquivo nao encontrado: ' + config_file)
        sys.exit(1)

    try:
        config = ler_json(config_file)
    except Exception as e:
        log('ERRO ao ler JSON: ' + str(e))
        sys.exit(1)

    log('Arquivo carregado:')
    log('  Origem    : ' + str(config.get('source_url', '?')))
    log('  Dominio   : ' + str(config.get('domain', '?')))
    log('  Timestamp : ' + str(config.get('timestamp', '?')))
    log('')

    # Conectar
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
    log('')

    # Iniciar edicao (apenas se nao for dry-run)
    if not dry_run:
        try:
            edit()
            startEdit()
        except Exception as e:
            log('ERRO ao iniciar edicao: ' + str(e))
            disconnect()
            sys.exit(1)

    # Importar categorias
    try:
        if imp_startup:
            servidores = config.get('startup', {}).get('servidores', [])
            importar_startup(servidores, dry_run)
        else:
            log('Startup de servidores: IGNORADO (WLS_EXPORT_STARTUP=false)')

        if imp_jdbc:
            datasources = config.get('jdbc', {}).get('data_sources', [])
            importar_jdbc(datasources, dry_run)
        else:
            log('DataSources JDBC: IGNORADO (WLS_EXPORT_JDBC=false)')

        if imp_jms_servers:
            jms_servers = config.get('jms_servers', {}).get('servidores', [])
            importar_jms_servers(jms_servers, dry_run)
        else:
            log('JMS Servers: IGNORADO (WLS_EXPORT_JMS_SERVERS=false)')

        if imp_jms_modules:
            jms_modules = config.get('jms_modules', {}).get('system_resources', [])
            importar_jms_modules(jms_modules, dry_run)
        else:
            log('JMS Modules: IGNORADO (WLS_EXPORT_JMS_MODULES=false)')

    except Exception as e_geral:
        log('ERRO inesperado durante importacao: ' + str(e_geral))
        if not dry_run:
            try:
                cancelEdit('y')
                log('Edicao cancelada (rollback).')
            except Exception:
                pass
        disconnect()
        sys.exit(1)

    # Ativar ou finalizar dry-run
    if dry_run:
        log('')
        log('DRY-RUN concluido. Nenhuma alteracao foi aplicada.')
        log('Para importar de verdade: defina WLS_DRY_RUN=false e execute novamente.')
    else:
        try:
            activate()
            log('')
            log('Importacao concluida e ativada com sucesso.')
            log('')
            log('PROXIMOS PASSOS OBRIGATORIOS:')
            log('  1. Acesse o console WebLogic: http://<host>:7001/console')
            log('  2. Va em Services > Data Sources e redefina a senha de CADA DataSource')
            log('  3. Teste as conexoes dos DataSources (botao "Test")')
            log('  4. Se startup params foram alterados, reinicie os Managed Servers afetados')
        except Exception as e:
            log('ERRO ao ativar configuracoes: ' + str(e))
            try:
                cancelEdit('y')
                log('Edicao cancelada (rollback).')
            except Exception:
                pass
            disconnect()
            sys.exit(1)

    disconnect()


main()
