# modules/vm/cloudinit.tf -- first-boot configuration, generated from data.
#
# New in this use case:
#   * groups are created with FIXED group ids before users are created
#   * users get FIXED user ids
#   * the persistent volume is formatted (only if empty!), mounted and made permanent
#   * optional NFS mounts

locals {
  # Every distinct group (primary + supplementary) as name => gid, so cloud-init
  # can pre-create them with the right number BEFORE the users module runs.
  _group_pairs = flatten([
    for u in var.users : concat(
      [{ name = u.primary_group.name, gid = u.primary_group.gid }],
      u.groups
    )
  ])
  distinct_groups = merge([for g in local._group_pairs : { (g.name) = g.gid }]...)

  cloud_config = {
    # `bootcmd` runs early on every boot, before the users module. `groupadd -f`
    # succeeds silently if the group already exists, so re-running is harmless.
    bootcmd = [
      for name, gid in local.distinct_groups : "groupadd -f -g ${gid} ${name}"
    ]

    package_update = true

    # nfs-common provides the NFS client; only needed when mounts are requested.
    packages = concat(
      ["git", "ca-certificates", "curl", "gnupg", "jq"],
      length(var.nfs_mounts) > 0 ? ["nfs-common"] : []
    )

    users = concat(
      ["default"],
      [
        for u in var.users : merge(
          {
            name                = u.name
            uid                 = u.uid
            primary_group       = u.primary_group.name
            groups              = [for g in u.groups : g.name]
            shell               = "/bin/bash"
            lock_passwd         = true
            ssh_authorized_keys = u.ssh_authorized_keys
          },
          u.sudo ? { sudo = "ALL=(ALL) NOPASSWD:ALL" } : {}
        )
      ]
    )

    runcmd = concat(
      [
        # --- Docker from the official apt repository ---
        "install -m 0755 -d /etc/apt/keyrings",
        "curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc",
        "chmod a+r /etc/apt/keyrings/docker.asc",
        "bash -c 'echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list'",
        "apt-get update -y",
        "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
        "systemctl enable --now docker",
        "usermod -aG docker ubuntu",
      ],
      [for u in var.users : "usermod -aG docker ${u.name}"],
      [
        # --- Persistent data volume ---
        # 1. The volume is attached by a SEPARATE API call after the VM exists,
        #    so cloud-init can run before the device appears. Wait up to 60 s.
        "for i in $(seq 1 30); do [ -b ${var.data_device} ] && break; sleep 2; done",
        # 2. Format ONLY if the device has no filesystem. On a rebuild the volume
        #    already holds your data; formatting it again would destroy it.
        "if ! blkid ${var.data_device} >/dev/null 2>&1; then mkfs.ext4 -L data ${var.data_device}; fi",
        "mkdir -p ${var.data_mount_point}",
        # 3. Make the mount permanent. `nofail` = a missing disk must not stop the VM booting.
        "grep -q \"^${var.data_device} \" /etc/fstab || echo \"${var.data_device} ${var.data_mount_point} ext4 defaults,nofail 0 2\" >> /etc/fstab",
        "mount -a",
      ],
      # --- Optional NFS mounts (empty list => nothing below is generated) ---
      # `_netdev` = wait for the network; `nofail` = boot even if the server refuses us.
      [for m in var.nfs_mounts : "mkdir -p ${m.target}"],
      [for m in var.nfs_mounts : "grep -q ' ${m.target} ' /etc/fstab || echo '${m.source} ${m.target} nfs defaults,_netdev,nofail 0 0' >> /etc/fstab"],
      length(var.nfs_mounts) > 0 ? ["mount -a || echo 'WARNING: some mounts failed (access not granted yet?). Fix, then run: sudo mount -a'"] : []
    )
  }

  user_data = "#cloud-config\n${yamlencode(local.cloud_config)}"
}
