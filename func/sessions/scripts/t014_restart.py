#!/usr/bin/env python3
"""
T-014: 按服务依赖顺序 STOP->START 组件，使 Ambari 新堆配置生效。

用法（在可访问 Ambari 的主机执行）：
  python3 t014_restart.py            # 全部服务
  python3 t014_restart.py HDFS       # 仅指定服务组

注意：
- 会真实停止/启动组件，服务短暂中断
- Ranger 服务若启动失败，检查启动脚本 -Xms 是否 > 新 Xmx（BUG-035）
- ZK 重启可能连带停止 AMS 栈，需之后执行 ambari-metrics-collector start
"""
import json, urllib.request, base64, time, sys

BASE = 'http://localhost:20609/api/v1/clusters/qixuandata'
AUTH = base64.b64encode(b'admin:admin').decode()

H0 = 'bigtop-hostname0.bigtop.apache.org'
H1 = 'bigtop-hostname1.bigtop.apache.org'
H2 = 'bigtop-hostname2.bigtop.apache.org'
H3 = 'bigtop-hostname3.bigtop.apache.org'

GROUPS = {
    'MAPREDUCE2': [(H0, 'HISTORYSERVER')],
    'HDFS': [(H0, 'NAMENODE'), (H1, 'SECONDARY_NAMENODE'),
             (H1, 'DATANODE'), (H2, 'DATANODE'), (H3, 'DATANODE'), (H3, 'ROUTER')],
    'YARN': [(H0, 'RESOURCEMANAGER'), (H0, 'TIMELINE_READER'), (H0, 'YARN_REGISTRY_DNS'),
             (H1, 'APP_TIMELINE_SERVER'), (H1, 'NODEMANAGER'), (H2, 'NODEMANAGER'), (H3, 'NODEMANAGER')],
    'HBASE': [(H0, 'HBASE_MASTER'), (H3, 'HBASE_REGIONSERVER')],
    'HIVE': [(H0, 'HIVE_METASTORE'), (H0, 'HIVE_SERVER'), (H0, 'WEBHCAT_SERVER')],
    'RANGER': [(H0, 'RANGER_ADMIN'), (H0, 'RANGER_USERSYNC'), (H3, 'RANGER_TAGSYNC')],
    'RANGER_KMS': [(H0, 'RANGER_KMS_SERVER')],
    'AMBARI_INFRA_SOLR': [(H0, 'INFRA_SOLR')],
    'SPARK': [(H0, 'SPARK_JOBHISTORYSERVER'), (H1, 'SPARK_THRIFTSERVER')],
}


def req(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method,
        headers={'Authorization': 'Basic ' + AUTH, 'X-Requested-By': 'ambari',
                 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            t = resp.read().decode()
            return resp.status, (json.loads(t) if t.strip() else {})
    except urllib.error.HTTPError as e:
        return e.code, {'error': e.read().decode()[:200]}


def get_state(host, comp):
    st, body = req('GET', f'{BASE}/hosts/{host}/host_components/{comp}?fields=HostRoles/state')
    if st == 200 and isinstance(body, dict):
        return body.get('HostRoles', {}).get('state')
    return None


def set_state(host, comp, state):
    return req('PUT', f'{BASE}/hosts/{host}/host_components/{comp}',
               {'HostRoles': {'state': state}})[0]


def wait_state(host, comp, target, timeout=240):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if get_state(host, comp) == target:
            return True
        time.sleep(5)
    return False


def restart(host, comp):
    short = host.split('.')[0]
    print(f'  STOP  {comp}@{short} ...', end='', flush=True)
    set_state(host, comp, 'INSTALLED')
    print(' ok' if wait_state(host, comp, 'INSTALLED', 180) else ' timeout', flush=True)
    time.sleep(2)
    print(f'  START {comp}@{short} ...', end='', flush=True)
    set_state(host, comp, 'STARTED')
    print(' ok' if wait_state(host, comp, 'STARTED', 300) else ' timeout', flush=True)


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    for g, comps in GROUPS.items():
        if only and g != only:
            continue
        print(f'=== {g} ===')
        for host, comp in comps:
            restart(host, comp)
    print('DONE')


if __name__ == '__main__':
    main()
