# 개발 서버 수동 제어

개발 EC2 한 대를 GitHub Actions에서 조회·준비·시작·중지하기 위한 별도 Terraform 스택입니다.
기존 인프라의 root 스택이나 `production-ec2` 스택을 적용하지 않습니다.

## 대상과 경계

| 항목 | 고정값 |
| --- | --- |
| AWS 계정 | `395931907754` |
| 리전 | `ap-northeast-2` |
| 개발 EC2 | `i-06da8518d0a416c98`, Name `nearby-app` |
| 개발 HTTPS 상태 확인 | `https://nearby-server.p-e.kr/readyz` |
| GitHub | `TEAM-Nearby/nearby-server`, `develop` |
| 상태 파일 | `s3://nearby-terraform-state-395931907754/dev-server-control/terraform.tfstate` |
| 제어 역할 | `nearby-github-actions-dev-server-control` |
| SSM 문서 | `nearby-dev-server-runtime` |

대상 EC2 ID와 계정은 사용자 입력이나 기존 배포 변수를 사용하지 않습니다. 인스턴스가 교체되면
이 스택과 backend의 `scripts/operations/dev_server.py`를 함께 변경하고 검증해야 합니다.

추가되는 리소스는 IAM 역할 1개, 인라인 정책 1개, SSM Command 문서 1개입니다.
EC2, EBS, EIP, 보안 그룹, DB, Valkey, S3와 기존 역할은 이 스택에서 관리하지 않습니다.
운영 EC2 `i-0e345dd1422312f87`를 제어하는 권한도 부여하지 않습니다.
자동 종료 예약, Lambda, API Gateway, 웹 대시보드는 이번 범위에 없습니다.

## 인증과 권한

이미 존재하는 GitHub OIDC provider를 ARN으로 참조합니다. 장기 AWS Access Key를 추가하지 않습니다.
역할 신뢰 조건은 audience `sts.amazonaws.com`, subject
`repo:TEAM-Nearby/nearby-server:ref:refs/heads/develop`입니다.
새 workflow에는 GitHub `environment`를 지정하지 않습니다. 지정하면 OIDC subject가 달라지므로
현재 역할과 맞지 않습니다.

- EC2 `StartInstances`와 `StopInstances`는 개발 인스턴스 ARN 하나에만 허용합니다.
- SSM `SendCommand`는 개발 인스턴스와 이 스택의 문서에만 허용합니다.
- `AWS-RunShellScript`를 통한 임의 명령, DB 접근, Parameter Store 비밀 읽기,
  EC2 종료·삭제와 공유 리소스 변경 권한은 부여하지 않습니다.
- 리소스 단위 제한을 지원하지 않는 상태 조회 API는 `Resource = "*"`로 별도 분리합니다.
- SSM 문서도 IMDSv2로 실제 계정·리전·인스턴스를 확인한 후 시스템 명령을 실행합니다.

GitHub 저장소의 쓰기 권한이 있는 사용자만 수동 workflow를 실행할 수 있습니다.
develop의 workflow를 수정할 수 있는 사용자를 신뢰하는 구조이므로 기존 저장소 권한·리뷰 규칙을 유지합니다.

## 자동 시작 설정

`runtime.py`는 SSM에서 실행됩니다. 사용자가 전달할 수 있는 값은 `prepare`와 `verify`뿐입니다.
SSM 환경 변수 보간을 지원하는 Agent 3.3.2746.0 이상이 필요합니다. Mode 환경 변수가 없으면
명령을 추측해서 실행하지 않고 실패합니다.

`prepare`는 다음 조건을 모두 확인합니다.

1. 개발 EC2이며 root로 실행 중입니다.
2. 영구 디스크의 `/opt/nearby/app.jar`와 `/opt/nearby/app.env`가 존재합니다.
3. `nearby.service`가 해당 JAR와 환경 파일을 참조합니다.
4. 앱, Caddy, CloudWatch Agent가 실행 중이고 로컬 `/readyz`가 JSON `status=UP`입니다.
5. 현재 배포 스크립트와 같은 `/opt/nearby/.deploy.lock`을 획득할 수 있습니다.

조건을 통과하면 `systemctl enable nearby.service caddy.service amazon-cloudwatch-agent.service`만 실행합니다.
`--now`, start, restart, JAR 배포, 환경 변수 수정, DB migration은 실행하지 않습니다.
설정 전후 앱 PID가 같은지 확인해 의도하지 않은 재시작을 성공으로 보고하지 않습니다.

`verify`는 서비스를 시작하거나 수정하지 않습니다. enabled 상태, 서비스 활성 상태와 앱 준비 상태를
확인합니다. 앱 준비 대기는 150초로 제한합니다. 따라서 `start`에서 앱 자동 기동이 실패했을 때
검증 명령이 앱을 몰래 시작해서 문제를 감추지 않습니다.

## 적용 순서

저장소 root에서 다음 명령을 실행합니다. 기본 root 스택의 계정·backend는 사용하지 않습니다.

```bash
terraform -chdir=dev-server-control init
terraform -chdir=dev-server-control plan -out=dev-control.tfplan
terraform -chdir=dev-server-control show dev-control.tfplan
```

첫 계획은 위 3개 리소스의 생성만 포함해야 합니다. 기존 리소스의 변경·삭제가 있거나 대상 계정이
다르면 적용하지 않고 먼저 backend와 계획을 확인합니다.

```bash
terraform -chdir=dev-server-control apply dev-control.tfplan
terraform -chdir=dev-server-control output
```

Terraform 적용은 권한과 명령 문서만 설치합니다. SSM Association을 만들지 않으므로
적용만으로 EC2 설정이 바뀌거나 서버가 시작·중지되지는 않습니다.

