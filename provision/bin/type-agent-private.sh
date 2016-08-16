#!/usr/bin/env bash

set -o nounset
set -o pipefail

# By default, agents are provisioned in parallel during boot machine provisioning.
# The following agent provisioning should only run if the boot machine provisioning has already occurred.
# This ready check validates that the boot machine is ready and not just being impersonated by DNS hijacking.
if [ "$(curl --fail --location --max-redir 0 --silent http://boot.dcos/ready)" != "ok" ]; then
  echo "Skipping DC/OS private agent install (boot machine will provision in parallel)"
  exit 0
fi

set -o errexit

echo ">>> Installing DC/OS slave"
curl --fail --location --max-redir 0 --silent --show-error --verbose http://boot.dcos/dcos_install.sh | bash -s -- slave

echo ">>> Executing DC/OS Postflight"
dcos-postflight

if [ -n "${DCOS_TASK_MEMORY:-}" ]; then
  echo ">>> Setting Mesos Memory: ${DCOS_TASK_MEMORY} (role=*)"
  mesos-memory ${DCOS_TASK_MEMORY}
  echo ">>> Restarting Mesos Agent"
  systemctl stop dcos-mesos-slave.service
  rm -f /var/lib/mesos/slave/meta/slaves/latest
  systemctl start dcos-mesos-slave.service --no-block
fi

# Setup Docker daemon for overlay networking support
if [ -n "${DCOS_OVERLAYNET_ENABLED:-}" ]; then
  echo ">>> Registering cluster for Docker overlay networking (store=boot.dcos:2181, listen=:2376, advertise=:3376)"
  # TODO: TLS authentication - see https://docs.docker.com/v1.11/engine/security/https/
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
