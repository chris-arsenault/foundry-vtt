# ── Assets bucket ───────────────────────────────────────────
# Foundry's native S3 media integration serves asset URLs directly to player
# browsers, which requires public GetObject. This is a deliberate exception to
# the platform's CloudFront-OAC-only posture: the bucket holds only game media
# (maps, tokens, audio), never player data. Worlds and config live on EFS.

resource "aws_s3_bucket" "assets" {
  bucket = local.assets_bucket
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "assets_public_read" {
  statement {
    sid     = "PublicReadGetObject"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = data.aws_iam_policy_document.assets_public_read.json

  depends_on = [aws_s3_bucket_public_access_block.assets]
}

# Foundry's in-app S3 file browser uploads from the browser session.
resource "aws_s3_bucket_cors_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  cors_rule {
    allowed_origins = ["https://${local.hostname}"]
    allowed_methods = ["GET", "PUT", "POST", "HEAD", "DELETE"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ── Releases bucket ─────────────────────────────────────────
# Foundry downloads are license-gated, so the release zip is staged here once
# by hand (see README) and pulled by the instance at first boot.

resource "aws_s3_bucket" "releases" {
  bucket = local.releases_bucket
}

resource "aws_s3_bucket_public_access_block" "releases" {
  bucket = aws_s3_bucket.releases.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
