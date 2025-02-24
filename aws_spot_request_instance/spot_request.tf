# AWS provider configuration
provider "aws" {
  region = "ap-south-1" # Customize this as needed
}

# Create random security group ID
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
  name        = "minikube-sg-${random_id.sg_suffix.hex}"
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

# Spot instance request
resource "aws_spot_instance_request" "minikube" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = "subnet-03c511ebf87ec21aa" # Replace with your subnet ID
  vpc_security_group_ids = [aws_security_group.minikube_sg.id]
  key_name               = "plab" # Replace with your AWS key pair name
  spot_price             = "0.0222" # Adjust based on current market rates
  wait_for_fulfillment   = true

  user_data = <<-EOF
              #!/bin/bash
              set -x  # Debug mode enabled

              # Update system packages
              apt-get update -y
              apt-get upgrade -y

              # Install required dependencies
              apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release conntrack

              # Install Docker
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
              echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
              apt-get update -y
              apt-get install -y docker-ce docker-ce-cli containerd.io

              # Start and enable Docker
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              chmod 666 /var/run/docker.sock  # Fix Docker socket permissions
              sleep 10  # Give Docker some time to start

              # Make Docker socket permission persistent
              mkdir -p /etc/systemd/system/docker.service.d
              echo "[Service]" | tee /etc/systemd/system/docker.service.d/override.conf
              echo "ExecStartPost=/bin/chmod 666 /var/run/docker.sock" | tee -a /etc/systemd/system/docker.service.d/override.conf
              systemctl daemon-reload
              systemctl restart docker

              # Install kubectl
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
              rm kubectl  # Cleanup

              # Install Minikube
              curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
              install minikube-linux-amd64 /usr/local/bin/minikube
              rm minikube-linux-amd64  # Cleanup

              # Ensure Minikube and Docker work for all users
              echo 'export PATH=$PATH:/usr/local/bin' | tee -a /etc/profile
              echo 'export PATH=$PATH:/usr/local/bin' | tee -a /home/ubuntu/.bashrc

              # Start Minikube as root to avoid permission issues
              sudo minikube start --driver=docker --force

              # Verify installation
              sudo kubectl get nodes > /home/ubuntu/minikube_setup.log 2>&1
              EOF

  tags = {
    Name = "minikube-instance"
  }
}

# Outputs for convenience
output "instance_public_ip" {
  description = "Public IP of the Minikube EC2 instance"
  value       = aws_spot_instance_request.minikube.public_ip
}

output "instance_id" {
  description = "ID of the Minikube EC2 instance"
  value       = aws_spot_instance_request.minikube.id
}

# Variable for instance types
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.medium"
}
