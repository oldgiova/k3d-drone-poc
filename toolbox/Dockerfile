FROM ubuntu:jammy-20231211.1

ARG platform

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
      && apt-get install -y \
        curl \
        pwgen

RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${platform}/kubectl" \
      && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
      && chmod 700 get_helm.sh \
      && ./get_helm.sh

CMD /bin/bash
