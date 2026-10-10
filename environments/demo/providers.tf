terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Bonus: remote state. Uncomment after creating the bucket + lock table.
  # backend "s3" {
  #   bucket         = "YOUR-TFSTATE-BUCKET"
  #   key            = "kstpl-demo/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "kstpl-devops-demo", ManagedBy = "terraform" }
  }
}
