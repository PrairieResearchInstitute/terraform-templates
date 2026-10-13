# Use case 4 — A team workflow: shared state and GitHub Actions

Use case 3 gave you a sound architecture, but it still depends on **one person at one laptop** running
commands in the right order. This use case keeps the same code and adds what a *team* needs:

| Problem in use case 3 | What use case 4 adds |
|---|---|
| State lives on one laptop. | **Remote state** in an S3-compatible bucket, with locking. |
| Anyone can `apply` anything, unreviewed. | Changes happen **only through pull requests**: a plan is posted for review, and the merge applies it. |
| "Apply in the right order" lives in someone's head. | The pipeline applies **network → storage → VMs**, always. |
| No record of who changed what. | Git history + pull-request discussion + workflow logs. |
| Credentials on laptops. | A **dedicated CI credential** in GitHub secrets; humans keep their own for read-only exploration. |

```
 developer ──► branch ──► pull request ──► lint + plan (comment) ──► review ──► merge to main
                                                                                 │
                                                       apply: network → storage → vm-*  (one at a time)
                                                                                 │
                                          S3 bucket: network/…  storage/…  vm-a/…  (one state object each)
```

**Time needed:** 1–2 hours the first time (most of it one-time setup).

---

## 1. This folder is a *complete repository*

Unlike use cases 1–3, this folder is meant to become **the root of your own repository**.
GitHub only runs workflows found in `.github/workflows/` at the **top** of a repository, so the folder
must be copied out of `terraform-templates`:

```bash
cp -R terraform-templates/04-github-actions ~/my-infra       # copies hidden files (.github, .gitignore) too
cd ~/my-infra
git init -b main
```

```
my-infra/
├── .github/
│   ├── actions/terraform-setup/action.yml   # reusable steps: install Terraform, credentials, init
│   └── workflows/
│       ├── plan.yml      # pull request  -> lint + plan, commented on the PR
│       ├── apply.yml     # merge to main -> apply, in order
│       └── destroy.yml   # manual button -> destroy ONE VM (never network/storage)
├── backend.hcl           # shared, NON-secret remote-state settings
├── users.yaml            # who gets an account (committed; edited by pull request)
├── modules/              # same two modules as use case 3
├── network/  storage/    # persistent layers, one state each
└── vm-a/  vm-b/  vm-c/   # one VM per folder; each has terraform.tfvars
```

---

## 2. One-time setup

### 2.1 Fill in the placeholders

Search for `<` in `*.tfvars` and `users.yaml` and replace every placeholder
(network name, flavor, key pair, security group, real users and **public** keys).

```bash
grep -rn "<" --include=terraform.tfvars . ; grep -n "replace-with" users.yaml
```

> **These files are committed.** That is only safe because they hold no secrets: names, sizes and
> *public* keys. Never put a password, token or private key in them. If your repository is public, keep
> only placeholders or users who agreed to appear.

### 2.2 Create the state bucket and its keys

Ask your object-storage provider (or use any S3-compatible service) for:

* a **bucket** (private), e.g. `my-terraform-state`;
* an **access key + secret key** with read/write on that bucket (list, get, put and delete on objects —
  delete is needed to release the lock file).

Enable **versioning** on the bucket if the service offers it: it turns an accidental overwrite of a
state file into a recoverable event.

Export them in the shell you will use for the next steps:

```bash
export BUCKET_NAME="my-terraform-state"
export AWS_ENDPOINT_URL="https://<s3-endpoint-of-your-provider>"
export AWS_ACCESS_KEY_ID="<access-key>"
export AWS_SECRET_ACCESS_KEY="<secret-key>"
```

(The names look "AWS" because the S3 protocol was invented there; the S3 backend simply reads them.)

### 2.3 Create a credential for CI

CI is a robot. Give it its **own** OpenStack application credential, not yours — you can then revoke it
without touching anyone's access, and the audit log shows who did what.

1. In Horizon: *Identity → Application Credentials → Create*. Name it `terraform-ci`, set an **expiry
   date**, leave *unrestricted* **off**.
2. Download its `clouds.yaml`. It should look like this, and **the entry name must equal `os_cloud` in the
   `terraform.tfvars` files** (`my-cloud`):

```yaml
clouds:
  my-cloud:
    auth_type: v3applicationcredential
    auth_url: https://<your-openstack-keystone-endpoint>/v3
    application_credential_id: "<id>"
    application_credential_secret: "<secret>"
    region_name: "<region>"
    interface: public
    identity_api_version: 3
```

