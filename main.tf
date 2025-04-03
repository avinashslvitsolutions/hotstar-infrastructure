provider "aws" {
  region = var.aws_region
}

# Create a new VPC
resource "aws_vpc" "hotstar_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "hotstar-vpc"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "hotstar_igw" {
  vpc_id = aws_vpc.hotstar_vpc.id

  tags = {
    Name = "hotstar-igw"
  }
}

# Create public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.hotstar_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "hotstar-public-subnet"
  }
}

# Create private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.hotstar_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "hotstar-private-subnet"
  }
}

# Create route table for public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.hotstar_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hotstar_igw.id
  }

  tags = {
    Name = "hotstar-public-rt"
  }
}

# Associate public route table with public subnet
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Create NAT Gateway in public subnet for private subnet internet access
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "hotstar_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "hotstar-nat"
  }

  depends_on = [aws_internet_gateway.hotstar_igw]
}

# Create route table for private subnet
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.hotstar_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.hotstar_nat.id
  }

  tags = {
    Name = "hotstar-private-rt"
  }
}

# Associate private route table with private subnet
resource "aws_route_table_association" "private_rt_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# Create security group for bastion host in public subnet
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH from my IP"
  vpc_id      = aws_vpc.hotstar_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-sg"
  }
}

# Create security group for private instance
resource "aws_security_group" "private_instance_sg" {
  name        = "private-instance-sg"
  description = "Allow SSH from bastion and internal traffic"
  vpc_id      = aws_vpc.hotstar_vpc.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private-instance-sg"
  }
}

# Create a new key pair
resource "aws_key_pair" "hotstar_key" {
  key_name   = var.key_name
  public_key = tls_private_key.hotstar_rsa.public_key_openssh
}

# Generate RSA key pair
resource "tls_private_key" "hotstar_rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save private key to file
resource "local_file" "private_key" {
  content  = tls_private_key.hotstar_rsa.private_key_pem
  filename = "${var.key_name}.pem"
  file_permission = "0400"
}

# Create bastion host in public subnet
resource "aws_instance" "bastion_host" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  key_name                    = aws_key_pair.hotstar_key.key_name
  associate_public_ip_address = true

  tags = {
    Name = "bastion-host"
  }
}

# Create the hotstar application instance in private subnet
resource "aws_instance" "hotstar_application" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.private_instance_sg.id]
  key_name               = aws_key_pair.hotstar_key.key_name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp2"
  }

  tags = {
    Name = var.instance_name
  }
}

# Find latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}
