# NOTE: This is intentionally insecure Terraform code used only to verify
# that the trivy-scan action detects HIGH/CRITICAL misconfigurations.
# It is not meant to be applied and will be removed before merging.

resource "aws_s3_bucket" "insecure" {
  bucket = "example-insecure-bucket"
}

resource "aws_security_group" "insecure" {
  name = "insecure-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
