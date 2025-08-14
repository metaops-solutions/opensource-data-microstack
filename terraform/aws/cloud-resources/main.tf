# Get the public IP of the machine running Terraform
data "http" "my_ip" {
  url = "https://api.ipify.org/"
}

resource "random_id" "ssh_secret_suffix" {
  byte_length = 4
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  enable_nat_gateway = true
  single_nat_gateway = true
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_secretsmanager_secret" "ssh_private_key" {
  name = "k3s-ssh-private-key-${random_id.ssh_secret_suffix.hex}"
}

resource "aws_secretsmanager_secret_version" "ssh_private_key_version" {
  secret_id     = aws_secretsmanager_secret.ssh_private_key.id
  secret_string = tls_private_key.ssh.private_key_pem
}

resource "aws_key_pair" "k3s" {
  key_name   = "k3s-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "aws_security_group" "k3s" {
  name        = "k3s-sg"
  description = "Allow SSH, HTTP, HTTPS, K3s"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat(var.ssh_whitelist_cidrs, ["${chomp(data.http.my_ip.response_body)}/32"])
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = concat(var.ssh_whitelist_cidrs, ["${chomp(data.http.my_ip.response_body)}/32"])
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = concat(var.ssh_whitelist_cidrs, ["${chomp(data.http.my_ip.response_body)}/32"])
  }
  # Allow K3s API access from the machine running Terraform and whitelisted CIDRs
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = concat(var.ssh_whitelist_cidrs, ["${chomp(data.http.my_ip.response_body)}/32"])
    description = "K3s API access from Terraform runner and whitelisted CIDRs"
  }
  # Add more ports as needed for K3s
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "k3s" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  key_name                    = aws_key_pair.k3s.key_name
  iam_instance_profile        = aws_iam_instance_profile.k3s_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_disk_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user-data.sh", {})

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.ssh.private_key_pem
    host        = self.public_ip
  }

  provisioner "file" {
    source      = "${path.module}/99-auto-lvm.rules"
    destination = "/tmp/99-auto-lvm.rules"
  }
  provisioner "file" {
    source      = "${path.module}/auto-lvm-add.sh"
    destination = "/tmp/auto-lvm-add.sh"
  }

  tags = {
    Name = "k3s-server"
  }
  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do echo 'Waiting for k3s.yaml...'; sleep 5; done",
      "sudo cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/k3s.yaml",
      "sudo chown ubuntu:ubuntu /home/ubuntu/k3s.yaml"
    ]
  }

  provisioner "local-exec" {
    command = <<EOT
      echo '${tls_private_key.ssh.private_key_pem}' > ./k3s_id_rsa && chmod 600 ./k3s_id_rsa
      for i in {1..30}; do \
        scp -o StrictHostKeyChecking=no -i ./k3s_id_rsa ubuntu@${self.public_ip}:/home/ubuntu/k3s.yaml ./k3s.yaml && break || sleep 5; \
      done
      sed -i '' 's#server: https://127.0.0.1:6443#server: https://${self.public_dns}:6443#' ./k3s.yaml
      rm -f ./k3s_id_rsa
    EOT
  }
}

resource "aws_ebs_volume" "data" {
  for_each          = { for disk in var.data_disks : disk.name => disk }
  availability_zone = var.azs[0]
  size              = each.value.size
  type              = "gp3"
  tags = {
    Name = each.value.name
  }
}

# Attach all data disks using for_each and device_name from variable
resource "aws_volume_attachment" "data" {
  for_each    = aws_ebs_volume.data
  device_name = lookup({ for disk in var.data_disks : disk.name => disk.device_name }, each.key, "/dev/xvdb")
  volume_id   = each.value.id
  instance_id = aws_instance.k3s.id
}

resource "aws_iam_role" "k3s" {
  name               = "k3s-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_instance_profile" "k3s_profile" {
  name = "k3s-ec2-profile"
  role = aws_iam_role.k3s.name
}

# Generate kubeconfig with public DNS for K3s using built-in templatefile()
resource "aws_secretsmanager_secret" "kubeconfig" {
  name = "k3s-kubeconfig-${random_id.ssh_secret_suffix.hex}"
}


# Upload k3s.yaml to Secrets Manager after it is present using AWS CLI
resource "null_resource" "upload_kubeconfig" {
  depends_on = [aws_instance.k3s]
  provisioner "local-exec" {
    command     = <<EOT
      # Wait for k3s.yaml to be present
      for i in {1..30}; do \
        if [ -f "${path.module}/k3s.yaml" ]; then \
          break; \
        fi; \
        sleep 5; \
      done

      # Patch k3s.yaml: remove certificate-authority-data and add insecure-skip-tls-verify: true
      yq eval 'del(.clusters[].cluster."certificate-authority-data") | .clusters[].cluster."insecure-skip-tls-verify" = true' -i "${path.module}/k3s.yaml"

      # Upload patched k3s.yaml to Secrets Manager
      aws secretsmanager put-secret-value \
        --secret-id ${aws_secretsmanager_secret.kubeconfig.id} \
        --secret-string "$(cat ${path.module}/k3s.yaml)" \
        --region ${var.aws_region}
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}
