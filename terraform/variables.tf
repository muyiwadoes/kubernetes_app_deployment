# GENERAL
variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "github_repo" {
  description = "GitHub owner/repository format without .git"
  type        = string
}

# NETWORK
variable "vpc_name" {
  description = "VPC name"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "availability_zones" {
  description = "Availability Zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  type        = list(string)
}

# ECR
variable "frontend_ecr_repository" {
  description = "Frontend ECR repository"
  type        = string
}

variable "backend_ecr_repository" {
  description = "Backend ECR repository"
  type        = string
}

# ALB
variable "alb_name" {
  description = "Application Load Balancer name"
  type        = string
}

# ECS
variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_frontend_service" {
  description = "Frontend ECS service name"
  type        = string
}

variable "ecs_frontend_task_family" {
  description = "Frontend ECS task definition family"
  type        = string
}

variable "ecs_frontend_container_name" {
  description = "Frontend ECS container name"
  type        = string
}

variable "ecs_initial_image_tag" {
  description = "Initial ECR image tag used by Terraform before GitHub Actions deploys a commit SHA image"
  type        = string
}

# RDS
variable "rds_identifier" {
  description = "RDS instance identifier"
  type        = string
}

variable "rds_db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "execute_techacademy"
}

variable "rds_username" {
  description = "PostgreSQL master username"
  type        = string
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
}

# EKS
variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "eks_kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
}

variable "eks_node_instance_type" {
  description = "EKS managed node instance type"
  type        = string
}

variable "eks_node_count" {
  description = "Number of EKS nodes"
  type        = number
}