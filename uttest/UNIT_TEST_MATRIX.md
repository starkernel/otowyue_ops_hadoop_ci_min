# 单元测试矩阵（UNIT TEST MATRIX）

> 针对脚本、配置、工具函数的单元级验证。可用 `bash -n` / `python -m py_compile` / `jq` / `xmllint` 执行。
> 更新：2026-10-29

## 1. Shell 脚本

| ID | 对象 | 测试内容 | 命令 | 期望 | 状态 |
|---|---|---|---|---|---|
| UT-SH-001 | `ambari3/scripts/setup-nat-forward.sh` | 语法 | `bash -n` | 无错误 | ✅ |
| UT-SH-002 | `setup-nat-forward.sh` | 非 root 拒绝 | 直接执行 | 退出码 1 + 提示 | ✅ |
| UT-SH-003 | `setup-nat-forward.sh` | usage 输出 | 无参数/非法参数 | 显示 6 个动作 | ✅ |
| UT-SH-004 | `setup-nat-forward.sh` | persist 生成 unit | `grep After=docker.service` on unit | 存在 | ⏳ 需 root |
| UT-SH-005 | `install-ambari-agent-script.sh` | 语法 | `bash -n` | 无错误 | ✅ |
| UT-SH-006 | `install-ambari-server-script.sh` | 语法 | `bash -n` | 无错误 | ✅ |
| UT-SH-007 | `install-*.sh` | python 软链接逻辑 | 模拟缺失 | 创建 `/usr/bin/python` | ⏳ |
| UT-SH-008 | `ambari3/scripts/setup-nat-forward.sh` | 计数逻辑 | 审查 | `count/total` 自增 | ✅ |

## 2. 配置文件

| ID | 对象 | 测试内容 | 命令 | 期望 | 状态 |
|---|---|---|---|---|---|
| UT-CFG-001 | `metric_groups.conf` | 纯 JSON | `python3 -m json.tool` | 解析成功 | ✅ |
| UT-CFG-002 | `*-site.xml` | XML 合法 | `xmllint --noout` | 无错误 | ⏳ |
| UT-CFG-003 | `flink-conf.yaml` | YAML 合法 | `python3 -c yaml.safe_load` | 成功 | ⏳ |
| UT-CFG-004 | `metric_monitor.ini` | INI 解析 | `python3 configparser` | 成功 | ✅ |
| UT-CFG-005 | `hadoop-env.sh` | 无重复尾部 | `grep -c 'HADOOP_SECONDARYNAMENODE_OPTS'` | 每行 1 次 | ✅ |
| UT-CFG-006 | JVM 参数范围 | Xmx 在 [256m, 3g] | 正则扫描 | 全部合规 | ⏳ |

## 3. Python / 工具

| ID | 对象 | 测试内容 | 命令 | 期望 | 状态 |
|---|---|---|---|---|---|
| UT-PY-001 | `ambari3/scripts/ambari-cfg.py` | 语法 | `python3 -m py_compile` | 成功 | ⏳ |
| UT-PY-002 | `insert-repo-version.py` | 语法 | `python3 -m py_compile` | 成功 | ⏳ |
| UT-PY-003 | AMS `config_reader.py` | 读取 ini | 单测 | 返回 collector host | ✅ |
| UT-PY-004 | AMS `emitter.compute_hash` | 空 hostname | 单测 | 抛错（已知） | ✅ |

## 4. Ambari REST 辅助

| ID | 对象 | 测试内容 | 期望 | 状态 |
|---|---|---|---|---|
| UT-API-001 | 告警查询 | `items` 字段解析 | 数量正确 | ✅ |
| UT-API-002 | 组件状态查询 | `HostRoles/state` | 可读 | ✅ |
| UT-API-003 | PUT STARTED | 返回 200/202 | 接受 | ✅ |
| UT-API-004 | 404 组件名 | 错误处理 | 可识别 | ✅ |

## 执行建议

```bash
# 批量语法检查
for f in ambari3/scripts/*.sh; do bash -n "$f" || echo "FAIL $f"; done
for f in ambari3/scripts/*.py; do python3 -m py_compile "$f" || echo "FAIL $f"; done

# JSON 校验
python3 -m json.tool /etc/ambari-metrics-monitor/conf/metric_groups.conf >/dev/null && echo OK
```
