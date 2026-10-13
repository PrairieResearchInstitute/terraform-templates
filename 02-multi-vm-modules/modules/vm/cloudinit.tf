# modules/vm/cloudinit.tf -- builds the cloud-init document (user_data) in code.
#
# In use case 1 cloud-init.yaml was a static file. Now the content depends on
# the list of users, so we build it as a Terraform value and convert it to YAML
# with yamlencode(). That also avoids hand-writing YAML indentation for loops.

locals {
  cloud_config = {
    package_update = true
    packages       = ["git", "ca-certificates", "curl", "gnupg", "jq"]

    # "default" keeps the image's own user (ubuntu) and the OpenStack key pair.
    # Then one entry per user from users.yaml.
    users = concat(
      ["default"],
      [
        for u in var.users : merge(
          {
            name                = u.name
            shell               = "/bin/bash"
            groups              = u.groups
            lock_passwd         = true
            ssh_authorized_keys = u.ssh_authorized_keys
          },
          # merge() combines objects. The `? :` adds the sudo entry only for
          # users flagged `sudo: true`; otherwise it adds nothing ({}).
          u.sudo ? { sudo = "ALL=(ALL) NOPASSWD:ALL" } : {}
        )
      ]
    )

    runcmd = concat(
      [
        # Docker from the official apt repository (same steps as use case 1).
        "install -m 0755 -d /etc/apt/keyrings",
        "curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc",
        "chmod a+r /etc/apt/keyrings/docker.asc",
        "bash -c 'echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list'",
        "apt-get update -y",
        "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
        "systemctl enable --now docker",
        "usermod -aG docker ubuntu",
      ],
      # The docker group only exists after the install above, so the users are
      # added to it here and not in the `users` section.
      [for u in var.users : "usermod -aG docker ${u.name}"]
    )
  }

  # cloud-init requires the first line to be exactly "#cloud-config".
  user_data = "#cloud-config\n${yamlencode(local.cloud_config)}"
}
