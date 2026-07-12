# Spring Boot CloudWatch Logs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 운영 EC2의 Spring Boot 파일 로그를 14일 보관하는 CloudWatch Logs 그룹으로 전송한다.

**Architecture:** Spring Boot에 `LOGGING_FILE_NAME`을 systemd 환경 변수로 주어 `/var/log/nearby/application.log`를 생성하고, Amazon CloudWatch Agent가 해당 파일만 전송한다. Terraform은 로그 그룹, 최소 IAM 정책, 기존 및 교체 EC2에 멱등 설정을 적용하는 SSM Association을 관리한다.

**Tech Stack:** Terraform 1.10 이상, AWS Provider 6.x, Amazon Linux 2023, AWS Systems Manager, Amazon CloudWatch Agent, Spring Boot systemd service.

## Global Constraints

- 로그 그룹 이름은 `/nearby/prod/application`이다.
- 로그 보관 기간은 14일이다.
- 수집 대상은 `/var/log/nearby/application.log` 하나이다.
- 로그 스트림 이름은 EC2 instance id이다.
- 메트릭, 알람, Caddy 로그, 시스템 로그, Grafana 연동은 추가하지 않는다.
- 기존 EC2를 교체하거나 삭제하지 않는다.
- 설정 반영 중 `nearby.service` 재시작은 한 번만 허용한다.
- AWS 자격 증명은 파일에 저장하지 않고 EC2 instance profile을 사용한다.

---

## 파일 구조

- Create `cloudwatch.tf`: CloudWatch 로그 그룹, EC2 최소 IAM 정책, SSM Association을 정의한다.
- Create `cloudwatch_setup.sh.tftpl`: EC2에서 Spring 파일 로그와 CloudWatch Agent를 멱등 구성한다.
- Modify `README.md`: CloudWatch Logs 조회 경로와 운영 확인 명령을 기록한다.
- Modify `checklist.md`: 구현과 검증 진행 상태를 기록한다.
- Modify `context-notes.md`: 실제 AWS 적용 결과와 판단 근거를 기록한다.

### Task 1: CloudWatch 로그 그룹과 최소 IAM 권한

**Files:**
- Create: `cloudwatch.tf`

**Interfaces:**
- Consumes: `var.project_name`, `var.aws_region`, `aws_iam_role.app`.
- Produces: `aws_cloudwatch_log_group.application`, `aws_iam_role_policy.app_cloudwatch_logs`.

- [ ] **Step 1: 현재 구성에 CloudWatch 리소스가 없음을 확인한다.**

Run: `rg -n "aws_cloudwatch_log_group|app_cloudwatch_logs" --glob '*.tf'`

Expected: 일치 항목이 없어 종료 코드 1을 반환한다.

- [ ] **Step 2: 로그 그룹과 최소 IAM 정책을 추가한다.**

Create `cloudwatch.tf` with:

```hcl
# Spring Boot 애플리케이션 로그를 CloudWatch Logs로 전송합니다.
resource "aws_cloudwatch_log_group" "application" {
  name              = "/${var.project_name}/prod/application"
  retention_in_days = 14

  tags = local.tags
}

resource "aws_iam_role_policy" "app_cloudwatch_logs" {
  name = "${var.project_name}-cloudwatch-logs"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeApplicationLogStreams"
        Effect   = "Allow"
        Action   = "logs:DescribeLogStreams"
        Resource = aws_cloudwatch_log_group.application.arn
      },
      {
        Sid    = "WriteApplicationLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.application.arn}:log-stream:*"
      },
    ]
  })
}
```

- [ ] **Step 3: Terraform 정적 검증을 실행한다.**

Run: `terraform fmt -recursive -check && terraform validate`

Expected: formatting 변경 없이 `Success! The configuration is valid.`를 반환한다.

- [ ] **Step 4: 리소스 범위를 점검한다.**

Run: `terraform plan -out=tfplan`

