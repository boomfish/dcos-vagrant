#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Setup Docker daemon for overlay networking support
if [ -n "${DCOS_OVERLAYNET_ENABLED:-}" ]; then
  echo ">>> Registering cluster for Docker overlay networking (store=boot.dcos:2181, listen=:2376, advertise=:3376)"
  # TODO: TLS authentication
  sed -i -e '/^ExecStart=/ s/$/ --cluster-store=zk:\/\/boot.dcos:2181 --cluster-advertise=enp0s8:3376/' /usr/lib/systemd/system/docker.service
  cat << 'EOF' > "/usr/lib/systemd/system/docker-tcp.socket"
[Unit]
Description=Docker Socket for the API

[Socket]
ListenStream=2376
Service=docker.service
BindIPv6Only=both

[Install]
WantedBy=sockets.target
EOF

  echo ">>> Reloading systemd service configs"
  systemctl daemon-reload
  echo ">>> Restarting docker"
  systemctl restart docker
fi

if docker ps --format="{{.Image}}" --filter status=running | grep -q jplock/zookeeper; then
  echo ">>> Not starting zookeeper (already running)"
else
  echo ">>> Starting zookeeper (for exhibitor bootstrap and quorum)"
  docker run -d -p 2181:2181 -p 2888:2888 -p 3888:3888 --restart=always jplock/zookeeper
fi

if docker ps --format="{{.Image}}" --filter status=running | grep -q nginx; then
  echo ">>> Not starting nginx (already running)"
else
  echo ">>> Starting nginx (for distributing bootstrap artifacts to cluster)"
  docker run -d -v /var/tmp/dcos:/usr/share/nginx/html -p 80:80 --restart=always nginx
fi

# Provide a local docker registry for testing purposes. Agents will also get
# the boot node allowed as an insecure registry.
if [ "${DCOS_PRIVATE_REGISTRY}" == "true" ]; then
  if docker ps --format="{{.Image}}" --filter status=running | grep -q registry; then
    echo ">>> Not starting private docker registry (already running)"
  else
    echo ">>> Starting private docker registry"
    docker run -d -p 5000:5000 --restart=always registry:2
  fi
fi
fi

if [ "${DCOS_JAVA_ENABLED:-false}" == "true" ]; then
  echo ">>> Copying java artifacts to nginx directory (/var/tmp/dcos/java)."
  mkdir -p /var/tmp/dcos/java
  cp -rp /vagrant/provision/gs-spring-boot-0.1.0.jar /var/tmp/dcos/java/
  cp -rp /vagrant/provision/jre-*-linux-x64.* /var/tmp/dcos/java/
fi

mkdir -p ~/dcos/genconf

echo ">>> Downloading dcos_generate_config.sh (for building bootstrap image for system)"
curl "${DCOS_GENERATE_CONFIG_PATH}" > ~/dcos/dcos_generate_config.sh
