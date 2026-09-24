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

resource "aws_vpc_security_group_ingress_rule" "kubeapi_from_me" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = var.my_ip
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

resource "aws_vpc_security_group_ingress_rule" "node_to_node" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "all_out" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_iam_role" "node" {
    name = "cluster-week-node"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = { Service = "ec2.amazonaws.com" }
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
    role    = aws_iam_role.node.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_iam_instance_profile" "node" {
    name = "cluster-week-node"
    role = aws_iam_role.node.name
}

resource "aws_key_pair" "me" {
    key_name   = "cluster-week"
    public_key = file("${path.module}/cluster-week.pub")
}

resource "aws_instance" "node" {
    count = var.node_count
    ami = data.aws_ssm_parameter.ubuntu.insecure_value
    instance_type = "t4g.small"
    subnet_id = aws_subnet.public.id
    vpc_security_group_ids = [aws_security_group.nodes.id]
    key_name = aws_key_pair.me.key_name
    iam_instance_profile = aws_iam_instance_profile.node.name


root_block_device {
    volume_size = 20
    volume_type = "gp3"
}

metadata_options {
    http_tokens = "required"
}

tags = {
    Name = count.index == 0 ? "k3s-server" : "k3s-agent-${count.index}" }
}

resource "aws_ecr_repository" "web" {
    name = "cluster-week/web"
    image_tag_mutability = "IMMUTABLE"
    force_delete = true
    image_scanning_configuration {
        scan_on_push = true
    }
}

output "node_public_ips" {value = aws_instance.node[*].public_ip}
output "node_private_ips" {value = aws_instance.node[*].private_ip}
output "ecr_url" {value = aws_ecr_repository.web.repository_url}

