# terraform-templates

A hands-on path from **"I click buttons in the cloud dashboard"** to **"my team's virtual machines are
described in code, reviewed in pull requests and deployed by a pipeline"** — using
[Terraform](https://www.terraform.io/) on an **OpenStack** cloud.

It grew out of real work managing a research group's VMs on NCSA's Radiant cloud (University of
Illinois). The four folders are four steps of the same story, each adding exactly one idea and
explaining every decision. The code is commented line by line for teaching, and written to be *almost*
ready to use: replace the `<placeholders>` and it runs.

> Everything here uses **standard OpenStack APIs and the community OpenStack Terraform provider**. Nothing
> is specific to one institution, so it works on any OpenStack cloud (a university cluster, a regional
> provider, your own DevStack). Names of images, networks and flavors differ per cloud; those are the
> placeholders you fill in.

---

## The problem this repository solves

Creating VMs in a web dashboard works for one machine. It stops working when:

* **Nobody remembers how a machine was built.** Which image? Which firewall group? Which disk?
* **Rebuilding is scary.** Destroy a VM and you lose its public IP and its data.
* **Two people change things at once**, or someone changes something "just this once".
* **Every VM is slightly different**, because each was assembled by hand on a different day.
* **Nothing is reviewed.** There is no "show me what will change before it changes".

*Infrastructure as Code* answers all of these: the desired state lives in text files, in git, and a tool
makes reality match them.

---

## Terraform in five minutes

Terraform reads files that **declare what should exist**, compares that with what **actually exists**, and
makes the minimum changes to reconcile them.

```hcl
resource "openstack_compute_instance_v2" "web" {   # "a VM, which I will call 'web' in this code"
  name        = "web-01"
  flavor_name = "m1.small"
  ...
}
```

| Concept | In one sentence |
|---|---|
| **Provider** | A plugin that knows how to talk to one platform's API. Here: `terraform-provider-openstack/openstack`. |
| **Resource** | A thing Terraform creates and manages: a VM, a volume, a floating IP. |
| **Data source** | A thing that already exists, which you only *read* (an image, a network). |
| **Variable / output** | Inputs you can change / results worth printing (e.g. the VM's IP). |
| **Module** | A reusable folder of Terraform code that you call like a function. |
| **State** | Terraform's notebook: which real object belongs to which resource in your code. Treat it as precious. |
| **Plan / apply** | `plan` shows what *would* change. `apply` does it. Always read the plan. |
| **Backend** | Where the state is stored (a local file, or a shared bucket). |

The loop is always:

```bash
terraform init      # once per folder: download the provider
terraform plan      # preview
terraform apply     # do it (asks for confirmation)
terraform destroy   # remove everything this folder manages
```

---

## OpenStack, and the Radiant cloud

[OpenStack](https://www.openstack.org/) is an open-source cloud platform. Compute (Nova), networking
(Neutron), block storage (Cinder), images (Glance) and identity (Keystone) are all exposed through
**standard, documented REST APIs**, which is exactly what Terraform's OpenStack provider calls.

[Radiant](https://docs.ncsa.illinois.edu/systems/radiant/en/latest/) is NCSA's OpenStack-based private cloud for
University of Illinois researchers and staff, with VMs of various sizes, SSD-backed volumes and public IP addresses.
This repository uses it as the worked example, but follows one rule throughout:

> **Only use what OpenStack itself defines.** Standard resources (`instance`, `port`, `floating IP`,
> `volume`), standard authentication (**application credentials** via `clouds.yaml`), standard metadata
> (**cloud-init** via a **config drive**). If your cloud runs OpenStack, these templates apply; only the
> names change.

Radiant-style clouds share a few facts the templates rely on, each explained where it first appears:
VMs are configured at first boot by cloud-init (read from a *config drive*), public addresses are
*floating IPs* attached to a *port*, and persistent disks are separate *Cinder volumes*.

---

## The four use cases

Each folder is self-contained and builds on the previous idea. Read the folder's `README.md` — it
contains the step-by-step instructions *and* the table of decisions.

| # | Folder | You will learn | You will build |
|---|---|---|---|
| 1 | [`01-single-vm`](01-single-vm/README.md) | The Terraform workflow end to end. | **One VM** from your laptop: image and flavor by name, port, floating IP, cloud-init. |
| 2 | [`02-multi-vm-modules`](02-multi-vm-modules/README.md) | Modules: removing repetition without hiding differences. | **Three VMs** that share one `vm` module and one list of users. |
| 3 | [`03-persistent-network-storage`](03-persistent-network-storage/README.md) | Separating what must **last** from what can be **rebuilt**. | Public IPs and data disks in their own states; rebuild VMs and **keep IP and data**. |
| 4 | [`04-github-actions`](04-github-actions/README.md) | Team workflow: remote state, locking, review, CI. | Use case 3 plus a **GitHub Actions pipeline**: plan on pull request, apply on merge, ordered. |

```
 1  one VM ──►  2  many VMs, shared module ──►  3  IP + data outlive VMs ──►  4  shared state + pipeline
   "how"           "don't repeat yourself"         "don't lose what matters"      "don't do it alone, don't do it unreviewed"
```

**Before the first one:** the VMs boot from an Ubuntu image that must exist in your OpenStack project.
[`bootstrap/`](bootstrap/README.md) shows how to create your credential, set up `clouds.yaml`, and upload
that image — or a **newer Linux release** whenever you want one.

### Which one do I need?

* Learning, or a single throwaway VM → **1**.
* A handful of similar machines, one person → **2**.
* Machines whose address or data matter (DNS, firewall allow-lists, databases) → **3**.
* More than one person, or you want review and an audit trail → **4**.

Use case 4 is the real-world setup; 1–3 are the staircase that explains why it looks the way it does.

---

## Installing the tools (no Homebrew)

You need **git**, **Terraform** and the **OpenStack command-line client**. Everything below installs into
your home directory — no administrator rights, no package manager.

> Supported: macOS (Apple Silicon or Intel) and Linux. On **Windows**, install
> [WSL2](https://learn.microsoft.com/windows/wsl/install) (`wsl --install` in an administrator PowerShell),
> open the Ubuntu terminal and follow the Linux steps.

### 0. A folder for your own programs

```bash
mkdir -p ~/.local/bin
case ":$PATH:" in *":$HOME/.local/bin:"*) echo "already on PATH";; *)
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc    # macOS default shell; use ~/.bashrc on most Linux
  echo "added: open a new terminal afterwards";; esac
```

### 1. git

* **macOS:** `xcode-select --install` (Apple's command-line tools; includes git, `python3`, `curl`).
* **Linux:** `sudo apt install git` (Debian/Ubuntu) or your distribution's equivalent.

Check: `git --version`

### 2. Terraform (download, verify, install)

This detects your system, downloads the official release, **verifies its checksum**, and installs it.

```bash
TF_VERSION=1.15.6        # known to work with these templates; newer 1.x releases exist
                         # at https://releases.hashicorp.com/terraform/

OS=$(uname -s | tr '[:upper:]' '[:lower:]')                     # darwin | linux
case "$(uname -m)" in x86_64) ARCH=amd64;; arm64|aarch64) ARCH=arm64;; esac

cd "$(mktemp -d)"
BASE=https://releases.hashicorp.com/terraform/${TF_VERSION}
curl -fsSLO "$BASE/terraform_${TF_VERSION}_${OS}_${ARCH}.zip"
curl -fsSLO "$BASE/terraform_${TF_VERSION}_SHA256SUMS"

# Verify the download against the published checksum (shasum exists on macOS and Linux)
grep "terraform_${TF_VERSION}_${OS}_${ARCH}.zip" "terraform_${TF_VERSION}_SHA256SUMS" | shasum -a 256 -c -

unzip -o "terraform_${TF_VERSION}_${OS}_${ARCH}.zip" terraform
install -m 755 terraform ~/.local/bin/terraform
terraform version
```

You must see `OK` after the checksum line. If it says `FAILED`, do not install.

### 3. OpenStack command-line client

The client is a Python program. Install it into its own isolated environment (so it can't clash with
anything else) and make the command available:

```bash
python3 -m venv ~/.venvs/openstack
~/.venvs/openstack/bin/pip install --upgrade pip python-openstackclient
ln -sf ~/.venvs/openstack/bin/openstack ~/.local/bin/openstack
openstack --version
```

*Alternative:* if you already use [`uv`](https://docs.astral.sh/uv/) (a fast Python tool manager that
installs without Homebrew: `curl -LsSf https://astral.sh/uv/install.sh | sh`), then
`uv tool install python-openstackclient` does the same in one line.

### 4. Credentials: `clouds.yaml`

Both the CLI and Terraform read one file with your cloud's address and credential. Create an
**application credential** in your cloud's web dashboard and save the file it offers as
`~/.config/openstack/clouds.yaml`. [Use case 1](01-single-vm/README.md#12-credentials-cloudsyaml) walks
through it, and the file must **never** be committed to git (every `.gitignore` here excludes it).

Check the whole chain:

```bash
export OS_CLOUD=my-cloud          # the entry name inside your clouds.yaml
openstack image list              # a table of images = your credentials work
```

The [`bootstrap/`](bootstrap/README.md) folder walks through this step by step (including every field of
the credential form) and then uploads the Linux image the VMs boot from.

---

## How to use this repository

1. **Read in order, build in order.** Each use case explains *why* it differs from the previous one; the
   explanations only make sense in sequence. Even if you only need use case 4, build 1 once — it takes
   ten minutes and is cheap.
2. **Copy, don't edit in place.** Copy the folder you want out of this repository
   (`cp -R 01-single-vm ~/my-vm`) and work there. Use case 4 *must* be copied out: GitHub only runs
   workflows from a repository's top level.
3. **Replace every `<placeholder>`.** Find them with `grep -rn "<" --include=*.tfvars* .`. Names of
   images, networks, flavors and security groups come from `openstack image list`, `network list`,
   `flavor list` and `security group list` — the README of each folder tells you which.
4. **Always read the plan.** `terraform plan` before every `apply`. The most important skill in
   Terraform is recognising `destroy` and `replace` in a plan before you agree to it.
5. **Format your code.** `terraform fmt -recursive` once after editing; it standardises layout.
6. **Clean up.** Each README ends with how to destroy what you built. Cloud resources cost allocation.
7. **Validate before trusting.** `terraform init -backend=false && terraform validate` in each root folder
   checks syntax and references without touching your cloud. In use cases 2 and 3 the VM folders read
   `../users.yaml`, so create it first (`cp users.example.yaml users.yaml`); without it `validate` stops with
   *"no file exists at ./../users.yaml"*. That is intentional: a missing user list should fail loudly rather
   than silently create VMs with example accounts.

### Conventions used everywhere

* Images and flavors are looked up **by name** (data sources), never hard-coded IDs.
* `config_drive = true` on every VM (cloud-init needs it on OpenStack clouds that use config drives).
* **One folder = one VM = one state**, so each VM has an independent lifecycle.
* Provider and backend settings live in each *root* folder; modules contain none.
* Versions are pinned (`required_version`, provider `~> 3.0`).

### Security checklist

* ☐ `clouds.yaml`, `*.tfstate`, `*.pem`/private keys are **never** committed (check `git status` before every commit).
* ☐ Each person uses **their own** application credential; automation gets its own.
* ☐ Firewall rules name **specific source ranges** instead of `0.0.0.0/0` wherever you can.
* ☐ Only **public** SSH keys appear in code.
* ☐ Real names, project IDs and addresses stay out of any public repository — keep the examples as placeholders.
* ☐ Application credentials have an expiry date, and you know how to revoke them.

---

## Repository layout

```
terraform-templates/
├── README.md                          ← you are here
├── bootstrap/                         step 0: credential, clouds.yaml, upload a Linux image
├── 01-single-vm/                      one VM, local state
├── 02-multi-vm-modules/               three VMs, shared module
├── 03-persistent-network-storage/     IPs and data outlive VMs
└── 04-github-actions/                 use case 3 + shared state + CI/CD pipeline
```

## License

[BSD 3-Clause License](LICENSE).
