# NOTE: This directory intentionally contains many duplicated insecure resources
# to exercise the >50k-character "too long" fallback path for the Trivy PR comment.
# Not meant to be applied, will be removed before merging.

resource "aws_s3_bucket" "insecure_01" {
  bucket = "example-insecure-bucket-01"
}

resource "aws_s3_bucket" "insecure_02" {
  bucket = "example-insecure-bucket-02"
}

resource "aws_s3_bucket" "insecure_03" {
  bucket = "example-insecure-bucket-03"
}

resource "aws_s3_bucket" "insecure_04" {
  bucket = "example-insecure-bucket-04"
}

resource "aws_s3_bucket" "insecure_05" {
  bucket = "example-insecure-bucket-05"
}

resource "aws_s3_bucket" "insecure_06" {
  bucket = "example-insecure-bucket-06"
}

resource "aws_s3_bucket" "insecure_07" {
  bucket = "example-insecure-bucket-07"
}

resource "aws_s3_bucket" "insecure_08" {
  bucket = "example-insecure-bucket-08"
}

resource "aws_s3_bucket" "insecure_09" {
  bucket = "example-insecure-bucket-09"
}

resource "aws_s3_bucket" "insecure_10" {
  bucket = "example-insecure-bucket-10"
}

resource "aws_s3_bucket" "insecure_11" {
  bucket = "example-insecure-bucket-11"
}

resource "aws_s3_bucket" "insecure_12" {
  bucket = "example-insecure-bucket-12"
}

resource "aws_s3_bucket" "insecure_13" {
  bucket = "example-insecure-bucket-13"
}

resource "aws_s3_bucket" "insecure_14" {
  bucket = "example-insecure-bucket-14"
}

resource "aws_s3_bucket" "insecure_15" {
  bucket = "example-insecure-bucket-15"
}
