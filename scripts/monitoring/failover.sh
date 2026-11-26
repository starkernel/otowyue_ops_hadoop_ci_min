#!/usr/bin/env bash
# Switch the LAN monitoring endpoint between the h1 primary and h2 standby.
#
#   bash scripts/monitoring/failover.sh status
#   bash scripts/monitoring/failover.sh h1
#   bash scripts/monitoring/failover.sh h2
#
# Ports:
#   9090  -> Prometheus (h1 or h2)
#   19093 -> Alertmanager (h1 or h2)
#   9093  is intentionally NOT touched: it belongs to Kafka broker 1002.
set -euo pipefail

H1=172.19.0.5
H2=172.19.0.3
HOST_IP=192.168.0.60
IMAGE=busybox

ipt() {
  docker run --rm --privileged --net=host -v /:/host:ro "$IMAGE" \
    chroot /host iptables "$@"
}

set_target() {
  local port="$1" dst="$2" chain spec n
  for chain in PREROUTING OUTPUT; do
    n=0
    while ipt -t nat -S "$chain" | grep -q -- "--dport ${port} .*DNAT"; do
      spec=$(ipt -t nat -S "$chain" | grep -- "--dport ${port} .*DNAT" | head -1 | sed 's/^-A //')
      ipt -t nat -D $spec || break
      n=$((n + 1))
      [ "$n" -ge 10 ] && break
    done
    ipt -t nat -A "$chain" -p tcp -m tcp --dport "$port" \
      -m addrtype --dst-type LOCAL -j DNAT --to-destination "$dst"
  done
  echo "  ${port} -> ${dst}"
}

show_status() {
  echo "=== DNAT ==="
  ipt -t nat -S PREROUTING | grep -E -- "--dport (9090|19093) " || true
  echo "=== health ==="
  for url in "http://${HOST_IP}:9090/-/ready" "http://${HOST_IP}:19093/-/ready"; do
    printf '  %-42s ' "$url"
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 6 "$url" || echo "FAIL"
  done
  echo "=== backends ==="
  for spec in "h1 ${H1}" "h2 ${H2}"; do
    set -- $spec
    printf '  %s prometheus=' "$1"
    curl -s -o /dev/null -w '%{http_code} ' --max-time 4 "http://$2:9090/-/ready" || true
    printf 'alertmanager='
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 4 "http://$2:9093/-/ready" || true
  done
}

case "${1:-status}" in
  status)
    show_status
    ;;
  h1)
    set_target 9090 "${H1}:9090"
    set_target 19093 "${H1}:9093"
    show_status
    ;;
  h2)
    set_target 9090 "${H2}:9090"
    set_target 19093 "${H2}:9093"
    show_status
    ;;
  *)
    echo "用法: $0 {status|h1|h2}" >&2
    exit 1
    ;;
esac
