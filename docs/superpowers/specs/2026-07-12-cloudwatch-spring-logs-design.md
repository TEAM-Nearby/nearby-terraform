# Spring Boot CloudWatch Logs 수집 설계

## 목적

운영 EC2에서 실행 중인 Spring Boot 애플리케이션 로그를 AWS CloudWatch Logs에서 조회할 수 있게 한다. 현재 필요한 것은 로그 검색이며 메트릭, 알람, 트레이싱, Caddy 로그는 범위에 포함하지 않는다.

## 결정 사항

- 수집 대상은 `nearby.service`가 실행하는 Spring Boot 애플리케이션 로그이다.
- 로컬 로그 파일은 `/var/log/nearby/application.log`를 사용한다.
- CloudWatch 로그 그룹은 `/nearby/prod/application`으로 만든다.
- 로그 스트림은 EC2 instance id별로 분리한다.
- CloudWatch Logs의 보관 기간은 14일이다.
- EC2를 교체하지 않고 기존 SSM 연결을 이용해 설정한다.
- 설정 반영 과정에서 Spring Boot 서비스를 한 번 재시작한다.

## 검토한 방식

### 전용 로그 파일과 통합 CloudWatch Agent

Spring Boot가 전용 파일에 로그를 기록하고 CloudWatch Agent가 해당 파일을 전송한다. AWS가 EC2 로그 수집에 권장하는 통합 Agent를 사용하며, 수집 경로와 장애 지점이 명확하다. 이 방식을 채택한다.

### systemd journal과 Fluent Bit

현재 콘솔 로그 구조를 유지할 수 있지만 CloudWatch Agent 외의 수집기를 별도로 운영해야 한다. Spring Boot 로그 하나만 수집하려는 현재 범위에는 구성 복잡도가 크므로 채택하지 않는다.

### 애플리케이션의 CloudWatch 직접 전송

애플리케이션 의존성과 런타임 설정이 늘고, 외부 로그 전송 문제를 애플리케이션 프로세스가 직접 부담한다. 인프라 관심사를 애플리케이션과 분리하기 위해 채택하지 않는다.

## 구성 요소

### CloudWatch 로그 그룹

Terraform이 `/nearby/prod/application` 로그 그룹과 14일 보관 정책을 관리한다. Agent가 로그 그룹을 임의로 만들거나 보관 기간을 변경하지 않는다.

### EC2 IAM 권한

기존 `nearby-ec2` 역할에 대상 로그 그룹의 스트림 생성, 스트림 조회, 로그 이벤트 전송에 필요한 최소 권한만 추가한다. 메트릭, X-Ray, 임의 로그 그룹 생성 권한은 부여하지 않는다.

### Spring Boot 파일 로그

`nearby.service`의 systemd drop-in에 `LOGGING_FILE_NAME=/var/log/nearby/application.log` 환경 변수를 설정한다. Spring Boot의 기본 로깅 설정이 콘솔 출력과 함께 파일 로그를 기록하고 회전하도록 한다. 로그 디렉터리는 `nearby` 사용자가 쓸 수 있게 생성한다.

### CloudWatch Agent

Amazon Linux 2023 패키지 저장소의 `amazon-cloudwatch-agent`를 설치한다. Agent 설정에는 metrics 섹션을 넣지 않고 `/var/log/nearby/application.log` 파일 수집만 정의한다. 로그 스트림 이름에는 EC2 instance id를 사용한다.

### SSM Association

기존 EC2와 이후 교체될 EC2 모두에 적용할 수 있도록 Terraform이 `AWS-RunShellScript` 기반 SSM Association을 관리한다. 스크립트는 다음 작업을 멱등하게 수행한다.

1. Spring Boot 서비스와 패키지 관리자가 준비될 때까지 기다린다.
2. 로그 디렉터리를 만든다.
3. systemd drop-in을 배치한다.
4. CloudWatch Agent를 설치하고 로그 전용 설정을 배치한다.
5. systemd 설정을 다시 읽고 `nearby.service`를 재시작한다.
6. CloudWatch Agent 설정을 검증하며 서비스를 시작하고 부팅 시 자동 시작하게 한다.

## 데이터 흐름

```text
nearby.service
  -> Spring Boot file appender
  -> /var/log/nearby/application.log
  -> Amazon CloudWatch Agent
  -> /nearby/prod/application
  -> instance id 로그 스트림
```

## 실패 처리

- Agent 설정이 유효하지 않으면 Agent 시작 단계가 실패하고 SSM Association 상태에서 오류를 확인할 수 있어야 한다.
- CloudWatch 전송 장애가 발생해도 Spring Boot 프로세스는 로컬 파일 기록을 계속한다.
- Spring Boot 재시작이 실패하면 SSM 명령이 실패하도록 하며 `systemctl status nearby`와 journal을 통해 원인을 확인한다.
- 반복 적용 시 파일과 설정을 같은 내용으로 갱신하여 중복 Agent나 중복 설정을 만들지 않는다.

## 보안과 비용

- AWS 자격 증명은 파일에 저장하지 않고 EC2 instance profile을 사용한다.
- IAM 권한은 `/nearby/prod/application` 로그 그룹으로 제한한다.
- 14일 보관 정책으로 오래된 로그를 자동 삭제한다.
- 커스텀 메트릭과 상세 모니터링을 활성화하지 않는다.

## 검증 기준

- `terraform fmt -recursive -check`가 통과한다.
- `terraform validate`가 통과한다.
- Terraform plan에서 EC2 교체나 삭제가 없어야 한다.
- SSM Association 적용 결과가 성공이어야 한다.
- EC2에서 `nearby.service`와 `amazon-cloudwatch-agent`가 active 상태여야 한다.
- `/var/log/nearby/application.log`에 새 로그가 기록되어야 한다.
- `/nearby/prod/application`의 해당 instance id 스트림에서 새 Spring Boot 로그를 조회할 수 있어야 한다.
- 적용 완료 후 Terraform plan이 `No changes`를 반환해야 한다.

## 제외 범위

- Caddy 접근 및 오류 로그.
- EC2 시스템 로그.
- CPU, 메모리, 디스크와 JVM 메트릭.
- CloudWatch Alarm과 Dashboard.
- Grafana Cloud, trace, OTLP 연동.
