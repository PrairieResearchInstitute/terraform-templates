# Use case 3 — Keep your IP addresses and your data (persistent network and storage)

In use case 2, three VMs share one recipe. But there is still a trap: **the VM, its public IP and its
disk have the same lifetime.** Destroy the VM to fix something, and:

* the public IP is released — your DNS record, firewall allow-list and every bookmark now point nowhere;
* anything stored on the VM is gone.

Virtual machines are *disposable*; addresses and data are *not*. This use case separates the two, so
you can destroy and rebuild a VM as often as you like and **keep the same IP address and the same
data**.

```
                    ┌───────────────────────────────────────────────────────────────┐
  PERSISTENT        │  network/  (one state, all VMs)     storage/  (one state)     │
  (apply rarely,    │  per VM: port + fixed IP            per VM: a data volume     │
   protected)       │          floating (public) IP               "<vm>-data"       │
                    │          firewall wiring                                      │
                    └──────────────┬───────────────────────────────┬────────────────┘
                                   │ found BY NAME                 │ found BY NAME
                                   │ "<vm>-port"                   │ "<vm>-data"
                    ┌──────────────▼───────────────────────────────▼────────────────┐
  EPHEMERAL         │  vm-a/   vm-b/   vm-c/    (one state each; safe to destroy)    │
  (destroy/rebuild  │  instance + volume attachment + cloud-init                     │
   freely)          └───────────────────────────────────────────────────────────────┘
```

**Time needed:** about 45 minutes. You need three free floating IPs and three volumes of quota.

---

## 1. Folder map

```
03-persistent-network-storage/
├── modules/
│   ├── network-identity/    # port + floating IP + firewall wiring       (used by network/)
│   └── vm/                  # instance + attach volume + cloud-init      (used by vm-*/)
├── network/                 # ROOT, shared state: addresses of ALL VMs   ← apply first
├── storage/                 # ROOT, shared state: data volumes of ALL VMs ← apply second
├── vm-a/  vm-b/  vm-c/      # ROOTS, one state each: only compute        ← apply last
└── users.example.yaml       # who gets an account (now with fixed numeric ids)
```

| Layer | Folder | State | Run… | `terraform destroy` here… |
|---|---|---|---|---|
| Network identity | `network/` | one, all VMs | when VMs are added/removed or rules change | **fails on purpose** (public IPs are protected) |
| Data | `storage/` | one, all VMs | when VMs are added or a disk must grow | **fails on purpose** (volumes are protected) |
| Compute | `vm-a/` … | one per VM | whenever you want to rebuild a VM | removes the VM and its disk *attachment*, nothing else |

---

## 2. Prerequisites

[Use case 1, section 1](../01-single-vm/README.md#1-before-you-start) (tools, `clouds.yaml`, key pair,
image). Check your quota allows what you are about to create:

```bash
openstack quota show      # floating-ips, volumes and gigabytes must cover 3 IPs / 3 volumes
```

---

## 3. Build it

```bash
cd 03-persistent-network-storage

cp users.example.yaml users.yaml && $EDITOR users.yaml
for d in network storage vm-a vm-b vm-c; do cp $d/terraform.tfvars.example $d/terraform.tfvars; done
$EDITOR network/terraform.tfvars storage/terraform.tfvars vm-a/terraform.tfvars vm-b/terraform.tfvars vm-c/terraform.tfvars
```

**The order matters.** Each layer *looks up* what the previous one created, so it must exist first.

```bash
# 1. Network identity: ports + public IPs
cd network && terraform init && terraform plan     # expect: Plan: 9 to add (3 per VM x 3 VMs)
terraform apply
terraform output floating_ips                       # write these down: they are now yours to keep
cd ..

# 2. Data volumes
cd storage && terraform init && terraform apply     # expect: Plan: 3 to add
cd ..

# 3. The VMs
cd vm-a && terraform init && terraform plan         # expect: Plan: 2 to add (instance + volume attachment)
terraform apply
```

Log in and check the disk:

```bash
ssh -i ~/.ssh/<your-private-key>.pem ubuntu@<floating-ip-of-vm-a>
cloud-init status --wait            # status: done
lsblk                               # a disk named vdb, mounted on /data
df -h /data
mount | grep " /data "              # /dev/vdb on /data type ext4 ...
id alice                            # the fixed numeric id you chose in users.yaml
```

### The experiment that proves it works

```bash
# on the VM:
echo "still here" | sudo tee /data/proof.txt

# on your laptop:
cd vm-a
terraform destroy                   # Plan: 2 to destroy -- the instance and the attachment. Nothing else.
terraform apply                     # a brand-new VM...
terraform output floating_ip        # ...with the SAME public IP

# SSH will warn "REMOTE HOST IDENTIFICATION HAS CHANGED": the new VM generated new host keys. Expected.
ssh-keygen -R <floating-ip>         # forget the old key, then log in again
cat /data/proof.txt                 # "still here"
```

