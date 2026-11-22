import { readFileSync, writeFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { parseVersion } from './semver.mjs'

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
  let version
  try { version = parseVersion(value.version) } catch { throw new Error('Invalid build identity.') }
  const prereleaseChannel = version.prerelease[0]
  if (!['local', 'development', 'internal', 'beta', 'rc', 'stable'].includes(channel)
    || !Number.isSafeInteger(value.buildNumber) || !Number.isSafeInteger(value.buildAttempt)
    || value.buildNumber < 0 || value.buildAttempt < 0 || !Number.isFinite(Date.parse(value.builtUtc)))
    throw new Error('Invalid build identity.')
  if (channel !== 'local' && (!/^[a-f0-9]{40}$/.test(value.commit)
    || value.buildNumber < 1 || value.buildAttempt < 1
    || !/^https:\/\/github\.com\/Phthisicus\/ROM-Checker\/actions\/runs\/\d+$/.test(value.workflowUrl ?? '')
    || !env.BUILT_UTC
    || (channel === 'development' && (prereleaseChannel !== 'development'
      || version.prerelease[1] !== String(value.buildNumber)))
    || (channel === 'internal' && (prereleaseChannel !== 'internal'
      || version.prerelease.length !== 2 || version.prerelease[1] !== String(value.buildNumber)
      || version.build.join('.') !== value.commit.slice(0, 7)))
    || (channel === 'beta' && (prereleaseChannel !== 'beta' || version.prerelease.length !== 2))
    || (channel === 'rc' && (prereleaseChannel !== 'rc' || version.prerelease.length !== 2))
    || (channel === 'stable' && version.prerelease.length > 0)))
    throw new Error('Published builds require complete, channel-consistent metadata.')
  return value
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const value = buildInfo(process.env)
  writeFileSync('build-info.json', JSON.stringify(value, null, 2) + '\n')
  const existingRelease = JSON.parse(readFileSync('release-info.json', 'utf8'))
  const release = existingRelease.version === value.version && existingRelease.channel === value.channel
    && existingRelease.commit === value.commit ? existingRelease : {
      metadataFormatVersion: 1,
      version: value.version,
      channel: value.channel,
      commit: value.commit,
      releaseUrl: value.channel === 'local' ? null
        : `https://github.com/Phthisicus/ROM-Checker/commit/${value.commit}`,
      notes: value.channel === 'internal'
        ? `Internal build ${value.buildNumber} for release target ${value.version.split('-')[0]}.`
        : existingRelease.notes,
      upgradeNotes: [],
      limitations: []
    }
  if (release.metadataFormatVersion !== 1 || typeof release.notes !== 'string'
    || !Array.isArray(release.upgradeNotes) || !Array.isArray(release.limitations))
    throw new Error('Release information does not match the image build identity.')
  writeFileSync('release-info.json', JSON.stringify(release, null, 2) + '\n')
  writeFileSync('release-notes.md', release.notes)
  for (const name of ['package.json', 'package-lock.json']) {
    const pkg = JSON.parse(readFileSync(name, 'utf8'))
    pkg.version = value.version
    if (pkg.packages?.['']) pkg.packages[''].version = value.version
    writeFileSync(name, JSON.stringify(pkg, null, 2) + '\n')
  }
}
