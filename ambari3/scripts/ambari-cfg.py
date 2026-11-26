#!/usr/bin/env python3
import json, sys, time, urllib.request, os
base = "http://localhost:20609/api/v1/clusters/qixuandata"


def http(url, method="GET", body=None):
    headers = {"Authorization": os.environ.get("AMBARI_AUTH", "Basic YWRtaW46YWRtaW4=")}
    if body is not None:
        headers.update({"Content-Type": "application/json", "X-Requested-By": "ambari"})
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode() or "{}")


if len(sys.argv) < 3:
    print("usage: ambari-cfg.py <type> [baseTag|auto] key=value [key=value ...]")
    print("  省略 baseTag 或写 auto -> 自动继承当前 desired_config 的属性")
    sys.exit(2)

ctype = sys.argv[1]
kv, offset = {}, 2
btag = None
if sys.argv[2] != "auto" and "=" not in sys.argv[2]:
    btag, offset = sys.argv[2], 3
if btag is None:
    offset = 3
    btag = http(base + "?fields=Clusters/desired_configs")["Clusters"]["desired_configs"][ctype]["tag"]
for a in sys.argv[offset:]:
    k, v = a.split("=", 1)
    kv[k] = v

props = http(base + "/configurations?type=%s&tag=%s" % (ctype, btag))["items"][0]["properties"]
props.update(kv)
newtag = "%s-%s" % (ctype, time.time())
body = json.dumps({"Clusters": {"desired_config": {"type": ctype, "tag": newtag, "properties": props}}}).encode()
http(base, "PUT", body)
print("OK %s -> %s (base %s)" % (ctype, newtag, btag))
for k in kv:
    print("   %s = %s" % (k, kv[k]))