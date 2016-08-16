#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [ -L /etc/ssl/certs/ca-certificates.crt ]; then
  echo "Certificate Authorities already installed"
  exit 0
fi

echo ">>> Installing Certificate Authorities"
# DC/OS was compiled on ubuntu with certs in a different place!
ln -s /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
