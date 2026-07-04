# 생성된 EC2 서버의 주요 접속 정보를 출력합니다.
output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "public_dns" {
  value = aws_instance.app.public_dns
}

output "service_url" {
  value = var.domain_name == "" ? "http://${aws_instance.app.public_dns}" : "https://${var.domain_name}"
}
