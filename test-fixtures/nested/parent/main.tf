# NOTE: This directory is intentionally "clean" and is configured as a separate
# tofu-actions dir alongside its own subdirectory "child" (also separately configured),
# to verify that scanning "parent" does not recurse into "child" and pick up its findings
# (skip-dirs regression test). Not meant to be applied, will be removed before merging.

resource "random_id" "example" {
  byte_length = 8
}
