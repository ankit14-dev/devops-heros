# ---------------------------------------------------------------------------
# S3 bucket + best-practice settings
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "demo" {
  bucket        = var.bucket_name
  force_destroy = true # allow `terraform destroy` even if objects exist (demo only!)

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
  }
}

# Block every form of public access
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning (protects against accidental overwrite/delete)
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Default encryption at rest (SSE-S3 / AES-256)
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload a small object so the bucket is not empty
resource "aws_s3_object" "readme" {
  bucket       = aws_s3_bucket.demo.id
  key          = "hello/README.txt"
  content      = "Hello from Terraform! Uploaded by ${var.owner} for DevOps Heros Session 18.\n"
  content_type = "text/plain"

  # the encryption config must exist before the first object is written
  depends_on = [aws_s3_bucket_server_side_encryption_configuration.demo]
}
