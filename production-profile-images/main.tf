terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket              = "nearby-terraform-state-395931907754"
    key                 = "production-profile-images/terraform.tfstate"
    region              = "ap-northeast-2"
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
  region              = local.region
  allowed_account_ids = [local.account_id]

  default_tags {
    tags = {
      Project     = "nearby"
      Environment = "production"
    }
  }
}

locals {
  account_id = "395931907754"
  region     = "ap-northeast-2"
  origin_id  = "nearby-production-profile-images"
}

resource "aws_s3_bucket" "profile_images" {
  bucket = "nearby-production-profile-images-${local.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "profile_images" {
  bucket                  = aws_s3_bucket.profile_images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "profile_images" {
  bucket = aws_s3_bucket.profile_images.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "profile_images" {
  bucket = aws_s3_bucket.profile_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role_policy" "upload" {
  name = "nearby-production-profile-image-upload"
  role = "nearby-production-ec2"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.profile_images.arn}/profiles/*"
    }]
  })
}

resource "aws_cloudfront_origin_access_control" "profile_images" {
  name                              = local.origin_id
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "images" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "profile_images" {
  enabled = true
  comment = "Nearby production profile images"

  origin {
    domain_name              = aws_s3_bucket.profile_images.bucket_regional_domain_name
    origin_id                = local.origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.profile_images.id
  }

  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.images.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket_policy" "cloudfront_read" {
  bucket = aws_s3_bucket.profile_images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.profile_images.arn}/profiles/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.profile_images.arn
        }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.profile_images]
}

output "runtime_environment" {
  value = {
    NEARBY_STORAGE_S3_BUCKET       = aws_s3_bucket.profile_images.bucket
    NEARBY_STORAGE_S3_REGION       = local.region
    NEARBY_STORAGE_S3_CDN_BASE_URL = "https://${aws_cloudfront_distribution.profile_images.domain_name}"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "deployment_checks" {
  bucket = aws_s3_bucket.profile_images.id

  rule {
    id     = "expire-deployment-check-images"
    status = "Enabled"

    filter {
      prefix = "profiles/.deployment-check/"
    }

    expiration {
      days = 1
    }
  }
}
