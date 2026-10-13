# Bootstrap — give your OpenStack project a modern Linux image

Every use case in this repository creates VMs from an **image looked up by name** (default
`Ubuntu 24.04`). Before the first `terraform apply`, that image has to exist in your OpenStack project —
and when you want a newer Linux, you add a newer image. This folder shows how, from zero:

1. create an **application credential** in the OpenStack dashboard,
2. put it in a local **`clouds.yaml`**,
3. run **`upload_ubuntu_image.sh`**, which downloads an official Ubuntu image, verifies it and uploads it.

**Time needed:** 20 minutes, most of it the ~600 MB download and upload. You do this once per project
and per Ubuntu release.

> **Image or flavor?** Two words are easy to mix up. A **flavor** is a *size* (vCPUs, RAM, disk) and is
> defined by the cloud's administrators; you can only pick one. An **image** is the *operating system*
> a VM boots from, and you can upload your own. So "getting a newer Linux" means adding an **image**; the
> flavor stays whatever size you need.

```
 Horizon (web dashboard)         your computer                                OpenStack project
 ───────────────────────         ─────────────                                ─────────────────
 1. create application   ──►   2. ~/.config/openstack/clouds.yaml
    credential (ID+secret)         (the credential, stored locally)
                                          │
                                   3. upload_ubuntu_image.sh my-cloud ──────►  image "Ubuntu 26.04"
                                          │                                    (Glance image service)
                                    downloads + verifies from Ubuntu
```

---

## 1. Prerequisites

