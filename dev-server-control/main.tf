# 개발 EC2의 수동 전원 제어와 제한된 자동 시작 점검 권한을 별도 상태로 관리합니다.
terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket              = "nearby-terraform-state-395931907754"
    key                 = "dev-server-control/terraform.tfstate"
    region              = "ap-northeast-2"
    profile             = "nearby-395931907754"
    encrypt             = true
    use_lockfile        = true
    allowed_account_ids = ["395931907754"]
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = "ap-northeast-2"
  profile             = "nearby-395931907754"
  allowed_account_ids = ["395931907754"]
}

locals {
  # 대상을 입력값으로 받지 않습니다. 인스턴스 교체 시 코드와 권한을 함께 검토합니다.
  instance_id  = "i-06da8518d0a416c98"
  instance_arn = "arn:aws:ec2:ap-northeast-2:395931907754:instance/${local.instance_id}"
  tags = {
    Project     = "nearby"
    Environment = "development"
    ManagedBy   = "terraform"
  }
}

resource "aws_ssm_document" "runtime" {
  name            = "nearby-dev-server-runtime"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Prepare or verify automatic startup on the fixed Nearby development EC2."
    parameters = {
      Mode = {
        type              = "String"
        allowedValues     = ["prepare", "verify"]
        allowedPattern    = "^(prepare|verify)$"
        interpolationType = "ENV_VAR"
      }
    }
    mainSteps = [{
      action       = "aws:runShellScript"
      name         = "developmentRuntime"
      precondition = { StringEquals = ["platformType", "Linux"] }
      inputs = {
        timeoutSeconds = "240"
        runCommand     = ["python3 - <<'NEARBY_RUNTIME_PY'\n${file("${path.module}/runtime.py")}\nNEARBY_RUNTIME_PY"]
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role" "control" {
  name = "nearby-github-actions-dev-server-control"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = "arn:aws:iam::395931907754:oidc-provider/token.actions.githubusercontent.com"
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:TEAM-Nearby/nearby-server:ref:refs/heads/develop"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "control" {
  name = "nearby-dev-server-control"
  role = aws_iam_role.control.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PowerOnlyTheDevelopmentInstance"
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances"]
        Resource = local.instance_arn
      },
      {
        Sid      = "RunOnlyTheDevelopmentRuntimeDocument"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = [local.instance_arn, aws_ssm_document.runtime.arn]
      },
      {
        Sid      = "ReadRuntimeDocumentVersion"
        Effect   = "Allow"
        Action   = "ssm:DescribeDocument"
        Resource = aws_ssm_document.runtime.arn
      },
      {
        Sid    = "ReadControlStatus"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ssm:DescribeInstanceInformation",
          "ssm:GetCommandInvocation",
        ]
        Resource = "*"
      },
    ]
  })
}

output "github_dev_server_control_role_arn" {
  value = aws_iam_role.control.arn
}

output "runtime_document" {
  value = {
    name    = aws_ssm_document.runtime.name
    version = aws_ssm_document.runtime.latest_version
  }
}

output "development_instance_id" {
  value = local.instance_id
}
