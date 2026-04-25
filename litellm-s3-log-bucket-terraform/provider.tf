provider "aws" {
  default_tags {
    tags = {
      "stack-id" = var.name
      "project"  = "llmgateway"
    }
  }
}

terraform {
  backend "s3" {}
}