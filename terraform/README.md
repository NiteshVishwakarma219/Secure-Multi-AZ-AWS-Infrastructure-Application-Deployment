# Terraform

This directory contains the root Terraform configuration and reusable modules for the Enterprise Cloud Security Platform.

## Safe order

1. Configure the `nitesh-terraform` AWS CLI profile.
2. Copy `terraform.tfvars.example` to `terraform.tfvars`.
3. Run `terraform init`.
4. Run `terraform fmt -recursive`.
5. Run `terraform validate`.
6. Run `terraform plan`.
7. Apply only after reviewing the plan and confirming the AWS cost.

Do not use the AWS root account for Terraform.
