#!/usr/bin/env python3
"""
T-014: 通过 Ambari 配置中心降低 JVM 堆内存（逐个 type 提交）

关键点：
- Ambari 配置更新必须带 "type" 字段，否则 500
- 一次只提交一个 type，批量提交会导致配置合并错乱（BUG-034）
- 提交前自动备份当前 selected 配置
- 提交后需重启组件（见 t014_restart.py）才会生效

用法（在可访问 Ambari 的主机执行）：
  python3 t014_apply.py              # dry-run，打印变更并备份
  python3 t014_apply.py --apply      # 实际提交
"""
import json, urllib.request, base64, time, sys, os

BASE = os.environ.get('AMBARI_BASE', 'http://localhost:20609/api/v1/clusters/qixuandata')
USER = os.environ.get('AMBARI_USER', 'admin')
PASS = os.environ.get('AMBARI_PASS', 'admin')
AUTH = base64.b64encode(f'{USER}:{PASS}'.encode()).decode()
BACKUP_DIR = os.environ.get('T014_BACKUP_DIR', '/tmp/t014-config-backup')

# 当前 selected 版本的 tag（如变化请先查询 clusterconfig.selected=1）
CURRENT_TAGS = {
    'hadoop-env':      'hadoop-env-memtune-1792028776',
    'yarn-env':        'yarn-env-memtune-1792028775',
    'mapred-env':      'mapred-env-memtune-1792028777',
    'hbase-env':       'hbase-env-memtune-1792028776',
    'hive-env':        'hive-env-memtune-1792028801',
    'zookeeper-env':   '08a0df67-07fa-4f41-8d9b-f587b2044369',
    'infra-solr-env':  '6663a18e-4cee-4074-91bc-cccfbdad5916',
    'ranger-env':      '248f9e70-5081-4723-9f73-cdbcb2edc185',
    'kms-env':         '7f461d5c-8548-4315-9d7a-42992e5065ca',
    'spark-env':       'jdk17v3',
}

CHANGES = {
    'hadoop-env':      {'namenode_heapsize': '1536m', 'dtnode_heapsize': '512m'},
    'yarn-env':        {'resourcemanager_heapsize': '1536',
                        'nodemanager_heapsize': '1024',
                        'apptimelineserver_heapsize': '512'},
    'mapred-env':      {'jobhistory_heapsize': '512'},
    'hbase-env':       {'hbase_master_heapsize': '1024',
                        'hbase_regionserver_heapsize': '2048'},
    'hive-env':        {'hive.heapsize': '1024', 'hive.metastore.heapsize': '512'},
    'zookeeper-env':   {'zk_server_heapsize': '512m'},
    'infra-solr-env':  {'infra_solr_maxmem': '1024', 'infra_solr_minmem': '512'},
    'ranger-env':      {'ranger_admin_max_heap_size': '768m',
                        'ranger_tagsync_max_heap_size': '512m',
                        'ranger_usersync_max_heap_size': '512m'},
    'kms-env':         {'ranger_kms_max_heap_size': '512m'},
    'spark-env':       {'spark_daemon_memory': '1024'},
}


def req(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method,
        headers={'Authorization': 'Basic ' + AUTH, 'X-Requested-By': 'ambari',
                 'Content-Type': 'application/json'})
    with urllib.request.urlopen(r, timeout=60) as resp:
        txt = resp.read().decode()
        return json.loads(txt) if txt.strip() else {}


def get_props(t, tag):
    d = req('GET', f'{BASE}/configurations?type={t}&tag={tag}')
    items = d.get('items', [])
    if not items:
        raise RuntimeError(f'config not found: {t}/{tag}')
    return items[0].get('properties', {})


def main():
    apply = '--apply' in sys.argv
    ts = int(time.time())
    os.makedirs(BACKUP_DIR, exist_ok=True)
    backup = {}

    for t, changes in CHANGES.items():
        tag = CURRENT_TAGS[t]
        props = get_props(t, tag)
        backup[t] = {'tag': tag, 'properties': props}
        print(f'{t}: {changes}')

    path = os.path.join(BACKUP_DIR, f'before-{ts}.json')
    with open(path, 'w') as f:
        json.dump(backup, f, indent=2)
    print(f'\n备份: {path}')

    if not apply:
        print('\n[DRY-RUN] 未提交。加 --apply 实际提交。')
        return

    for t, changes in CHANGES.items():
        props = dict(backup[t]['properties'])
        props.update(changes)
        new_tag = f'{t}-memopt-{ts}'
        body = {'Clusters': {'desired_configs': {t: {
            'tag': new_tag, 'type': t, 'properties': props}}}}
        try:
            req('PUT', BASE, body)
            print(f'OK   {t} -> {new_tag}')
        except Exception as e:
            print(f'FAIL {t}: {e}')
        time.sleep(1)  # 逐个提交，避免批量合并 bug


if __name__ == '__main__':
    main()
