# backend.hcl -- the SHARED, NON-SECRET part of the remote-state configuration.
# Every root passes it to `terraform init`:
#
#   terraform init -backend-config=../backend.hcl -backend-config="bucket=$BUCKET_NAME"
#
# What is NOT here, on purpose:
#   * bucket name        -> -backend-config="bucket=..."   (CI: secret BUCKET_NAME)
#   * endpoint URL       -> environment variable AWS_ENDPOINT_URL
#   * access/secret keys -> environment variables AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# The `key` (object name) of each state is written in each root's main.tf.

# Any non-empty value works for most S3-compatible stores (e.g. Ceph); the AWS
# provider code just insists on one.
region = "us-east-1"

# Path-style URLs: https://host/bucket instead of https://bucket.host. Most
# self-hosted S3-compatible stores need this.
use_path_style = true

# The S3 backend normally talks to AWS-only services (STS, EC2 metadata) to
# validate credentials. A non-AWS store has none of them, so skip those checks.
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_metadata_api_check     = true
skip_region_validation      = true

# LOCKING: while one `apply` runs, Terraform writes a small "<key>.tflock" object
# next to the state; a second apply fails instead of corrupting the state. Needs
# Terraform >= 1.10 and a store that supports conditional writes (see the README
# for how to test yours). No separate lock database is needed.
use_lockfile = true
