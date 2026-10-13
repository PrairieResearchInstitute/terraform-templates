#!/usr/bin/env bash
#
# upload_ubuntu_2404.sh
# Upload (or refresh) ONLY the Ubuntu 24.04 (Noble) cloud image into Glance
# for a single OpenStack cloud configured in ~/.config/openstack/clouds.yaml.
#
# Usage:
#   ./upload_ubuntu_2404.sh <cloud_name> [--cleanup]
#
# Example:
#   ./upload_ubuntu_2404.sh my-cloud --cleanup
#
# Notes:
# - This uploads an image; it does NOT upgrade existing VMs.
# - It DELETES any existing image with the same name before uploading the new
#   one. The new image gets a NEW ID, so any Terraform root that looks the image
#   up by name will see a different image_id on its next plan (see README).
# - You normally need this ONCE per OpenStack project (the image is shared by
#   every VM in the project), or when you deliberately want a fresher base image.
# - The image file is downloaded locally to /tmp, then uploaded to Glance.
# - By default it creates/replaces an image named "Ubuntu 24.04".
# - Prefer a safer custom name? Change IMAGE_NAME below (and image_name in your Terraform variables).

set -euo pipefail

# -------------------------
# Config
# -------------------------
ARCH="x86_64"
MIN_DISK_GB=20
MIN_RAM_MB=2048

# Glance image display name (what you will see in Horizon -> Images)
IMAGE_NAME="Ubuntu 24.04"

# Upstream Ubuntu Noble cloud image
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

# Local download path
LOCAL_FILE="/tmp/noble.qcow2"

# -------------------------
# Helpers
# -------------------------
die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

usage() {
  cat >&2 <<EOF
Usage: $0 <cloud_name> [--cleanup]

Arguments:
  cloud_name   Name of the cloud entry in ~/.config/openstack/clouds.yaml
  --cleanup    Remove the downloaded image file from /tmp after a successful upload

Example:
  $0 my-cloud --cleanup
EOF
  exit 2
}

download_image() {
  echo "Downloading Ubuntu 24.04 image to: $LOCAL_FILE"
  # Always re-download to ensure you get the latest 'current' build
  rm -f "$LOCAL_FILE"
  curl -L -o "$LOCAL_FILE" "$IMAGE_URL"
  [[ -s "$LOCAL_FILE" ]] || die "Download failed or file is empty: $LOCAL_FILE"
}

delete_image_if_exists() {
  if openstack image show "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Deleting existing Glance image named: $IMAGE_NAME"
    openstack image delete "$IMAGE_NAME"
  else
    echo "No existing image named '$IMAGE_NAME' (ok)"
  fi
}

create_image() {
  echo "Creating Glance image: $IMAGE_NAME"
  openstack image create \
    --container-format bare \
    --disk-format qcow2 \
    --min-disk "$MIN_DISK_GB" \
    --min-ram "$MIN_RAM_MB" \
    --property architecture="$ARCH" \
    --file "$LOCAL_FILE" \
    "$IMAGE_NAME" >/dev/null

  echo "Verifying Glance image:"
  openstack image show "$IMAGE_NAME" -c status -c disk_format -c size -c min_disk -c min_ram -f yaml
}

# -------------------------
# Main
# -------------------------
need_cmd openstack
need_cmd curl

CLOUD_NAME="${1:-}"
[[ -n "$CLOUD_NAME" ]] || usage

CLEANUP="false"
if [[ "${2:-}" == "--cleanup" ]]; then
  CLEANUP="true"
elif [[ "${2:-}" != "" ]]; then
  usage
fi

export OS_CLOUD="$CLOUD_NAME"

echo "----------------------------------------------------------------------"
echo "-- Cloud: $OS_CLOUD"
echo "-- Uploading image: $IMAGE_NAME"
echo "----------------------------------------------------------------------"

# Auth sanity check (does not require identity:list_projects)
echo "Auth check..."
openstack token issue >/dev/null
echo "OK: token issued."

download_image
delete_image_if_exists
create_image

echo "----------------------------------------------------------------------"
echo "-- Done. Matching images:"
openstack image list | egrep "Ubuntu 24.04" || true
echo "----------------------------------------------------------------------"

if [[ "$CLEANUP" == "true" ]]; then
  echo "Cleaning up local file: $LOCAL_FILE"
  rm -f "$LOCAL_FILE"
fi
