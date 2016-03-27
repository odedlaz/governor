#!/bin/bash
leader=$(etcdctl get /service/postgres-ha/leader)
for pid in $(docker ps | awk '/ha-pos/ {print $1}'); do
  name=$(docker inspect $pid | awk -F '"' '/Hostname"/ {print $4}')
  port=$(docker port $pid 5432 | cut -d ":" -f 2)
  msg="name: $name | port: $port | cid: $pid"
  if [ "$leader" != $name ]; then
    echo "F: $msg"
    continue
  fi
  echo "L: $msg"
done
