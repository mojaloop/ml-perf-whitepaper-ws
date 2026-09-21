# IAM role for the AWS EBS CSI driver. This cluster is self-managed MicroK8s
# on plain EC2 (not EKS), so there's no IRSA/OIDC federation available — the
# CSI driver's pods get AWS credentials the same way any process on the
# instance would: via the instance's attached IAM role over IMDS. Attached
# unconditionally to every switch-cluster instance (not gated per-scenario)
# since the permissions are scoped to EBS volume management only, and it
# keeps this file scenario-agnostic like the rest of instances.tf.
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${local.project_config.name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_instance_profile" "ebs_csi_driver" {
  name = "${local.project_config.name}-ebs-csi-driver"
  role = aws_iam_role.ebs_csi_driver.name
}
