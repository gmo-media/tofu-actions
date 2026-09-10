# NOTE: This is intentionally "clean" Terraform code (no known misconfigurations)
# used only to verify the trivy-scan / plan-comment "Pass" path with multiple directories.
# It is not meant to be applied and will be removed before merging.

resource "random_id" "example" {
  byte_length = 8
}
