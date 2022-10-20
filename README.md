# eck-cloud
Sample configuration files for running Elastic Cloud on Kubernetes (ECK) on top of a managed K8s service

_This is not an official Elastic repository, just the documented process of my work deploying ECK on a German Cloud. For official resources and documentation, check the links at the bottom of the page._ 

## 1. Infrastructure

In this example, ECK will be hosted by the managed K8s service of German cloud provider IONOS.

For provisioning the K8s Cluster and the needed additional cloud ressources we'll use Terraform. 

Install terraform following the official documentation.

An example of [main.tf](terraform/ionos/main.tf) is provided in this repo.
The _main.tf_ uses variables, defined in file _variables.tf_. The value of the variables can be included in a local _.tfvars_ file or can be provided later interactively when prompted by _terraform apply_.

Initialize terraform: 
```
eramon@applejuice eck-cloud % cd terraform/ionos
eramon@applejuice ionos % terraform init
```
Apply the configuration:
```
eramon@applejuice ionos % terraform apply
```
You'll be prompted to provide the variables defined in [variables.tf](terraform/ionos/variables.tf). Alternatively, you can create a file _myvars.tfvars_ assigning values to the variables, and then pass it as parameter to the apply command:
```
eramon@applejuice ionos % terraform apply -var-file=myvars.tfvars
```
Answer _yes_ when prompted.

Following things will happen:
* A Data Center is created associated to the IONOS account defined in the environment variables _ionos_username_ and _ionos_password_
* A K8s Cluster is provisioned in the Data Center, according to the settings specified in the terraform configuration
* A Node Pool is created for the K8s Cluster, with the size and ressources specified in the terraform configuration
* A Public IP is provisioned for the Data Center
* The kubeconfig of the K8s cluster is dumped to the local file _kubeconfig.json_
* Using the Helm Provider, the nginx-ingress-controller is installed with type LoadBalancer and the provisioned IP
* A DNS A Record is created binding my hostname.domain to the provisioned public IP

_Note: I created a DNS Record in GCP Cloud DNS. The DNS Record can be created in this way for any DNS service provider supporting Terraform._

Using the _nginx ingress-controller_ is specific for this PoC and not necessarily the only way to manage access. It's just my preferred way to do so, instead of exposing directly the kibana service, which would also work.

## 2. K8s ressources

Set the $KUBECONFIG environment variable:
```
eramon@applejuice eck-cloud % export KUBECONFIG=terraform/ionos/kubeconfig.json
``` 
Our K8s cluster is up and running:
```
eramon@applejuice eck-cloud % kubectl cluster-info
Kubernetes control plane is running at https://cp-42876.cluster.ionos.com:12268
CoreDNS is running at https://cp-42876.cluster.ionos.com:12268/api/v1/namespaces/kube-system/services/coredns:udp-53/proxy
```

### 2.2. kustomize

The provisioning of the K8s ressources can be automated via kustomize. Following resources will be deployed:
 * The ECK Custom Resource Definitions (CRDs)
 * The ECK Operator
 * The cert-manager and the cluster issuer, to automate the creation of the SSL certificate, signed by Let's Encrypt CA
 * Ingress, to manage access to the kibana service
 * Elasticsearch
 * Kibana
 * Fleet server (which is indeed an agent)
 * The Agents (for K8s System Integration, one for each K8s node)
 * Resources needed by fleet and the agents: service accounts, cluster roles and cluster role bindings 
 
Sample [kustomize.yaml](kustomization.yaml) file and manifests for the K8s ressources are available in this repo.

As manifests for the elastic resources, I mainly used the available manifests from the ECK guides mentioned below and the _cloud_on_k8s_ repo(see links at the bottom of the page), with very little modifications. 

_NOTE: There are available manifests containing all ressources, I downloaded the manifests and separated their content in dedicated files mainly to ease my own understanding._

Worth to mention might be following changes:
 * I changed the type of the Kibana service from LoadBalancer to ClusterIP and deactivated SSL for Kibana, in order to manage SSL termination at the ingress
 * I set the number of elasticsearch nodes to 2
 * I created a persistent volume claim for each elasticsearch node, using the _ionos-enterprise-ssd_ storage class of the cloud provider

Specific to this PoC are _cert-manager_ and _clusterissuer_, in order to automatically retrieve trusted SSL certificates from open CA Let's Encrypt when accesing Kibana. 

The ingress provides access to the Kibana service and takes care of SSL termination. The file [ingress.yaml.sample](ingress.yaml.sample) does not include the actual domain I used. The host and domain must be set and the file must be renamed to _ingress.yaml_.

Regarding persistent volumes, this approach is good for demo purposes but it might not be the right call for some use cases in a productive setup. See links below for further information about _Storage recommendations_.

With the manifests ready, just apply the K8s configuration:
```
eramon@applejuice eck-cloud % kubectl apply -k .
```

That's it. After that Kibana will be accessible under the defined hostname. The username is "elastic" and the password can be read from the secret:
```
eramon@applejuice eck-cloud % kubectl get secret -o json elasticsearch-es-elastic-user
```

## References

Elastic ECK resources:

https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-eck.html

https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-quickstart.html

https://github.com/elastic/cloud-on-k8s/tree/main/config/recipes/elastic-agent

IONOS Terraform documentation:

https://registry.terraform.io/providers/ionos-cloud/ionoscloud/latest/docs

Storage recommendations:

https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-storage-recommendations.html

Installation of kubectl (not covered in this README):

https://kubernetes.io/docs/tasks/tools

Installation of terraform (not covered in this README):

https://learn.hashicorp.com/tutorials/terraform/install-cli
