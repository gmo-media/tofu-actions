import * as core from '@actions/core'
import * as fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from "node:path";

interface Config {
  dirs: string[];
}

const readConfig = async (): Promise<Config> => {
  const configPath = core.getInput('config')
  const module = await import(path.resolve(process.cwd(), configPath))
  return module.default
}

interface TerraformConfigInspect {
  module_calls: {
    [key: string]: {
      name: string;
      source: string;
    }
  }
}

const inspectDir = (dir: string): TerraformConfigInspect => {
  const bin = core.getInput('terraform-config-inspect')
  const res = spawnSync(bin, ['--json', dir])
  if (res.error) {
    throw res.error
  }
  if (res.status !== 0) {
    throw new Error(`terraform-config-inspect exited with status ${res.status}, stdout: ${res.stdout.toString()}, stderr: ${res.stderr.toString()}`)
  }
  return JSON.parse(res.stdout.toString())
}

const getModuleSources = (dir: string): string[] => {
  const tfConfig = inspectDir(dir)
  let paths = Object.values(tfConfig.module_calls)
    .map(m => m.source)
    // Resolve relative path to the project
    .map(moduleSrc => path.relative(process.cwd(), path.resolve(dir, moduleSrc)))
  paths = [...new Set(paths)]
  if (paths.length > 0) {
    console.log(`[terraform-config-inspect] ${dir} is dependent on ${paths.join(', ')}`)
  }
  return paths
}

const calculateRunDirs = (config: Config): string[] => {
  // Read the tj-actions/changed-files output file
  const outputFile = '.github/outputs/all_changed_and_modified_files.txt';
  const fileContent = fs.readFileSync(outputFile, 'utf8').trim();
  const changedFiles = fileContent ? fileContent.split(' ') : [];
  console.log(`${changedFiles.length} files were changed, calculating which CI to run...`)

  // Determine which CI to run
  const hasPaths = (matchers: RegExp[]) => {
    for (const matcher of matchers) {
      if (changedFiles.some(file => matcher.test(file))) {
        return true;
      }
    }
    return false;
  }
  return config.dirs
    .filter(dir => hasPaths([
      new RegExp(`^${dir}/[^/]+$`),
      ...getModuleSources(dir)
        .map(src => new RegExp(`${src}/[^/]+$`)),
    ]))
}

const run = async () => {
  const config = await readConfig()

  const forceAllChanged = core.getInput('force-all-changed') === 'true'
  if (forceAllChanged) {
    console.log(`[prepare] force-all-changed flag is on. Short-circuiting and outputting all paths as 'changed'...`)
  }
  const runDirs = forceAllChanged ? config.dirs : calculateRunDirs(config)

  console.log(`Running on directories: ${runDirs}`)
  const strategy = runDirs.map(dir => ({ dir }))
  core.setOutput('strategy', JSON.stringify(strategy))
  core.setOutput('dirs', runDirs.join(' '))
  core.setOutput('count', runDirs.length)
}

run().catch(err => {
  console.error(err)
  process.exit(1)
});
