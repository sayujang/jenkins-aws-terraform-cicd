terraform {
  backend "s3" {
    bucket = "s3-backend-sa"
    key    = "tfstate/state1"
    region = "us-west-1"
  }
}