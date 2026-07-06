# Context Notes

## 2026-07-05

- AWS profile은 `nearby-terraform`이고 STS 확인 계정은 `340271093505`이다.
- S3 backend bucket 이름은 account id를 포함해 `nearby-terraform-state-340271093505`로 고정한다.
- Terraform S3 backend lock은 DynamoDB가 아니라 `use_lockfile = true`를 사용한다.
- SSH는 열지 않고 EC2 instance profile에 SSM 권한을 붙여 운영 접근 여지를 남긴다.
- 도메인이 아직 정해지지 않았으므로 Caddy site label은 `domain_name`이 비어 있으면 `:80`, 값이 있으면 해당 도메인을 사용한다.
- 실제 AWS 비용이 생기는 `terraform apply`는 이번 자동 작업에서 실행하지 않는다.
- EC2는 default VPC와 첫 번째 default subnet을 사용한다. 별도 VPC는 필요해질 때 추가한다.
- Spring jar는 Terraform에 포함하지 않고 `/opt/nearby/app.jar`를 실행하는 systemd service file만 준비한다.
- `terraform -chdir=bootstrap plan`은 S3 bucket 관련 4개 리소스 생성으로 통과했다.
- root `terraform plan`은 backend bucket을 실제 생성하고 `terraform init`을 끝낸 뒤 실행해야 한다.
- `terraform fmt -recursive -check`, `terraform -chdir=bootstrap validate`, `terraform validate`가 통과했다.
- 최초 단일 커밋은 파일을 보존한 채 풀고, ignore, backend bootstrap, EC2 stack, usage docs로 나눠 다시 커밋한다.
- EC2에 Elastic IP를 붙이고, `public_ip`와 `elastic_ip` output은 Elastic IP를 가리키게 한다.
- 2026-07-05 root apply 결과 Elastic IP는 `54.116.237.58`, instance id는 `i-097624a91c126abae`이다.
- AWS `describe-addresses`에서 `54.116.237.58`이 `i-097624a91c126abae`에 연결된 것을 확인했다.
- Elastic IP 적용 후 `terraform plan`은 `No changes`로 통과했다.
- `nearby-server.p-e.kr`은 Caddy HTTPS 도메인으로 사용한다.
- 2026-07-05 DNS 조회 시 `nearby-server.p-e.kr` A record는 아직 응답하지 않았다.
- Amazon Linux 2023에서는 `dnf copr enable @caddy/caddy`가 실패하므로 `epel-9-x86_64` repo를 명시한다.
- 이후 DNS 조회에서 `nearby-server.p-e.kr`은 `54.116.237.58`로 확인됐다.
- SSM으로 현재 EC2에 Caddy v2.11.4를 설치하고 `/etc/caddy/Caddyfile`을 `nearby-server.p-e.kr -> 127.0.0.1:8080`으로 반영했다.
- `curl -I http://nearby-server.p-e.kr`은 Caddy `308` HTTPS redirect를 반환했다.
- `curl -I https://nearby-server.p-e.kr`은 유효한 TLS 연결 후 `502`를 반환했다. 이는 Spring app이 아직 `127.0.0.1:8080`에서 실행 중이지 않기 때문이다.
- 배포 artifact bucket은 `nearby-deploy-artifacts-340271093505`로 만든다.
- GitHub OIDC deploy role은 `nearby-github-actions-deploy`로 만들고 기본 trust 대상은 `TEAM-Nearby/nearby-server`의 `develop` 브랜치로 제한한다.
- EC2 role `nearby-ec2`에는 배포 artifact bucket의 `s3:GetObject`만 추가한다.
- 2026-07-05 apply 결과 배포 bucket, GitHub OIDC provider, deploy role, deploy role policy, EC2 read policy가 생성됐다.
- deploy role ARN은 `arn:aws:iam::340271093505:role/nearby-github-actions-deploy`이다.
- 배포 권한 적용 후 `terraform plan`은 `No changes`로 통과했다.
- `gh repo view TEAM-Nearby/nearby-backend` 확인 결과 실제 repo는 `TEAM-Nearby/nearby-server`, 기본 브랜치는 `develop`으로 확인되어 OIDC trust 기본값을 수정했다.
- OIDC trust 수정 apply 후 대상은 `repo:TEAM-Nearby/nearby-server:ref:refs/heads/develop`이다.
- 런타임 환경 변수 path는 `/nearby/prod/env`로 둔다.
- secret 값은 Terraform state에 남기지 않고 AWS SSM Parameter Store에 직접 저장한다.
- Supabase datasource URL, username, password는 placeholder만 있어서 실제 값을 받기 전까지 저장하지 않는다.
- EC2에서 `GetParametersByPath`를 호출하려면 `/nearby/prod/env/*`뿐 아니라 `/nearby/prod/env` base path ARN도 IAM resource에 포함해야 한다.
- SSM Parameter Store에는 실제 값이 있는 6개 항목을 저장했다. secret 계열은 SecureString, profile/pool size/from number는 String으로 저장했다.
- EC2 role `nearby-ec2`로 `/nearby/prod/env`를 `--with-decryption` 조회했을 때 count `6`이 반환됐다.
- Supabase datasource 실제 값과 `NEARBY_JWT_SECRET`을 받은 뒤 SSM Parameter Store 대상은 10개가 됐다.
- `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`, `NEARBY_JWT_SECRET`은 secret 취급해 SecureString으로 저장한다.
- 전체 10개 SSM env를 저장한 뒤 EC2 role `nearby-ec2`로 `/nearby/prod/env`를 `--with-decryption` 조회했을 때 count `10`이 반환됐다.

## 2026-07-06

- 로컬 AWS CLI profile에는 `nearby-terraform`이 없고, 사용 가능한 `dev-kc`와 `codex-ec2-readonly`는 배포 계정 `340271093505`가 아니다.
- `TEAM-Nearby/nearby-server`의 배포 경로는 `.github/workflows/ci.yml`의 `workflow_dispatch`이다.
- 최근 수동 배포 run `28750446102`는 테스트, jar 빌드, S3 업로드까지 성공했고 `Deploy through SSM`에서 command id `379a4a03-3955-4dd7-acc8-c0b4905ef30a` 대기 중 타임아웃됐다.
- 2026-07-06 수동 배포 run `28766306916`을 `develop` 브랜치에서 시작했다.
- 수동 배포 run `28766306916`은 SSM health check에서 실패했다. 앱이 `127.0.0.1:8080`을 열지 못했다.
- `nearby-server` workflow에 실패 시 `systemctl status nearby`와 `journalctl -u nearby`를 출력하는 커밋 `382fc5f`를 추가했다.
- 수동 배포 run `28766867059`의 EC2 journal에서 root cause는 `Could not resolve placeholder 'nearby.storage.s3.access-key'`로 확인됐다.
- `nearby-server`에서 S3 storage access key와 secret key를 앱 시작 필수값에서 호출 시점 검증으로 낮추는 커밋 `9ebf674`를 추가했다.
- push CI run `28767113892`는 성공했다.
- 수동 배포 run `28767193476`은 테스트, jar 빌드, S3 업로드, SSM 배포, 외부 health check까지 성공했다.
- `curl https://nearby-server.p-e.kr/actuator/health`는 HTTP 200과 `{"status":"UP"}`를 반환했다. DB component도 `UP`이다.
