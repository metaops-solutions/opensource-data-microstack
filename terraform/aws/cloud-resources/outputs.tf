
output "instance_ip" {
  value = aws_instance.k3s.public_ip
}
