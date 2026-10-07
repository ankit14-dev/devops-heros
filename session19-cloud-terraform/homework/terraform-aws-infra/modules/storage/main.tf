data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "assets" {
  # account id makes the (global) name unique
  bucket        = "${var.name}-assets-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# page content that the EC2 instance downloads at boot (private bucket, read via IAM role)
resource "aws_s3_object" "message" {
  bucket       = aws_s3_bucket.assets.id
  key          = "site/message.txt"
  content      = "This line was read from a private S3 bucket by the EC2 instance through its IAM role."
  content_type = "text/plain"
  depends_on   = [aws_s3_bucket_server_side_encryption_configuration.assets]
}
