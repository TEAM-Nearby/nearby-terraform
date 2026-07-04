# nearby-terraform
니어바이 인프라 리포지토리입니다. ✈️

## 구성

- Terraform state는 `nearby-terraform-state-340271093505` S3 bucket에 저장합니다.
- Terraform state lock은 S3 backend의 `use_lockfile = true`를 사용합니다.
- EC2는 `t3.micro`, Amazon Linux 2023, Java 21, Caddy를 사용합니다.
- Caddy는 `80`과 `443`을 받고 Spring Boot `8080` 포트로 reverse proxy합니다.
- SSH ingress는 열지 않습니다. 운영 접근은 SSM을 사용합니다.

## 처음 적용

1. State bucket을 먼저 만듭니다.

```bash
terraform -chdir=bootstrap init
terraform -chdir=bootstrap plan
terraform -chdir=bootstrap apply
```

2. 루트 스택을 S3 backend로 초기화합니다.

```bash
terraform init
```

3. EC2 생성 계획을 확인하고 적용합니다.

```bash
terraform plan
terraform apply
```

도메인을 연결할 때는 `domain_name`을 넘깁니다. Caddy는 DNS가 EC2 public IP를 가리키면 HTTPS 인증서를 자동 발급합니다.

```bash
terraform plan -var='domain_name=api.example.com'
terraform apply -var='domain_name=api.example.com'
```

backend 설정을 바꾼 뒤에는 루트에서 다시 초기화합니다.

```bash
terraform init -reconfigure
```

Spring Boot jar는 EC2의 `/opt/nearby/app.jar`에 배치하면 됩니다. 서비스 이름은 `nearby`입니다.

```bash
aws ssm start-session --target <instance-id> --profile nearby-terraform
sudo systemctl status nearby
sudo systemctl restart nearby
```

인프라를 정리할 때는 루트 스택을 먼저 제거합니다. state bucket은 `prevent_destroy`가 걸려 있어 실수로 같이 삭제되지 않습니다.

```bash
terraform destroy
```
