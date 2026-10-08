output "vpc_id" { value = module.network.vpc_id }
output "public_subnet_id" { value = module.network.public_subnet_id }
output "security_group_id" { value = module.network.web_sg_id }
output "instance_id" { value = module.compute.instance_id }
output "instance_public_ip" { value = module.compute.public_ip }
output "website_url" { value = "http://${module.compute.public_ip}" }
output "s3_bucket" { value = module.storage.bucket_name }
