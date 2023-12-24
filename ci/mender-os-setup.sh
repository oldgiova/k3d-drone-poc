#!/bin/bash
set -euxo pipefail

# Kubectl config
source ./.build_info
#until test -f ${KUBECONFIG}; do sleep 1s; done # wait for k3d service to write the kubeconfig to the workspace

export MENDER_SERVER_DOMAIN="host.k3d.internal"
export MENDER_SERVER_URL="https://${MENDER_SERVER_DOMAIN}"
export MENDER_VERSION_TAG="mender-3.6.3"
export MONGODB_ROOT_PASSWORD=$(pwgen 32 1)
export MONGODB_REPLICA_SET_KEY=$(pwgen 32 1)
export MINIO_DOMAIN_NAME="artifacts.host.k3d.internal"

function install_minio() {
#  cat > ${BUILDDIR}/minio-operator.yml <<EOF
#tenants: {}
#EOF

  source ${BUILDDIR}/build_envs

  helm install minio-operator minio/minio-operator --version 4.1.7 -f ${BUILDDIR}/minio-operator.yml --wait

  export MINIO_ACCESS_KEY=$(pwgen 32 1)
  export MINIO_SECRET_KEY=$(pwgen 32 1)

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: minio-creds-secret
type: Opaque
data:
  accesskey: $(echo -n $MINIO_ACCESS_KEY | base64)
  secretkey: $(echo -n $MINIO_SECRET_KEY | base64)
---
apiVersion: minio.min.io/v2
kind: Tenant
metadata:
  name: minio
  labels:
    app: minio
spec:
  image: minio/minio:RELEASE.2021-06-17T00-10-46Z
  credsSecret:
    name: minio-creds-secret
  pools:
    - servers: 2
      volumesPerServer: 2
      volumeClaimTemplate:
        metadata:
          name: data
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 10Gi
          storageClassName: "local-path"
  mountPath: /export
  requestAutoCert: false
EOF


  cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: minio-ingress
  annotations:
    cert-manager.io/issuer: "letsencrypt"
spec:
  tls:
  - hosts:
    - ${MINIO_DOMAIN_NAME}
    secretName: minio-ingress-tls
  rules:
  - host: "${MINIO_DOMAIN_NAME}"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: minio
            port:
              number: 80
EOF
}

function mender_os_gen_keys() {
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 | openssl rsa -out ${BUILDDIR}/device_auth.key
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 | openssl rsa -out ${BUILDDIR}/useradm.key
}

function helm_init() {
  helm repo add mender https://charts.mender.io
  helm repo add jetstack https://charts.jetstack.io
  helm repo add minio https://operator.min.io/
  helm repo update
}

function mender_os_values_init() {
  source ${BUILDDIR}/build_envs

  cat >${BUILDDIR}/mender-3.6.3.yml <<EOF
global:
  enterprise: false
  image:
    tag: ${MENDER_VERSION_TAG}
  mongodb:
    URL: ""
  nats:
    URL: ""
  s3:
    AWS_URI: "https://${MINIO_DOMAIN_NAME}"
    AWS_BUCKET: "mender-artifact-storage"
    AWS_ACCESS_KEY_ID: "${MINIO_ACCESS_KEY}"
    AWS_SECRET_ACCESS_KEY: "${MINIO_SECRET_KEY}"
  url: "${MENDER_SERVER_URL}"

# This enables bitnami/mongodb sub-chart
mongodb:
  enabled: true
  auth:
    enabled: true
    rootPassword: ${MONGODB_ROOT_PASSWORD}
    replicaSetKey: ${MONGODB_REPLICA_SET_KEY}

# This enabled nats sub-chart
nats:
  enabled: true

api_gateway:
  env:
    SSL: false

device_auth:
  certs:
    key: |-
$(cat device_auth.key | sed -e 's/^/      /g')

useradm:
  certs:
    key: |-
$(cat useradm.key | sed -e 's/^/      /g')

ingress:
  enabled: true
  annotations:
    cert-manager.io/issuer: "letsencrypt"
  path: /
  extraPaths:
    - path: /
      backend:
        serviceName: ssl-redirect
        servicePort: use-annotation

  hosts:
    - ${MENDER_SERVER_DOMAIN}
  tls:
  # this secret must exists or can be created from a working cert-manager instance
   - secretName: mender-ingress-tls
     hosts:
       - ${MENDER_SERVER_DOMAIN}
EOF
}

function mender_os_upgrade() {
  source ${BUILDDIR}/build_envs
  helm upgrade --install mender mender/mender -f ${BUILDDIR}/mender-3.6.3.yml --wait
}

function setup_certmanager() {
  source ${BUILDDIR}/build_envs
  echo "DEBUG - kubeconfig file"
  helm install cert-manager jetstack/cert-manager \
    --version v1.4.0 \
    --wait \
    --set installCRDs=true

  cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: "https://acme-staging-v02.api.letsencrypt.org/directory"
    #email: ${LETSENCRYPT_EMAIL:-roberto.giova+letsencrypt@gmail.com}
    privateKeySecretRef:
      name: letsencrypt
    solvers:
    - http01:
        ingress: {}
EOF
}

function cluster_setup() {
  source .build_info
  export KUBECONFIG=${BUILDDIR}/kubeconfig-${DRONE_BUILD_STARTED}.yaml
  until test -f ${KUBECONFIG}; do sleep 1s; done

  echo "export KUBECONFIG=${BUILDDIR}/kubeconfig-${DRONE_BUILD_STARTED}.yaml" > ${BUILDDIR}/build_envs
  kubectl config view
  kubectl get pods --all-namespaces
  kubectl create namespace mender
  kubectl config set-context --current --namespace=mender
  kubectl get pods
}


helm_init

case $1 in
  "cluster")
    cluster_setup
    ;;
  "minio")
    install_minio
    ;;
  "certmanager")
    setup_certmanager
    ;;
  "mender")
    mender_os_gen_keys
    mender_os_values_init
    mender_os_upgrade
    ;;
  "all")
    install_minio
    setup_certmanager
    mender_os_gen_keys
    mender_os_values_init
    mender_os_upgrade
esac

