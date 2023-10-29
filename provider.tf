terraform {
  cloud {
    organization = "pium"
    workspaces {
      name = "node-ecs"
    }
  }
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = var.aws_region
}