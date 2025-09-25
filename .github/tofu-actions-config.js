// Values here are examples

const commonConfig = {
  // Terraform or OpenTofu binary name.
  // If 'tofu' is specified, the 'configure' action will try to read `.opentofu-version` file in the root directory.
  // Possible values: terraform, tofu (default)
  tfBinary: '',
  auth: {
    // Authentication mode.
    // You can activate multiple modes with a string array.
    // Possible values: aws-oidc, gcp-oidc
    mode: '',
    // AWS region (required when auth-mode contains aws-oidc)
    // e.g.: ap-northeast-1
    awsRegion: '',
    // AWS role to assume (required when auth-mode contains aws-oidc)
    // e.g.: arn:aws:iam::<aws-account-id>:role/tofu-plan
    awsPlanRole: '',
    // AWS role to assume (required when auth-mode contains aws-oidc)
    // e.g.: arn:aws:iam::<aws-account-id>:role/tofu-apply
    awsApplyRole: '',
    // GCP project ID (required when auth-mode contains gcp-oidc)
    gcpProject: '',
    // GCP workload identity provider (required when auth-mode contains gcp-oidc)
    // e.g.: projects/<numeric-project-id>/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider
    gcpIdentityProvider: '',
  },
};

export default {
  // Specify directories that contain Terraform code.
  // You can specify different config per directory.
  dirs: {
    // Empty string '' means root directory.
    // You must *not* put `./` at the start or `/` at the end for directory names.
    '': commonConfig,
    'dev': commonConfig,
    'prod': commonConfig,
    // For example, override 'tfBinary' for a specific directory
    'foo/bar': { ...commonConfig, tfBinary: 'terraform' },
  }
};
