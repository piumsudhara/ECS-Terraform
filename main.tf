module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.aws_vpc_name
  cidr = var.aws_vpc_cidr

  azs             = var.aws_vpc_azs
  private_subnets = var.aws_vpc_private_subnets
  public_subnets  = var.aws_vpc_public_subnets

  enable_nat_gateway = var.enable_nat_gateway

  tags = {
    Name        = var.aws_vpc_name
    Terraform   = "true"
    Environment = var.environment
  }
}

resource "aws_security_group" "lb" {
  name   = var.aws_sg_name
  vpc_id = module.vpc.vpc_id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = var.app_port
    protocol    = "tcp"
    to_port     = var.app_port
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }
}
resource "aws_security_group" "ecs_task" {
  name   = "node_ecs_task_sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
    to_port         = var.app_port
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }
}

resource "aws_ecs_cluster" "ecs-cluster" {
  name = var.aws_ecs_cluster_name
}

data "template_file" "node_ecs_app" {
  template = file("./templates/node_ecs_app.json.tpl")
  vars = {
    app_image      = aws_ecr_repository.node_ecs_app.repository_url
    app_port       = var.app_port
    fargate_cpu    = var.fargate_cpu
    fargate_memory = var.fargate_memory
    tag            = var.tag
    name           = var.aws_ecr_repository
  }
}

resource "aws_ecs_task_definition" "node_ecs_app_def" {

  family                   = var.aws_ecs_task_def_fam
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  container_definitions = jsonencode([
    {
      name   = var.aws_ecr_repository
      image  = "600023384173.dkr.ecr.ap-southeast-1.amazonaws.com/node_ecs_app:latest"
      cpu    = var.fargate_cpu
      memory = var.fargate_memory
      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "main" {
  name            = var.aws_ecs_service_name
  cluster         = aws_ecs_cluster.ecs-cluster.id
  task_definition = aws_ecs_task_definition.node_ecs_app_def.arn
  desired_count   = var.app_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_task.id]
    subnets          = module.vpc.private_subnets
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.app.id
    container_port   = var.app_port
    container_name   = var.aws_ecr_repository
  }

  depends_on = [
    aws_ecr_repository.node_ecs_app,
    aws_ecs_task_definition.node_ecs_app_def,
    module.vpc
  ]

}
resource "aws_alb" "main" {
  name            = var.ecs_alb_name
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.lb.id]
}

resource "aws_alb_target_group" "app" {
  name        = "node-ecs-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = var.health_check_path
    unhealthy_threshold = "2"
  }
}

resource "aws_alb_listener" "front_end" {
  load_balancer_arn = aws_alb.main.id
  port              = var.app_port
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.app.id
    type             = "forward"
  }
}

resource "aws_ecr_repository" "node_ecs_app" {
  name                 = var.aws_ecr_repository
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    "env" = var.environment
  }
}

data "aws_iam_policy_document" "ecs_task_execution_role" {
  version = "2012-10-17"
  statement {
    sid     = ""
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = var.ecs_task_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}