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
    description = "The AWS region to create resources in"
  default = "us-east-1"
}

variable "base_cidr_block" {
  description = "A /16 CIDR range definition, such as 10.1.0.0/16, that the VPC will use"
  default = "10.0.0.0/16"
}

variable "pub_cidr_block" {
  description = "A /24 CIDR range definition for public access"
  default = "10.0.1.0/24"
}

variable "key_pair" {
  description = "key_pair"
  default = "eventskeypair"
}

variable "priv_cidr_block" {
  description = "A /16 CIDR range definition private"
  default = "10.0.2.0/24"
}

variable "pub_sub_availability_zones" {
  description = "A list of availability zones in which to create subnets"
  default = "us-east-1a"
}

variable "priv_sub_availability_zones" {
  description = "A list of availability zones in which to create subnets"
  default = "us-east-1a"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "main" {
  # Referencing the base_cidr_block variable allows the network address
  # to be changed without modifying the configuration.
  cidr_block = var.base_cidr_block
  tags = {
    Name = "event-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "event-igw"
    }
}

variable "instance_type" {
    description = "instance type"
    default = "t2.micro"
}

resource "aws_subnet" "publicsbt" {
  # For each subnet, use one of the specified availability zones.
  availability_zone = var.pub_sub_availability_zones

  # By referencing the aws_vpc.main object, Terraform knows that the subnet
  # must be created only after the VPC is created.
  vpc_id = aws_vpc.main.id

  # Built-in functions and operators can be used for simple transformations of
  # values, such as computing a subnet address. Here we create a /20 prefix for
  # each subnet, using consecutive addresses for each availability zone,
  # such as 10.1.16.0/20 .
  cidr_block = var.pub_cidr_block
  tags = {
    Name = "event-public-subnet"
  }
}

resource "aws_subnet" "privatesbt" {
  # For each subnet, use one of the specified availability zones.
  availability_zone = var.priv_sub_availability_zones

  # By referencing the aws_vpc.main object, Terraform knows that the subnet
  # must be created only after the VPC is created.
  vpc_id = aws_vpc.main.id

  # Built-in functions and operators can be used for simple transformations of
  # values, such as computing a subnet address. Here we create a /20 prefix for
  # each subnet, using consecutive addresses for each availability zone,
  # such as 10.1.16.0/20 .
  cidr_block = var.priv_cidr_block
  tags = {
    Name = "event-private-subnet"
  }
}

resource "aws_route_table" "event_route_tabl_pub" {
    vpc_id = aws_vpc.main.id
    tags = {
      Name = "event_route_tabl_pub"
    }
}

# private subnets don't have internet routes however, they require subnet association
resource "aws_route_table" "event_route_tabl_pri" {
    vpc_id = aws_vpc.main.id
    tags = {
      Name = "event_route_tabl_pri"
    }
}

resource "aws_route" "event_route" {
    route_table_id  = aws_route_table.event_route_tabl_pub.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
    depends_on = [
        aws_route_table.event_route_tabl_pub
    ]
}

resource "aws_route_table_association" "event_route_assoc_pub" {
    route_table_id = aws_route_table.event_route_tabl_pub.id
    subnet_id = aws_subnet.publicsbt.id
    depends_on = [
        aws_route_table.event_route_tabl_pub
    ]
}


resource "aws_route_table_association" "event_route_assoc_priv" {
    route_table_id = aws_route_table.event_route_tabl_pri.id
    subnet_id = aws_subnet.privatesbt.id
}

resource "aws_security_group" "pub_sg" {
  name        = "event_sec_grp"
  description = "security group for the events resources"
  vpc_id      = aws_vpc.main.id
  tags = {
    Name = "event_sg"
  }
}

# resource "aws_vpc_security_group_ingress_rule" "pub_sg_ing" {
#   security_group_id = aws_security_group.pub_sg.id

#   cidr_ipv4   = "10.0.0.0/16"
#   from_port   = 80
#   ip_protocol = "tcp"
#   to_port     = 80
# }

resource "aws_vpc_security_group_ingress_rule" "pub_sg_ing" {
  security_group_id = aws_security_group.pub_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_instance" "event_instnce_pub" {
    ami = "ami-080e1f13689e07408"
    instance_type = var.instance_type
    subnet_id = aws_subnet.publicsbt.id
    key_name = var.key_pair
    security_groups = [ aws_security_group.pub_sg.id ]
    associate_public_ip_address = true
    tags = {
        Name = "event-instance_pub"
    }
}


resource "aws_instance" "event_instnce_pri" {
    ami = "ami-080e1f13689e07408"
    instance_type = var.instance_type
    subnet_id = aws_subnet.privatesbt.id
    key_name = var.key_pair
    tags = {
        Name = "event-instance_pri"
    }
}


output "public_ip" {
    value = aws_instance.event_instnce_pub.public_ip
    description = "public ip of the instance"
    depends_on = [ aws_instance.event_instnce_pub ]
}
