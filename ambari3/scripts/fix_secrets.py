#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#
import json, urllib.request, base64, time

CLUSTER = "otowyue_redoop"
BASE = "http://localhost:8080/api/v1"
AUTH = base64.b64encode(b"admin:admin").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

PASSWORDS = {
    "javax.jdo.option.ConnectionPassword": "hive",
    "ranger.jpa.jdbc.password": "ranger",
    "ranger.audit.solr.password": "ranger",
    "ranger.service.https.attrib.keystore.pass": "ranger123",
    "ranger.truststore.password": "ranger123",
    "admin_password": "Admin1234!",
    "ranger_admin_password": "Admin1234!",
    "keyadmin_user_password": "Admin1234!",
    "rangertagsync_user_password": "Admin1234!",
    "rangerusersync_user_password": "Admin1234!",
    "REPOSITORY_CONFIG_PASSWORD": "Admin1234!",
}

def api(method, path, data=None):
    url = f"{BASE}{path}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=HEADERS, method=method)
    with urllib.request.urlopen(req) as r:
        content = r.read()
        return json.loads(content) if content.strip() else {}

def patch_config(cfgtype):
    resp = api("GET", f"/clusters/{CLUSTER}/configurations?type={cfgtype}")
    if not resp["items"]:
        print(f"  skip {cfgtype}: no config found")
        return
    tag = sorted(i["tag"] for i in resp["items"])[-1]
    props = api("GET", f"/clusters/{CLUSTER}/configurations?type={cfgtype}&tag={tag}")["items"][0]["properties"]
    changed = []
    for k, v in props.items():
        if "SECRET" in str(v):
            props[k] = PASSWORDS.get(k, "changeme123")
            changed.append(k)
    if changed:
        new_tag = f"plaintext-{int(time.time())}"
        payload = {"Clusters": {"desired_configs": {"type": cfgtype, "tag": new_tag, "properties": props}}}
        api("PUT", f"/clusters/{CLUSTER}", payload)
        print(f"  {cfgtype}: fixed {changed}")
    else:
        print(f"  {cfgtype}: no SECRET found")

for t in ["hive-site", "ranger-admin-site", "ranger-env", "ranger-hive-plugin-properties"]:
    print(f"==> {t}")
    patch_config(t)

print("Done")
