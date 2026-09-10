# NOTE: Intentionally insecure, and separately configured as its own tofu-actions dir
# nested under "parent". Not meant to be applied, will be removed before merging.

resource "aws_s3_bucket" "insecure" {
  bucket = "example-insecure-bucket-child"
}
