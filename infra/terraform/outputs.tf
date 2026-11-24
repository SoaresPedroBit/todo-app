output "app_url" {
  description = "Endereço HTTPS da aplicação"
  value       = var.https_port == 443 ? "https://${var.site_address}" : "https://${var.site_address}:${var.https_port}"
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}

output "inventario" {
  description = "Inventário dos recursos (ACE-02)"
  value = {
    vpc = {
      id            = aws_vpc.todo.id
      cidr          = aws_vpc.todo.cidr_block
      sub_rede_pub  = "${aws_subnet.publica.id} (${aws_subnet.publica.cidr_block})"
      sub_rede_priv = "${aws_subnet.privada.id} (${aws_subnet.privada.cidr_block})"
      sg_aplicacao  = aws_security_group.app.id
      sg_banco      = aws_security_group.db.id
      nat_gateway   = aws_nat_gateway.todo.id
    }
    vm_aplicacao = {
      instancia  = aws_instance.app.id
      tipo       = aws_instance.app.instance_type
      ip_privado = aws_instance.app.private_ip
      ip_publico = aws_eip.app.public_ip
      vm_local   = docker_container.vm_app.name
    }
    vm_banco = {
      instancia  = aws_instance.db.id
      tipo       = aws_instance.db.instance_type
      ip_privado = aws_instance.db.private_ip
      ip_publico = "nenhum"
      volume_ebs = "${aws_ebs_volume.mongo_data.id} (${aws_ebs_volume.mongo_data.size} GB, ${aws_ebs_volume.mongo_data.type})"
      vm_local   = docker_container.vm_db.name
    }
    backups = "s3://${aws_s3_bucket.backups.bucket}/mongo/ (retenção ${var.backup_retention_days} dias)"
  }
}
