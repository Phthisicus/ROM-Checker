import { readFileSync, writeFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

export function buildInfo(env) {
  const channel = env.CHANNEL || 'local'
  const value = {
    version: env.VERSION || '0.0.0-local',
    buildNumber: Number(env.BUILD_NUMBER || 0),
    buildAttempt: Number(env.BUILD_ATTEMPT || 0),
    channel,
    commit: env.REVISION || 'development',
    builtUtc: env.BUILT_UTC || new Date().toISOString(),
    workflowUrl: env.WORKFLOW_URL || null,
    schemaVersion: 1,
    metadataFormatVersion: 1
  }
  if (!['local', 'development', 'beta', 'stable'].includes(channel)
    || !/^\d+\.\d+\.\d+(?:-(?:local|development\.[1-9]\d*|beta\.[1-9]\d*))?$/.test(value.version)
    || !Number.isSafeInteger(value.buildNumber) || !Number.isSafeInteger(value.buildAttempt)
    || value.buildNumber < 0 || value.buildAttempt < 0 || !Number.isFinite(Date.parse(value.builtUtc)))
    throw new Error('Invalid build identity.')
  if (channel !== 'local' && (!/^[a-f0-9]{40}$/.test(value.commit)
    || value.buildNumber < 1 || value.buildAttempt < 1
    || !/^https:\/\/github\.com\/Phthisicus\/ROM-Checker\/actions\/runs\/\d+$/.test(value.workflowUrl ?? '')
    || !env.BUILT_UTC
    || (channel === 'development' && !value.version.endsWith(`-development.${value.buildNumber}`))
    || (channel === 'beta' && !/-beta\.[1-9]\d*$/.test(value.version))
    || (channel === 'stable' && value.version.includes('-'))))
    throw new Error('Published builds require complete, channel-consistent metadata.')
  return value
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const value = buildInfo(process.env)
  writeFileSync('build-info.json', JSON.stringify(value, null, 2) + '\n')
  const release = JSON.parse(readFileSync('release-info.json', 'utf8'))
  if (release.version !== value.version || release.channel !== value.channel || release.commit !== value.commit
    || release.metadataFormatVersion !== 1 || typeof release.notes !== 'string'
    || !Array.isArray(release.upgradeNotes) || !Array.isArray(release.limitations))
    throw new Error('Release information does not match the image build identity.')
  writeFileSync('release-notes.md', release.notes)
  for (const name of ['package.json', 'package-lock.json']) {
    const pkg = JSON.parse(readFileSync(name, 'utf8'))
    pkg.version = value.version
    if (pkg.packages?.['']) pkg.packages[''].version = value.version
    writeFileSync(name, JSON.stringify(pkg, null, 2) + '\n')
  }
}
