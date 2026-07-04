# nearby-terraform
니어바이 인프라 리포지토리입니다. ✈️

## 구성

- Terraform state는 `nearby-terraform-state-340271093505` S3 bucket에 저장합니다.
- Terraform state lock은 S3 backend의 `use_lockfile = true`를 사용합니다.
- 도메인은 `nearby-server.p-e.kr`을 사용합니다.
- 배포 artifact는 `nearby-deploy-artifacts-340271093505` S3 bucket에 저장합니다.
- GitHub Actions OIDC 배포 role은 `nearby-github-actions-deploy`입니다.
- EC2는 `t3.micro`, Amazon Linux 2023, Java 21, Caddy를 사용합니다.
- EC2에는 Elastic IP를 붙이고, 도메인 DNS는 이 IP를 바라보게 합니다.
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

도메인은 기본값으로 `nearby-server.p-e.kr`을 사용합니다. Caddy는 DNS가 Elastic IP를 가리키면 HTTPS 인증서를 자동 발급합니다.

`내도메인.한국`에서는 Terraform output의 `elastic_ip`를 A record로 등록합니다.

```bash
terraform output elastic_ip
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

## GitHub Actions 배포 설정

Repository Variables.

```text
AWS_REGION=ap-northeast-2
AWS_ACCOUNT_ID=340271093505
EC2_INSTANCE_ID=i-097624a91c126abae
APP_SERVICE_NAME=nearby
APP_DIR=/opt/nearby
APP_JAR_PATH=/opt/nearby/app.jar
APP_PORT=8080
DOMAIN_NAME=nearby-server.p-e.kr
SERVICE_URL=https://nearby-server.p-e.kr
DEPLOY_S3_BUCKET=nearby-deploy-artifacts-340271093505
HEALTHCHECK_PATH=/actuator/health
```

Repository Secret.

```text
AWS_ROLE_TO_ASSUME=arn:aws:iam::340271093505:role/nearby-github-actions-deploy
```

기본 OIDC trust 대상은 `TEAM-Nearby/nearby-server`의 `develop` 브랜치입니다. 다른 repo나 브랜치에서 배포하려면 `github_repository`, `github_deploy_branches` 변수를 수정합니다.
