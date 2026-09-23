terraform {
  backend "s3" {
    bucket         = "enterprise-cloud-security-platform-terraform-state-920235988251"
    key            = "enterprise-cloud-security-platform/terraform.tfstate"
    region         = "ap-south-1"
    profile        = "nitesh-terraform"
    encrypt        = true
    dynamodb_table = "enterprise-cloud-security-platform-terraform-locks"
  }
}