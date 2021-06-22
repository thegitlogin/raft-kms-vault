output "endpoints" {
  value = <<EOF

  NOTE: While Terraform's work is done, these instances need time to complete
        their own installation and configuration. Progress is reported within
        the log file `/var/log/tf-user-data.log` and reports 'Complete' when
        the instance is ready.

  vault_1 (${aws_instance.vault-server[0].public_ip}) | internal: (${aws_instance.vault-server[0].private_ip})
    - Initialized and unsealed.
    - The root token and recovery key is stored in /tmp/key.json.
    - K/V-V2 secret engine enabled and secret stored.
    - Leader of HA cluster

    $ ssh -l ubuntu ${aws_instance.vault-server[0].public_ip} -i ${var.key_pair}.pem

    # Root token:
    $ ssh -l ubuntu ${aws_instance.vault-server[0].public_ip} -i ${var.key_pair}.pem "cat ~/root_token"
    # Recovery key:
    $ ssh -l ubuntu ${aws_instance.vault-server[0].public_ip} -i ${var.key_pair}.pem "cat ~/recovery_key"

  vault_2 (${aws_instance.vault-server[1].public_ip}) | internal: (${aws_instance.vault-server[1].private_ip})
    - Started
    - You will join it to cluster started by vault_2

    $ ssh -l ubuntu ${aws_instance.vault-server[1].public_ip} -i ${var.key_pair}.pem

  vault_3 (${aws_instance.vault-server[2].public_ip}) | internal: (${aws_instance.vault-server[2].private_ip})
    - Started
    - You will join it to cluster started by vault_2

    $ ssh -l ubuntu ${aws_instance.vault-server[2].public_ip} -i ${var.key_pair}.pem

EOF
}
