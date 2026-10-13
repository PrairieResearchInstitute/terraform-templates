output "volume_ids" {
  description = "ID of every persistent data volume."
  value       = { for name, v in openstack_blockstorage_volume_v3.vm_data : name => v.id }
}
