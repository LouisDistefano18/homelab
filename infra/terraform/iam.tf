# IAM role assumed by the homelab EC2 instance.
resource "aws_iam_role" "ec2" {
  name        = "homelab-ec2-role"
  description = "Read-only access to EC2 and S3 for homelab dashboard"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# AWS-managed read-only policies: the dashboard lists EC2 instances and reads
# S3 bucket stats, nothing more.
resource "aws_iam_role_policy_attachment" "ec2_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "s3_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Instance profile the EC2 instance references (same name as the role).
resource "aws_iam_instance_profile" "ec2" {
  name = "homelab-ec2-role"
  role = aws_iam_role.ec2.name
}

