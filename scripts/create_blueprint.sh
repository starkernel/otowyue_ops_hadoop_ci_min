#!/bin/bash
if [ -r /etc/hodoopforge/ambari.env ]; then . /etc/hodoopforge/ambari.env; fi
AMBARI_USER="${AMBARI_USER:-admin}"
AMBARI_PASS="${AMBARI_PASS:-admin}"
read -p "What is the cluster name? " CLUSTERNAME
CLUSTERNAME_FORMATTED=`echo -n $CLUSTERNAME`
curl -u "$AMBARI_USER:$AMBARI_PASS" http://localhost:8080/api/v1/clusters/${CLUSTERNAME_FORMATTED}?format=blueprint > blueprint.json
echo "Wrote blueprint.json."
