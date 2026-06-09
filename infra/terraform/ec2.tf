# Security group for homelab-server-01.
#
# Name and description are the auto-generated values from the EC2 launch
# wizard. AWS does not allow renaming a security group in place, so changing
# them requires creating a replacement SG, swapping it onto the instance, and
# deleting the old one. Out of scope for the initial import.
resource "aws_security_group" "homelab" {
  name        = "launch-wizard-1"
  description = "launch-wizard-1 created 2026-05-27T17:37:14.593Z"
  vpc_id      = "vpc-0bfc915a552cd849c"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Flask dashboard"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Purpose = "homelab-server-01 access control"
  }
}

# The cloud server hosting the Flask monitoring dashboard.
resource "aws_instance" "homelab" {
  ami                    = "ami-00e801948462f718a" # Amazon Linux 2023
  instance_type          = "t3.micro"
  key_name               = "homelab-key"
  subnet_id              = "subnet-07cc2f2112a10671d"
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  vpc_security_group_ids = [aws_security_group.homelab.id]

  tags = {
    Name    = "homelab-server-01"
    Purpose = "Flask monitoring dashboard host"
  }
}

