#!/bin/bash

DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

DATA_DIR=/var/debug-data
MAX_ITERATIONS=5
TIME_BETWEEN_ROLLOVERS=10

function ctrl_c() {
  echo "CTRL-C - cleaning up"
  i=0
  while [ $i -lt $MAX_ITERATIONS ]; do 
    "${DIR}"/gather.sh stop "${i}" &
    i=$((i+1))
  done
  echo "Sleeping for 60 seconds before shutting down"
  sleep 60
  exit 0
}

trap ctrl_c SIGINT

mkdir "${DATA_DIR}"

# Run first iteration.
iteration=0
echo "On iteration ${iteration}"
rm -Rf "${DATA_DIR:?}/${iteration:?}"
"${DIR}"/gather.sh start "${DATA_DIR}/${iteration}" "${iteration}"

# Now start with second iteration.
while true; do 
  sleep $TIME_BETWEEN_ROLLOVERS

  old_iteration=$iteration
  iteration=$((iteration+1))
  iteration=$((iteration%MAX_ITERATIONS))

  echo "On iteration ${iteration}"
  rm -Rf "${DATA_DIR:?}/${iteration:?}"
  "${DIR}"/gather.sh start "${DATA_DIR}/${iteration}" "${iteration}"

  echo "Archiving iteration ${old_iteration}"
  rm -f "${DATA_DIR}/${old_iteration}.tar.gz"
  "${DIR}"/gather.sh archive "${DATA_DIR}/${old_iteration}" "${old_iteration}" "${DATA_DIR}/${old_iteration}.tar.gz"
done
