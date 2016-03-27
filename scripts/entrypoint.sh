#!/bin/bash

if [ "$1" != 'postgres' ]; then
  exec "$@"
fi

cleanup () {
  kill -s SIGTERM $!
  exit 0
}

trap cleanup SIGINT SIGTERM

SERVICE_IP=$(dig +short ${HOSTNAME})
if [ "${SERVICE_IP}" == "" ]; then
    echo "looks like networking is not setup. setting network alias to hostname"
    SERVICE_NAME=${HOSTNAME}
else
  SERVICE_NAME=$(dig +noall +answer -x ${SERVICE_IP} | awk '{ split($5,arr,"."); print arr[1] }' )
fi

BRIDGE_IP=$(ip route | awk '/default via .* dev eth0/ {print $3}')
export PGDATA="${PGDATA}/${SERVICE_NAME}"

sed -i "s#%%ETCD_URL%%#http:/\/${BRIDGE_IP}:4001#g" /postgres.yml
sed -i "s#%%ETCD_SCOPE%%#${ETCD_SCOPE-postgres-ha}#g" /postgres.yml
sed -i "s#%%NODE_NAME%%#${SERVICE_NAME}#g" /postgres.yml
sed -i "s#%%REPLICATION_USER%%#${REPLICATION_USER:-replication}#g" /postgres.yml
sed -i "s#%%REPLICATION_PASSWORD%%#${POSTGRES_PASSWORD}#g" /postgres.yml
sed -i "s#%%PGDATA%%#${PGDATA}#g" /postgres.yml

mkdir -p "$PGDATA"
chmod 700 "$PGDATA"
chown -R postgres "$PGDATA"

chmod g+s /run/postgresql
chown -R postgres /run/postgresql

echo "LOG: starting up governor haproxy-status"
gosu postgres governor --serve-status /postgres.yml &
disown
echo "LOG: starting up governor"
gosu postgres governor /postgres.yml --log-level debug &
governor_pid=$!


if [ -s "$PGDATA/PG_VERSION" ]; then
  wait $governor_pid
  exit $?
fi

# use the run.sh file to spin up a cluster and see if they talk to each other
until gosu postgres nc -z localhost 5432; do
  sleep 1 &
  wait $!
done

if [ "$POSTGRES_PASSWORD" ]; then
			pass="PASSWORD '$POSTGRES_PASSWORD'"
			authMethod=md5
else
	# The - option suppresses leading tabs but *not* spaces. :)
	cat >&2 <<-'EOWARN'
		****************************************************
		WARNING: No password has been set for the database.
		         This will allow anyone with access to the
		         Postgres port to access your database. In
		         Docker's default configuration, this is
		         effectively any other container on the same
		         system.
		         Use "-e POSTGRES_PASSWORD=password" to set
		         it in "docker run".
		****************************************************
	EOWARN

	pass=
	authMethod=trust
fi

{ echo; echo "host all all 0.0.0.0/0 $authMethod"; } >> "$PGDATA/pg_hba.conf"

echo "LOG: setting up a new database & user"

: ${POSTGRES_USER:=postgres}
: ${POSTGRES_DB:=$POSTGRES_USER}

export POSTGRES_USER POSTGRES_DB

psql=( psql -v ON_ERROR_STOP=1 )

if [ "$POSTGRES_DB" != 'postgres' ]; then
	"${psql[@]}" --username postgres <<-EOSQL
		CREATE DATABASE "$POSTGRES_DB" ;
	EOSQL
	echo
fi

if [ "${POSTGRES_USER}" = 'postgres' ]; then
	op='ALTER'
else
	op='CREATE'
fi

"${psql[@]}" --username postgres <<-EOSQL
  $op USER "$POSTGRES_USER" WITH SUPERUSER $pass ;
EOSQL
echo

psql+=( --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" )

wait $governor_pid
