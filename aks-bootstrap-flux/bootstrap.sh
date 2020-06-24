#!/bin/bash

###############
## Variables ## 

## -- undeclared variables passed from Terraform -- ##

## path dictated by terraform-aws-modules/terraform-aws-eks module
#export KUBECONFIG=${config_output_path}kubeconfig_${cluster_name}
az aks get-credentials --resource-group app-llansetest-sandbox-useast2 --name aks-app-llansetest-sandbox-useast2 --admin --file kubeconfig
export KUBECONFIG=kubeconfig

######################################
## Remove default gp2 storage class ##

#kubectl delete sc gp2 


############################################
## Install Tiller (Helm server component) ##

#kubectl -n kube-system create sa tiller
#kubectl create clusterrolebinding tiller-cluster-role --clusterrole=cluster-admin --serviceaccount=kube-system:tiller

#helm init --history-max 5 --skip-refresh --upgrade --service-account tiller

#until helm version --server --tiller-connection-timeout 5
#do
#  echo "Waiting for tiller to become available..."  &&  sleep 5
#done

#helm repo update



###############################  
## Install cert-manager crds ##

kubectl apply --validate=false -f https://raw.githubusercontent.com/jetstack/cert-manager/v0.13.0/deploy/manifests/00-crds.yaml 

#################################  
## Install Prometheus Operator ##

kubectl create ns iog-platform

helm upgrade -i prometheus-operator \
  --set prometheus.enabled=false \
  --set alertmanager.enabled=false \
  --set grafana.enabled=false \
  --namespace iog-platform \
  stable/prometheus-operator
  
  
##################
## Install Flux ##

kubectl create ns flux

helm repo add fluxcd https://charts.fluxcd.io

helm upgrade -i flux \
  --set git.url=${config_repo_url} \
  --set-string ssh.known_hosts="$(ssh-keyscan ${config_repo_host})" \
  --set syncGarbageCollection.enabled=true \
  --namespace flux \
  fluxcd/flux
  
helm upgrade -i flux-helm-operator \
  --set createCRD=true \
  --namespace flux \
  fluxcd/helm-operator
