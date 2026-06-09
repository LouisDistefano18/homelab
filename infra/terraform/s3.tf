resource "aws_s3_bucket" "logs" {
  bucket = "louislab-logs"

  tags = {
    Purpose = "AD and application log archival"
  }
}
