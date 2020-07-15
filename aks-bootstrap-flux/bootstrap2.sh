#!/bin/bash

# #################################################
## Configure                                     ##
az aks get-credentials --subscription ${subscription_id} --resource-group ${resource_group} --name ${cluster_name} --admin --file ${config_output_path}/kubeconfig_${cluster_name}
export KUBECONFIG=${config_output_path}/kubeconfig_${cluster_name}

helm repo add fluxcd https://charts.fluxcd.io/
helm repo update


# ################################################
## Install Flux & Flux Helm Operator            ##

echo "Installing Flux..."

known_host=`echo "\"$(ssh-keyscan -t rsa -p "$(echo "${config_repo_url}" | sed -e "s/\([^@]*\)\@\([^:]*\):\([0-9]*\).*/\3/" | sed -e "s/^$/22/")" "$(echo "${config_repo_url}" | sed -e "s/\([^@]*\)\@\([^:]*\).*/\2/")")"\"`

kubectl apply --filename https://raw.githubusercontent.com/fluxcd/helm-operator/v1.1.0/deploy/crds.yaml

kubectl create namespace fluxcd

kubectl create secret generic flux-ssh \
   --namespace fluxcd \
   --from-file=identity="${config_repo_ssh_key}"

kubectl create secret generic flux-ssh2 \
   --namespace fluxcd \
   --from-file=identity="${reference_repo_ssh_key}"

printf '%s' "# Values
apiVersion: v1
data:
  ssh_config: |
    Host llanse01.github.com
     HostName github.com
     StrictHostKeyChecking no
     User git
     IdentityFile /root/reference/identity
     LogLevel error
    Host *
     StrictHostKeyChecking yes
     IdentityFile /etc/fluxd/ssh/identity
     IdentityFile /var/fluxd/keygen/identity
     LogLevel error
kind: ConfigMap
metadata:
 name: ssh-config
 namespace: fluxcd" >  "${config_map}"

kubectl apply -f ${config_map} \
   --namespace fluxcd

flux_values=${flux_values}
printf '%s' "# VALUES
git:
  url: ${config_repo_url}
  path: ${config_repo_path}
  secretName: flux-ssh
ssh:
  known_hosts: ${known_host}
  enabled: true
extraVolumes:
 - name: git-keygen2
   secret:
     secretName: flux-ssh2
     defaultMode: 0400
 - name: ssh-config
   configMap:
    name: ssh-config
extraVolumeMounts:
 - name: git-keygen2
   mountPath: /root/reference
 - name: ssh-config
   mountPath: /etc/ssh/
" > "${flux_values}"

helm upgrade --install --skip-crds \
  --values "${flux_values}" \
  --namespace fluxcd \
  --version 1.3.0 \
  --wait \
  flux fluxcd/flux

sleep 1m
fluxctl --k8s-fwd-ns fluxcd sync --timeout 5m
