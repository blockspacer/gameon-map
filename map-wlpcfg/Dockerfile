FROM gameontext/docker-liberty-custom:master-14

ENV SERVERDIRNAME map

ADD https://raw.githubusercontent.com/gameontext/gameon/master/bin/init_couchdb.sh /opt/init_couchdb.sh
COPY ./startup.sh /opt/startup.sh
COPY ./servers/gameon-map /opt/ol/wlp/usr/servers/defaultServer/

COPY ./site.json /opt/site.json
COPY ./firstRoom.json /opt/firstRoom.json

CMD ["/opt/startup.sh"]

# Generous start time for constrained systems
HEALTHCHECK \
  --timeout=10s \
  --start-period=2m \
  CMD wget -q -O /dev/null http://localhost:9080/map/v1/health
