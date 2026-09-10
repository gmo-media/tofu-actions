# NOTE: This directory is intentionally named "raw" to regression-test the
# fix for the /tmp/trivy-raw.txt filename collision. Not meant to be applied,
# will be removed before merging.

resource "aws_s3_bucket" "insecure" {
  bucket = "example-insecure-bucket-raw"
}
