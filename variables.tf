# Nearby 인프라의 입력값을 정의합니다.
variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  description = "AWS CLI profile."
  type        = string
  default     = "nearby-terraform"
}

variable "project_name" {
  description = "Project name used for resource names and tags."
  type        = string
  default     = "nearby"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Spring Boot application port."
  type        = number
  default     = 8080
}

variable "domain_name" {
  description = "Domain name for Caddy automatic HTTPS."
  type        = string
  default     = "nearby-server.p-e.kr"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 20
}

variable "deploy_artifact_bucket_name" {
  description = "S3 bucket for backend deployment artifacts."
  type        = string
  default     = "nearby-deploy-artifacts-340271093505"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy role."
  type        = string
  default     = "TEAM-Nearby/nearby-server"
}

variable "github_deploy_branches" {
  description = "GitHub branches allowed to assume the deploy role."
  type        = list(string)
  default     = ["develop"]
}

variable "runtime_env_parameter_path" {
  description = "SSM Parameter Store path for runtime environment variables."
  type        = string
  default     = "/nearby/prod/env"
}