* The OpenStack command-line client — see
  [Installing the tools](../README.md#installing-the-tools-no-homebrew) in the root README.
  `openstack --version` must work.
* A login to your cloud's web dashboard (**Horizon**) and a project where your role allows creating
  images (normally the `member` role). On a shared cloud ask the project owner if you are unsure.
* About 1 GB of free disk space in `/tmp` and a stable connection.

---

## 2. Create an application credential

A normal login uses your password, which would then sit in a file. An **application credential** is a
separate ID + secret that:

* only works for **one project**,
* can have an **expiry date**,
* can be **revoked on its own** without changing your password,
* by default **cannot create or delete other credentials**, so a leaked one can't spawn more.

**In the dashboard (Horizon):**

1. Log in and select your **project** (top-left project switcher).
2. Open **Identity → Application Credentials** and click **Create Application Credential**.
   (Menu labels can differ slightly between OpenStack versions.)
3. Fill in the form:

   | Field | What to enter |
   |---|---|
   | Name | Something that says *where it lives*, e.g. `laptop-yourname`. One credential per computer or person. |
   | Description | Optional: why it exists. |
   | Secret | Leave **empty**: OpenStack generates a strong one. |
   | Expiration date | Set one (e.g. 3–6 months ahead). A forgotten credential then dies by itself. |
   | Roles | Leave the default (your roles on this project). You can only choose roles you already have. |
   | Unrestricted | Leave **off**. Turning it on lets the credential create other credentials. |
   | Access rules | Leave empty (advanced: limits which API calls are allowed). |

4. Click **Create**. A window shows the credential **ID** and **secret**.

> **⚠ The secret is shown only once.** OpenStack stores just a hash. If you close the window without
> saving it, delete the credential and make a new one.

5. Click **Download clouds.yaml File** (the window also offers an `openrc` file; you don't need it).

> **Each person creates their own credential.** Never share one between teammates: if they all use the
> same one you cannot tell who did what, and revoking it locks everybody out.

*Command-line alternative (only if you are already authenticated another way):*

```bash
openstack application credential create laptop-yourname --expiration 2027-01-31T00:00:00
```

---

## 3. Set up `clouds.yaml` locally

Both the OpenStack CLI and Terraform read credentials from a file named **`clouds.yaml`** (an *a*, not
`.yml`). Each tool looks in these places and uses the first file found:

1. `./clouds.yaml` — the folder you run the command from
2. `~/.config/openstack/clouds.yaml` — **use this one**
3. `/etc/openstack/clouds.yaml`

Put the downloaded file in place and lock it down:

```bash
mkdir -p ~/.config/openstack
mv ~/Downloads/clouds.yaml ~/.config/openstack/clouds.yaml
chmod 600 ~/.config/openstack/clouds.yaml        # it contains a secret: only you may read it
```

Open it. It should look like this (placeholders shown; yours has real values):

```yaml
clouds:
  my-cloud:                                   # <- the cloud NAME. Scripts and Terraform refer to it.
    auth_type: v3applicationcredential
    auth:
      auth_url: https://<keystone-endpoint>:5000/v3
      application_credential_id: "<id>"
      application_credential_secret: "<secret>"
    region_name: "<region>"
    interface: public
    identity_api_version: 3
```

Notes:

* The name under `clouds:` (here `my-cloud`) is yours to choose. It is what you pass to the script and
  what `os_cloud` means in the Terraform files. Rename it if you want something clearer, and keep using
  the same name everywhere.
* One file can hold several clouds (several projects, or a personal one): add more entries under
  `clouds:`.
* If the dashboard's download is missing a line, `auth_type: v3applicationcredential` is the one that
  matters: it tells the tools to use the ID and secret instead of a password.

**Test the whole chain:**

```bash
export OS_CLOUD=my-cloud          # tells the CLI which entry to use (the script sets it for itself)
openstack token issue             # a table with an 'id' and 'expires' = your credential works
openstack image list              # the images already in your project (may be empty)
```

> **Never commit `clouds.yaml`.** It lives in `~/.config/openstack/`, outside any repository, and every
> `.gitignore` in this repo excludes it as a second line of defence. If you ever do push it, **revoke the
> credential immediately** (Identity → Application Credentials → Delete) — removing the file from git
> history is not enough, because the secret may already have been copied.

---

## 4. Run the script

```bash
cd bootstrap
chmod +x upload_ubuntu_image.sh                 # once: allow the file to run as a program
./upload_ubuntu_image.sh my-cloud               # uploads "Ubuntu 24.04" (Noble)
```

To add a **newer** Linux next to it:

```bash
./upload_ubuntu_image.sh my-cloud --release resolute        # "Ubuntu 26.04" (Resolute Raccoon)
```

What the script does, in order — and why:

| Step | What happens | Why |
|---|---|---|
| 1 | `openstack token issue` | Fails fast, before any download, if the credential is wrong. |
| 2 | Looks for an image with that name | By default an existing image is **left alone** (see *Options*). |
| 3 | Downloads the official image from `cloud-images.ubuntu.com` into a private temporary folder | The temp folder is deleted on exit, even after an error. |
| 4 | Checks the file against Ubuntu's published **SHA256SUMS** | Never upload something that is corrupt or tampered with. |
| 5 | `openstack image create` | Uploads it as a `qcow2` image with a minimum disk and RAM, tagged `x86_64`. |
| 6 | Prints the image's status | You should see `status: active`. |

### Options

| Option | Meaning |
|---|---|
| `--release <codename>` | Ubuntu release: `jammy` (22.04), `noble` (24.04, **default**), `resolute` (26.04). Any other codename works if you also pass `--name`. |
| `--name "<name>"` | Name of the image in OpenStack — **the name Terraform will look up**. |
| `--replace` | If an image with that name exists, delete it and upload a fresh build (see the warning below). |

Choosing a release: use an **LTS** (long-term support) release. Each release's `current` folder always
points at the newest build of that release, so re-running later gives you a build with the latest
security updates.

> **⚠ `--replace` gives the image a new ID.** Terraform looks images up by *name*, then stores the *ID*.
> After a replace, a root that wasn't built to expect this would see a different ID and plan to
> **replace every VM** using that image. The use case 3 and 4 modules ignore ID changes on purpose
> (`ignore_changes = [image_id]`), but use cases 1 and 2 do not. To get a newer OS, prefer **adding a
> second image** (`--release …`) over replacing the first one.

---

## 5. Verify the image

```bash
openstack image list | grep -E "Ubuntu|ID"
openstack image show "Ubuntu 26.04" -c name -c status -c size -c min_disk -c min_ram
```

`status` must be `active`. In the dashboard it appears under **Project → Compute → Images**.

---

## 6. Use it from Terraform

Terraform needs the **name** only:

* **Use case 1** — in `terraform.tfvars`: `image_name = "Ubuntu 26.04"`.
* **Use cases 2–4** — the VM module has `image_name` with a default of `Ubuntu 24.04`. To switch **all**
  VMs, change that default in `modules/vm/variables.tf`. To try the new image on **one** VM first,
  pass it in that VM's module call (e.g. in `vm-a/main.tf`):

  ```hcl
  module "vm" {
    source     = "../modules/vm"
    image_name = "Ubuntu 26.04"       # only vm-a uses the new image
    ...
  }
  ```

Things to know before you move machines to a newer release:

1. **Existing VMs are not upgraded.** A VM keeps the OS it booted from. A new image only affects VMs
   created (or rebuilt) after the change. In use cases 3 and 4, VMs deliberately ignore image changes, so
   rebuilding is a decision you take on purpose (`terraform apply -replace=…`).
2. **Try one VM first (a canary).** The `cloud-init` script installs Docker from Docker's own apt
   repository, picked by the release codename (`$VERSION_CODENAME`). A brand-new Ubuntu release may not be
   published there yet, in which case the Docker step fails on first boot. Check with
   `cloud-init status --long` and `/var/log/cloud-init-output.log` on the canary before moving the rest.
3. **Persistent data survives the move** in use cases 3 and 4, because the data lives on its own volume.
   Still, snapshot it before rebuilding: `openstack volume snapshot create --volume vm-a-data --force before-upgrade`.
4. **Want to keep the same machine?** Ubuntu can upgrade itself in place (`do-release-upgrade`), but it is
   riskier than rebuilding from a fresh image, and Terraform's description of the VM wouldn't change.
   For VMs described as code, rebuilding is the cleaner path.

---

## 7. Decisions and justifications

| # | Decision | Why — and what we gave up |
|---|---|---|
| 1 | **Official Ubuntu cloud images**, downloaded from `cloud-images.ubuntu.com`. | They are built for cloud-init and receive security rebuilds. Nothing else to maintain. *Cost:* a ~600 MB download. |
| 2 | **Verify SHA256SUMS before uploading.** | A truncated or tampered download would otherwise become the base of every VM. |
| 3 | **Existing image is left alone unless `--replace`.** | The earlier version of this script always deleted first, which silently changes the image ID. Doing nothing is the safe default. |
| 4 | **Release selected by name; newer release added alongside.** | Old and new coexist, so you can test the new one on one VM and keep the old for the rest. |
| 5 | **Application credential, per person, with an expiry.** | Revocable on its own, limited to one project, auditable. See section 2. |
| 6 | **`clouds.yaml` kept in `~/.config/openstack`, mode 600, never in a repository.** | Out of reach of `git add`, and unreadable by other users on the machine. |
| 7 | **Private temporary download folder, removed on exit.** | The image is large and shouldn't linger in a shared `/tmp`; nobody else can swap it between the checksum and the upload. |
| 8 | **Credentials checked first.** | A wrong secret fails in seconds, not after a 10-minute download. |
| 9 | **Plain `x86_64` image.** | Matches common cloud hardware. For ARM clouds use the `arm64` image and set `ARCH` in the script. |

---

## 8. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Missing value auth-url required for auth plugin password` | The CLI didn't find your `clouds.yaml`, or `OS_CLOUD` names an entry that isn't in it. Check the path (section 3) and `echo $OS_CLOUD`. |
| `The request you have made requires authentication` (HTTP 401) | Wrong or revoked credential, or it **expired**. Create a new one (section 2). |
| `Could not find requested endpoint in Service Catalog` | Wrong `region_name` or `interface` in `clouds.yaml`. Copy them from the dashboard's downloaded file. |
| `HTTP 403 ... Policy doesn't allow add_image to be performed` | Your role can't create images in this project. Ask the project owner for the `member` role (or have an administrator upload the image). |
| `Image storage quota exceeded` / `413` | The project's image quota is full. Delete images you don't use: `openstack image delete <name-or-id>`. |
| `An image named '…' already exists. Nothing to do.` | Working as intended. Use `--replace` only if you need a fresh build, and read the warning in section 4. |
| `Checksum mismatch ... Not uploading` | The download was corrupted or interrupted. Run the script again. If it persists, check any proxy or VPN on your network. |
| `curl: (22) ... 404` | That release has no image at that address (typo in `--release`?). Browse `https://cloud-images.ubuntu.com/`. |
| `Multiple possible matches found for image` | Two images share a name. OpenStack allows duplicates; Terraform's lookup needs exactly one. Delete or rename the extra one with `openstack image set --name`. |
| Upload hangs or times out | Large uploads need a stable connection. Run it from a machine with a good uplink (a server in the same network is ideal). |
| `Permission denied` when running the script | `chmod +x upload_ubuntu_image.sh`, or run it with `bash upload_ubuntu_image.sh my-cloud`. |

---

## 9. Housekeeping

* **Old images:** once no VM needs an old release, remove it: `openstack image delete "Ubuntu 24.04"`.
  Check first that no VM still depends on it (`openstack server list --image "Ubuntu 24.04"`).
* **Credentials:** delete application credentials you no longer use
  (Identity → Application Credentials, or `openstack application credential delete <name>`) and
  rotate them before they expire.
* **Build ahead of time:** the upload is only needed when the image is missing or you want a newer
  release. It is not part of the Terraform run, on purpose: images are shared by the whole project,
  while Terraform folders manage individual VMs.

➡️ Back to the use cases: start with [`01-single-vm`](../01-single-vm/README.md).
