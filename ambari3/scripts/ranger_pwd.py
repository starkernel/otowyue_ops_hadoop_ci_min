#
# HodoopForge - 专为现代Hadoop集群量身打造的一站式部署与管理平台
# Forge Stability. Connect the Future.
#
# This script is part of the HodoopForge project.
# Project: HodoopForge - Ambari 3.x + Bigtop 3.5.0 Integration Platform
#
import hashlib
pwd = "Admin1234!"
user = "admin"
print("sha256(pwd):", hashlib.sha256(pwd.encode()).hexdigest())
print("sha256(user:pwd):", hashlib.sha256(f"{user}:{pwd}".encode()).hexdigest())
print("md5(pwd):", hashlib.md5(pwd.encode()).hexdigest())
# Ranger 有时用 sha256 两次
h1 = hashlib.sha256(pwd.encode()).hexdigest()
print("sha256(sha256(pwd)):", hashlib.sha256(h1.encode()).hexdigest())
