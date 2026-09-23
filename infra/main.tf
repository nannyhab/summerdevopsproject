terraform {
    required_version = ">= 1.11"
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 6.0"
        }
    }
    #The bucket has to exist before 'terraform init'.
    backend "s3" {
        bucket = "cluster-week-tfstate-958486868913"
        key    = "cluster-week.tfstate"
        region = "us-east-2"
        use_lockfile = true
    }
}

provider "aws" {
    region = "us-east-2"
    default_tags { tags = { Project = "cluster-week" }}
}

variable "my_ip" {
    type = string
    description = "Your public IP as x.x.x.x/32. The pipeline reads it from MY_IP secret."
}

variable "node_count" {
    type = number
    default = 2
}

data "aws_ssm_parameter" "ubuntu" {
    name = "/aws/service/canonical/ubuntu/server/noble/stable/current/arm64/hvm/ebs-gp3/ami-id"
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true
}

resource "aws_internet_gateway" "main" {
    vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
    vpc_id            = aws_vpc.main.id
    cidr_block        = "10.0.1.0/24"
    availability_zone = data.aws_availability_zones.available.names[0]
    map_public_ip_on_launch = true
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main.id
    }
}

resource "aws_route_table_association" "public" {
    subnet_id      = aws_subnet.public.id
    route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "nodes" {
    name = "cluster-week-nodes"
    vpc_id = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_me" {
    security_group_id = aws_security_group.nodes.id
    ip_protocol = "tcp"
    cidr_ipv4      = [var.my_ip]
    from_port         = 22
    to_port           = 22
}

