# eks-bootstrap-flux

Terraform deployments call `bootstrap.sh` during bootstrapping to install [Weave Flux](https://github.com/weaveworks/flux).

Configuration of Flux is then managed by the Flux Operator, in the configuration repo passed as an argument to this script.
