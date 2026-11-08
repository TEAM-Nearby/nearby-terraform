# 수동 제어 권한이 개발 EC2와 제한된 SSM 문서에만 부여되는지 검증합니다.
mock_provider "aws" {
  mock_resource "aws_ssm_document" {
    defaults = {
      arn = "arn:aws:ssm:ap-northeast-2:395931907754:document/nearby-dev-server-runtime"
    }
  }
}

run "development_control_boundaries" {
  command = apply

  assert {
    condition = tomap(jsondecode(aws_iam_role.control.assume_role_policy).Statement[0].Condition.StringEquals) == tomap({
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
      "token.actions.githubusercontent.com:sub" = "repo:TEAM-Nearby/nearby-server:ref:refs/heads/develop"
    })
    error_message = "Only the Nearby backend develop branch may assume the control role."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.control.policy).Statement :
      statement.Resource == "arn:aws:ec2:ap-northeast-2:395931907754:instance/i-06da8518d0a416c98"
      if statement.Sid == "PowerOnlyTheDevelopmentInstance"
    ])
    error_message = "Power operations must never target production or a wildcard instance."
  }

  assert {
    condition = toset(jsondecode(aws_iam_role_policy.control.policy).Statement[0].Action) == toset([
      "ec2:StartInstances", "ec2:StopInstances"
    ])
    error_message = "Control must not grant terminate, recreate, or shared-resource write access."
  }

  assert {
    condition = toset(jsondecode(aws_iam_role_policy.control.policy).Statement[1].Resource) == toset([
      "arn:aws:ec2:ap-northeast-2:395931907754:instance/i-06da8518d0a416c98",
      "arn:aws:ssm:ap-northeast-2:395931907754:document/nearby-dev-server-runtime"
    ])
    error_message = "SendCommand must allow only the fixed development instance and custom document."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.control.policy).Statement) == 4 &&
      alltrue([for action in jsondecode(aws_iam_role_policy.control.policy).Statement[3].Action :
        startswith(action, "ec2:Describe") || startswith(action, "ssm:Describe") || action == "ssm:GetCommandInvocation"
      ])
    )
    error_message = "Wildcard resource permissions must remain read-only."
  }

  assert {
    condition = (
      toset(jsondecode(aws_ssm_document.runtime.content).parameters.Mode.allowedValues) == toset(["prepare", "verify"]) &&
      jsondecode(aws_ssm_document.runtime.content).parameters.Mode.interpolationType == "ENV_VAR" &&
      length(keys(jsondecode(aws_ssm_document.runtime.content).parameters)) == 1
    )
    error_message = "The SSM document must not accept arbitrary shell commands or instance IDs."
  }
}
