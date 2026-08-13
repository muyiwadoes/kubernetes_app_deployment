# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.0.1"

  name = var.vpc_name
  cidr = var.vpc_cidr
  azs  = var.availability_zones

  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Project = var.project_name
  }
}

# ECR
resource "aws_ecr_repository" "frontend" {
  name                 = var.frontend_ecr_repository
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
    Service = "frontend"
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = var.backend_ecr_repository
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
    Service = "backend"
  }
}

# SECURITY GROUPS
resource "aws_security_group" "alb" {
  name        = "alb-security-group-${var.project_name}"
  description = "ALB security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "ecs" {
  name        = "ecs-security-group-${var.project_name}"
  description = "ECS frontend security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Frontend traffic from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "rds" {
  name        = "rds-security-group-${var.project_name}"
  description = "RDS security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}

# RDS
resource "aws_db_subnet_group" "rds" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Project = var.project_name
  }
}

resource "aws_db_instance" "postgres" {
  identifier = var.rds_identifier

  engine         = "postgres"
  engine_version = "16"

  instance_class        = var.rds_instance_class
  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"

  storage_encrypted = true

  db_name  = var.rds_db_name
  username = var.rds_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false

  backup_retention_period = 0
  skip_final_snapshot     = true

  tags = {
    Project = var.project_name
  }
}

# ALB (frontend, ECS)
resource "aws_lb" "main" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"

  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.alb.id]

  drop_invalid_header_fields = true

  tags = {
    Project = var.project_name
  }
}

resource "aws_lb_target_group" "frontend" {
  name        = "tg-frontend-execute-techacademy"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id

  health_check {
    path = "/"
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# IAM - ECS EXECUTION ROLE
resource "aws_iam_role" "ecs_execution" {
  name = "ECSExecutionRole-${var.project_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM - ECS TASK ROLE
resource "aws_iam_role" "ecs_task" {
  name = "ECSTaskRole-${var.project_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# ECS Exec requires the TASK role (not the execution role) to be able to
# open the SSM data/control channels. AmazonSSMManagedInstanceCore is the
# usual shortcut here, but it's an EC2-instance-shaped policy with far
# more permissions than a task needs. Per the project brief's
# least-privilege requirement, scope this to exactly the four
# ssmmessages actions ECS Exec actually calls.
resource "aws_iam_role_policy" "ecs_task_exec" {
  name = "ECSExecSSMMessages-${var.project_name}"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}

# IAM - EXTERNAL SECRETS OPERATOR (IRSA)
resource "aws_iam_role" "external_secrets" {
  name = "ExternalSecretsRole-${var.project_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }]
  })

  tags = {
    Project = var.project_name
    Service = "external-secrets"
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "ExternalSecretsSecretsManager-${var.project_name}"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue"
      ]
      Resource = aws_db_instance.postgres.master_user_secret[0].secret_arn
    }]
  })
}

# IAM - AWS LOAD BALANCER CONTROLLER (IRSA)
resource "aws_iam_role" "lb_controller" {
  name = "AWSLoadBalancerControllerRole-${var.project_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })

  tags = {
    Project = var.project_name
    Service = "aws-load-balancer-controller"
  }
}

resource "aws_iam_policy" "lb_controller" {
  name        = "AWSLoadBalancerControllerPolicy-${var.project_name}"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/aws-load-balancer-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# ECS
resource "aws_ecs_cluster" "main" {
  name = var.ecs_cluster_name

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.ecs_frontend_task_family}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = var.ecs_frontend_task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = 256
  memory = 512

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = var.ecs_frontend_container_name
      image     = "${aws_ecr_repository.frontend.repository_url}:${var.ecs_initial_image_tag}"
      essential = true

      portMappings = [{
        containerPort = 80
        hostPort      = 80
        protocol      = "tcp"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.frontend.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "frontend"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "frontend" {
  name            = var.ecs_frontend_service
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  # Enables `aws ecs execute-command` (ECS Exec) against running tasks.
  enable_execute_command = true

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = var.ecs_frontend_container_name
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.http
  ]

  tags = {
    Project = var.project_name
    Service = "frontend"
  }
}

# EKS
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.0"

  name               = var.eks_cluster_name
  kubernetes_version = var.eks_kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access  = true
  endpoint_private_access = false

  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
  }

  security_group_additional_rules = {
    cluster_egress_all = {
      description = "Allow EKS control plane outbound traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  eks_managed_node_groups = {
    workers = {
      name               = "workers"
      instance_types     = [var.eks_node_instance_type]
      kubernetes_version = var.eks_kubernetes_version

      min_size     = var.eks_node_count
      max_size     = var.eks_node_count
      desired_size = var.eks_node_count

      subnet_ids = module.vpc.private_subnets
    }
  }

  tags = {
    Project = var.project_name
  }
}

# External Secrets Operator — installs the operator + CRDs only.
# ClusterSecretStore and ExternalSecret are applied via kubectl in
# backend-ci.yml, NOT here, to avoid Terraform's kubernetes_manifest
# needing the CRD schema to exist at plan time (it doesn't yet, on a
# fresh apply, since the CRD is installed by this same Helm release).

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "external-secrets"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.external_secrets.arn
    }
  ]

  wait    = true
  timeout = 900

  depends_on = [
    module.eks,
    aws_iam_role.external_secrets,
    aws_iam_role_policy.external_secrets
  ]
}


