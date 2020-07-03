#!/bin/bash
#: Title        : bootstrap.sh
#: Date         : 23-04-2020
#: Variables    : undeclared variables passed from Terraform
#: About        : This script will boot strap the EKs cluster with the required base install requirements in order
#:              : to allow the helm charts to deploy into the cluster. Each step provides dependencies of the next.

export PATH=$PATH:$HOME/bin
export KUBECONFIG=${config_output_path}kubeconfig_${cluster_name}

function DEBUG() { [[ "$_DEBUG" == "on" ]] && $@ || :; }

function err() { local -n v="$1"; shift && { v="$("$@" 2>&1 1>&3 3>&-)"; } 3>&1; }

function std_err() { printf "\n%s\n\n" "error: Message was: $@"; }

function check_binaries() {
  # Check for the Binaries. Fail script if unavailable.
  for binary in "$@"; do
    sleep 0.1 ; command -v "$binary" >/dev/null 2>&1 || { std_err "$binary not found" >&2; exit 1; }
  done
  return
}


function ia_tiller() {
  # Install tiller to the cluster for Helm interaction.
  [[ $(kubectl -n kube-system create sa tiller) ]] && \
  [[ $(kubectl create clusterrolebinding tiller-cluster-role \
    --clusterrole=cluster-admin                              \
    --serviceaccount=kube-system:tiller) ]] && \
  [[ $(helm init    \
    --history-max 5 \
    --skip-refresh  \
    --upgrade       \
    --service-account tiller) ]] && \
  until helm version --server --tiller-connection-timeout 5; do
    printf "%s\n" "Waiting for tiller to become available..." && sleep 5
  done && \
  [[ $(helm repo update) ]] && return || false
}


function ic_cert_manager() {
  # Install cert-manager crds for use by letsencrypt and external dns
  [[ $(kubectl apply --validate=false -f \
    https://raw.githubusercontent.com/jetstack/cert-manager/release-0.12/deploy/manifests/00-crds.yaml) ]] && \
    return || false
}

function id_prometheus() {
  # Install Prometheus Operator into the iog-platform namespace and disable
  # default install components
  [[ $(kubectl create ns iog-platform) ]] && \
  [[ $(helm upgrade -i prometheus-operator \
    --set prometheus.enabled=false         \
    --set alertmanager.enabled=false       \
    --set grafana.enabled=false            \
    --namespace iog-platform               \
    stable/prometheus-operator) ]] && return
  false
}

function ie_flux() {
  # Install Flux for GitOps,  Flux will install into the flux namespace and scan
  # gitlab for its ssh key. Manually adding the flux key to the repo is required.
  [[ $(kubectl create ns flux && helm repo add fluxcd https://charts.fluxcd.io) ]] && \
  [[ $(helm repo add fluxcd https://charts.fluxcd.io) ]] && \
  [[ $(helm upgrade -i flux                                           \
    --set git.url=${config_repo_url}                                  \
    --set-string ssh.known_hosts="$(ssh-keyscan ${config_repo_host})" \
    --set syncGarbageCollection.enabled=true                          \
    --namespace flux                                                  \
    fluxcd/flux) ]] && \
  [[ $(helm upgrade -i flux-helm-operator \
    --set createCRD=true                  \
    --namespace flux                      \
    fluxcd/helm-operator) ]] && return || false
}


_DEBUG="off"

main() {
  # Main function call, will scan the script and select all functions,
  # running each in order of declaration from top to bottom.
  printf "%s\n" "Starting $(basename $0)" ; sleep 0.1
  declare -a execute_all
  for f in $(typeset -f | awk '!/^main[ (]/ && /^[^ {}]+ *\(\)/ { gsub(/[()]/, "", $1); print $1}'); do
    if [[ "$f" != "DEBUG" ]] && [[ "$f" != "err" ]] && [[ "$f" != "std_err" ]] && [[ "$f" != "check_binaries" ]]; then
      execute_all+=( "$f" )
    fi
  done
  while :; do
    # Check to ensure default binaries are in place on the system to
    # allow the script to cleanly execute
    printf "%s\n" "1. Checking for installed binaries" ; sleep 0.1
    check_binaries "kubectl" "helm" && printf "%s\n" "done."
    kubectl config view ; sleep 0.1
    # Execute over the array of function names
    for (( i=0; i < $${#execute_all[@]}; i++ )); do
      printf "%s\n" "$((i+2)). Running $(echo $${execute_all[$i]} | sed -r 's/^[i][abcdefg]_/install /g')" ; sleep 0.1
      err error $${execute_all[$i]} && printf "%s\n" "done." || { std_err "$error" >&2; exit $((i+2)); }
    done
    break
  done
  printf "%s\n" "$(basename $0) finished successfully."
}
main "$@"
