#!/bin/bash

set -eux

PROJECT="home:steven.hardy:testing:Cloud:OpenStack:Bobcat"
UPPER_CONSTRAINTS="https://opendev.org/openstack/requirements/raw/branch/stable/2023.2/upper-constraints.txt"
IRONIC_REQUIREMENTS="https://opendev.org/openstack/ironic/raw/branch/stable/2023.2/requirements.txt"

if [ $# != 1 ]; then
  echo "Usasge: $0 <package name>"
  exit 1

fi
PACKAGE=$1

# checkout out openSUSE:Factory package or update if it already exists
if [ -d "openSUSE:Factory/${PACKAGE}" ]; then
  echo "openSUSE:Factory/${PACKAGE} exists"
  osc -A https://api.opensuse.org update openSUSE:Factory/${PACKAGE}
else
  echo "openSUSE:Factory/${PACKAGE} does not exist"
  osc -A https://api.opensuse.org checkout openSUSE:Factory/${PACKAGE}
fi

NUM_SOURCES=$(grep "^Source" openSUSE:Factory/${PACKAGE}/*.spec | wc -l)
if [ ${NUM_SOURCES} -ne 1 ]; then
  echo "Error only one Source file supported"
  exit 1
fi
FACTORY_SOURCE=$(grep "^Source" openSUSE:Factory/${PACKAGE}/*.spec)

# checkout the target package or update if it already exists
if [ -d "${PROJECT}/${PACKAGE}" ]; then
  echo "${PROJECT}/${PACKAGE} exists"
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

REQ_NAME=$(echo ${PACKAGE} | sed 's/python-//g')
echo "REQ_NAME=${REQ_NAME}"
TARGET_URL=$(echo ${TARGET_SOURCE} | awk '{print $2}')
FACTORY_URL=$(echo ${FACTORY_SOURCE} | awk '{print $2}')
TARGET_VERSION=$(basename -s '.tar.gz' ${TARGET_URL} | sed "s/^${REQ_NAME}-//")
FACTORY_VERSION=$(basename -s '.tar.gz' ${FACTORY_URL} | sed "s/^${REQ_NAME}-//")
if [ "${TARGET_URL}" != "${FACTORY_URL}" ]; then
  echo "${TARGET_URL} != ${FACTORY_URL}"
  echo "${TARGET_VERSION} != ${FACTORY_VERSION}"
else
  echo "${TARGET_URL}" =!= "${FACTORY_URL}, nothing to do"
  exit 0
fi

if [ ! -f ${PROJECT}/upper-constraints.txt ]; then
  curl ${UPPER_CONSTRAINTS} -o ${PROJECT}/upper-constraints.txt
fi

if [ ! -f ${PROJECT}/ironic-requirements.txt ]; then
  curl ${IRONIC_REQUIREMENTS} -o ${PROJECT}/ironic-requirements.txt
fi

# Check the factory version meets the ironic constraints
if grep ${REQ_NAME} ${PROJECT}/ironic-requirements.txt; then
  IRONIC_REQ=$(grep ${REQ_NAME} ${PROJECT}/ironic-requirements.txt)
  echo "IRONIC_REQ=${IRONIC_REQ}"

  IFS=',' read -ra IRONIC_REQS <<< $(echo ${IRONIC_REQ} | sed "s/^${REQ_NAME}//" | sed 's/#.*$//')
  for req in "${IRONIC_REQS[@]}"; do
    echo "req=$req"
    if [[ ${req} =~ ^'>=' ]]; then
      ver=$(echo ${req} | sed 's/^>=//')
      if printf '%s\n' "${FACTORY_VERSION}" "${ver}" | sort -C -V; then
        echo "Version ${FACTORY_VERSION} does not satisfy requirement ${req}"
        exit 1
      fi
    elif [[ ${req} =~ ^'!=' ]]; then
      ver=$(echo ${req} | sed 's/^!=//')
      if [[ ${FACTORY_VERSION} == ${ver} ]]; then
        echo "Version ${FACTORY_VERSION} does not satisfy requirement ${req}"
        exit 1
      fi
    elif [[ ${req} =~ ^'==' ]]; then
      ver=$(echo ${req} | sed 's/^==//')
      if [[ ${FACTORY_VERSION} != ${ver} ]]; then
        echo "Version ${FACTORY_VERSION} does not satisfy requirement ${req}"
        exit 1
      fi
    else
      echo "Unexpected requirement ${req}"
      exit 1
    fi
  done
else
  echo "${REQ_NAME} not found in ${PROJECT}/ironic-requirements.txt"
fi

# Check the factory version does not exceed the upper contraint
UPPER_REQ=$(grep $REQ_NAME ${PROJECT}/upper-constraints.txt)
echo "UPPER_REQ=${UPPER_REQ}"
UPPER_VERSION=$(echo ${UPPER_REQ} | sed "s/^${REQ_NAME}===//" | sed 's/#.*$//')
echo "UPPER_VERSION=${UPPER_VERSION}"
if ! printf '%s\n' "${FACTORY_VERSION}" "${UPPER_VERSION}"; then
  echo "${FACTORY_VERSION} exceeds upper constraint ${UPPER_VERSION}"
  exit 1
fi


# If we got here it should be safe to update the source
FACTORY_SRC_FILE=$(basename ${FACTORY_URL})
if [ ! -f "openSUSE:Factory/${PACKAGE}/${FACTORY_SRC_FILE}" ]; then
  echo "openSUSE:Factory/${PACKAGE}/${FACTORY_SRC_FILE} does not exist!"
  exit 1
else
  echo "copying openSUSE:Factory/${PACKAGE}/${FACTORY_SRC_FILE}"
  cp openSUSE:Factory/${PACKAGE}/${FACTORY_SRC_FILE} ${PROJECT}/${PACKAGE}
  osc add ${PROJECT}/${PACKAGE}/${FACTORY_SRC_FILE}

  TARGET_SRC_FILE=$(basename ${TARGET_URL})
  osc rm ${PROJECT}/${PACKAGE}/${TARGET_SRC_FILE}

  sed -i "s;${TARGET_SOURCE};${FACTORY_SOURCE};" ${PROJECT}/${PACKAGE}/*.spec


  FACTORY_SPEC_VERSION=$(grep "^Version:" openSUSE:Factory/${PACKAGE}/*.spec)
  TARGET_SPEC_VERSION=$(grep "^Version:" ${PROJECT}/${PACKAGE}/*.spec)
  sed -i "s;${TARGET_SPEC_VERSION};${FACTORY_SPEC_VERSION};" ${PROJECT}/${PACKAGE}/*.spec

  FACTORY_SPEC_AUTOSETUP=$(grep "^%autosetup" openSUSE:Factory/${PACKAGE}/*.spec)
  TARGET_SPEC_AUTOSETUP=$(grep "^%autosetup" ${PROJECT}/${PACKAGE}/*.spec)
  sed -i "s;${TARGET_SPEC_AUTOSETUP};${FACTORY_SPEC_AUTOSETUP};" ${PROJECT}/${PACKAGE}/*.spec

  osc diff ${PROJECT}/${PACKAGE}
  echo "Done - if OK then osc ci -m \"Updated to $FACTORY_VERSION\" ${PROJECT}/${PACKAGE}"
fi