### 2.4 Test that locking really works — before trusting it

Locking is what stops two people (or a person and a pipeline) from corrupting the state. Not every
S3-compatible store supports the mechanism Terraform uses (`use_lockfile` needs *conditional writes*), so
test yours **once**. You need no extra tool: Terraform itself is the test.

```bash
cd network
terraform init -backend-config=../backend.hcl -backend-config="bucket=$BUCKET_NAME"
terraform apply            # ← at the "Enter a value:" prompt, DO NOT answer. Leave it waiting.
```

Open a **second terminal** (export the same four variables), and run `terraform apply` in `network/`
again. It must fail with **`Error acquiring the state lock`**. Then answer `no` in the first terminal.

* Failed with the lock error → locking works. ✔
* The second apply started normally → your store ignores the lock. Do not continue; ask the provider
  about conditional-write (`If-None-Match`) support, or use a store that has it.

### 2.5 First deployment — by hand, once

Do this first run **locally**. It proves your credentials, bucket and variables before the pipeline
depends on them. (If your own `clouds.yaml` has the same entry name, no more setup is needed.)

```bash
# network/ -> storage/ -> VMs, exactly as in use case 3
for dir in network storage vm-a vm-b vm-c; do
  (cd $dir &&
   terraform init -backend-config=../backend.hcl -backend-config="bucket=$BUCKET_NAME" &&
   terraform apply)
done
```

