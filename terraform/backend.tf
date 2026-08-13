terraform {
  backend "s3" {
    bucket         = "execute-techacademy-tfstate"
    key            = "execute-techacademy/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "execute-techacademy-tflock"
    encrypt        = true
  }
}