output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion_host.public_ip
}

output "hotstar_application_private_ip" {
  description = "Private IP address of the Hotstar application instance"
  value       = aws_instance.hotstar_application.private_ip
}

output "ssh_command" {
  description = "Command to SSH to the private instance via bastion"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.hotstar_application.private_ip} -o ProxyCommand=\"ssh -i ${var.key_name}.pem -W %h:%p ubuntu@${aws_instance.bastion_host.public_ip}\""
}

output "private_key_path" {
  description = "Path to the generated private key"
  value       = "${path.root}/${var.key_name}.pem"
}
