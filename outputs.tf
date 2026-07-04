# 생성된 EC2 서버의 주요 접속 정보를 출력합니다.
output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_eip.app.public_ip
}

output "public_dns" {
  value = aws_eip.app.public_dns
}

output "elastic_ip" {
  value = aws_eip.app.public_ip
}

output "service_url" {
  value = var.domain_name == "" ? "http://${aws_eip.app.public_ip}" : "https://${var.domain_name}"
}

output "deploy_artifact_bucket_name" {
  value = aws_s3_bucket.deploy_artifacts.bucket
}

output "github_actions_deploy_role_arn" {
  value = aws_iam_role.github_actions_deploy.arn
}

output "runtime_env_parameter_path" {
  value = var.runtime_env_parameter_path
}