Expected: 로그 그룹 1개와 IAM inline policy 1개가 생성되고 EC2 교체 또는 삭제가 없다. SSM Association은 Task 2 완료 후 함께 나타난다.

### Task 2: Spring 파일 로그와 CloudWatch Agent 자동 구성

**Files:**
- Create: `cloudwatch_setup.sh.tftpl`
- Modify: `cloudwatch.tf`

**Interfaces:**
- Consumes: `aws_instance.app.id`, `aws_cloudwatch_log_group.application.name`, `var.aws_region`.
- Produces: `aws_ssm_association.cloudwatch_logs`; EC2의 `/etc/systemd/system/nearby.service.d/cloudwatch-logs.conf`, `/opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-agent.json`, `/var/log/nearby/application.log`.

- [ ] **Step 1: EC2 설정 스크립트를 추가한다.**

Create `cloudwatch_setup.sh.tftpl` with:

```bash
#!/bin/bash
# Spring Boot 파일 로그와 CloudWatch Logs Agent를 구성합니다.
set -euo pipefail

for attempt in $(seq 1 60); do
  if id nearby >/dev/null 2>&1 && systemctl cat nearby.service >/dev/null 2>&1 && ! pgrep -x dnf >/dev/null; then
    break
  fi

  if [ "$attempt" -eq 60 ]; then
    echo "nearby service prerequisites were not ready" >&2
    exit 1
  fi

  sleep 5
done

dnf install -y amazon-cloudwatch-agent

install -d -o nearby -g nearby -m 0750 /var/log/nearby
install -d -m 0755 /etc/systemd/system/nearby.service.d

cat >/etc/systemd/system/nearby.service.d/cloudwatch-logs.conf <<'DROPIN'
[Service]
Environment="LOGGING_FILE_NAME=/var/log/nearby/application.log"
DROPIN

install -d -m 0755 /opt/aws/amazon-cloudwatch-agent/etc
cat >/opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-agent.json <<'CONFIG'
{
  "agent": {
    "region": "${aws_region}"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nearby/application.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CONFIG

systemctl daemon-reload
systemctl restart nearby.service

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-agent.json

systemctl enable amazon-cloudwatch-agent.service
systemctl is-active --quiet nearby.service
systemctl is-active --quiet amazon-cloudwatch-agent.service
test -f /var/log/nearby/application.log
```

- [ ] **Step 2: SSM Association을 추가한다.**

Append to `cloudwatch.tf`:

```hcl
locals {
  cloudwatch_setup_script = templatefile("${path.module}/cloudwatch_setup.sh.tftpl", {
    aws_region     = var.aws_region
    log_group_name = aws_cloudwatch_log_group.application.name
  })
}

resource "aws_ssm_association" "cloudwatch_logs" {
  name             = "AWS-RunShellScript"
  association_name = "${var.project_name}-cloudwatch-logs"

  parameters = {
    commands = "echo '${base64encode(local.cloudwatch_setup_script)}' | base64 -d | bash"
  }

  targets {
    key    = "InstanceIds"
    values = [aws_instance.app.id]
  }

  depends_on = [aws_iam_role_policy.app_cloudwatch_logs]
}
```

- [ ] **Step 3: Terraform 정적 검증을 실행한다.**

Run: `terraform fmt -recursive && terraform fmt -recursive -check && terraform validate`

Expected: `Success! The configuration is valid.`를 반환한다.

- [ ] **Step 4: Terraform plan을 저장하고 변경 범위를 확인한다.**

Run: `terraform plan -out=tfplan`

Expected: 로그 그룹, IAM inline policy, SSM Association만 생성되고 `Plan: 3 to add, 0 to change, 0 to destroy.`를 반환한다.

Run: `terraform show -json tfplan | jq -r '.resource_changes[] | select(.change.actions != ["no-op"]) | [.address, .change.actions | join(",")] | @tsv'`

Expected:

```text
aws_cloudwatch_log_group.application	create
aws_iam_role_policy.app_cloudwatch_logs	create
aws_ssm_association.cloudwatch_logs	create
```

