terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "ap-south-1"
}

resource "aws_route" "internet_route" {
  route_table_id = aws_vpc.main.default_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.PearlThoughtsIGW.id
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnet1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "subnet1"
  }
}

resource "aws_subnet" "subnet2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "subnet2"
  }
}

resource "aws_subnet" "subnet3" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"

  tags = {
    Name = "subnet3"
  }
}

resource "aws_security_group" "port_3000" {
  name        = "port_3000"
  description = "allow incoming requests from the internet to port 3000"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "HTTP from internet"
    from_port        = 3000
    to_port          = 3000
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "port_3000"
  }
}

resource "aws_internet_gateway" "PearlThoughtsIGW" {
  vpc_id = aws_vpc.main.id
}

resource "aws_ecr_repository" "ecr_repo" {
  name                 = "ecr_repo"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecs_cluster" "PearlThoughtsCluster" {
  name = "PearlThoughtsCluster"

  tags = {
    Name = "PearlThoughtsCluster"
  }
}


resource "aws_ecs_cluster_capacity_providers" "ECSCapacityProvider" {
  cluster_name = aws_ecs_cluster.PearlThoughtsCluster.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_iam_role" "PearlThoughts_ECS_role" {
  name = "PearlThoughts_ECS_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  tags = {
    tag-key = "tag-value"
  }
}

resource "aws_ecs_task_definition" "PearlThoughts_Task" {
  family = "PearlThoughts_Tasks"
  execution_role_arn = aws_iam_role.PearlThoughts_ECS_role.arn
  container_definitions = jsonencode([
    {
      name      = "app"
      image     = aws_ecr_repository.ecr_repo.repository_url
      cpu       = 0
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
	  protocol      = "tcp"
        }
      ]
    }
  ])
  cpu = 256
  memory = 512
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"
}

resource "aws_ecs_service" "ECSService" {
  name            = "service"
  cluster         = aws_ecs_cluster.PearlThoughtsCluster.id
  task_definition = aws_ecs_task_definition.PearlThoughts_Task.arn
  desired_count   = 1

  capacity_provider_strategy  {
    base              = 1
    capacity_provider = "FARGATE"
    weight            = 1
  }

  network_configuration {
    subnets = [
      aws_subnet.subnet1.id,
      aws_subnet.subnet2.id,
      aws_subnet.subnet3.id,
    ]
    security_groups = [
      aws_security_group.port_3000.id
    ]
    assign_public_ip = true
  }

  platform_version = "LATEST"
}