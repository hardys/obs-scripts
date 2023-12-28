#!/bin/bash

set -eux

PROJECT="home:steven.hardy:testing:Cloud:OpenStack:Bobcat"

if [ $# != 1 ]; then
  echo "Usasge: $0 <package name>"
  exit 1

fi
PACKAGE=$1

# checkout the target package or update if it already exists
if [ -d "${PROJECT}/${PACKAGE}" ]; then
  echo "${PROJECT}/${PACKAGE} exists"
  osc -A https://api.opensuse.org revert ${PROJECT}/${PACKAGE}
  osc -A https://api.opensuse.org update ${PROJECT}/${PACKAGE}
else
  echo "${PROJECT}/${PACKAGE} does not exist"
  osc -A https://api.opensuse.org checkout ${PROJECT}/${PACKAGE}
fi

NUM_SOURCES=$(grep "^Source" ${PROJECT}/${PACKAGE}/*.spec | wc -l)
if [ ${NUM_SOURCES} -ne 1 ]; then
  echo "Error only one Source file supported"
  exit 1
fi
TARGET_SOURCE=$(grep "^Source" ${PROJECT}/${PACKAGE}/*.spec)
TARGET_URL=$(echo ${TARGET_SOURCE} | awk '{print $2}')

# Update the source from upstream
REQ_NAME=$(echo ${PACKAGE} | sed 's/python-//g')
echo "REQ_NAME=${REQ_NAME}"
STABLE_VERSION=${STABLE_VERSION:-2023.2}
MINOR_VERSION=${MINOR_VERSION:-0}
STABLE_URL="https://opendev.org/openstack/${REQ_NAME}/archive/stable/${STABLE_VERSION}.tar.gz"

STABLE_TARBALL="${REQ_NAME}-%{version}.tar.xz"
if [ "${TARGET_URL}" == "${STABLE_TARBALL}" ]; then
  echo "Spec already contains ${STABLE_TARBALL}, nothing to do"
  exit 0
fi

if ! curl -sSf https://opendev.org/openstack/cliff/src/branch/stable/${STABLE_VERSION} > /dev/null; then
  echo "https://opendev.org/openstack/cliff/src/branch/stable/${STABLE_VERSION}" | tee -a ${PROJECT}/failures.txt
  exit 1
fi

cat > ${PROJECT}/${PACKAGE}/_service <<EOF
<services>
  <service name="obs_scm">
    <param name="url">https://opendev.org/openstack/${REQ_NAME}.git</param>
    <param name="revision">stable/2023.2</param>
    <param name="versionformat">2023.2.0</param>
    <param name="scm">git</param>
  </service>
  <service mode="buildtime" name="tar" />
  <service mode="buildtime" name="recompress">
    <param name="file">*.tar</param>
    <param name="compression">xz</param>
  </service>
  <service mode="buildtime" name="set_version" />
</services>
EOF

osc add ${PROJECT}/${PACKAGE}/_service

TARGET_SRC_FILE=$(basename ${TARGET_URL})
osc rm ${PROJECT}/${PACKAGE}/${TARGET_SRC_FILE}

sed -i "s;${TARGET_URL};${STABLE_TARBALL};" ${PROJECT}/${PACKAGE}/*.spec

NEW_SPEC_VERSION="Version:        ${STABLE_VERSION}.${MINOR_VERSION}"
TARGET_SPEC_VERSION=$(grep "^Version:" ${PROJECT}/${PACKAGE}/*.spec)
sed -i "s;${TARGET_SPEC_VERSION};${NEW_SPEC_VERSION};" ${PROJECT}/${PACKAGE}/*.spec

NEW_SPEC_AUTOSETUP="%autosetup -p1 -n ${REQ_NAME}-%{version}"
TARGET_SPEC_AUTOSETUP=$(grep "^%autosetup" ${PROJECT}/${PACKAGE}/*.spec)
sed -i "s;${TARGET_SPEC_AUTOSETUP};${NEW_SPEC_AUTOSETUP};" ${PROJECT}/${PACKAGE}/*.spec

sed -i '/^%build/a export PBR_VERSION=%{version}' ${PROJECT}/${PACKAGE}/*.spec
sed -i '/^%install/a export PBR_VERSION=%{version}' ${PROJECT}/${PACKAGE}/*.spec

osc diff ${PROJECT}/${PACKAGE}
osc ci -m "Updated to $STABLE_VERSION" ${PROJECT}/${PACKAGE}
