# Use case 2 — Three VMs without repeating yourself (modules)

In use case 1 you built one VM. Now you need **three**. The naive route is to copy the folder twice —
and then every bug fix, every new package, every security tweak has to be applied three times, and the
copies slowly drift apart.

This use case solves that with a **Terraform module**: the shared recipe is written **once**, and each VM
is a tiny folder that says *"build one of those, called `vm-b`"*.

```
02-multi-vm-modules/
├── modules/
│   └── vm/                  ← the ONE shared recipe (network port, public IP, VM, cloud-init)
│       ├── main.tf
│       ├── variables.tf     (its inputs)
│       ├── outputs.tf       (its return values)
│       └── cloudinit.tf     (builds first-boot config incl. user accounts)
├── users.example.yaml       ← who gets an account on every VM   (copy to users.yaml)
├── vm-a/                    ← ~35 lines: "call the module with name vm-a"
├── vm-b/                    ← same, name vm-b
└── vm-c/                    ← same, name vm-c       (each folder = its own Terraform state)
```

**Time needed:** about 30 minutes (you already did the prerequisites in use case 1).

---

## 1. Prerequisites

Everything from [use case 1, section 1](../01-single-vm/README.md#1-before-you-start): tools installed,
`clouds.yaml` working, an SSH key pair registered in OpenStack, the `Ubuntu 24.04` image present.

You will need **three free floating IPs** in your project quota (one per VM).

---

## 2. What changed compared to use case 1, and why

| Use case 1 | Use case 2 | Why |
|---|---|---|
| One folder with everything in `main.tf`. | **`modules/vm/`** holds the infrastructure; **`vm-a/`, `vm-b/`, `vm-c/`** only *call* it. | Write once, use three times. A fix to the module reaches every VM. |
| Names like `my-first-vm` came from a variable. | `instance_name` is **hard-coded in each VM folder** (`"vm-a"`) and is the *only* per-VM line. | The folder name, the VM name and the Terraform state now always agree — nothing to mistype at 2 a.m. |
| `cloud-init.yaml`, a static file. | **`cloudinit.tf`**, which *generates* the cloud-init document. | The content now depends on a list of users, so it must be built from data. |
| Only the `ubuntu` account. | **`users.yaml`**: named accounts with SSH keys and optional sudo, on every VM. | Real teams log in as themselves. |
| `providers.tf` + `variables.tf` + `main.tf` + `outputs.tf`. | Same files, but **split between the module and each root**. | See *what goes where* below. |
| State on the laptop, one state. | State on the laptop, **one state per VM folder**. | Independent lifecycles (decision 3). |

### What goes in the module, and what stays in the root?

A useful test: *"would this line be different for another VM?"*

| Belongs to… | What | Example |
|---|---|---|
| **The module** (identical for every VM) | Resources and their wiring | port, floating IP, instance, `config_drive = true`, Docker install |
| **The root** (differs per VM) | The VM's identity | `instance_name = "vm-b"`, optionally `flavor_name` |
| **The root** (shared project values) | Passed *into* the module | key pair, network name, security groups |
| **The root** (a module may not own it) | Terraform/provider versions, `provider` block, and later the `backend` | `provider "openstack" { cloud = ... }` |
| **A shared file** | Data about people | `users.yaml` |

---

## 3. Build it

```bash
cd 02-multi-vm-modules

# 1. Describe your team (public keys only).
cp users.example.yaml users.yaml
$EDITOR users.yaml

# 2. Give every VM folder its values. They are the same in all three, except flavor_name if you want.
for d in vm-a vm-b vm-c; do cp $d/terraform.tfvars.example $d/terraform.tfvars; done
$EDITOR vm-a/terraform.tfvars vm-b/terraform.tfvars vm-c/terraform.tfvars

# 3. Build ONE VM first and read the plan.
cd vm-a
terraform init        # also installs the module: look for "Initializing modules... - vm in ../modules/vm"
terraform plan        # expect: Plan: 4 to add, 0 to change, 0 to destroy.
terraform apply
cd ..

# 4. Same for the others.
for d in vm-b vm-c; do (cd $d && terraform init && terraform apply); done
```

Each `apply` prints the VM's outputs:

```
floating_ip       = "203.0.113.25"
provisioned_users = ["alice", "bob"]
ssh_command       = "ssh -i ~/.ssh/<your-private-key>.pem ubuntu@203.0.113.25"
```

Log in with **your own account** (not `ubuntu`) to check the users worked:

```bash
ssh alice@203.0.113.25
sudo whoami           # "root" without a password prompt if alice has sudo: true
docker ps             # works without sudo
```

### Touch only one VM

```bash
cd vm-b && terraform destroy     # removes ONLY vm-b; vm-a and vm-c are not even read
```

### The payoff: add a fourth VM in one minute

```bash
cp -r vm-c vm-d
rm -f vm-d/terraform.tfstate* && rm -rf vm-d/.terraform     # never copy another folder's state
sed -i.bak 's/vm-c/vm-d/g' vm-d/main.tf vm-d/outputs.tf && rm vm-d/*.bak
cd vm-d && terraform init && terraform apply
```

---

## 4. The module, line by line

### 4.1 Its contract: inputs and outputs

A module behaves like a function.

| Inputs (`modules/vm/variables.tf`) | Required? | Meaning |
|---|---|---|
| `instance_name` | yes | VM name and prefix of everything it creates |
| `flavor_name` | yes | VM size |
| `key_pair` | yes | OpenStack key pair for the `ubuntu` user |
| `network_name` | yes | project network |
| `security_groups` | yes | firewall groups to attach |
| `image_name` | no (`Ubuntu 24.04`) | base image |
| `external_network_name` | no (`ext-net`) | pool for floating IPs |
| `users` | no (`[]`) | accounts to create |

| Outputs (`modules/vm/outputs.tf`) | Meaning |
|---|---|
| `instance_id`, `floating_ip`, `fixed_ip`, `provisioned_users` | What the caller may read as `module.vm.<name>` |

A module's outputs are **not** shown automatically: each root re-exports the ones it wants in its own
`outputs.tf`.

### 4.2 How a root calls it

```hcl
module "vm" {
  source = "../modules/vm"           # a local folder (could also be a Git URL or registry address)

  instance_name = "vm-a"             # the only thing that makes vm-a vm-a
  flavor_name   = var.flavor_name
  ...
  users = yamldecode(file("${path.module}/../users.yaml")).users
}
```

### 4.3 How user accounts reach the VM

1. `users.yaml` (one file, for all VMs) →
2. each root reads and parses it: `yamldecode(file(...)).users` →
3. passes it to the module as the `users` variable →
4. `cloudinit.tf` turns each user into a cloud-init `users:` entry, adds `sudo` only when requested, and
   adds a `usermod -aG docker <name>` command →
5. cloud-init creates the accounts on first boot.

---

## 5. Decisions and justifications

| # | Decision | Why — and what we gave up |
|---|---|---|
| 1 | **Extract a module for everything that is identical** (port, floating IP, instance, cloud-init). | Don't Repeat Yourself: one place to fix a bug or bump the Docker install. *Cost:* one more level of indirection to learn. |
| 2 | **The module contains no `provider` and no `backend`.** It only declares `required_providers`. | Provider and backend settings describe *where and as whom* Terraform runs; they belong to the caller. If a module owned them, it could not be reused with another cloud or state location. |
| 3 | **One folder per VM → one state per VM.** | *Independent lifecycles and small blast radius:* destroying or breaking `vm-b` cannot touch `vm-a`. Plans are short and fast. It also maps cleanly to CI later (use case 4 plans only the folders that changed). *Cost:* three near-identical ~35-line folders; changing the module means running `apply` in each folder (CI automates that later). |
| 4 | **Rejected alternative: one root with `for_each` over a map of VMs** (see below). | It has zero repetition, but all VMs share one state: a single `terraform destroy` or a mistaken plan can affect every VM, and one broken VM blocks changes to the others. Good for tightly coupled things, wrong for "pets" with separate owners. |
| 5 | **The module never reads files; the root reads `users.yaml` and passes the data in.** | Inside a module `path.module` points at the *module's* folder, so a file read there would depend on where the module lives. Passing data in keeps the module a pure function. |
| 6 | **Users live in YAML, not in `.tf`.** | People who manage access should not need to know HCL; diffs show exactly who was added; the same file feeds every VM. |
| 7 | **cloud-init is built with `yamlencode()`, not a hand-written template.** | Loops that emit YAML by string concatenation break on indentation and quoting. `yamlencode` always emits valid YAML. |
| 8 | **Every resource name derives from `instance_name`** (`vm-a-port`, …). | Three VMs from one module never collide, and in the dashboard you can see which port belongs to which VM. |
| 9 | **Accounts are key-only and get `NOPASSWD` sudo** when `sudo: true`. | `lock_passwd: true` means the account has *no* password, so a password-prompting `sudo` would be impossible. Security therefore rests entirely on SSH keys — protect them. |
| 10 | **Shared values (key pair, network, …) are repeated in each folder's `terraform.tfvars`.** | `terraform.tfvars` is loaded automatically, so there is nothing to remember on the command line. Alternative: one shared file passed with `terraform apply -var-file=../common.tfvars` — less repetition, but easy to forget. |
| 11 | **`users.yaml` is git-ignored here; only `users.example.yaml` is committed.** | Public keys are not secret, but the file names real people. In a private team repository you may prefer to commit it (use case 4 does). |

### The alternative we rejected: `for_each` in a single root

```hcl
# One folder, one state, three VMs. Compact, but see decision 4.
locals {
  vms = {
    "vm-a" = "<flavor-a>"
    "vm-b" = "<flavor-b>"
    "vm-c" = "<flavor-c>"
  }
}

module "vm" {
  for_each = local.vms
  source   = "../modules/vm"

  instance_name = each.key
  flavor_name   = each.value
  # ...same shared inputs...
}
```

---

## 6. Troubleshooting

| Symptom | Fix |
|---|---|
| `Error: Module not installed` | Run `terraform init` in that folder. Adding or changing a `module` block always requires `init`. |
| `no file exists at "../users.yaml"` | You skipped `cp users.example.yaml users.yaml`. |
| `Error: Invalid YAML` / `Invalid value for "users"` | Check indentation in `users.yaml`; every user needs a `name`. |
| `Unsupported argument` on the module block | The root passes an input the module does not declare. Compare with `modules/vm/variables.tf`. |
| `ssh alice@…` says `Permission denied (publickey)` | The key in `users.yaml` is not the one your SSH client offers, or you edited the file *after* the VM was created. `user_data` is only read at first boot — see limits below. |
| A plan after editing `users.yaml` shows `must be replaced` | Expected. `user_data` cannot be changed on a running VM, so Terraform plans to replace it. |

---

## 7. Limits of this design — why use case 3 exists

* **Destroying a VM destroys its public IP.** The floating IP lives in the same state as the VM, so a
  rebuilt `vm-b` gets a *different* address. DNS records, firewall allow-lists and your users' bookmarks
  all break.
* **No persistent data.** Everything on the VM's disk disappears with the VM.
* **Account numbers can change.** A rebuilt VM may assign different numeric user IDs, which matters as
  soon as files outlive the VM (a persistent disk or a shared network filesystem).
* **Every user change rebuilds every VM** (decision in *Troubleshooting*). Acceptable here, painful once
  VMs hold data — see use case 4's discussion.

➡️ Next: [`../03-persistent-network-storage`](../03-persistent-network-storage/README.md)
