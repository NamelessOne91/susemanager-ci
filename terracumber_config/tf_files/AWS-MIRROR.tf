terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
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

variable "DEPLOY_NAT" {
  type        = bool
  default     = false
  description = "Set to true during sync windows to provision an outbound internet path"
}

variable "MIRROR_VPC_CIDR" {
  type    = string
  default = "172.17.255.0/24"
}

variable "MIRROR_PRIVATE_SUBNET_CIDR" {
  type    = string
  default = "172.17.255.0/28"
}

variable "MIRROR_PUBLIC_SUBNET_CIDR" {
  type    = string
  default = "172.17.255.16/28"
}

variable "MIRROR_PRIVATE_IP" {
  type    = string
  default = "172.17.255.4"
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

variable "SSH_KEY" {
  type        = string
  default     = "testing-suma"
  description = "The exact name of the SSH Key Pair that already exists in your AWS account region"
}

variable "ALLOWED_IPS" {
  type    = list(string)
  default = []
}

provider "aws" {
  region = var.AWS_REGION
}

# --- AMI LOOKUP ---
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

# --- NETWORKING LAYER ---
resource "aws_vpc" "mirror_vpc" {
  cidr_block           = var.MIRROR_VPC_CIDR
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.NAME_PREFIX}-vpc"
  }
}

resource "aws_subnet" "mirror_subnet" {
  vpc_id                  = aws_vpc.mirror_vpc.id
  cidr_block              = var.MIRROR_PRIVATE_SUBNET_CIDR
  availability_zone       = var.AWS_AVAILABILITY_ZONE
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.NAME_PREFIX}-private-subnet"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.mirror_vpc.id
  tags   = { Name = "${var.NAME_PREFIX}-private-rt" }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.mirror_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_security_group" "mirror_sg" {
  name        = "${var.NAME_PREFIX}-secure-sg"
  description = "Allow direct SSH traffic and out-of-band traffic to worker VMs"
  vpc_id      = aws_vpc.mirror_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ALLOWED_IPS
    description = "SSH access from custom pipeline networks or administrators"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.PEER_VPC_CIDR]
    description = "Allows data mirroring to the dynamic worker VPC"
  }

  # (Only functions when DEPLOY_NAT is active, otherwise traffic hits a wall)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allows outbound mirror acquisition over the temporary NAT"
  }

  tags = {
    Name = "${var.NAME_PREFIX}-firewall"
  }
}

# --- CONDITIONAL INTERNET INFRASTRUCTURE (NAT LAYER) ---
resource "aws_internet_gateway" "igw" {
  count  = var.DEPLOY_NAT ? 1 : 0
  vpc_id = aws_vpc.mirror_vpc.id
  tags   = { Name = "${var.NAME_PREFIX}-igw" }
}

resource "aws_subnet" "public_subnet" {
  count             = var.DEPLOY_NAT ? 1 : 0
  vpc_id            = aws_vpc.mirror_vpc.id
  cidr_block        = "172.17.255.0/28" 
  availability_zone = var.AWS_AVAILABILITY_ZONE
  tags              = { Name = "${var.NAME_PREFIX}-public-subnet" }
}

resource "aws_eip" "nat_eip" {
  count  = var.DEPLOY_NAT ? 1 : 0
  domain = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  count         = var.DEPLOY_NAT ? 1 : 0
  allocation_id = aws_eip.nat_eip[0].id
  subnet_id     = aws_subnet.public_subnet[0].id
  tags          = { Name = "${var.NAME_PREFIX}-nat-gw" }
}

resource "aws_route" "private_internet_out" {
  count                  = var.DEPLOY_NAT ? 1 : 0
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[0].id
}

# --- EC2 INSTANCE (THE MIRROR) ---
resource "aws_instance" "mirror_host" {
  ami                    = data.aws_ami.opensuse160o.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.mirror_subnet.id
  vpc_security_group_ids = [aws_security_group.mirror_sg.id]
  private_ip             = var.MIRROR_PRIVATE_IP
  key_name               = var.SSH_KEY

  root_block_device {
    volume_size           = 500
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.NAME_PREFIX}-host"
  }
}

# --- OUTPUTS ---
output "mirror_instance_id" {
  value       = aws_instance.mirror_host.id
  description = "The exact AWS ID of the instance"
}

output "mirror_private_ip" {
  value       = aws_instance.mirror_host.private_ip
  description = "The target static internal IP address"
}

output "mirror_private_dns" {
  value       = aws_instance.mirror_host.private_dns
  description = "The internal AWS private DNS name"
}