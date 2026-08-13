aws_region   = "eu-north-1"
project_name = "execute-techacademy"
github_repo  = "muyiwadoes/kubernetes_app_deployment"

vpc_name             = "vpc-execute-techacademy"
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["eu-north-1a", "eu-north-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

frontend_ecr_repository = "frontend-execute-techacademy"
backend_ecr_repository  = "backend-execute-techacademy"

alb_name = "alb-execute-techacademy"

ecs_cluster_name            = "ecs-cluster-execute-techacademy"
ecs_frontend_service        = "frontend-ecs-service-execute-techacademy"
ecs_frontend_task_family    = "frontend-task-family-execute-techacademy"
ecs_frontend_container_name = "frontend-container-execute-techacademy"
ecs_initial_image_tag       = "initial"

rds_identifier     = "rds-execute-techacademy"
rds_db_name        = "execute_techacademy"
rds_username       = "etaadmin"
rds_instance_class = "db.t3.micro"

eks_cluster_name       = "eks-execute-techacademy"
eks_kubernetes_version = "1.36"
eks_node_instance_type = "t3.small"
eks_node_count         = 2