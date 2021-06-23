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

ssh on to vault_1 
  1. $ cat /var/log/tf-user-data.log
  2. Wait for the process to complete
  3. Once complete and you see that the files are downloaded from s3 bucket
  4. $ cat root_token 
  5. copy the token and use in vault login
  6. $ export VAULT_ADDR=http://127.0.0.1:8200
  7. $ vault login <root_token>
  8. $ export VAULT_TOKEN=$VAULT_TOKEN
  9. cd /home/ 
  10. ls -l
  11. $ ./testing.sh - to run a batch process

To check if a cluster has formed, run

  $ vault operator raft list-peers
