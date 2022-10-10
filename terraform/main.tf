# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A GKE PRIVATE CLUSTER IN GOOGLE CLOUD PLATFORM
# This is an example of how to use the gke-cluster module to deploy a private Kubernetes cluster in GCP
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 1.0.x. However, to make upgrading easier, we are setting
  # 0.12.26 as the minimum version, as that version added support for required_providers with source URLs, making it
  # forwards compatible with 1.0.x code.
  required_version = ">= 0.12.26"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.39.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "4.39.0"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# PREPARE PROVIDERS
# ---------------------------------------------------------------------------------------------------------------------

provider "google" {
  project = var.project
  region  = var.region
}

provider "google-beta" {
  project = var.project
  region  = var.region
}

# ---------------------------------------------------------------------------------------------------------------------
# ENABLE SERVICES
# ---------------------------------------------------------------------------------------------------------------------
resource "google_project_service" "iam" {
  project = var.project
  service = "iam.googleapis.com"
}
resource "google_project_service" "compute" {
  project = var.project
  service = "compute.googleapis.com"
}
resource "google_project_service" "artifact_registry" {
  project = var.project
  service = "artifactregistry.googleapis.com"
}
resource "google_project_service" "cloudbuild" {
  project = var.project
  service = "cloudbuild.googleapis.com"
}
resource "google_project_service" "container" {
  project = var.project
  service = "container.googleapis.com"
}

# ---------------------------------------------------------------------------------------------------------------------
# Provision docker container registry
# ---------------------------------------------------------------------------------------------------------------------

resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = "${var.project}-container-registry"
  description   = "docker repository"
  format        = "DOCKER"
}


# # ---------------------------------------------------------------------------------------------------------------------
# # Provision Google Storage for storing model
# # ---------------------------------------------------------------------------------------------------------------------

# resource "google_storage_bucket" "static-site" {
#   name          = "${var.project}-model-registry"
#   location      = var.region
#   force_destroy = true
#   versioning    = {
#     enabled = "true"
#   }

#   uniform_bucket_level_access = true
# }


# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A PRIVATE CLUSTER IN GOOGLE CLOUD PLATFORM
# ---------------------------------------------------------------------------------------------------------------------

module "gke_cluster" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "github.com/gruntwork-io/terraform-google-gke.git//modules/gke-cluster?ref=v0.2.0"
  source = "./modules/gke-cluster"

  name = var.cluster_name

  project  = var.project
  location = var.location
  network  = module.vpc_network.network

  # We're deploying the cluster in the 'public' subnetwork to allow outbound internet access
  # See the network access tier table for full details:
  # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
  subnetwork                    = module.vpc_network.public_subnetwork
  cluster_secondary_range_name  = module.vpc_network.public_subnetwork_secondary_range_name
  services_secondary_range_name = module.vpc_network.public_services_secondary_range_name

  # When creating a private cluster, the 'master_ipv4_cidr_block' has to be defined and the size must be /28
  master_ipv4_cidr_block = var.master_ipv4_cidr_block

  # This setting will make the cluster private
  enable_private_nodes = "true"

  # To make testing easier, we keep the public endpoint available. In production, we highly recommend restricting access to only within the network boundary, requiring your users to use a bastion host or VPN.
  disable_public_endpoint = "false" #Setting to false to access from external network

  # With a private cluster, it is highly recommended to restrict access to the cluster master
  master_authorized_networks_config = [
    {
      cidr_blocks = [
        {
          cidr_block   = "210.6.0.0/16"
          display_name = "Allow personal IP for connecting to cluster master"
        },
      ]
    },
  ]

  enable_vertical_pod_autoscaling = var.enable_vertical_pod_autoscaling

  resource_labels = {
    environment = "dev"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A NODE POOL
# ---------------------------------------------------------------------------------------------------------------------

resource "google_container_node_pool" "node_pool" {
  provider = google-beta

  name     = "private-pool"
  project  = var.project
  location = var.location
  cluster  = module.gke_cluster.name

  initial_node_count = "1"

  autoscaling {
    min_node_count = "1"
    max_node_count = "5"
  }

  management {
    auto_repair  = "true"
    auto_upgrade = "true"
  }

  node_config {
    machine_type = "n2-highcpu-8"

    ## For Future testing with gpus. 
    # guest_accelerator = [{
    #   type  = "nvidia-tesla-p4",
    #   count = 1,
    #   gpu_partition_size= ""

    # }]

    labels = {
      private-pools-example = "true"
    }

    # Add a private tag to the instances. See the network access tier table for full details:
    # https://github.com/gruntwork-io/terraform-google-network/tree/master/modules/vpc-network#access-tier
    tags = [
      module.vpc_network.private,
      "private-pool-example",
    ]

    disk_size_gb = "30"
    disk_type    = "pd-standard"
    preemptible  = true

    service_account = module.gke_service_account.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A CUSTOM SERVICE ACCOUNT TO USE WITH THE GKE CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "gke_service_account" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "github.com/gruntwork-io/terraform-google-gke.git//modules/gke-service-account?ref=v0.2.0"
  source = "./modules/gke-service-account"

  name        = var.cluster_service_account_name
  project     = var.project
  description = var.cluster_service_account_description
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A NETWORK TO DEPLOY THE CLUSTER TO
# ---------------------------------------------------------------------------------------------------------------------

module "vpc_network" {
  source = "./modules/vpc-network"

  name_prefix = "${var.cluster_name}-network"
  project     = var.project
  region      = var.region

  cidr_block           = var.vpc_cidr_block
  secondary_cidr_block = var.vpc_secondary_cidr_block

  public_subnetwork_secondary_range_name = var.public_subnetwork_secondary_range_name
  public_services_secondary_range_name   = var.public_services_secondary_range_name
  public_services_secondary_cidr_block   = var.public_services_secondary_cidr_block
  private_services_secondary_cidr_block  = var.private_services_secondary_cidr_block
  secondary_cidr_subnetwork_width_delta  = var.secondary_cidr_subnetwork_width_delta
  secondary_cidr_subnetwork_spacing      = var.secondary_cidr_subnetwork_spacing
}


# resource "google_iap_brand" "project_brand" {
#   support_email     = "terraform@${var.ADMIN_PROJ_ID}.iam.gserviceaccount.com"
#   application_title = "${local.res_prefix}-${local.module_name}"
#   project           = google_project_service.project_service["iap.googleapis.com"].project
# }



# resource "google_iap_tunnel_instance_iam_member" "instance" {
#   provider = "google-beta"
#   instance = "${var.instance_name}"
#   zone     = "${var.zone}"
#   role     = "roles/iap.tunnelResourceAccessor"
#   member   = "user:xxx@xxx.com"
#   depends_on = [google_compute_instance.default]
# }



# resource "google_compute_firewall" "ssh" {
#   name = "allow-ssh"
#   allow {
#     ports    = ["22"]
#     protocol = "tcp"
#   }
#   direction     = "INGRESS"
#   network       = google_compute_network.vpc_network.id
#   priority      = 1000
#   source_ranges = ["0.0.0.0/0"]
#   target_tags   = ["ssh"]
# }