#!/bin/bash

set -euo pipefail


function install_os_packages() {
  DEBIAN_FRONTEND=noninteractive apt-get update \
    && apt-get install -y \
      curl \
      pwgen

}

platform=$(uname -i)
test "${platform}" == "x86_64" && platform="amd64"

function setup_kubectl() {
  # Setup kubectl
  echo "INFO - setup kubectl tool"
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${platform}/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
}

function setup_helm() {
  # Setup helm
  echo "INFO - setup helm"
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
}

install_os_packages
setup_kubectl
setup_helm