On the second boot cloud-init finds a filesystem on `/dev/vdb` and **does not format it** (see decision 9).

---

## 4. Day-2 operations

### Add a fourth VM — without touching the existing three

Both shared states use `for_each`, so adding a key only ever plans *new* resources.

```bash
# 1. Add "vm-d" to `vms` in network/terraform.tfvars and to `volumes` in storage/terraform.tfvars.
cd network && terraform plan     # must show ONLY resources with ["vm-d"]; "0 to change, 0 to destroy"
terraform apply && cd ..
cd storage && terraform plan && terraform apply && cd ..

# 2. Create its folder and build it.
cp -r vm-c vm-d && rm -rf vm-d/.terraform vm-d/terraform.tfstate*
sed -i.bak 's/vm-c/vm-d/g' vm-d/main.tf vm-d/outputs.tf && rm vm-d/*.bak
cd vm-d && terraform init && terraform apply
```

> **Rule:** always read the plan of the shared states before applying. If it mentions anything other
> than the new key, or shows `change`/`destroy` counts above zero, stop and investigate.

### Grow a data volume

```bash
# 0. Safety first: snapshot it.
openstack volume snapshot create --volume vm-a-data --force vm-a-data-before-resize

# 1. Raise the size in storage/terraform.tfvars (20 -> 40) and apply. Growing is in-place;
#    shrinking is impossible.
cd storage && terraform apply

# 2. Tell the filesystem inside the VM (ext4 supports online growth):
ssh ubuntu@<ip> 'sudo resize2fs /dev/vdb && df -h /data'
```

### Rebuild a VM on purpose (new base image, new cloud-init, new users)

```bash
cd vm-a
terraform apply -replace=module.vm.openstack_compute_instance_v2.vm
```

### Tear everything down

The protections are deliberate, so removing them is deliberate too.

```bash
# 1. VMs first (always allowed)
for d in vm-a vm-b vm-c; do (cd $d && terraform destroy); done

# 2. Edit the files to remove the two `lifecycle { prevent_destroy = true }` blocks:
#      modules/network-identity/main.tf   (floating IP)
#      storage/main.tf                    (volumes)
#    THIS DELETES THE DATA ON THE VOLUMES. Snapshot or copy anything you need first.

# 3. Then the persistent layers, in reverse order
(cd storage && terraform destroy)
(cd network && terraform destroy)
```

---

## 5. How it works

### 5.1 The naming contract

The three layers never share Terraform state. They are connected only by **names**:

| Created by | Resource | Name | Found by |
|---|---|---|---|
| `network/` | network port | `<vm>-port` | `data "openstack_networking_port_v2"` in `modules/vm` |
| `network/` | floating IP | *(attached to that port)* | `data "openstack_networking_floatingip_v2"` filtered by `port_id` |
| `storage/` | data volume | `<vm>-data` | `data "openstack_blockstorage_volume_v3"` in `modules/vm` |

`<vm>` is the **map key** in `network/` and `storage/` and the **`instance_name`** in the VM folder.
These three must be identical. If one is mistyped, `terraform plan` in the VM folder fails with *"no
port found"* — a loud, early failure, not a silent wrong VM.

### 5.2 `for_each`: why adding a VM cannot disturb the others

```hcl
module "network_identity" {
  for_each = var.vms          # { "vm-a" = {...}, "vm-b" = {...} }
  ...
}
```

Terraform tracks each instance by its key: `module.network_identity["vm-a"]`,
`module.network_identity["vm-b"]`. Adding `"vm-d"` to the map adds one new entry; there is no mechanism by
which the others are recomputed. (Had we used `count`, which numbers instances 0, 1, 2, removing the
*first* VM would renumber all the others — and Terraform would try to destroy and recreate them.)

### 5.3 Fixed numeric ids

A file on a disk is owned by numbers (uid/gid), not names. If a rebuilt VM gave `alice` uid 1001 today and
1002 tomorrow, she would no longer own her files on the persistent volume. So `users.yaml` now pins each
user's `uid` and each group's `gid`, and cloud-init creates the groups first (`bootcmd`) with those exact
numbers. The same ids make shared network storage (NFS) work, because the file server also identifies
people by number.

### 5.4 Mounting the disk safely

`modules/vm/cloudinit.tf` does four things, in this order:

1. **Wait** up to 60 s for `/dev/vdb` — the volume is attached by a separate API call *after* the VM
   exists, so cloud-init can win the race.
