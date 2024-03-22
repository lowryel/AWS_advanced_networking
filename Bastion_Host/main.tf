terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
} 

variable "region" {
  default = "us-east-1"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "base_cidr_block" {
  description = "vpc cidr block"
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr_block" {
  description = "public subnet cidr block"
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr_block" {
  description = "public subnet cidr block"
  default = "10.0.2.0/24"
}

variable "availability_zones_pub" {
  description = "availability zones"
  default = "us-east-1a"
}

variable "availability_zones_priv" {
  description = "availability zones"
  default = "us-east-1a"
}

resource "aws_vpc" "basion_host_vpc" {
  cidr_block = var.base_cidr_block
  tags = {
    Name="basion-vpc"
  }
}

resource "aws_internet_gateway" "basion_host_igw" {
  vpc_id = aws_vpc.basion_host_vpc.id
  tags = {
    Name="basion-igw"
  }
}

resource "aws_subnet" "basion_host_public_subnet"  {
    vpc_id = aws_vpc.basion_host_vpc.id
    cidr_block = var.public_subnet_cidr_block
    availability_zone = var.availability_zones_pub
    tags = {
        Name="basion-public-subnet"
    }
}


resource "aws_subnet" "basion_host_private_subnet"  {
    vpc_id = aws_vpc.basion_host_vpc.id
    cidr_block = var.private_subnet_cidr_block
    availability_zone = var.availability_zones_priv
    tags = {
        Name="basion-private-subnet"
    }
}

resource "aws_route_table" "basion_host_public_rt" {
    vpc_id = aws_vpc.basion_host_vpc.id

  tags = {
    Name="basion-public-rt"
  }
}

resource "aws_route_table" "basion_host_private_rt" {
    vpc_id = aws_vpc.basion_host_vpc.id

  tags = {
    Name="basion-private-rt"
  }
}

resource  "aws_route" "subnet-routes" {
    route_table_id = aws_route_table.basion_host_public_rt.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.basion_host_igw.id
}

resource "aws_route_table_association" "basion_host_public_rt_association" {
    subnet_id = aws_subnet.basion_host_public_subnet.id
    route_table_id = aws_route_table.basion_host_public_rt.id
    depends_on = [ aws_route_table.basion_host_public_rt ]
}

resource "aws_route_table_association" "basion_host_private_rt_association" {
    subnet_id = aws_subnet.basion_host_private_subnet.id
    route_table_id = aws_route_table.basion_host_private_rt.id
    depends_on = [ aws_route_table.basion_host_private_rt ]
}

resource "aws_security_group" "basion_host_sg" {
    name        = "basion-sg"
    description = "Allow SSH inbound traffic"
    vpc_id      = aws_vpc.basion_host_vpc.id
}

resource "aws_security_group" "priv_instance" {
    name        = "basion-priv-sg"
    description = "Allow SSH inbound traffic"
    vpc_id      = aws_vpc.basion_host_vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "pub_sg" {
  security_group_id = aws_security_group.basion_host_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

# Establish egress rule for the security grp with (private_subnet_cidr_block) to allow traffic from the bastion host 
resource "aws_vpc_security_group_egress_rule" "basion_host_sg_egress" {
  security_group_id = aws_security_group.basion_host_sg.id
  cidr_ipv4         = var.private_subnet_cidr_block
  ip_protocol       = "tcp"
  to_port           = 22
  from_port         = 22
}

resource "aws_vpc_security_group_ingress_rule" "priv_sg"{
    security_group_id = aws_security_group.priv_instance.id
    cidr_ipv4 = var.public_subnet_cidr_block # attach this to allow traffic to the private subnet
    ip_protocol = "tcp"
    to_port = 22
    from_port = 22
}

resource "aws_instance" "basion_host_instance" {
    ami = "ami-080e1f13689e07408"
    instance_type = var.instance_type
    subnet_id = aws_subnet.basion_host_public_subnet.id
    security_groups = [aws_security_group.basion_host_sg.id]
    associate_public_ip_address = true
    key_name = "eventskeypair"
    tags = {
      Name="pub-basion-instance"
    }
}

resource "aws_instance" "basion_host_priv_instance" {
    ami = "ami-080e1f13689e07408"
    instance_type = var.instance_type
    subnet_id = aws_subnet.basion_host_private_subnet.id
    security_groups = [aws_security_group.priv_instance.id]
    key_name = "eventskeypair"
    tags = {
      Name="basion-instance-priv"
    }
}

