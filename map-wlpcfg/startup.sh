#!/bin/bash

export CONTAINER_NAME=map

SERVER_PATH=/opt/ol/wlp/usr/servers/defaultServer

if [ "$ETCDCTL_ENDPOINT" != "" ]; then
  echo Setting up etcd...
  echo "** Testing etcd is accessible"
  etcdctl --debug ls
  RC=$?

  while [ $RC -ne 0 ]; do
    sleep 15

    # recheck condition
    echo "** Re-testing etcd connection"
    etcdctl --debug ls
    RC=$?
  done
  echo "etcdctl returned sucessfully, continuing"

  mkdir -p /etc/cert
  etcdctl get /proxy/third-party-ssl-cert > /etc/cert/cert.pem

  export COUCHDB_SERVICE_URL=$(etcdctl get /couchdb/url)
  export COUCHDB_USER=$(etcdctl get /couchdb/user)
  export COUCHDB_PASSWORD=$(etcdctl get /passwords/couchdb)

  export MAP_KEY=$(etcdctl get /passwords/map-key)

  export PLAYER_SERVICE_URL=$(etcdctl get /player/url)

  export LOGMET_HOST=$(etcdctl get /logmet/host)
  export LOGMET_PORT=$(etcdctl get /logmet/port)
  export LOGMET_TENANT=$(etcdctl get /logmet/tenant)
  export LOGMET_PWD=$(etcdctl get /logmet/pwd)

  export SYSTEM_ID=$(etcdctl get /global/system_id)
  export SWEEP_ID=$(etcdctl get /npc/sweep/id)
  export SWEEP_SECRET=$(etcdctl get /npc/sweep/password)

  GAMEON_MODE=$(etcdctl get /global/mode)
  export GAMEON_MODE=${GAMEON_MODE:-production}
  export TARGET_PLATFORM=$(etcdctl get /global/targetPlatform)

  export KAFKA_SERVICE_URL=$(etcdctl get /kafka/url)

  #to run with message hub, we need a jaas jar we can only obtain
  #from github, and have to use an extra config snippet to enable it.
  export MESSAGEHUB_USER=$(etcdctl get /kafka/user)
  export MESSAGEHUB_PASSWORD=$(etcdctl get /passwords/kafka)
fi

if [ -f /etc/cert/cert.pem ]; then
  echo "Building keystore/truststore from cert.pem"
  echo "-creating dir"
  mkdir -p ${SERVER_PATH}/resources/security
  echo "-cd dir"
  cd ${SERVER_PATH}/resources/
  echo "-converting pem to pkcs12"
  openssl pkcs12 -passin pass:keystore -passout pass:keystore -export -out cert.pkcs12 -in /etc/cert/cert.pem
  echo "-importing pem to truststore.jks"
  keytool -import -v -trustcacerts -alias default -file /etc/cert/cert.pem -storepass truststore -keypass keystore -noprompt -keystore security/truststore.jks
  echo "-creating dummy key.jks"
  keytool -genkey -storepass testOnlyKeystore -keypass wefwef -keyalg RSA -alias endeca -keystore security/key.jks -dname CN=rsssl,OU=unknown,O=unknown,L=unknown,ST=unknown,C=CA
  echo "-emptying key.jks"
  keytool -delete -storepass testOnlyKeystore -alias endeca -keystore security/key.jks
  echo "-importing pkcs12 to key.jks"
  keytool -v -importkeystore -srcalias 1 -alias 1 -destalias default -noprompt -srcstorepass keystore -deststorepass testOnlyKeystore -srckeypass keystore -destkeypass testOnlyKeystore -srckeystore cert.pkcs12 -srcstoretype PKCS12 -destkeystore security/key.jks -deststoretype JKS
  echo "done"
  cd ${SERVER_PATH}
fi

# Check for couchdb. Retry a few times, fail if it doesn't show up.
AUTH_URL=${COUCHDB_SERVICE_URL/\/\//\/\/$COUCHDB_USER:$COUCHDB_PASSWORD@}

# RC=7 means the host isn't there yet. Let's do some re-trying until it
# does start / is ready
RC=7
count=0
while [ $RC -eq 7 ]; do
  echo "** Testing connection to ${COUCHDB_SERVICE_URL}"
  curl -s --fail -X GET ${AUTH_URL}
  RC=$?

  if [ $RC -eq 7 ]; then
    if [ $count -gt 30 ]; then
      echo "Unable to connect to ${COUCHDB_SERVICE_URL}"
      exit 1
    fi
    ((count++))
    sleep 15
  fi
done

ensure_exists() {
  local result=0
  local uri=$1
  local url=${AUTH_URL}/$uri
  shift

  count=0
  while [ $result -ne 200 ]; do
    result=$(curl -s -o /dev/null -w "%{http_code}" --fail -X GET $url)
    echo "**** curl -X GET $uri  ==>  $result"

    case "$result" in
      200)
        continue
      ;;
      404)
        echo "-- curl -X PUT $url"
        curl -s $@ -X PUT $url
      ;;
      409)
        sleep 5
      ;;
      *)
        echo "unknown";
        exit 1
      ;;
    esac
  done
}

if [ "$GAMEON_MODE" == "development" ]; then
  # LOCAL DEVELOPMENT!
  # We do not want to ruin the cloudant admin party, but our code is written to expect
  # that creds are required, so we should make sure the required user/password exist

  echo "** Checking map_repository"
  ensure_exists map_repository

  echo "** Checking design documents"
  ensure_exists map_repository/_design/site --data-binary @/opt/site.json

  echo "** Checking firstroom"
  sed "s/game-on.org/${SYSTEM_ID}/g" /opt/firstRoom.json > /opt/firstRoom.withid.json
  ensure_exists map_repository/firstroom --data-binary @/opt/firstRoom.withid.json
fi

exec /opt/ol/wlp/bin/server run defaultServer
