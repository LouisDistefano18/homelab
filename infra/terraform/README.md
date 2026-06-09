# Terraform — Homelab AWS Layer

The AWS resources from [Layer 2](../../README.md#layer-2--aws) of the main README, defined as code.

## What's managed

| File | Resources |
|------|-----------|
| `main.tf` | Terraform + AWS provider config; `default_tags` applied to every resource |
| `s3.tf` | `aws_s3_bucket.logs` → `louislab-logs` |
| `ec2.tf` | `aws_instance.homelab` + `aws_security_group.homelab` |
| `iam.tf` | `aws_iam_role.ec2`, 2× `aws_iam_role_policy_attachment`, `aws_iam_instance_profile.ec2` |
| `outputs.tf` | Bucket name, instance ID/IP/DNS, role ARN, SG ID |

Seven resources in total: the EC2 instance, its security group, the log bucket, and the IAM role, profile, and policy attachments that connect them.

## What I left out

The VPC, subnet, and key pair stay on the AWS defaults, and my `louis-admin` login is kept out of the code so a bad `terraform destroy` can't lock me out of my own account. State is local and gitignored, which is all a one-person lab needs.

The Azure/Entra side isn't here either, on purpose. Entra Cloud Sync is configured through the portal and a provisioning agent on DC01, not declared as infrastructure, so it stays out of this stack. AWS is the IaC story; Entra is hybrid identity. Keeping them separate keeps it honest about what Terraform actually owns.

## Daily workflow

```bash
cd infra/terraform

terraform fmt        # auto-format .tf files
terraform validate   # syntax + reference checks (offline)
terraform plan       # diff: code vs. real AWS
terraform apply      # make AWS match code (prompts for confirmation)
terraform output     # show the outputs (bucket name, public IP, etc.)
```

`plan` only reads, so run it whenever. `apply` is the one that changes AWS.

## How the resources got imported

I imported them in three passes, each with a Terraform 1.5+ `import` block:

1. `aws_s3_bucket.logs`
2. `aws_security_group.homelab` and `aws_instance.homelab`
3. `aws_iam_role.ec2`, its two policy attachments, and `aws_iam_instance_profile.ec2`

An `import {}` block runs once and then it's done, so I deleted each one after its import succeeded.

## Lab-grade, not prod-grade

This is a homelab, so a couple of things are looser than they'd be in production. SSH is open to `0.0.0.0/0`; for real use I'd scope it to a known CIDR. The root volume isn't encrypted; encrypting it means rebuilding it from an encrypted snapshot. Both are deliberate trade-offs for a single-operator lab, not oversights.
