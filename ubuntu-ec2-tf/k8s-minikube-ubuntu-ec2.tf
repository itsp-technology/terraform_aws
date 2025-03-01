# AWS provider configuration
provider "aws" {
  region = "ap-south-1" # Customize this as needed
}

# create random security group id 
resource "random_id" "sg_suffix" {
  byte_length = 4
}

# Data source to fetch the latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's owner ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Security group for the EC2 instance
resource "aws_security_group" "minikube_sg" {
 # name        = "minikube-sg"
  name = "minikube-sg-${random_id.sg_suffix.hex}"
  description = "Security group for Minikube EC2 instance"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict this to your IP in production
  }

  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Minikube API server, restrict in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "minikube-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EC2 instance with Minikube and kubectl installation
resource "aws_instance" "minikube" {
  #In the Terraform configuration, the AMI ID is not
  #explicitly passed as a hardcoded value but is dynamically fetched using the aws_ami data source.
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.medium"
  subnet_id              = "subnet-03c511ebf87ec21aa" # Replace with your subnet ID
  vpc_security_group_ids = [aws_security_group.minikube_sg.id]
  key_name               = "personLap"             # Replace with your AWS key pair name

  # User data script to install Minikube, kubectl, and start Kubernetes
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get upgrade -y

              # Install Docker prerequisites
              apt-get install -y ca-certificates curl gnupg

              # Add Docker's official GPG key
              install -m 0755 -d /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
              chmod a+r /etc/apt/keyrings/docker.gpg

              # Setup Docker repository
              echo \
                "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
                tee /etc/apt/sources.list.d/docker.list > /dev/null

              apt-get update -y

              # Install Docker
              apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

              systemctl enable docker
              systemctl start docker
              usermod -aG docker ubuntu

              # Install kubectl
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

              # Install Minikube
              curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
              install minikube-linux-amd64 /usr/local/bin/minikube

              # Start Minikube as ubuntu user
              su - ubuntu -c "minikube start --driver=docker"

              # Verify installation
              su - ubuntu -c "kubectl get nodes"
              EOF

  tags = {
    Name = "minikube-instance"
  }
}

# Outputs for convenience
output "instance_public_ip" {
  description = "Public IP of the Minikube EC2 instance"
  value       = aws_instance.minikube.public_ip
}

output "instance_id" {
  description = "ID of the Minikube EC2 instance"
  value       = aws_instance.minikube.id
}