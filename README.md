# raft-kms-vault
Vault with integrated storage and AWS KMS unseal

# Variables

Create a key pair in AWS us-east-1 and update that in variables.tf

Add vault ips in "vault_server_private_ips" in Variables.tf

Step 1. Add AWS env variables
Step 2. terraform init
Step 3. terraform plan
Step 4. terraform apply

Vault_1 will be Leader. 
