#!/bin/bash

set -exu

export DEBIAN_FRONTEND=noninteractive

apt update
apt install -V -y lsb-release

. $(dirname $0)/commonvar.sh

apt install -V -y \
  ${repositories_dir}/${distribution}/pool/${code_name}/${channel}/*/*/*_${architecture}.deb

td-agent --version

case ${code_name} in
    xenial)
	apt install -V -y gnupg wget apt-transport-https
	;;
    *)
	apt install -V -y gnupg1 wget
	;;
esac

/usr/sbin/td-agent-gem install --no-document serverspec
wget -qO - https://packages.confluent.io/deb/5.5/archive.key | apt-key add -
echo "deb [arch=${architecture}] https://packages.confluent.io/deb/5.5 stable main" > /etc/apt/sources.list.d/confluent.list
apt update && apt install -y confluent-community-2.12 ${java_jdk} netcat-openbsd

export KAFKA_OPTS=-Dzookeeper.4lw.commands.whitelist=ruok
/usr/bin/zookeeper-server-start /etc/kafka/zookeeper.properties  &
while true ; do
    sleep 1
    status=$(echo ruok | nc localhost 2181)
    if [ "$status" = "imok" ]; then
	break
    fi
done
/usr/bin/kafka-server-start /etc/kafka/server.properties &
while true ; do
    sleep 1
    status=$(/usr/bin/zookeeper-shell localhost:2181 ls /brokers/ids | sed -n 6p)
    if [ "$status" = "[0]" ]; then
	break
    fi
done
/usr/bin/kafka-topics --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic test
/usr/sbin/td-agent -c /fluentd/serverspec/test.conf &
export PATH=/opt/td-agent/bin:$PATH
export INSTALLATION_TEST=true
cd /fluentd && rake serverspec:linux
