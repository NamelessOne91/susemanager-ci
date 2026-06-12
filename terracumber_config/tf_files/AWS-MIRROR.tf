terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws  = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}


# --- CONFIGURATION VARIABLES ---
variable "AWS_REGION" {
  type        = string
  default     = "eu-west-1"
  description = "The target AWS Region"
}

variable "AWS_AVAILABILITY_ZONE" {
  type        = string
  default     = "eu-west-1a"
  description = "The exact Availability Zone for the subnet and instance"
}

variable "MIRROR_VPC_CIDR" {
  type        = string
  default     = "172.17.255.240/28"
}

variable "MIRROR_PRIVATE_IP" {
  type        = string
  default     = "172.17.255.244"
}

variable "PEER_VPC_CIDR" {
  type        = string
  default     = "172.16.0.0/16"
  description = "The CIDR range of the VPC to peer with"
}

variable "NAME_PREFIX" {
  type        = string
  default     = "testing-mirror"
  description = "A prefix for all resource names to easily identify them in the AWS console"
}

provider "aws" {
  region = var.AWS_REGION
}

data "aws_ami" "opensuse160o" {
  most_recent = true
  name_regex  = "^openSUSE-Leap-16-0-"
  owners      = ["679593333241"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
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

# --- STABLE NETWORKING LAYER ---
resource "aws_vpc" "mirror_vpc" {
  cidr_block           = var.MIRROR_VPC_CIDR
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "mirror-isolated-vpc"
  }
}

resource "aws_subnet" "mirror_subnet" {
  vpc_id                  = aws_vpc.mirror_vpc.id
  cidr_block              = var.MIRROR_VPC_CIDR
  availability_zone       = var.AWS_AVAILABILITY_ZONE
  map_public_ip_on_launch = false # Strictly no public IP generation

  tags = {
    Name = "${var.NAME_PREFIX}-private-subnet"
  }
}

# --- SECURE FIREWALL (SECURITY GROUP) ---
resource "aws_security_group" "mirror_sg" {
  name        = "${var.NAME_PREFIX}-secure-sg"
  description = "Allow SSM connectivity and out-of-band traffic to worker VMs"
  vpc_id      = aws_vpc.mirror_vpc.id

  # Inbound is empty by default (No open inbound ports to the world)

  # Outbound Rule 1: HTTPS for SSM Agent connectivity to AWS API
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Required for outbound SSM connectivity"
  }

  # Outbound Rule 2: Open all ports strictly to your dynamic worker VMs
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 means all protocols
    cidr_blocks = [var.PEER_VPC_CIDR]
    description = "Allows data mirroring to the dynamic worker VPC"
  }

  tags = {
    Name = "${var.NAME_PREFIX}-firewall"
  }
}

# --- IAM INSTANCE PROFILE FOR NATIVE SSM ACCESS ---
resource "aws_iam_role" "ssm_role" {
  name = "${var.NAME_PREFIX}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "mirror_profile" {
  name = "${var.NAME_PREFIX}-instance-profile"
  role = aws_iam_role.ssm_role.name
}

# --- EC2 INSTANCE (THE MIRROR) ---
resource "aws_instance" "mirror_host" {
  ami                  = data.aws_ami.opensuse160o.id
  instance_type        = "t3.medium"
  subnet_id            = aws_subnet.mirror_subnet.id
  vpc_security_group_ids = [aws_security_group.mirror_sg.id]
  iam_instance_profile = aws_iam_instance_profile.mirror_profile.id
  
  private_ip = var.MIRROR_PRIVATE_IP

  # Size the storage disk space directly
  root_block_device {
    volume_size           = 500
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # User-Data script to download and wire up the SSM agent on openSUSE bootup
  user_data = <<-EOF
              #!/bin/bash
              mkdir /tmp/ssm
              cd /tmp/ssm
              wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
              zypper --non-interactive install amazon-ssm-agent.rpm
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent
              EOF

  tags = {
    Name = "${var.NAME_PREFIX}-host"
  }
}

# --- RELIABLE STANDARD OUTPUTS ---
output "mirror_instance_id" {
  value       = aws_instance.mirror_host.id
  description = "The exact AWS ID of the instance for your SSM push script"
}

output "mirror_private_ip" {
  value       = aws_instance.mirror_host.private_ip
  description = "The target static internal IP address"
}

output "mirror_private_dns" {
  value       = aws_instance.mirror_host.private_dns
  description = "The internal AWS private DNS name"
}