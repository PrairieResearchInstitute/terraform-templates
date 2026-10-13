#!/usr/bin/env bash
#
# upload_ubuntu_image.sh -- put an official Ubuntu cloud image into your OpenStack project.
#
# WHY: Terraform creates VMs from an IMAGE looked up by NAME (e.g. "Ubuntu 24.04").
# If your project has no image with that name, or only an old one, you upload one
# with this script. Images are per-project and shared by every VM in the project,
# so you normally run this once per Ubuntu release, not once per VM.
#
# USAGE
#   ./upload_ubuntu_image.sh <cloud_name> [--release <codename>] [--name "<image name>"]
#                            [--replace]
#
#   cloud_name   entry in ~/.config/openstack/clouds.yaml (see bootstrap/README.md)
#   --release    Ubuntu codename: jammy (22.04), noble (24.04, default), resolute (26.04), ...
#   --name       image name shown in OpenStack and used by Terraform.
#                Defaults for the three releases above; REQUIRED for any other release.
#   --replace    if an image with that name already exists, DELETE it and upload again.
#                Without this flag an existing image is left alone (safe default).
#
# EXAMPLES
#   ./upload_ubuntu_image.sh my-cloud                              # Ubuntu 24.04, first time
#   ./upload_ubuntu_image.sh my-cloud --release resolute           # add Ubuntu 26.04 NEXT TO it
#   ./upload_ubuntu_image.sh my-cloud --replace                    # refresh 24.04 with today's build
#
# NOTES
# - This uploads an image. It does NOT upgrade existing VMs (a VM keeps the OS it booted from).
# - --replace gives the image a NEW ID. Terraform roots that look the image up by name
#   will then see a different image_id on the next plan (the case-3/4 modules ignore that
#   on purpose; see the main README).
# - The download goes to a private temporary folder that is always deleted on exit.
# - The download is checked against Ubuntu's published SHA256SUMS before anything is uploaded.

set -euo pipefail

# -------------------------
# Config
# -------------------------
ARCH="x86_64"            # architecture tag stored on the image
MIN_DISK_GB=20           # smallest root disk the image may be booted on
MIN_RAM_MB=2048          # smallest RAM it may be booted with
BASE_URL="https://cloud-images.ubuntu.com"

# -------------------------
# Helpers
# -------------------------
die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2
  exit 2
}

# sha256 of a file, on both macOS (shasum) and Linux (sha256sum)
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

default_name_for() {
  case "$1" in
    jammy)    echo "Ubuntu 22.04" ;;
    noble)    echo "Ubuntu 24.04" ;;
    resolute) echo "Ubuntu 26.04" ;;
    *)        echo "" ;;
  esac
}

# -------------------------
# Arguments
# -------------------------
CLOUD_NAME="${1:-}"
[[ -n "$CLOUD_NAME" && "$CLOUD_NAME" != -* ]] || usage
shift

RELEASE="noble"
IMAGE_NAME=""
REPLACE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) RELEASE="${2:-}"; [[ -n "$RELEASE" ]] || usage; shift 2 ;;
    --name)    IMAGE_NAME="${2:-}"; [[ -n "$IMAGE_NAME" ]] || usage; shift 2 ;;
    --replace) REPLACE="true"; shift ;;
    -h|--help) usage ;;
    *)         echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ -n "$IMAGE_NAME" ]] || IMAGE_NAME="$(default_name_for "$RELEASE")"
[[ -n "$IMAGE_NAME" ]] || die "No default image name for release '$RELEASE'. Pass --name \"Ubuntu XX.YY\"."

IMAGE_FILE="${RELEASE}-server-cloudimg-amd64.img"
IMAGE_URL="${BASE_URL}/${RELEASE}/current/${IMAGE_FILE}"
SUMS_URL="${BASE_URL}/${RELEASE}/current/SHA256SUMS"

need_cmd openstack
need_cmd curl

# mktemp gives a private folder, so nothing else can swap the file between download and upload
WORKDIR="$(mktemp -d)"
LOCAL_FILE="$WORKDIR/$IMAGE_FILE"
trap 'rm -rf "$WORKDIR"' EXIT          # always removed, even on error (the file is ~600 MB)

# Tell the OpenStack CLI which clouds.yaml entry to use
export OS_CLOUD="$CLOUD_NAME"

echo "----------------------------------------------------------------------"
echo "-- Cloud:   $OS_CLOUD"
echo "-- Release: $RELEASE"
echo "-- Image:   $IMAGE_NAME"
echo "----------------------------------------------------------------------"

# -------------------------
# 1. Do the credentials work?
# -------------------------
echo "Auth check..."
openstack token issue >/dev/null
echo "OK: token issued."

# -------------------------
# 2. Does the image already exist?
# -------------------------
if openstack image show "$IMAGE_NAME" >/dev/null 2>&1; then
  if [[ "$REPLACE" != "true" ]]; then
    echo "An image named '$IMAGE_NAME' already exists. Nothing to do."
    echo "(Use --replace to delete it and upload a fresh build.)"
    exit 0
  fi
  EXISTING=true
else
  EXISTING=false
fi

# -------------------------
# 3. Download and verify
# -------------------------
echo "Downloading $IMAGE_URL"
curl -fL --retry 3 -o "$LOCAL_FILE" "$IMAGE_URL"
[[ -s "$LOCAL_FILE" ]] || die "Download failed or file is empty."

echo "Verifying checksum..."
curl -fsSL --retry 3 -o "$WORKDIR/SHA256SUMS" "$SUMS_URL"
# Each line looks like:  <hash> *<file name>   (the * is optional)
EXPECTED="$(awk -v f="$IMAGE_FILE" '$2==f || $2=="*"f {print $1}' "$WORKDIR/SHA256SUMS")"
[[ -n "$EXPECTED" ]] || die "$IMAGE_FILE not found in SHA256SUMS."
ACTUAL="$(sha256_of "$LOCAL_FILE")"
[[ "$EXPECTED" == "$ACTUAL" ]] || die "Checksum mismatch! expected $EXPECTED, got $ACTUAL. Not uploading."
echo "OK: checksum matches."

# -------------------------
# 4. Replace (only when asked) and upload
# -------------------------
if [[ "$EXISTING" == "true" ]]; then
  echo "Deleting existing image named: $IMAGE_NAME"
  openstack image delete "$IMAGE_NAME"
fi

echo "Creating image: $IMAGE_NAME (this can take a few minutes)"
openstack image create \
  --container-format bare \
  --disk-format qcow2 \
  --min-disk "$MIN_DISK_GB" \
  --min-ram "$MIN_RAM_MB" \
  --property architecture="$ARCH" \
  --file "$LOCAL_FILE" \
  "$IMAGE_NAME" >/dev/null

echo "Verifying:"
openstack image show "$IMAGE_NAME" -c status -c disk_format -c size -c min_disk -c min_ram -f yaml

echo "----------------------------------------------------------------------"
echo "-- Done. Ubuntu images in this project:"
openstack image list | grep -E "Ubuntu|ID" || true
echo "----------------------------------------------------------------------"
