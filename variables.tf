# AWS region and AZs in which to deploy
variable "aws_region" {
  default = "us-east-1"
}

variable "availability_zones" {
  default = "us-east-1a"
}

# All resources will be tagged with this
variable "environment_name" {
  default = "raft-demo"
}


variable "vault_server_names" {
  description = "Names of the Vault nodes that will join the cluster"
  type = list(string)
  default = [ "vault_1", "vault_2", "vault_3" ]
}

variable "vault_server_private_ips" {
  description = "The private ips of the Vault nodes that will join the cluster"
  # @see https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Subnets.html
  type = list(string)
  default = [ "10.0.101.xx", "10.0.101.xx", "10.0.101.xx" ]
}


# URL for Vault Ent binary
variable "vault_zip_file" {
  default = "https://releases.hashicorp.com/vault/1.7.1+ent/vault_1.7.1+ent_linux_amd64.zip"
}

# Instance size
variable "instance_type" {
  default = "m5.large"
}

# SSH key name to access EC2 instances (should already exist) in the AWS Region
variable "key_pair" {
  description = "SSH Key pair used to connect on AWS east-1"
  type        = string
  default     = "vault_kp_e1"
}

variable "instance_ami" {
  description = "ID of the AMI used"
  type        = string
  default     = "ami-0747bdcabd34c712a"
}

# S3 bucket
variable "s3bucket" {
  default = "vaulttext"
}
