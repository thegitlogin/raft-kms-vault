provider "aws" {
  region = var.aws_region
}

resource "aws_kms_key" "vault" {
  description             = "Vault unseal key"
  deletion_window_in_days = 10

  tags = {
    Name = "vault-kms-unseal-trav"
  }
}

//--------------------------------------------------------------------
// Vault Server Instance

resource "aws_instance" "vault-server" {
  count                       = length(var.vault_server_names)
  ami                         = var.instance_ami
  instance_type               = var.instance_type
  subnet_id                   = module.vault_demo_vpc.public_subnets[0]
  key_name                    = var.key_pair
  vpc_security_group_ids      = [aws_security_group.testing.id]
  associate_public_ip_address = true
  private_ip                  = var.vault_server_private_ips[count.index]
  iam_instance_profile        = aws_iam_instance_profile.vault-server.id

  root_block_device {
    delete_on_termination = false
    encrypted             = false
    volume_size           = 50
    volume_type           = "gp2"
  }


  # user_data = data.template_file.vault-server[count.index].rendered
  user_data = templatefile("${path.module}/templates/userdata-vault-server.tpl", {
    tpl_vault_node_name          = var.vault_server_names[count.index],
    tpl_vault_storage_path       = "/vault/${var.vault_server_names[count.index]}",
    tpl_vault_zip_file           = var.vault_zip_file,
    tpl_vault_service_name       = "vault-${var.environment_name}",
    tpl_vault_node_address_names = zipmap(var.vault_server_private_ips, var.vault_server_names)
    kms_key                      = aws_kms_key.vault.id
    aws_region                   = var.aws_region
  })

  tags = {
    Name         = "${var.environment_name}-vault-server-${var.vault_server_names[count.index]}"
    cluster_name = "raft-test"
  }

  lifecycle {
    ignore_changes = [ami, tags]
  }
}
