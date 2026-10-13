# Use case 1 — One VM, from your laptop

The simplest useful Terraform project: **one virtual machine with a public IP address**, created from
your own computer with four commands. Everything later in this repository is an evolution of this
folder, so read it first even if you are in a hurry.

```
 your laptop                         OpenStack project
┌───────────────┐   OpenStack API   ┌──────────────────────────────────────┐
│  terraform    │ ────────────────► │  Floating IP ──► Port ──► VM (Ubuntu) │
│  (+ clouds.   │                   │  (public)      (fixed IP,  + cloud-init│
│   yaml creds) │                   │                 firewall)    (Docker…) │
└───────────────┘                   └──────────────────────────────────────┘
        │
        └── terraform.tfstate  (Terraform's memory of what it created — stays on your laptop)
```

**Time needed:** about 30 minutes the first time, 5 minutes afterwards.

---

## 1. Before you start

You need four things. Steps 1 and 2 are done once per computer, steps 3 and 4 once per OpenStack project.

### 1.1 The tools

Terraform and the OpenStack CLI installed — see [Installing the tools](../README.md#installing-the-tools-no-homebrew)
in the root README. Check:

```bash
terraform version
openstack --version
```

### 1.2 Credentials (`clouds.yaml`)

Terraform and the OpenStack CLI both read your credentials from a file called **`clouds.yaml`**
(with an *a*, not `.yml`). They look in this order and use the first file they find:

1. `./clouds.yaml` (the folder you run the command from)
2. `~/.config/openstack/clouds.yaml` ← **use this one**
3. `/etc/openstack/clouds.yaml`

To get one, create an **application credential** in the web dashboard (Horizon):
*Identity → Application Credentials → Create*, then download the `clouds.yaml` it offers. An application
credential is better than your personal password: it can be revoked on its own and it never expires
your real login. It looks like this:

```yaml
clouds:
  my-cloud:                       # <- this name is what `os_cloud` refers to. Rename it if you like.
    auth_type: v3applicationcredential
    auth:
      auth_url: https://<keystone-endpoint>:5000/v3
      application_credential_id: "<id>"
      application_credential_secret: "<secret>"
    region_name: "<region>"
    interface: "public"
    identity_api_version: 3
```

```bash
mkdir -p ~/.config/openstack
mv ~/Downloads/clouds.yaml ~/.config/openstack/clouds.yaml
chmod 600 ~/.config/openstack/clouds.yaml     # it contains a secret: only you may read it
export OS_CLOUD=my-cloud                       # tells the CLI which entry to use
openstack token issue                          # prints a token table => your credentials work
```

> **Never commit `clouds.yaml`.** It is in this folder's `.gitignore`, but the best protection is
> keeping the file in `~/.config/openstack/`, outside any repository.

### 1.3 An SSH key pair registered in OpenStack

You log in to the VM with an SSH key. OpenStack stores the **public** half under a name; Terraform only
needs that name.

```bash
# Option A (recommended): register a key you already have. The private key never leaves your laptop.
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519      # create one if you have none
openstack keypair create --public-key ~/.ssh/id_ed25519.pub my-keypair

# Option B: let OpenStack generate a pair and save the private half yourself.
openstack keypair create my-keypair > ~/.ssh/my-keypair.pem && chmod 600 ~/.ssh/my-keypair.pem
```

### 1.4 The base image

The VM boots from an image named **`Ubuntu 24.04`**. Check it exists:

```bash
openstack image list | grep "Ubuntu 24.04"
```

If it is missing, upload it once (about 600 MB download):

```bash
./bootstrap/upload_ubuntu_2404.sh my-cloud --cleanup
```

> ⚠️ That script **deletes and re-creates** the image. The new image has a new ID, which makes Terraform
> want to *replace* VMs that use it. Run it once per project, not routinely. Use case 3 shows how to
> make that safe.

---

## 2. What is in this folder

| File | Purpose |
|---|---|
| `providers.tf` | Which Terraform version and which provider (plugin) are required; how to authenticate. |
| `variables.tf` | Every value that differs between people/projects, with a description. |
| `main.tf` | The infrastructure itself: lookups, port, floating IP, VM. **Read this one carefully.** |
| `outputs.tf` | What gets printed after `apply` (VM ID, public IP, SSH command). |
| `cloud-init.yaml` | Script the VM runs on first boot (installs Docker, git, …). |
| `terraform.tfvars.example` | Template for **your** values. Copy it to `terraform.tfvars`. |
| `bootstrap/upload_ubuntu_2404.sh` | One-off helper that uploads the base image (step 1.4). |
| `.gitignore` | Keeps state, credentials and your real values out of Git. |

Terraform reads **every** `*.tf` file in the folder as one configuration. The split into several
files is only for humans.

---

## 3. Build it

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: flavor, key pair, network, security groups…
# every value can be found with the `openstack ... list` command written next to it

terraform init       # 1. download the OpenStack provider plugin into .terraform/
terraform plan       # 2. dry run: show what WOULD be created. Changes nothing.
terraform apply      # 3. show the plan again, ask "yes", then build it
```

`terraform plan` should end with **`Plan: 4 to add, 0 to change, 0 to destroy.`** The four are the
port, the floating IP, the association between them, and the VM. When you answer `yes`, Terraform
prints the outputs:

```
floating_ip = "203.0.113.25"
ssh_command = "ssh -i ~/.ssh/<your-private-key>.pem ubuntu@203.0.113.25"
```

Give cloud-init a minute or two to finish (it is installing Docker), then log in:

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@203.0.113.25
cloud-init status --wait        # prints "status: done" when first-boot setup finished
docker run --rm hello-world     # prove Docker works (log out and in once if "permission denied")
```

### What those commands actually did

| Command | What happens |
|---|---|
| `terraform init` | Reads `required_providers`, downloads the plugin into `.terraform/`, and records its exact version in `.terraform.lock.hcl`. Run it again whenever you change providers. |
| `terraform plan` | Reads your `.tf` files, asks OpenStack what exists now, compares with `terraform.tfstate`, and prints the difference. **Always read it.** `+` create, `~` change in place, `-/+` destroy and recreate, `-` destroy. |
| `terraform apply` | Executes the plan, then writes what it built into `terraform.tfstate`. |
| `terraform destroy` | Deletes everything recorded in the state file. |

### Day-to-day

```bash
terraform output                 # print the outputs again (e.g. forgot the IP)
terraform plan                   # "does reality still match my code?" (shows drift too)
terraform apply                  # after editing a .tf file
terraform destroy                # tear everything down when you are done (stops resource usage)
```

---

## 4. Decisions made in this use case, and why

| # | Decision | Why |
|---|---|---|
| 1 | **Look up image, flavor, network and security groups by *name*** with `data` sources. | Names are readable in code review and survive changes (re-uploading an image changes its ID but not its name). No UUIDs are hardcoded, so the folder works in any project. |
| 2 | **`config_drive = true`** on the instance. | Radiant delivers `user_data` through a config drive. Without it cloud-init never receives the script and the VM boots without Docker, users or packages. |
| 3 | **Create the network *port* explicitly** instead of letting the VM create one. | The port owns the private IP and the security groups, and gives the floating IP something stable to attach to. It looks like extra work now, but it is the seam that use case 3 uses to separate "network identity" from "VM". |
| 4 | **Attach existing security groups; do not create any.** | Radiant projects ship shared groups (SSH, HTTP/HTTPS). A starter template that silently opened `0.0.0.0/0` would be a bad habit. You choose the groups in `terraform.tfvars`. Use case 3 shows how to add custom rules when you need them. |
| 5 | **Use an existing key pair by name.** | The private key never passes through Terraform, so it can never end up in the state file. |
| 6 | **`user_data` is a plain YAML file** (`cloud-init.yaml`). | The first-boot script is easy to read, diff and test on its own. Use case 2 generates it from code because it will need per-user content. |
| 7 | **Site-specific variables have no default.** | Forgetting to set the flavor should be an error, not a silent wrong choice. |
| 8 | **Pin `required_version` and the provider (`~> 3.0`).** | Everyone on the team gets compatible behavior; a major provider release cannot surprise you. |
| 9 | **State stays on your laptop** (Terraform's default "local" backend). | Zero setup. This is the right choice for learning and a poor one for teams — see *Limits* below. |
| 10 | **`terraform.tfvars`, `*.tfstate`, `clouds.yaml`, `*.pem` are git-ignored.** | The state file contains every attribute of every resource and may contain secrets; the others contain your identity and credentials. |

---

## 5. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `cloud my-cloud does not exist in clouds.yaml` | The name in `os_cloud` does not match the entry name in your `clouds.yaml`, or the file is not where the tools look (section 1.2). |
| `Error: ... no image found` / `multiple ... found` | `image_name` does not match exactly. Compare with `openstack image list`. |
| `Quota exceeded for resources: ['floatingip']` | Your project has no free floating IPs. Ask your cloud administrators or release an unused one: `openstack floating ip list`. |
| `ssh: Connection timed out` | No security group on the port allows TCP 22. Add one that does to `security_groups`, then `terraform apply`. |
| `Permission denied (publickey)` | Wrong user or wrong key. The user is `ubuntu`; the key must be the private half of `key_pair`. |
| VM works but Docker is missing | cloud-init failed. Log in and read `sudo cat /var/log/cloud-init-output.log`. |
| `terraform plan` suddenly wants to replace the VM | The image was re-uploaded (new image ID) or `cloud-init.yaml` changed. `user_data` and `image_id` cannot be changed on a running VM, so Terraform must replace it. |

---

## 6. Clean up

```bash
terraform destroy      # type "yes"; removes the VM, floating IP and port
```

---

## 7. Limits of this design — why use case 2 exists

* **One VM only.** A second VM means copy-pasting this folder, and every future fix must be repeated
  in every copy.
* **No users.** Only the default `ubuntu` account exists. Real teams need named accounts.
* **Destroying the VM destroys its public IP.** The port and floating IP live in the same state as the
  VM, so rebuilding it gives you a *different* address (use case 3 fixes this).
* **State on one laptop.** If it is lost, Terraform forgets what it built; two people cannot safely
  work on the same infrastructure (use case 4 fixes this).

➡️ Next: [`../02-multi-vm-modules`](../02-multi-vm-modules/README.md)