2. **Format only if empty** (`blkid` finds no filesystem). This is the line that protects your data.
3. **Persist** the mount in `/etc/fstab` with `nofail`, so a missing disk can never block booting.
4. `mount -a`.

---

## 6. Decisions and justifications

| # | Decision | Why — and what we gave up |
|---|---|---|
| 1 | **Split network and storage into their own states**, applied separately from VMs. | The thing you want to *keep* must not live in the same state as the thing you want to *destroy*. A `terraform destroy` in a VM folder physically cannot see those resources. *Cost:* three layers to apply in order. |
| 2 | **One shared state for all VMs' network, one for all volumes** (not one per VM). | These change rarely and are protected, so there is little blast-radius benefit to splitting them, while one place to see "all our IPs" is convenient. |
| 3 | **Connect layers by name via data sources, not by `terraform_remote_state`.** | A VM folder then needs no access to another state file (which matters when state moves to remote storage with credentials — use case 4), and the live API is always the source of truth. The alternative is a `data "terraform_remote_state"` block reading `network/`'s outputs; it works, but couples every VM folder to the network state's location and credentials. |
| 4 | **Read the floating IP from the port it is attached to.** | Same reason: the output is always real, without reading another state. |
| 5 | **`for_each` over a map of VMs** in `network/` and `storage/`. | Adding or removing a VM only touches that VM's resources (5.2). |
| 6 | **`prevent_destroy = true` on floating IPs and volumes.** | A mistaken `terraform destroy` in `network/` or `storage/` becomes an error instead of an outage or data loss. *Cost:* intentional teardown needs a deliberate edit (section 4). |
| 7 | **`enable_online_resize = true` on volumes.** | Lets you grow a disk without detaching it or stopping the VM. |
| 8 | **`ignore_changes = [image_id]` on the instance.** | The image is looked up by name; re-uploading it changes its ID, which would make Terraform replace *every* VM. VMs now keep their image until you rebuild them on purpose (`-replace`). *Cost:* a VM does not pick up a newer image automatically. |
| 9 | **Format the volume only when it has no filesystem.** | A rebuilt VM re-attaches a volume full of data; formatting it again would destroy it. |
| 10 | **Pin numeric uid/gid in `users.yaml`** (required fields now). | See 5.3. Without fixed numbers, persistent storage and NFS ownership silently break. |
| 11 | **Mount by device path `/dev/vdb`** (variable, with `lsblk` as the check). | Simple and predictable with one extra disk. With several volumes per VM, prefer labels or UUIDs in `fstab`. |
| 12 | **Optional `nfs_mounts` list** (empty by default). | Many institutions provide shared storage over NFS. The same variable works for any server; leave it empty if you have none. |
| 13 | **Custom firewall rules are optional and restrictable** (`remote_ip_prefix`). | By default the template opens *nothing* itself. If you add a rule you can limit it to a range instead of the whole internet. |
| 14 | **State is still local.** | We are still learning the layering; sharing state is the topic of use case 4. |

---

## 7. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `no port found with name "vm-a-port"` (or `no volume found`) | `network/` or `storage/` has not been applied, or the VM name differs from the map key. The three names in 5.1 must match. |
| `Instance cannot be destroyed ... prevent_destroy` | Working as designed — see *Tear everything down*. |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` after a rebuild | The new VM has new host keys. `ssh-keygen -R <ip>` and reconnect. |
| `/data` is not mounted | `lsblk` — is the device really `vdb`? If it is `sdb`, set `data_device`. Then `sudo mount -a` and read `/var/log/cloud-init-output.log`. |
| `Volume ... status in-use` when the new VM tries to attach | The previous instance is still being deleted. Wait a minute: `openstack volume show vm-a-data -c status`. |
| Files on `/data` belong to `root` | The new filesystem is root-owned. Create a directory per user/project and `chown` it (once; it persists). |
| NFS: `mount.nfs: Permission denied` | Many file servers only accept clients whose **public IP** is registered. Ask the storage administrators to allow the VM's floating IP. Because the IP is now persistent, you ask **once**. |
| `terraform plan` in a VM folder wants to replace the VM after you edited `users.yaml` | Expected: `user_data` cannot be changed on a running VM. Decide when to rebuild. (Use case 4 discusses this.) |

---

## 8. Limits of this design — why use case 4 exists

* **Everything is applied by hand, from one laptop.** Nothing stops a mistaken `apply`, and nobody else
  reviews it.
* **State lives on that laptop.** Lose the disk, lose Terraform's memory of the infrastructure; a second
  person cannot work safely.
* **Changing the module means running `apply` in every VM folder**, in the right order.
* **No audit trail** of who changed what and why.

➡️ Next: [`../04-github-actions`](../04-github-actions/README.md)
