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
