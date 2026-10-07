# Root module: wires the three child modules together.
# Dependency chain: network (VPC -> subnet -> IGW -> route table -> SG) -> compute (EC2), storage (S3) -> compute (IAM read access)

# my public IP - used to show the website is reachable from outside
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

module "network" {
  source             = "./modules/network"
  name               = var.project
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  ssh_allowed_cidr   = var.ssh_allowed_cidr
}

module "storage" {
  source = "./modules/storage"
  name   = var.project
}

module "compute" {
  source            = "./modules/compute"
  name              = var.project
  instance_type     = var.instance_type
  subnet_id         = module.network.public_subnet_id
  security_group_id = module.network.web_sg_id
  bucket_name       = module.storage.bucket_name # implicit dependency on the S3 module
  bucket_arn        = module.storage.bucket_arn
}
