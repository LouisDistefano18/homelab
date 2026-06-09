output "s3_logs_bucket" {
  description = "Name of the log archival S3 bucket"
  value       = aws_s3_bucket.logs.bucket
}

output "ec2_instance_id" {
  description = "ID of the homelab EC2 instance"
  value       = aws_instance.homelab.id
}

output "ec2_public_ip" {
  description = "Public IP of the homelab EC2 instance"
  value       = aws_instance.homelab.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS name of the homelab EC2 instance"
  value       = aws_instance.homelab.public_dns
}

output "iam_role_arn" {
  description = "ARN of the IAM role assumed by the EC2 instance"
  value       = aws_iam_role.ec2.arn
}

output "security_group_id" {
  description = "ID of the security group attached to the EC2 instance"
  value       = aws_security_group.homelab.id
}
