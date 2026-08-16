# oidc-bootstrap/provider.tf
terraform {
  backend "s3" {
    bucket         = "execute-techacademy-tfstate"
    key            = "execute-techacademy/oidc-bootstrap.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "execute-techacademy-tflock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}