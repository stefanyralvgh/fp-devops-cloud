terraform {
  backend "s3" {
    bucket         = "terraform-state-cloud-auto-epam-stef"
    key            = "movie-analyst/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}