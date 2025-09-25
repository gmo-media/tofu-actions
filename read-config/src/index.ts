import * as core from '@actions/core'
import path from 'node:path'

interface AuthConfig {
  mode: string | string[]
  awsRegion?: string
  awsPlanRole?: string
  awsApplyRole?: string
  gcpProject?: string
  gcpIdentityProvider?: string
}

interface DirectoryConfig {
  tfBinary?: string
  auth?: AuthConfig
}

interface Config {
  dirs: { [dir: string]: DirectoryConfig }
}

const readConfig = async (configPath: string): Promise<Config> => {
  const module = await import(path.resolve(process.cwd(), configPath))
  return module.default
}

const mergeDefaults = (c: DirectoryConfig): void => {
  c.tfBinary ||= 'tofu'
}

const validateConfig = (c: DirectoryConfig): string | undefined => {
  if (c.tfBinary !== 'tofu' && c.tfBinary !== 'terraform') {
    return 'Invalid tfBinary value. Must be either "tofu" or "terraform".'
  }

  const authMode = Array.isArray(c.auth?.mode) ? c.auth?.mode.join(',') : (c.auth?.mode ?? '')
  const awsAuth = authMode.includes('aws-oidc')
  const gcpAuth = authMode.includes('gcp-oidc')

  if (awsAuth) {
    if (!c.auth?.awsRegion) {
      return 'AWS region is required when auth-mode contains aws-oidc.'
    }
    if (!c.auth?.awsPlanRole) {
      return 'AWS plan role is required when auth-mode contains aws-oidc.'
    }
    if (!c.auth?.awsApplyRole) {
      return 'AWS apply role is required when auth-mode contains aws-oidc.'
    }
  }

  if (gcpAuth) {
    if (!c.auth?.gcpProject) {
      return 'GCP project is required when auth-mode contains gcp-oidc.'
    }
    if (!c.auth?.gcpIdentityProvider) {
      return 'GCP workload identity provider is required when auth-mode contains gcp-oidc.'
    }
  }

  return
}

const run = async () => {
  const configPath = core.getInput('config', {required: true})
  const dir = core.getInput('dir', {required: true})

  const config = await readConfig(configPath)
  const c = config.dirs[dir]
  if (!c) {
    core.setFailed(`Directory ${dir} not found in config at ${configPath}. Perhaps you missed configuration, or invalid dir name was passed?`)
    return
  }

  mergeDefaults(c)
  const error = validateConfig(c)
  if (error) {
    core.setFailed(`Config validation failed: ${error}`)
    return
  }

  core.setOutput('tf-binary', c.tfBinary)
  const authMode = Array.isArray(c.auth?.mode) ? c.auth?.mode.join(',') : (c.auth?.mode ?? '')
  core.setOutput('auth-mode', authMode)
  core.setOutput('auth-aws-region', c.auth?.awsRegion ?? '')
  core.setOutput('auth-aws-plan-role', c.auth?.awsPlanRole ?? '')
  core.setOutput('auth-aws-apply-role', c.auth?.awsApplyRole ?? '')
  core.setOutput('auth-gcp-project', c.auth?.gcpProject ?? '')
  core.setOutput('auth-gcp-identity-provider', c.auth?.gcpIdentityProvider ?? '')
}

run().catch(err => {
  console.error(err)
  process.exit(1)
});
