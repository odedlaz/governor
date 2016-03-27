#!/bin/bash
docker-compose scale node=0
docker-compose stop
docker-compose rm
sudo rm -rf /tmp/postgres-ha
etcdctl rm --recursive /service/postgres-ha
if [ -z "$1" ]; then
	python setup.py sdist
	docker build -t governor_node .
	docker-compose scale node=5
fi
