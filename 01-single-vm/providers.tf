# providers.tf -- tells Terraform WHICH tools it needs.
#
# Terraform itself knows nothing about OpenStack. A "provider" is a plugin that
# translates Terraform resources into calls to one specific API. Here we use the
# community-maintained OpenStack provider, which talks to ANY standard OpenStack
# cloud (including Radiant).

terraform {
  # Refuse to run with a Terraform binary older than this. Prevents "works on my
  # machine" surprises when a teammate has an old version installed.
  required_version = ">= 1.5"

  required_providers {
    openstack = {
      # Where to download the plugin from (the public Terraform Registry).
      source = "terraform-provider-openstack/openstack"
      # "~> 3.0" means: any 3.x release, but never 4.0 (which could contain
      # breaking changes). `terraform init` downloads the newest 3.x.
      version = "~> 3.0"
    }
  }
}

# Provider configuration: HOW to authenticate.
#
# We do NOT put a URL, username or password here. `cloud = "..."` points at a
# named entry in your clouds.yaml file (see README), so credentials stay on your
# machine and never enter this repository.
provider "openstack" {
  cloud = var.os_cloud
}
