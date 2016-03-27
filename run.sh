#!/bin/bash
set -e

if [ -z "${CLUSTER_NAME}" ]; then
  echo "you need to set the cluster name"
  exit 1
fi

if [ -z "${NODE_ID}" ]; then
  echo "you need to set the node number"
  exit 1
fi


if [ ! -z "${INIT}" ]; then
  if [ "${INIT}" = "2" ]; then
    docker build -t ha-postgres .
  fi
  sudo rm -rf /tmp/postgres-ha
  set +e
  etcdctl rm --recursive /service &> /dev/null
  set -e
fi

NODE_NAME=${CLUSTER_NAME}_node_${NODE_ID}

mkdir -p /tmp/postgres-ha/$NODE_NAME
docker run -t -i -h $NODE_NAME \
           -p 3281${NODE_ID}:5432 \
           -v /tmp/postgres-ha/$NODE_NAME:/var/lib/postgresql/data \
           --net-alias=$NODE_NAME \
           --net="postgres" \
           ha-postgres "$@"