Check: the bucket now holds `network/terraform.tfstate`, `storage/terraform.tfstate`,
`vm-a/terraform.tfstate`, … (your provider's web console will list them).

> **After this first run, apply from CI, not from laptops.** Laptops are for `plan`, `console` and
> reading state. Section 7 explains why.

### 2.6 Commit the provider lock files

`terraform init` created a `.terraform.lock.hcl` in every root. They pin the **exact provider build**, so a
laptop and the CI runner can never silently use different versions. But a lock file made on a Mac only
contains the Mac's checksums, and CI runs Linux. Add all platforms you use:

```bash
for dir in network storage vm-a vm-b vm-c; do
  (cd $dir && terraform providers lock \
     -platform=linux_amd64 -platform=linux_arm64 \
     -platform=darwin_arm64 -platform=darwin_amd64 -platform=windows_amd64)
done
```

### 2.7 Create the GitHub repository and the secrets

```bash
git add -A && git status         # read the list: no clouds.yaml, no *.tfstate, no keys
git commit -m "Initial infrastructure"
# create an EMPTY private repo on GitHub (no README), then:
git remote add origin git@github.com:<you>/<repo>.git
git push -u origin main
```

Add the repository **secrets** (*Settings → Secrets and variables → Actions → New repository secret*):

| Secret | Value |
|---|---|
| `OS_CLOUDS_YAML` | the **entire contents** of the CI `clouds.yaml` (section 2.3) |
| `BUCKET_NAME` | bucket name |
| `AWS_ENDPOINT_URL` | the S3 endpoint URL |
| `AWS_ACCESS_KEY_ID` | state-bucket access key |
| `AWS_SECRET_ACCESS_KEY` | state-bucket secret key |

> **The first push runs `apply.yml`** before the secrets exist (it fails at `init`, harmlessly) — or, if you
> add the secrets first, it runs and finds *no changes*, because you applied by hand in 2.5. The second
> outcome is the best possible smoke test: *the pipeline can read the state and the cloud, and agrees
> that nothing needs to change.* Re-run it from the *Actions* tab after adding the secrets.

### 2.8 Protect `main`

*Settings → Rules → Rulesets → New branch ruleset* (or *Branches → Add rule*), target `main`:

* ✔ **Require a pull request before merging**, with at least **1 approval**.
* ✔ **Require status checks to pass**: select **`lint`** (and `plan`, once it has run once so the name appears).
* ✔ Block force pushes and deletions.

Optionally add a `CODEOWNERS` file so changes to `.github/**`, `modules/**` and `network/**` always need a
specific reviewer — **whoever can edit a workflow can make it run with the secrets** (section 6).

---

## 3. Day-to-day: adding a VM (two pull requests)

The rule from use case 3 still holds — the VM folder *looks up* the port and volume, so they must exist
before the VM's plan can succeed. In a pipeline that becomes **two pull requests**:

**PR 1 — the persistent parts**

```bash
git switch -c add-vm-d
# add "vm-d" to `vms` in network/terraform.tfvars and to `volumes` in storage/terraform.tfvars
git commit -am "Network identity and data volume for vm-d" && git push -u origin add-vm-d
```

Open the pull request. The pipeline plans `network` and `storage` and comments the result. **Read it**: it
must show only `vm-d` resources being added (`0 to change, 0 to destroy`). Merge → `apply.yml` creates
them.

**PR 2 — the VM**

```bash
git switch main && git pull && git switch -c vm-d
cp -R vm-c vm-d && rm -rf vm-d/.terraform
sed -i.bak 's/vm-c/vm-d/g' vm-d/main.tf vm-d/outputs.tf && rm vm-d/*.bak
# also add "vm-d" to the filters in BOTH plan.yml and apply.yml (see "Adding a folder to the pipeline")
git add -A && git commit -m "Add vm-d" && git push -u origin vm-d
```

> **macOS:** `sed -i.bak ... && rm *.bak` works on both macOS and Linux (the plain `sed -i` form does not).

Review the plan (`2 to add`), merge, and the VM appears.

### Adding a folder to the pipeline

Two places list the VM folders, and they must stay identical and in apply order:

1. the `filters:` block in `plan.yml` **and** `apply.yml` (add a `vm-d:` entry like `vm-c`);
2. the `options:` list in `destroy.yml` (if you want the destroy button for it).

(A "discover the folders automatically" job is possible, but it hides the apply order. See *Going further*.)

### Add or change a user

Edit `users.yaml` in a pull request. **Read the plan carefully:** `user_data` (the cloud-init script) can
only be set when a VM is created, so Terraform shows **every VM as "must be replaced"**. Merging
rebuilds them all. Data and IPs survive (that is the point of use case 3), but there is downtime and new
SSH host keys. Section 7 (decision 14) describes the trade-off and the option to avoid it.

### Rebuild or remove a VM

* **Remove for good:** delete its folder, its entry in `vms`/`volumes` (two PRs, in reverse order: VM first;
  `prevent_destroy` will stop you from deleting the IP/volume until you remove that block deliberately).
* **Destroy temporarily (keeping IP and data):** *Actions → Terraform Destroy → Run workflow*, choose the
  folder, type its name to confirm. Bring it back by re-running *Terraform Apply* (a trivial change in the
  folder works) or `terraform apply` locally.
* **Rebuild now:** locally, `terraform apply -replace=module.vm.openstack_compute_instance_v2.vm` (while
  CI is idle).

---

## 4. How the pipeline works

### 4.1 The three workflows

| File | Trigger | What it does |
|---|---|---|
| `plan.yml` | every pull request | **lint** (`fmt -check`, `validate` — no secrets needed) and **plan** for each folder whose files changed; posts/updates one comment per folder. |
| `apply.yml` | push to `main` (i.e. a merge) | applies each changed folder, **one at a time, in order**. |
| `destroy.yml` | manual button | destroys one chosen VM after a typed confirmation. Network and storage are not selectable. |

### 4.2 Which folders run? — `dorny/paths-filter` + a matrix

`detect-changes` compares the files touched by the pull request/merge with a map of
`folder → patterns`. It outputs a JSON list such as `["network","vm-a"]`, which becomes a **matrix**: one
job per entry. Two details matter:

* A folder is "changed" by **its own files *or* the module it uses**. Editing `modules/vm` therefore plans
  every VM; editing `modules/network-identity` plans only `network`.
* The list keeps the order of the filters, so **the order you write the filters is the apply order**.
  `apply.yml` adds `max-parallel: 1`, which makes the matrix run one entry at a time in that order.

### 4.3 What the setup action does

All three workflows start with `./.github/actions/terraform-setup`, which installs the pinned Terraform,
writes `clouds.yaml` for the OpenStack provider, and runs `terraform init` against the remote state.
It is a *composite action* — you write the shared steps once.

### 4.4 Secrets, safely

* Secrets are passed to steps as **environment variables** and written with `printf '%s'` — not pasted into
  the script with `${{ secrets.X }}`. Pasting makes the secret part of the script text, where quotes or
  newlines in the value could change what the script does.
* The same applies to `destroy.yml`'s free-text `confirm` input.
* GitHub masks secret values in logs, but masking is a courtesy, not a guarantee. Never print them.

---

## 5. Remote state

* **Backend:** the `s3` backend, which works with any S3-compatible service.
* **One object per root.** `network/terraform.tfstate`, `storage/terraform.tfstate`, `vm-a/terraform.tfstate`, …
  (the `key` in each `main.tf`). Same independence as before, now in a shared place.
* **Partial configuration.** `main.tf` contains only `backend "s3" { key = "…" }`. The rest is supplied at
  `init` time: `backend.hcl` (committed, non-secret), `-backend-config="bucket=…"` and environment
  variables for the endpoint and keys. This is why no secret ever reaches git.
* **Locking.** `use_lockfile = true` makes Terraform create `<key>.tflock` beside the state while it works.
  Requires Terraform ≥ 1.10 (hence `required_version = ">= 1.10"`) and a store with conditional writes
  (test: section 2.4).

---

## 6. Security model — read this once

* **Treat "write access to the repo" as "can use the cloud credential".** A pull request can change a
  workflow, and the PR's own version of the workflow runs. Mitigate with: private repo, few collaborators,
  required reviews, `CODEOWNERS` on `.github/**`, and GitHub *Environments* with required reviewers for
  apply/destroy (the commented `environment: production` lines).
* **Pull requests from forks do not receive secrets.** That is a feature. It also means plan comments won't
  appear for outside contributors; use a private repo for real infrastructure.
* **Least privilege.** Workflows declare `permissions: contents: read`; only the job that comments gets
  `pull-requests: write`. The CI OpenStack credential is a restricted application credential with an expiry.
  If your cloud allows it, scope its role to what Terraform needs.
* **Rotate** the CI credential and the bucket keys on a schedule; they are five secrets to update.
* **Pin third-party actions.** This template uses major-version tags (`@v4`) for readability. For stricter
  supply-chain safety, pin each to a full commit SHA and let Dependabot update them (*Going further*).
* **State can contain secrets** (e.g. generated passwords). Keep the bucket private.
* **Public keys and names in `users.yaml` identify people.** Keep that file out of public repositories.

---

## 7. Decisions and justifications

| # | Decision | Why — and what we gave up |
|---|---|---|
| 1 | **Remote state in an S3-compatible bucket.** | One shared source of truth for people and CI; survives a lost laptop. *Cost:* you now operate a bucket and its credentials. |
| 2 | **Locking with `use_lockfile` (no lock database).** | Prevents concurrent applies with zero extra infrastructure. *Cost:* needs Terraform ≥ 1.10 and a store that supports conditional writes — hence the test in 2.4. |
| 3 | **Partial backend configuration** (`key` in code; everything else injected). | The code stays identical for every user of the template, and no secret or provider-specific URL is committed. *Cost:* `init` needs flags — they are in the README and wrapped by the setup action. |
| 4 | **Commit `terraform.tfvars` and `users.yaml`.** | CI needs them, and a change to them *is* the change you want reviewed. In use cases 1–3 they were ignored. They are safe **only because they contain no secrets**; secrets stay in GitHub secrets. |
| 5 | **Commit `.terraform.lock.hcl` with multi-platform hashes.** | Everyone, including CI, uses the identical provider build; upgrades become visible diffs. |
| 6 | **Pin Terraform exactly (`1.15.6`) in CI; `required_version >= 1.10` in code.** | CI is reproducible; the code states its real minimum. Bump the pin in its own PR (and check the then-current release first). |
| 7 | **Plan on pull request, apply on merge.** | The reviewed artifact (the plan comment) is what gets applied. *Gap:* the apply re-plans, so a change made in the cloud between PR and merge can alter the result. Applying a *saved plan file* closes this — see *Going further*. |
| 8 | **Matrix of changed folders via `paths-filter`.** | Only touched folders run, in parallel for plans. *Cost:* the folder list lives in YAML and must be updated when you add a VM (section 3). |
| 9 | **`max-parallel: 1` + filter order = apply order; `fail-fast: true` on apply.** | VMs need network and storage to exist first. Serial execution makes that order real, and stopping at the first failure avoids cascading confusing errors. |
| 10 | **`concurrency` group on apply, no cancelling.** | Two quick merges queue instead of racing; cancelling an apply half-way is worse than waiting. |
| 11 | **One updated PR comment per folder, truncated at 60,000 characters.** | No comment spam on every push; GitHub rejects comments over 65,536. The tail is kept because the summary and errors are at the end. |
| 12 | **`plan -lock=false` in pull requests.** | A plan only reads, so it should never block a teammate's apply. |
| 13 | **Composite action for the shared steps.** | The same setup was needed three times; one edit now updates all workflows. |
| 14 | **A cloud-init change rebuilds every VM** (no users-sync mechanism here). | cloud-init (`user_data`) runs at first boot, so changing it forces replacement. We accept this for simplicity: with persistent IP and data (use case 3) a rebuild is cheap and the plan shows it in advance. If rebuilds are too disruptive, add `ignore_changes = [user_data]` to the instance and manage accounts with a separate sync job (*Going further*). |
| 15 | **Destroy is a manual, typed-confirmation button; network/storage excluded.** | Destruction should be deliberate and rare. Persistent resources can only be removed by editing code, which needs a reviewed PR. |
| 16 | **Secrets via env vars; inputs via env vars.** | Avoids script injection (4.4). |
| 17 | **No `paths:` filter on the `plan.yml` trigger.** | Otherwise a required status check never reports on PRs that don't touch Terraform, and the PR can't merge. Skipping is done at job level instead. |
| 18 | **A dedicated CI credential; humans use their own.** | Revocable independently; attributable in the cloud's audit log. "Who may destroy a VM" is decided by the OpenStack role of the credential, not by who can SSH in. |
| 19 | **First deployment by hand, then CI only.** | Proves credentials and state before the pipeline depends on them; the first CI run becomes a no-change smoke test. |

---

## 8. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Error acquiring the state lock` | Another run is active — wait. If a run was killed, the lock may remain: `terraform force-unlock <ID>` (the ID is in the message). Only do this when you are sure nobody is applying. |
| `Failed to get existing workspaces` / `NoSuchBucket` / `403` at init | Wrong `BUCKET_NAME`, `AWS_ENDPOINT_URL` or keys; or the keys lack permission on the bucket. Check the five values. |
| `x509` / certificate errors from the state endpoint | The store uses a private CA. Prefer a store with a trusted certificate; do not disable verification. |
| `Unsupported argument` / backend errors mentioning `use_lockfile` | Terraform older than 1.10. Upgrade locally; CI is pinned. |
| Plan of a new VM: `no port found` / `no volume found` | PR 1 (network/storage) has not been merged and applied yet, or the name differs from the map key. |
| Provider checksum mismatch in CI | The lock file lacks the Linux hash. Re-run section 2.6 and commit. |
| Workflow does not start | Workflows must live in the **repository root's** `.github/workflows/`. Did you copy this folder out of `terraform-templates`? (section 1) |
| `Resource not accessible by integration` when commenting | The job lacks `pull-requests: write`, or the PR comes from a fork. |
| Plan wants to replace every VM after a harmless edit | Something under `modules/vm` or `users.yaml` changed → new `user_data`. See decision 14. |
| `apply.yml` ran but a folder was skipped | It was not in the `filters:` list, or none of its patterns matched the changed files. |
| Fails at `terraform fmt -check` | Run `terraform fmt -recursive` locally and commit. |
| Commented plan is cut off | By design above 60,000 characters; open the workflow log for the full text. |

---

## 9. Going further (ideas, not included)

* **Apply the exact reviewed plan.** `plan -out=tfplan`, upload it as an artifact, and have the apply
  job download and `terraform apply tfplan`. Removes the PR-to-merge gap (decision 7).
* **Users without rebuilds.** Keep `users.yaml` as the single source of truth, but add a small job that
  connects over SSH and creates/updates accounts and keys on running VMs (and sets `ignore_changes = [user_data]`).
  New VMs still get everyone at first boot. That removes the downtime in decision 14.
* **Drift detection.** A scheduled workflow running `terraform plan -detailed-exitcode` and opening an issue
  when someone changed things by hand.
* **More checks in lint:** `tflint`, `checkov`/`trivy config` for security rules, and `terraform-docs` to
  generate variable tables.
* **Dependabot** for GitHub Actions and Terraform providers (`.github/dependabot.yml`), with actions pinned to SHAs.
* **Auto-discover VM folders** in the pipeline (a script that lists `vm-*`), once you have enough VMs that
  editing three lists hurts.
* **Environments**: separate `staging`/`production` roots with their own secrets and reviewers.

---

## 10. Where this leaves you

You now have: reusable modules (use case 2), network and data that outlive any VM (use case 3), and
reviewed, repeatable, auditable changes (this use case). The same shape — layers in separate states,
connected by names, changed only through pull requests — scales from three VMs to many.
