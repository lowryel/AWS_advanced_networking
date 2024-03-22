terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

variable "aws_region" {
    description = "region to deploy in"
    default = "us-east-1"
}

variable "instance_type" {
    description = "instance type"
    default = "t2.micro"
}

variable "key_pair" {
    description = "ssh key private pair"
    default = "eventskeypair"
}

variable "base_cidr_block" {
    description = "base cidr block"
    default = "20.0.0.0/16"
}

variable "public_subnet_cidr_block" {
    description = "public subnet cidr block"
    default = "20.0.1.0/24"
}

variable "private_subnet_cidr_block" {
    description = "public subnet cidr block"
    default = "20.0.2.0/24"
}

variable "availability_zone" {
    description = "AZ for both subnets"
    default = "us-east-1a"
}

provider "aws" {
    region = var.aws_region
}

resource "aws_vpc" "nat_vpc" {
    cidr_block = var.base_cidr_block
    tags = {
      Name="vpc-base-cidr"
    }
}

resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.nat_vpc.id
    tags = {    
        Name = "gw"
    }
}

resource "aws_subnet" "public_subnet" {
    vpc_id = aws_vpc.nat_vpc.id
    cidr_block = var.public_subnet_cidr_block
    availability_zone = var.availability_zone
    tags = {
      Name="public-subnet"
    }
}

resource "aws_subnet" "private_subnet" {
    vpc_id = aws_vpc.nat_vpc.id
    cidr_block = var.private_subnet_cidr_block
    availability_zone = var.availability_zone
    tags = {
      Name="private-subnet"
    }
}

resource "aws_route_table" "public_rt" {
    vpc_id = aws_vpc.nat_vpc.id
    tags = {
      Name= "route-table-pub"
    }
}

resource "aws_route_table" "private_rt" {
    vpc_id = aws_vpc.nat_vpc.id
    tags = {
      Name= "route-table-priv"
    }
}

resource "aws_route" "public-route" {
    route_table_id = aws_route_table.public_rt.id
    gateway_id = aws_internet_gateway.gw.id
    destination_cidr_block = "0.0.0.0/0"
    depends_on = [ aws_internet_gateway.gw ]
}

resource "aws_route_table_association" "public_rt" {
    route_table_id = aws_route_table.public_rt.id
    subnet_id = aws_subnet.public_subnet.id
    depends_on = [ aws_route_table.public_rt ]
}

resource "aws_route_table_association" "private_rt" {
    route_table_id = aws_route_table.private_rt.id
    subnet_id = aws_subnet.private_subnet.id
    depends_on = [ aws_route_table.private_rt ]
}

resource "aws_eip" "nat_eip" {
    vpc = true
    tags = {
        Name = "nat_eip"
    }
}

resource "aws_nat_gateway" "private_route_nat_gateway" {
    subnet_id = aws_subnet.public_subnet.id
    allocation_id = aws_eip.nat_eip.id
    connectivity_type = "public"
    tags = {
        Name = "private-route-nat_gateway"
    }
}

# associate the nat_gateway with the private route table
resource "aws_route" "private_route" {
    route_table_id = aws_route_table.private_rt.id
    nat_gateway_id = aws_nat_gateway.private_route_nat_gateway.id
    destination_cidr_block = "0.0.0.0/0"
    depends_on = [ aws_nat_gateway.private_route_nat_gateway ]
}

resource "aws_security_group" "pub_sg" {
  name        = "event_sec_grp"
  description = "security group for the events resources"
  vpc_id      = aws_vpc.nat_vpc.id
  tags = {
    Name = "public-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "pub_sg_ing" {
  security_group_id = aws_security_group.pub_sg.id

    cidr_ipv4   = "0.0.0.0/0"
    from_port   = 22
    ip_protocol = "tcp"
    to_port     = 22
}

resource "aws_instance" "public-instance" {
    ami = "ami-080e1f13689e07408"
    instance_type = var.instance_type
    security_groups = [ aws_security_group.pub_sg.id ]
    key_name = "eventskeypair"
    subnet_id = aws_subnet.public_subnet.id
    associate_public_ip_address = true
    tags = {
      Name="public-instance"
    }
    user_data     = <<-EOF
                                        !#/bin/bash
                                        yes | sudo apt update
                                        yes | sudo apt install apache2
                                        yes | sudo systemctl start apache2
                                        yes | sudo systemctl enable apache2
                                        yes | sudo chmod -R 777 /var/www/html
                                        yes | sudo systemctl restart apache2"
                                        EOF
}

resource "aws_instance" "private-instance" {
    ami = "ami-080e1f13689e07408"
    instance_type = var.instance_type
    key_name = "eventskeypair"
    subnet_id = aws_subnet.private_subnet.id
    tags = {
      Name="private-instance"
    }
    user_data     = <<-EOF
                                        !#/bin/bash
                                        yes | sudo apt update
                                        yes | sudo apt install apache2
                                        yes | sudo systemctl start apache2
                                        yes | sudo systemctl enable apache2
                                        yes | sudo chmod -R 777 /var/www/html
                                        yes | sudo systemctl restart apache2"
                                        EOF
}


output "public_instance_ip" {
    value = aws_instance.public-instance.public_ip
    description = "public ip of the instance"
    depends_on = [ aws_instance.public-instance ]
}

output "aws_eip" {
    description = "public ip of the nat gateway"
    value = aws_eip.nat_eip.public_ip
    depends_on = [ aws_eip.nat_eip ]
}

