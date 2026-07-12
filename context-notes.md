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

## 2026-07-09

- SSM command `29c1d442-0ecb-4e1b-b46b-1316c33ea7f1`은 EC2에서 `aws s3 cp` 중 `ExecutionTimedOut`, `ResponseCode 137`로 종료됐다.
- EC2 `i-097624a91c126abae`는 `t3.micro`이고 현재 `Mem available 46MiB`, `Swap 0B`였다.
- 디스크는 20GiB 중 2.4GiB 사용이라 배포 실패 원인은 디스크가 아니라 EC2 메모리 부족으로 본다.
- Java 서비스와 SSM agent를 같이 돌리기 위해 instance type 기본값을 `t3.small`로 올린다.
- `data.aws_ami.al2023`가 최신 AMI를 다시 읽으면 인스턴스 타입 변경과 무관하게 EC2 교체가 발생하므로, 운영 EC2에서는 AMI drift를 무시한다.
- `terraform apply tfplan` 결과 `aws_instance.app`만 in-place 변경됐고 리소스 교체는 없었다.
- 적용 후 EC2는 `t3.small`, instance id는 `i-097624a91c126abae`, Elastic IP는 `54.116.237.58`로 유지됐다.
- 적용 후 EC2 내부 메모리는 `Mem available 1.1GiB`, `Swap 0B`이고 `nearby.service`는 active 상태다.
- 외부 health check `https://nearby-server.p-e.kr/actuator/health`와 `/actuator/health/db` 모두 `UP`을 반환했다.

## 2026-07-10

- 백엔드 `develop`은 Redis를 Google Places 캐시뿐 아니라 리프레시 토큰과 휴대폰 인증 코드 저장소로 사용한다.
- Redis 장애가 인증 흐름에 영향을 주므로 운영 Valkey는 `cache.t4g.micro` 2노드 Multi-AZ와 자동 장애 조치로 구성한다.
- 모든 Redis key는 TTL 기반이며 오래된 인증 상태 복원 위험이 있어 자동 스냅샷은 사용하지 않는다.
- Redis는 default VPC에 배치하고 `6379/tcp`는 앱 보안 그룹에서만 허용한다.
- 저장 데이터 암호화와 TLS 전송 암호화를 활성화하고 애플리케이션은 SSL 연결을 사용한다.
- 별도 AUTH 토큰은 만들지 않고 VPC, 보안 그룹, TLS로 접근을 제한해 secret을 Terraform state에 추가하지 않는다.
- Redis endpoint는 코드나 GitHub 설정에 복사하지 않고 Terraform이 `/nearby/prod/env/SPRING_DATA_REDIS_HOST`에 자동 저장한다.
- 백엔드 환경 변수는 `SPRING_DATA_REDIS_HOST`, `SPRING_DATA_REDIS_PORT`, `SPRING_DATA_REDIS_SSL_ENABLED`로 통일한다.
- `nearby-prod-debug` profile은 대상 계정 `340271093505`의 `terraform` IAM 사용자이며 이번 실행의 backend와 provider override로 사용한다.
- 적용 전 AWS 조회에서 `nearby-redis` replication group과 Redis용 SSM 파라미터 세 개는 존재하지 않았다.
- Redis 추가 plan은 신규 리소스 6개 생성, 기존 리소스 14개 no-op, 변경 0개, 삭제 0개로 확인됐다.
- 최초 apply에서 보안 그룹과 subnet group은 생성됐지만 ElastiCache API가 일시적인 `408 InvalidCredentialsException`을 반환했다.
- STS 자격 증명, AWS 실제 리소스, Terraform state를 대조해 불일치가 없음을 확인하고 남은 4개 생성 plan을 다시 적용했다.
- 재적용 후 `nearby-redis`는 `available`이며 `cache.t4g.micro` primary와 replica가 `ap-northeast-2a`, `ap-northeast-2b`에 배치됐다.
- 자동 장애 조치, Multi-AZ, 저장 데이터 암호화, TLS required가 모두 활성화됐고 snapshot retention은 0이다.
- Redis 보안 그룹 `sg-0aae689112067384a`는 앱 보안 그룹 `sg-0e791800e36799f09`의 `6379/tcp`만 허용하고 egress는 없다.
- SSM Redis host는 ElastiCache primary endpoint와 일치했고 port는 `6379`, SSL enabled는 `true`로 확인됐다.
- 백엔드 PR `#122`를 `develop`에 병합하고 수동 배포 run `29074502173`을 실행했다.
- 배포 run은 테스트, bootJar, S3 업로드, SSM 배포, 외부 health check까지 성공했다.
- 외부 `/actuator/health`의 `redis` component와 `/actuator/health/redis`가 모두 `UP`을 반환했다.
- 적용과 배포 검증 후 `terraform plan -detailed-exitcode`는 exit code 0과 `No changes`를 반환했다.

## 2026-07-12

- 현재 우선순위는 메트릭, 알람, 트레이싱이 아니라 Spring Boot 운영 로그 조회이다.
- Grafana Cloud는 이번 범위에서 제외하고 AWS CloudWatch Logs를 사용한다.
- 수집 대상은 Caddy나 시스템 로그를 제외한 Spring Boot 애플리케이션 로그만으로 제한한다.
- CloudWatch Logs 보관 기간은 14일로 한다.
- Spring Boot는 `/var/log/nearby/application.log`에 로그를 기록하고 통합 CloudWatch Agent가 해당 파일만 수집한다.
- 로그 그룹 이름은 `/nearby/prod/application`, 로그 스트림 이름은 EC2 instance id로 한다.
- 기존 EC2를 교체하지 않고 SSM Association으로 멱등 적용하며 설정 반영 시 `nearby.service`를 한 번 재시작한다.
- EC2 역할에는 로그 스트림 생성과 이벤트 전송에 필요한 최소 CloudWatch Logs 권한만 부여한다.
- 최초 Terraform plan은 로그 그룹, IAM inline policy, SSM Association 3개 생성과 기존 리소스 변경 및 삭제 0개로 확인됐다.
- 최초 apply 결과 리소스 3개가 생성됐고 EC2 instance id와 Elastic IP는 유지됐다.
- 최초 Association은 Agent가 시작된 직후 postcondition을 한 번만 검사해 실패 상태가 됐지만, 실제 Agent 설정 검증은 성공했고 두 서비스와 로그 파일은 정상 상태였다.
- 서비스와 로그 파일 상태를 최대 60초 동안 조건 기반으로 기다리도록 수정했고 Association 재실행 `db6600f5-2e13-4367-a896-8dc58b8462f6`은 `Success`를 반환했다.
- `/nearby/prod/application` 로그 그룹의 보관 기간은 14일이고 `i-097624a91c126abae` 로그 스트림에서 실제 이벤트를 확인했다.
- EC2에서 `nearby.service`와 `amazon-cloudwatch-agent.service`는 모두 active이고 `/var/log/nearby/application.log`에 로그가 기록된다.
- 설정 적용 후 외부 `https://nearby-server.p-e.kr/actuator/health`는 DB와 Redis를 포함해 `UP`을 반환했다.
- 최종 `terraform plan -var aws_profile=nearby-prod-debug -detailed-exitcode`는 exit code 0과 `No changes`를 반환했다.
