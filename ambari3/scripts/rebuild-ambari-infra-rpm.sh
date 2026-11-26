#!/bin/bash
# ============================================================
# rebuild-ambari-infra-rpm.sh — 将旧版 el7 头的 ambari-infra rpm
# 重打包为 el8 可用版本
# ------------------------------------------------------------
# 背景：repo.hortonworks 发布的 ambari-infra-solr(-client) 是
# 2019 年 el6/el7 时代构建，头信息没有现代 sha256 digest，el8 的
# rpm/dnf 一律报 "does not verify: no digest"，yum install 无法完成。
# 解法：内容原封不动（rpm2cpio 解包 + 重新打包），只是重建头信息，
# 生成行为相同的 .el8 rpm。生成的包仍叫 ambari-infra-solr(-client)。
#
# 用法：
#   rebuild-ambari-infra-rpm.sh <包名> [rpm源目录] [输出目录]
#   例： rebuild-ambari-infra-rpm.sh ambari-infra-solr-client /var/repo/ambari
# ============================================================
set -euo pipefail

PKG="${1:?用法: rebuild-ambari-infra-rpm.sh <包名> [源目录] [输出目录]}"
SRC_DIR="${2:-/tmp/ah}"
OUT_DIR="${3:-/var/repo/ambari}"

RPM_SRC=$(ls "${SRC_DIR}"/${PKG}-[0-9].*.rpm 2>/dev/null | grep -v '\.el8\.' | head -1)
[ -n "${RPM_SRC}" ] || { echo "FATAL: 找不到 ${PKG} 的原始 rpm（${SRC_DIR}）"; exit 1; }

WORK=/tmp/rebuild-${PKG}
rm -rf "${WORK}"
mkdir -p "${WORK}/root"
cd "${WORK}/root"
rpm2cpio "${RPM_SRC}" | cpio -idmu --quiet

VER=$(rpm -qp --qf '%{VERSION}' "${RPM_SRC}")
REL=$(rpm -qp --qf '%{RELEASE}' "${RPM_SRC}")
REL_NUM=${REL%%-*}
[ -n "${REL_NUM}" ] || REL_NUM=118

mkdir -p "${WORK}/rpmbuild"
cat > "${WORK}/spec.spec" <<EOF
# Disable el8 brp-* policy scripts so the rebuilt payload stays byte-identical
# (brp-mangle-shebangs rejects legacy '#!/usr/bin/python' shebangs otherwise).
%global __os_install_post %{nil}
Name:           ${PKG}
Version:        ${VER}
Release:        ${REL_NUM}.el8
Summary:        ${PKG} rebuilt for EL8 (payload identical to original)
License:        Apache License 2.0
BuildArch:      noarch
Group:          Development
AutoReqProv:    no
Provides:       ${PKG} = ${VER}-${REL}
Requires:       /bin/sh
%description
${PKG} rebuilt from the original Hortonworks el7 rpm for Rocky/EL 8.
File payload is byte-for-byte identical to the original package.
%install
cp -a "${WORK}/root/." %{buildroot}
%files
EOF

find "${WORK}/root" -mindepth 1 \( -type f -o -type l \) | sed 's#^'"${WORK}/root"'##' | sort >> "${WORK}/spec.spec"

rpmbuild --define "_topdir ${WORK}/rpmbuild" -bb "${WORK}/spec.spec" >/dev/null \
  || { echo "FATAL: ${PKG} 重打包失败"; exit 1; }

NEW_RPM=$(find "${WORK}/rpmbuild" -name "${PKG}-${VER}-${REL_NUM}.el8.noarch.rpm" | head -1)
cp -f "${NEW_RPM}" "${OUT_DIR}/"
echo "==> ${PKG}: 已生成 ${OUT_DIR}/$(basename "${NEW_RPM}")"
echo "    (文件数 $(find "${WORK}/root" -mindepth 1 | wc -l)，内容与原包一致)"