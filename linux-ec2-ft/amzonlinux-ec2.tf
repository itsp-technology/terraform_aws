# AWS provider configuration
provider "aws" {
  region = "us-east-1" # Customize this as needed
}

# Data source to fetch the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
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
  name        = "minikube-sg"
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
}

# EC2 instance with Minikube and kubectl installation
resource "aws_instance" "minikube" {
  #In the Terraform configuration, the AMI ID is not
  #explicitly passed as a hardcoded value but is dynamically fetched using the aws_ami data source.
  ami                    = data.aws_ami.amazon_linux.id #  ami = "ami-0c55b159cbfafe1f0"  we can pass hardcode as well other we can get latest one form aws
  instance_type          = "t2.medium"              # Fixed as requested
  subnet_id              = "subnet-0c9e45bc56dcf63e4" # Replace with your subnet ID
  vpc_security_group_ids = [aws_security_group.minikube_sg.id]
  key_name               = "personLap"             # Replace with your AWS key pair name

  # User data script to install Minikube, kubectl, and start Kubernetes
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              
              # Install Docker
              yum install -y docker
              systemctl enable docker
              systemctl start docker
              usermod -aG docker ec2-user

              # Install kubectl
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              chmod +x kubectl
              mv kubectl /usr/local/bin/

              # Install Minikube
              curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
              install minikube-linux-amd64 /usr/local/bin/minikube

              # Start Minikube as ec2-user
              su - ec2-user -c "minikube start --driver=docker"

              # Verify installation
              su - ec2-user -c "kubectl get nodes"
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