# 운영 Redis 호환 Valkey와 애플리케이션 연결 정보를 정의합니다.
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis"
  description = "Allow Redis from the application"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Redis from application"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-redis"
  })
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis"
  subnet_ids = sort(data.aws_subnets.default.ids)

  tags = local.tags
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.project_name}-redis"
  description          = "Nearby application Redis-compatible cache"

  engine       = "valkey"
  node_type    = "cache.t4g.micro"
  port         = 6379
  cluster_mode = "disabled"

  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  snapshot_retention_limit   = 0

  tags = local.tags
}

resource "aws_ssm_parameter" "redis_host" {
  name  = "${var.runtime_env_parameter_path}/SPRING_DATA_REDIS_HOST"
  type  = "String"
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

resource "aws_ssm_parameter" "redis_port" {
  name  = "${var.runtime_env_parameter_path}/SPRING_DATA_REDIS_PORT"
  type  = "String"
  value = tostring(aws_elasticache_replication_group.redis.port)
}

resource "aws_ssm_parameter" "redis_ssl" {
  name  = "${var.runtime_env_parameter_path}/SPRING_DATA_REDIS_SSL_ENABLED"
  type  = "String"
  value = tostring(aws_elasticache_replication_group.redis.transit_encryption_enabled)
}