Backend 저장소의 `Dev server control` workflow가 기본 브랜치 `develop`에 반영된 뒤
GitHub Actions에서 다음 순서로 수동 실행합니다.

1. `status`로 대상과 현재 상태를 확인합니다.
2. 현재 앱이 정상 실행 중인 상태에서 `prepare`를 실행합니다.
3. 개발 서버 이용자가 없는 시간에 `stop`을 실행합니다. 사유 2~100자와 `stop-dev` 확인 문구가 필요합니다.
4. `start`를 실행하고 EC2 상태 검사, SSM, 앱 내부 상태, 외부 HTTPS `/readyz`까지 성공하는지 확인합니다.
5. 운영 서버는 계속 정상인지 별도로 확인합니다. 운영 상태 확인에 운영 리소스 변경은 필요하지 않습니다.

## 동시 실행과 실패 처리

Backend workflow는 기존 개발 배포·직접 실행 DB migration과 같은
`nearby-operations-dev`, `cancel-in-progress: false`를 사용합니다. 운영의
`nearby-operations-prod`는 사용하지 않습니다. 기존 배포 workflow 파일은 변경하지 않습니다.

GitHub concurrency는 실행 중 1개와 대기 중 1개만 유지하며, 새 실행이 기존 대기 실행을 대체할 수 있습니다.
엄격한 FIFO 큐가 아닙니다. 버튼을 반복해서 누르지 말고 실제 실행 상태를 확인합니다.
이 제어는 GitHub 경로끼리의 충돌을 막습니다. 콘솔의 직접 EC2 조작은 해당 잠금을 따르지 않습니다.
EC2 내부 잠금은 SSM 검증 중 다른 배포 명령과 충돌하는 것도 차단합니다.

- 이미 켜진 서버의 `start`는 재시작하지 않고 검증합니다.
- 이미 꺼진 서버의 `stop`은 중복 API 요청 없이 성공합니다.
- 자동 시작을 검증할 수 없으면 `stop`을 거부합니다. 먼저 `prepare` 또는 정상 배포로 복구합니다.
- 시작 후 앱 검증이 실패해도 진단할 수 있도록 EC2를 켜 둡니다. 실패가 비용 발생 중단을 뜻하지 않습니다.
- 시간 초과나 사용자의 workflow 취소는 이미 접수된 AWS 작업을 되돌리지 않습니다.
  SSM command ID와 실제 EC2 상태를 확인한 뒤 재시도합니다.
- 원격 SSM 명령은 240초 제한이며 별도 취소 권한은 부여하지 않습니다.
- 개발 서버가 꺼진 동안 기존 개발 배포를 실행하려면 먼저 `start`가 성공해야 합니다.
  배포 시 자동으로 EC2를 켜는 기능은 이번 변경에 포함하지 않습니다.

작업자, 사유, commit, run ID, 전후 상태, 진행 단계, SSM command ID와 검증 결과를
GitHub Summary 및 JSON artifact에 남깁니다. 비밀 환경 값과 앱 로그는 수집하지 않습니다.
AWS 인증 실패 시 artifact에는 `preflight_passed`까지만 남을 수 있으며 이것은 서버 제어 성공을 뜻하지 않습니다.

## 검증

```bash
terraform -chdir=dev-server-control fmt -check
terraform -chdir=dev-server-control init -backend=false -lockfile=readonly
terraform -chdir=dev-server-control validate
terraform -chdir=dev-server-control test
python3 -m unittest discover -s dev-server-control/tests -v
```

Terraform test는 mock provider만 사용합니다. 실제 인프라를 생성하지 않습니다.
Python 테스트는 잘못된 대상·미배포 앱·비영구 환경 파일·배포 중 상태를 차단하고,
prepare가 재시작 없이 자동 시작만 설정하는지 검증합니다.

로컬 테스트, 실제 계정 plan, GitHub OIDC 인증, prepare 실실행, stop/start 복구 검증은 서로 다른 증거입니다.
실제 운영 검증 기록은 수행한 단계만 남깁니다.

구현 시 확인한 결과입니다.

- `terraform fmt -check`, `validate`, mock test 1개 실행(권한·문서 경계 assertion 6개)이 통과했습니다.
- runtime Python 테스트 10개와 backend 배포·백업·서버 제어 테스트 43개가 통과했습니다.
- backend의 모든 workflow에 대해 actionlint와 ShellCheck가 통과했습니다.
- 인증된 계정에서 만든 실제 plan은 `3 to add, 0 to change, 0 to destroy`입니다. 아직 apply하지 않았습니다.
- 개발·운영 EC2 모두 `running`이며 개발 SSM Agent는 `3.3.5226.0`, `Online`입니다.
- 개발 EC2 읽기 전용 점검 `69bac555-b756-478d-8e94-dd72f702f30b`가 성공했습니다.
  앱은 `active`지만 자동 시작은 `disabled`입니다. Caddy와 CloudWatch Agent는 `active/enabled`입니다.
  JAR와 환경 파일이 존재하며 로컬 `/readyz`는 정상입니다.
- 자동 시작 변경, 실제 stop/start, GitHub OIDC 제어 실행은 아직 검증하지 않았습니다.

## 되돌리기

긴급 중단 시 먼저 workflow 사용을 중지하고 역할의 신뢰 정책 또는 정책을 회수합니다.
이 스택을 제거해도 EC2나 공유 리소스는 삭제되지 않습니다. 다만 `prepare`가 설정한 systemd enabled
상태는 유지됩니다. 자동 시작 설정까지 되돌려야 한다면 변경 전 각 서비스의 enabled 상태를 확인해
개발 EC2에만 수동으로 반영합니다. 앱을 끄는 `disable --now`를 무조건 실행하지 않습니다.
