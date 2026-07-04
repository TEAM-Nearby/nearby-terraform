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