# AWS ALB Controller
resource "helm_release" "aws_load_balancer_controller" {
  name      = "aws-load-balancer-controller"
  namespace = "kube-system"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.lb_controller.arn
    }
  ]

  wait    = true
  timeout = 600

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.lb_controller
  ]
}

# GITHUB ACTIONS OIDC ROLE

# NOTE: this role previously existed outside Terraform state (created by
# an "oidc-bootstrap" step) and I imported it manually into Terraform state with:
# terraform import aws_iam_role.github_actions GitHubActionsDeployRole-execute-techacademy
locals {
  github_owner = split("/", var.github_repo)[0]
  github_name  = split("/", var.github_repo)[1]
}

resource "aws_iam_role" "github_actions" {
  name = "GitHubActionsDeployRole-${var.project_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::390445022869:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              # legacy (mutable) format
              "repo:${var.github_repo}:ref:refs/heads/temp",
              "repo:${var.github_repo}:ref:refs/heads/main",
              "repo:${var.github_repo}:pull_request",
              # immutable format: owner@ownerId/repo@repoId
              "repo:${local.github_owner}@*/${local.github_name}@*:ref:refs/heads/temp",
              "repo:${local.github_owner}@*/${local.github_name}@*:ref:refs/heads/main",
              "repo:${local.github_owner}@*/${local.github_name}@*:pull_request",
            ]
          }
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}
# IAM - GITHUB ACTIONS DEPLOYMENT ROLE POLICY
data "aws_iam_role" "github_actions" {
  name = "GitHubActionsDeployRole-${var.project_name}"
}

resource "aws_iam_role_policy" "github_actions" {
  name = "GitHubActionsDeploy-${var.project_name}"
  role = data.aws_iam_role.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # Terraform infrastructure permissions
      {
        Sid    = "TerraformInfrastructure"
        Effect = "Allow"

        Action = [
          "ec2:*",
          "eks:*",
          "ecr:*",
          "ecs:*",
          "elasticloadbalancing:*",
          "rds:*",
          "logs:*",
          "iam:*",
          "secretsmanager:*",
          "kms:*",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "sts:GetCallerIdentity",
          "sts:AssumeRole",
          "sts:TagSession"
        ]

        Resource = "*"
      },

      # Terraform remote state - bucket metadata and state access
      {
        Sid    = "TerraformStateBucket"
        Effect = "Allow"

        Action = [
          "s3:GetBucketVersioning",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]

        Resource = "arn:aws:s3:::execute-techacademy-tfstate"
      },

      # Terraform remote state - state object access
      {
        Sid    = "TerraformStateObjects"
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]

        Resource = "arn:aws:s3:::execute-techacademy-tfstate/execute-techacademy/terraform.tfstate"
      },

      # Terraform state locking
      {
        Sid    = "TerraformStateLock"
        Effect = "Allow"

        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]

        Resource = "arn:aws:dynamodb:eu-north-1:390445022869:table/execute-techacademy-tflock"
      },

      # Explicit PassRole required by ECS and EKS
      {
        Sid    = "PassRoles"
        Effect = "Allow"

        Action = "iam:PassRole"

        Resource = [
          aws_iam_role.ecs_execution.arn,
          aws_iam_role.ecs_task.arn,
          aws_iam_role.external_secrets.arn,
          aws_iam_role.lb_controller.arn
        ]
      }
    ]
  })
}