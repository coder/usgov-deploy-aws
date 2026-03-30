################################################################################
# StorageClass – gp3 + KMS encryption (EKS-009)
################################################################################

resource "kubernetes_storage_class_v1" "gp3_encrypted" {
  metadata {
    name = "gp3-encrypted"

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    kmsKeyId  = local.kms_key_arn
  }

  # Moved from layer 3 to layer 4 to avoid RBAC propagation
  # race. By the time layer 4 runs, the EKS access entry from
  # layer 3 is fully propagated.
}