- [ ] **Step 5: 구현 변경을 커밋한다.**

Run: `git add cloudwatch.tf cloudwatch_setup.sh.tftpl && git commit -m "Spring 로그 CloudWatch 수집 구성 추가"`

Expected: 새 Terraform 구성과 EC2 설정 스크립트만 포함한 커밋이 생성된다.

### Task 3: AWS 적용과 실제 로그 유입 검증

**Files:**
- Modify: `README.md`
- Modify: `checklist.md`
- Modify: `context-notes.md`

**Interfaces:**
- Consumes: Task 2의 `tfplan`과 생성 리소스.
- Produces: AWS CloudWatch Logs의 `/nearby/prod/application` 로그 그룹과 실제 Spring Boot 로그 이벤트.

- [ ] **Step 1: 검토한 plan을 적용한다.**

Run: `terraform apply tfplan`

Expected: `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.`를 반환한다.

- [ ] **Step 2: SSM Association 실행 성공을 확인한다.**

Run: `aws ssm describe-association --association-id "$(terraform state show -no-color aws_ssm_association.cloudwatch_logs | awk -F' = ' '/^    association_id/ {gsub(/"/, "", $2); print $2}')" --region ap-northeast-2`

Expected: association overview 상태가 `Success`이다. 실제 실행에서는 Terraform state에서 association id를 읽어 명령에 넣는다.

- [ ] **Step 3: EC2 서비스와 로컬 로그 파일을 확인한다.**

Run through SSM Run Command:

```bash
systemctl is-active nearby.service
systemctl is-active amazon-cloudwatch-agent.service
test -s /var/log/nearby/application.log
tail -n 5 /var/log/nearby/application.log
```

Expected: 두 서비스가 `active`이고 Spring Boot 로그 파일에 최근 로그가 있다.

- [ ] **Step 4: CloudWatch Logs 유입을 확인한다.**

Run: `aws logs describe-log-streams --log-group-name /nearby/prod/application --region ap-northeast-2 --order-by LastEventTime --descending --limit 1`

Expected: `i-097624a91c126abae` 스트림의 `lastEventTimestamp`가 존재한다.

Run: `aws logs tail /nearby/prod/application --region ap-northeast-2 --since 10m --format short`

Expected: Spring Boot 애플리케이션 로그가 한 줄 이상 출력된다.

- [ ] **Step 5: README에 조회 경로를 기록한다.**

Append a `CloudWatch Logs` section to `README.md` documenting:

```markdown
## CloudWatch Logs

Spring Boot 애플리케이션 로그는 서울 리전 CloudWatch Logs의 `/nearby/prod/application` 로그 그룹에 14일간 보관합니다. 로그 스트림 이름은 EC2 instance id입니다.

AWS 콘솔에서는 `CloudWatch > 로그 > 로그 그룹 > /nearby/prod/application`에서 확인합니다.

```bash
aws logs tail /nearby/prod/application --region ap-northeast-2 --since 10m --follow
```
```

- [ ] **Step 6: 체크리스트와 컨텍스트 노트에 실제 결과를 기록한다.**

Mark the completed CloudWatch checklist items in `checklist.md`. Append the actual Terraform apply count, SSM Association status, service status, log stream name, and final no-change plan result to `context-notes.md` without recording log payloads or secrets.

- [ ] **Step 7: 최종 검증을 실행한다.**

Run: `terraform fmt -recursive -check && terraform validate && terraform plan -detailed-exitcode`

Expected: formatting과 validate가 통과하고 plan은 exit code 0과 `No changes`를 반환한다.

- [ ] **Step 8: 문서와 검증 기록을 커밋한다.**

Run: `git add README.md checklist.md context-notes.md && git commit -m "CloudWatch 로그 운영 결과 기록"`

Expected: 운영 문서와 검증 결과만 포함한 커밋이 생성되고 `git status --short`가 비어 있다.
