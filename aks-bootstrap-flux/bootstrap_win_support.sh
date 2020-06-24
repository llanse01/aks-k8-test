#!/bin/bash

###############
## Variables ## 

## -- undeclared variables passed from Terraform -- ##

## path dictated by terraform-aws-modules/terraform-aws-eks module
export KUBECONFIG=${config_output_path}kubeconfig_${cluster_name}


######################################
## Remove default gp2 storage class ##

kubectl delete sc gp2 


############################################
## Install Tiller (Helm server component) ##

kubectl -n kube-system create sa tiller
kubectl create clusterrolebinding tiller-cluster-role --clusterrole=cluster-admin --serviceaccount=kube-system:tiller

helm init --history-max 5 --skip-refresh --upgrade --service-account tiller

until helm version --server --tiller-connection-timeout 5
do
  echo "Waiting for tiller to become available..."  &&  sleep 5
done

helm repo update


##################################
## Install AWS VPC CNI & Calico ##

helm repo add eks https://aws.github.io/eks-charts

### temporary fix for known issue - command fails first time
for i in one two; do
  helm upgrade -i --recreate-pods --force --wait aws-vpc-cni \
    --set image.region=${aws_region} \
    --namespace kube-system \
    eks/aws-vpc-cni
done

kubectl apply -k github.com/aws/eks-charts/stable/aws-calico//crds?ref=master

helm upgrade -i aws-calico \
  --namespace kube-system \
  eks/aws-calico
  

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

###########################
# Install Windows Support #

# Deploy the VPC resource controller
kubectl apply -f https://amazon-eks.s3-us-west-2.amazonaws.com/manifests/us-west-2/vpc-resource-controller/latest/vpc-resource-controller.yaml

# Create the VPC admission controller webhook manifest
curl -o webhook-create-signed-cert.sh https://amazon-eks.s3-us-west-2.amazonaws.com/manifests/us-west-2/vpc-admission-webhook/latest/webhook-create-signed-cert.sh
curl -o webhook-patch-ca-bundle.sh https://amazon-eks.s3-us-west-2.amazonaws.com/manifests/us-west-2/vpc-admission-webhook/latest/webhook-patch-ca-bundle.sh
curl -o vpc-admission-webhook-deployment.yaml https://amazon-eks.s3-us-west-2.amazonaws.com/manifests/us-west-2/vpc-admission-webhook/latest/vpc-admission-webhook-deployment.yaml

chmod +x webhook-create-signed-cert.sh webhook-patch-ca-bundle.sh

./webhook-create-signed-cert.sh

cat ./vpc-admission-webhook-deployment.yaml | ./webhook-patch-ca-bundle.sh > vpc-admission-webhook.yaml

# Deploy the VPC admission webhook
kubectl apply -f vpc-admission-webhook.yaml