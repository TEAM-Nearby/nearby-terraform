# Nearby Terraform Infrastructure Plan

## Goal

Spring Boot backend를 올릴 EC2 단일 서버 인프라를 Terraform으로 만든다.

## Assumptions

- AWS profile은 `nearby-terraform`을 사용한다.
- AWS region은 `ap-northeast-2`를 사용한다.
- Terraform state는 S3 backend에 저장하고 S3 lock file을 사용한다.
- EC2 instance type은 `t3.micro`를 사용한다.
- Spring Boot app은 `8080` 포트에서 실행된다.
- SSH ingress는 열지 않는다.
- Caddy가 `80`과 `443`을 받아 `127.0.0.1:8080`으로 reverse proxy한다.
- 도메인은 나중에 연결할 수 있으므로 `domain_name` 변수로 받는다.
- DB, Redis, ALB, Auto Scaling은 이번 범위에서 제외한다.

## Files

- `bootstrap/main.tf`는 S3 backend bucket을 만든다.
- `main.tf`는 EC2, security group, IAM instance profile, Caddy user-data를 만든다.
- `variables.tf`는 변경 가능한 입력값을 정의한다.
- `outputs.tf`는 EC2 접속 확인에 필요한 값을 출력한다.
- `user_data.sh.tftpl`은 EC2 부팅 시 Java 21, Caddy, systemd service file을 설치한다.
- `.gitignore`는 Terraform 로컬 상태와 민감한 변수 파일을 제외한다.

## Verification

- `terraform fmt -recursive`.
- `terraform -chdir=bootstrap init`.
- `terraform -chdir=bootstrap validate`.
- `terraform init -backend=false`.
- `terraform validate`.
- `terraform plan`은 backend bucket 생성 전에는 root에서 바로 실행하지 않는다.

## Apply Order

1. `terraform -chdir=bootstrap apply`.
2. `terraform init`.
3. `terraform plan`.
4. `terraform apply`.
