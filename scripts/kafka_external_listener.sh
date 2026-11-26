#!/usr/bin/env bash
# ============================================================
# Kafka 外部访问：宿主机端口转发 + 容器内 hairpin DNAT + 验证
#
# 关键原则（2026-11-10 修正）：
#   - 9093/9094 端口开放 ≠ Kafka 客户端可用
#   - 客户端真正连接的是 metadata 返回的 advertised.listeners
#   - 因此 advertised.listeners 必须是客户端能直达的地址：
#       192.168.0.60:9092 / 9093 / 9094
#   - 不再 advertise as.long.kim（应用宿主不可达，且依赖进程内 override）
#
# 拓扑：
#   broker 1001 (h0) -> 192.168.0.60:9092 -> 172.19.0.2:9092
#   broker 1002 (h2) -> 192.168.0.60:9093 -> 172.19.0.3:9092
#   broker 1003 (h3) -> 192.168.0.60:9094 -> 172.19.0.4:9092
#
# 用法：
#   ./scripts/kafka_external_listener.sh status
#   ./scripts/kafka_external_listener.sh apply
#   ./scripts/kafka_external_listener.sh verify
#
# 依赖：docker、bigtop/puppet:trunk-rockylinux-8 镜像、Kafka CLI
# ============================================================
set -euo pipefail

H0=bigtop_hostname0
H1=bigtop_hostname1
H2=bigtop_hostname2
H3=bigtop_hostname3
H0_IP=172.19.0.2
H2_IP=172.19.0.3
H3_IP=172.19.0.4
HOST_IP=192.168.0.60
KAFKA_BIN=/usr/bigtop/current/kafka-broker/bin
BOOTSTRAP="${HOST_IP}:9092,${HOST_IP}:9093,${HOST_IP}:9094"
IMAGE=bigtop/puppet:trunk-rockylinux-8

info() { echo "[INFO] $*"; }
ok()   { echo "[ OK ] $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERR ] $*" >&2; }

host_iptables() {
  docker run --rm --privileged --net=host -v /:/host:ro "$IMAGE" \
    chroot /host /usr/sbin/iptables "$@"
}

container_iptables() {
  local name="$1"; shift
  docker run --rm --privileged --net="container:${name}" -v /:/host:ro "$IMAGE" \
    chroot /host /usr/sbin/iptables "$@"
}

ensure_host_rule() {
  local chain="$1" port="$2" dst="$3"
  if host_iptables -t nat -C "$chain" -p tcp --dport "$port" \
       -m addrtype --dst-type LOCAL -j DNAT --to-destination "$dst" 2>/dev/null; then
    ok "host ${chain} ${port} -> ${dst} (exists)"
  else
    host_iptables -t nat -A "$chain" -p tcp --dport "$port" \
      -m addrtype --dst-type LOCAL -j DNAT --to-destination "$dst"
    ok "host ${chain} ${port} -> ${dst} (added)"
  fi
}

ensure_container_rule() {
  local name="$1" port="$2" dst="$3"
  if container_iptables "$name" -t nat -C OUTPUT -d "$HOST_IP" -p tcp \
       --dport "$port" -j DNAT --to-destination "$dst" 2>/dev/null; then
    ok "${name} OUTPUT ${HOST_IP}:${port} -> ${dst} (exists)"
  else
    container_iptables "$name" -t nat -A OUTPUT -d "$HOST_IP" -p tcp \
      --dport "$port" -j DNAT --to-destination "$dst"
    ok "${name} OUTPUT ${HOST_IP}:${port} -> ${dst} (added)"
  fi
}

do_status() {
  echo "=== 宿主机 DNAT ==="
  host_iptables -t nat -S | grep -E 'dport (9092|9093|9094)' || true
  echo
  echo "=== 容器内 hairpin DNAT ==="
  for h in "$H0" "$H1" "$H2" "$H3"; do
    echo "--- $h"
    container_iptables "$h" -t nat -S OUTPUT | grep -E '9092|9093|9094' || true
  done
  echo
  echo "=== Kafka advertised listeners ==="
  for h in "$H0" "$H2" "$H3"; do
    echo "--- $h"
    docker exec "$h" grep -E '^(broker.id|listeners|advertised.listeners)' \
      "$KAFKA_BIN/../config/server.properties" || true
  done
  echo
  echo "=== 元数据（从 h2，标准 Kafka CLI）==="
  docker exec "$H2" "$KAFKA_BIN/kafka-broker-api-versions.sh" \
    --bootstrap-server "$BOOTSTRAP" 2>&1 | grep -E '\(id: 100[123]' || true
}

do_apply() {
  info "宿主机 DNAT：9092→h0:9092、9093→h2:9092、9094→h3:9092"
  ensure_host_rule PREROUTING 9092 "${H0_IP}:9092"
  ensure_host_rule OUTPUT     9092 "${H0_IP}:9092"
  ensure_host_rule PREROUTING 9093 "${H2_IP}:9092"
  ensure_host_rule OUTPUT     9093 "${H2_IP}:9092"
  ensure_host_rule PREROUTING 9094 "${H3_IP}:9092"
  ensure_host_rule OUTPUT     9094 "${H3_IP}:9092"

  info "容器 hairpin：每个容器都能直达 ${HOST_IP}:9092/9093/9094"
  for h in "$H0" "$H1" "$H2" "$H3"; do
    ensure_container_rule "$h" 9092 "${H0_IP}:9092"
    ensure_container_rule "$h" 9093 "${H2_IP}:9092"
    ensure_container_rule "$h" 9094 "${H3_IP}:9092"
  done

  warn "Kafka advertised.listeners 必须为："
  warn "  h0 = 192.168.0.60:9092"
  warn "  h2 = 192.168.0.60:9093"
  warn "  h3 = 192.168.0.60:9094"
  warn "若尚未修改，请按 docs/KAFKA_EXTERNAL_ACCESS.md 的滚动重启步骤执行。"
}

do_verify() {
  local topic="kafka-ext-write-test"
  info "创建测试 topic ${topic}（3 分区 RF3）"
  docker exec "$H2" "$KAFKA_BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP" \
    --create --if-not-exists --topic "$topic" --partitions 3 --replication-factor 3 >/dev/null

  info "发送 30 条带 key 消息（默认分区器散列）"
  docker exec "$H2" bash -c "for i in \$(seq 1 30); do printf 'key%s\tvalue%s\n' \$i \$i; done | \
    $KAFKA_BIN/kafka-console-producer.sh --bootstrap-server $BOOTSTRAP \
    --topic $topic --property parse.key=true 2>/dev/null"

  sleep 2
  echo "=== 三分区 end offset ==="
  local out
  out=$(docker exec "$H2" "$KAFKA_BIN/kafka-run-class.sh" kafka.tools.GetOffsetShell \
    --broker-list "$BOOTSTRAP" --topic "$topic" --time -1 2>/dev/null | sort)
  echo "$out"

  local zero
  zero=$(echo "$out" | awk -F: '$3==0{c++} END{print c+0}')
  if [ "$zero" -eq 0 ]; then
    ok "所有分区均可写"
  else
    err "仍有 ${zero} 个分区 offset=0，请检查 advertised listeners / NAT"
  fi

  info "删除测试 topic"
  docker exec "$H2" "$KAFKA_BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP" \
    --delete --topic "$topic" >/dev/null 2>&1 || true
}

case "${1:-status}" in
  status) do_status ;;
  apply)  do_apply ;;
  verify) do_verify ;;
  *) echo "用法: $0 {status|apply|verify}" >&2; exit 1 ;;
esac
