terraform {
  required_providers {
    ionoscloud = {
      source  = "ionos-cloud/ionoscloud"
      version = "6.3.1"
    }
  }
}

# Create IONOS datacenter, public IP, K8s cluster and nodepool

provider "ionoscloud" {
  username = var.ionos_username 
  password = var.ionos_password
}

resource "ionoscloud_datacenter" "eck" {
  name                = "eck"
  location            = "de/txl"
  description         = "Datacenter to host the ECK demo deployment"
  sec_auth_protection = false
}

resource "ionoscloud_ipblock" "ingress" {
  location  = "de/txl"
  size      = 1 
  name      = "ingress"
}

resource "ionoscloud_k8s_cluster" "eck" {
  name = "eck"
}

resource "ionoscloud_k8s_node_pool" "eck-nodepool" {
  datacenter_id     = ionoscloud_datacenter.eck.id
  k8s_cluster_id    = ionoscloud_k8s_cluster.eck.id
  name              = "eck-nodepool"
  k8s_version       = ionoscloud_k8s_cluster.eck.k8s_version
  cpu_family        = "INTEL_SKYLAKE"
  availability_zone = "AUTO"
  storage_type      = "SSD"
  node_count        = 2
  cores_count       = 4
  ram_size          = 10240 
  storage_size      = 100
}


# DNS A Record on GCP's Cloud DNS

output "ip" {
  value = ionoscloud_ipblock.ingress.ips[0]
}

provider "google" {
  project     = var.gcp_project 
  region      = var.gcp_region
  credentials = var.gcp_key_path 
} 

resource "google_dns_record_set" "a" {
  name         = var.dns_hostname 
  managed_zone = var.dns_managed_zone
  type         = "A"
  ttl          = 300
  rrdatas      = [ionoscloud_ipblock.ingress.ips[0]]
}

# Write kubeconfig to local file
data "ionoscloud_k8s_cluster" "eck" {
  name = "eck"
  depends_on = [ionoscloud_k8s_cluster.eck]
}

resource "local_sensitive_file" "kubeconfig" {
    content     = yamlencode(jsondecode(data.ionoscloud_k8s_cluster.eck.kube_config))
    filename    = "./kubeconfig.json"
    depends_on = [ionoscloud_k8s_cluster.eck]
}

# Install nginx-ingress-controller via helm
provider "helm" {
  kubernetes {
    config_path = "./kubeconfig.json"
  }
}

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress-controller"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  wait       = false
  depends_on = [local_sensitive_file.kubeconfig]

  set {
    name  = "controller.service.loadBalancerIP"
    value = ionoscloud_ipblock.ingress.ips[0]
  }
}

