#!/bin/bash

ACTION="$1"

GATHER_DIR=/var/gather-data
IDENTIFIER=0
ARCHIVE=/tmp/archive.tar.gz

help() {
  local prog
  prog=$(basename "$0")
  echo "./$prog"
  echo "    help"
  echo "          print this help text"
  echo "    start [gather directory] [identifier]"
  echo "          start data gathering in directory ${GATHER_DIR}"
  echo "    stop [identifier]"
  echo "          stop data gathering"
  echo "    cleanup [gather directory] [identifier]"
  echo "          stop data gathering and delete data gathering directory"
  echo "    archive [gather directory] [identifier] [archive])"
  echo "          stop data gathering, tar up contents to ${ARCHIVE} and delete gathering directory"
  echo "Example: ./$prog start /var/gather-data2"
}

gather_dir_exists() {
  if [ -d "${GATHER_DIR}" ]; then
    echo "Directory ${GATHER_DIR} exists. Delete it first (run cleanup action)"
    exit 1
  fi
}

gather_dir_does_not_exist() {
  if ! [ -d "${GATHER_DIR}" ]; then
    echo "Directory ${GATHER_DIR} does not exist. Nothing to do"
    exit 1
  fi
}

gather() {
  echo "Gathering data in ${GATHER_DIR} with identifier ${IDENTIFIER}"
  mkdir -p "${GATHER_DIR}"

  podman run \
    --name "gather-monitor-${IDENTIFIER}" \
    --privileged \
    --network=host \
    -v /proc/:/proc \
    -v "${GATHER_DIR}:/gather-dir:z" \
    -d --rm \
    quay.io/akaris/must-gather-network-metrics:v0.4 \
    /bin/bash -c "mkdir /gather-dir/monitor; cd /gather-dir/monitor; export SS_OPTS=\"-noemitaupwS\"; bash /resources/monitor.sh -d 10"

#  podman run \
#    --name "gather-pidstat-${IDENTIFIER}" \
#    -v "${GATHER_DIR}:/gather-dir:z" \
#    -d --rm \
#    --privileged \
#    -v /proc/:/proc \
#    --pid=host \
#    quay.io/akaris/must-gather-network-metrics:v0.4 \
#    /bin/bash -c "pidstat -p ALL -T ALL -I -l -r -t -u -d -w 5 > /gather-dir/pidstat.txt"

  podman run \
    --name "gather-top-${IDENTIFIER}" \
    -v "${GATHER_DIR}:/gather-dir:z" \
    -d --rm \
    --privileged \
    -v /proc/:/proc \
    --pid=host \
    quay.io/akaris/must-gather-network-metrics:v0.4 \
    /bin/bash -c "top -b > /gather-dir/top.txt"

  podman run \
    --name "gather-sar-${IDENTIFIER}" \
    -v "${GATHER_DIR}:/gather-dir:z" \
    -d --rm \
    quay.io/akaris/must-gather-network-metrics:v0.4 \
    /bin/bash -c "sar -A 5 > /gather-dir/sar.txt"
}

stop_gather() {
  # containers="gather-monitor-${IDENTIFIER} gather-pidstat-${IDENTIFIER} gather-top-${IDENTIFIER} gather-sar-${IDENTIFIER}"
  containers="gather-monitor-${IDENTIFIER} gather-top-${IDENTIFIER} gather-sar-${IDENTIFIER}"

  echo "Stopping gather with identifier ${IDENTIFIER}"
  for c in ${containers}; do
    if podman ps | grep -q "$c"; then
      echo "Stopping container ${c}"
      podman stop "${c}"
    fi
  done

  sleep 5

  echo "Force removing left over containers for identifier ${IDENTIFIER}"
  for c in ${containers}; do
    if podman ps -a | grep -q "$c"; then
      echo "Force removing container ${c}"
      podman rm -f "${c}"
    fi
  done
}

cleanup() {
  echo "Deleting ${GATHER_DIR}"
  rm -Rf "${GATHER_DIR}" 2>/dev/null
}

archive_exists() {
  if [ -f "${ARCHIVE}" ]; then
    echo "${ARCHIVE} exists. Delete it first"
    exit 1
  fi
}

archive() {
  echo "Archiving ${GATHER_DIR} to ${ARCHIVE}"
  ionice -c2 -n7 nice -n19 tar -czf "${ARCHIVE}" "${GATHER_DIR}"
}

if [ "${ACTION}" == "start" ]; then
  GATHER_DIR=${2:-$GATHER_DIR}
  IDENTIFIER=${3:-$IDENTIFIER}
  gather_dir_exists
  gather
elif [ "${ACTION}" == "stop" ]; then
  IDENTIFIER=${2:-$IDENTIFIER}
  stop_gather
elif [ "${ACTION}" == "cleanup" ]; then
  GATHER_DIR=${2:-$GATHER_DIR}
  IDENTIFIER=${3:-$IDENTIFIER}
  gather_dir_does_not_exist
  stop_gather
  cleanup
elif [ "${ACTION}" == "archive" ]; then
  GATHER_DIR=${2:-$GATHER_DIR}
  IDENTIFIER=${3:-$IDENTIFIER}
  ARCHIVE=${4:-$ARCHIVE}
  archive_exists
  gather_dir_does_not_exist
  stop_gather
  archive
  cleanup
else
  help
fi
