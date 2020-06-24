##################
# Bootstrap Flux #
##################
data "http" "eks_bootstrap" {
  #url = "https://gitlab.b2b.regn.net/kubernetes/source-files/eks-bootstrap-flux/raw/master/bootstrap.sh"
  url = "https://github.com/llanse01/aks-k8-test/raw/master/aks-bootstrap-flux/bootstrap.sh"
}



#############
# Providers #
#############

provider "azurerm" {
  version = ">=2.0.0"
  subscription_id = "78094477-0830-4b26-a864-26d1dc42deb9"
  features {}
}

provider "helm" {
  alias = "aks"
  kubernetes {
    host                   = module.kubernetes.host
    client_certificate     = base64decode(module.kubernetes.client_certificate)
    client_key             = base64decode(module.kubernetes.client_key)
    cluster_ca_certificate = base64decode(module.kubernetes.cluster_ca_certificate)
  }
}

#####################
# Pre-Build Modules #
#####################

module "subscription" {
  source = "github.com/Azure-Terraform/terraform-azurerm-subscription-data.git?ref=v1.0.0"
  subscription_id = "78094477-0830-4b26-a864-26d1dc42deb9"
}

module "rules" {

  source = "/Users/slland/terraform_work/LN-DEV/test/modules/python-azure-naming"
}

module "metadata"{
  source = "github.com/Azure-Terraform/terraform-azurerm-metadata.git?ref=v1.0.0"

  naming_rules = module.rules.yaml

  market              = "us"
  project             = "llanse01test"
  location            = "useast2"
  sre_team            = "core"
  cost_center         = "st106"
  environment         = "sandbox"
  product_name        = "llansetest"
  business_unit       = "iog"
  product_group       = "core"
  subscription_id     = module.subscription.output.subscription_id
  subscription_type   = "nonprod"
  resource_group_type = "app"
}

module "resource_group" {
  source = "github.com/Azure-Terraform/terraform-azurerm-resource-group.git?ref=v1.0.0"

  location = module.metadata.location
  names    = module.metadata.names
  tags     = module.metadata.tags
}

module "app_reg" {
  source = "github.com/Azure-Terraform/terraform-azuread-application-registration.git?ref=v1.0.0"

  names    = module.metadata.names
  tags     = module.metadata.tags

}

module "kubernetes" {
  source = "/Users/slland/terraform_work/LN-DEV/test/modules/terraform-azurerm-kubernetes"
  #source = "github.com/Azure-Terraform/terraform-azurerm-kubernetes.git"

  location                 = module.metadata.location
  names                    = module.metadata.names
  tags                     = module.metadata.tags
  kubernetes_version       = "1.18.2"
  resource_group_name      = module.resource_group.name
  service_principal_id     = module.app_reg.application_id
  service_principal_name   = module.app_reg.service_principal_name
  service_principal_secret = module.app_reg.service_principal_secret
}
