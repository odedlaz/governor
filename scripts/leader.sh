#!/bin/bash
leader=$(etcdctl get /service/postgres-ha/leader)
for pid in $(docker ps | awk '/governor/ {print $1}'); do
  name=$(docker inspect $pid | jq -r ". [] | .Name" | sed 's#/##')
  port=$(docker port $pid 5432 | cut -d ":" -f 2)
  http_port=$(docker port $pid 15432 | cut -d ":" -f 2)
  msg="name: $name | port: $port | http-port: $http_port | cid: $pid"
  if [ "$leader" != $name ]; then
    echo -e "\e[43;30m$msg\e[49m"
    continue
  fi
  echo -e "\e[44;97m$msg\e[49m"

done
