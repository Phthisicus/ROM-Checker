import { readFileSync } from 'node:fs'

const VERSION = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/

export function parseVersion(version) {
  const match = VERSION.exec(version)
  if (!match) throw new Error(`Invalid SemVer 2.0.0 version: ${version}`)
  return {
    major: BigInt(match[1]),
    minor: BigInt(match[2]),
    patch: BigInt(match[3]),
    prerelease: match[4]?.split('.') ?? [],
    build: match[5]?.split('.') ?? []
  }
}

export function compareVersions(left, right) {
  const a = parseVersion(left)
  const b = parseVersion(right)
  for (const key of ['major', 'minor', 'patch']) {
    if (a[key] !== b[key]) return a[key] < b[key] ? -1 : 1
  }
  if (a.prerelease.length === 0 || b.prerelease.length === 0)
    return a.prerelease.length === b.prerelease.length ? 0 : a.prerelease.length === 0 ? 1 : -1
  const length = Math.min(a.prerelease.length, b.prerelease.length)
  for (let index = 0; index < length; index++) {
    const one = a.prerelease[index]
    const two = b.prerelease[index]
    if (one === two) continue
    const numericOne = /^\d+$/.test(one)
    const numericTwo = /^\d+$/.test(two)
    if (numericOne && numericTwo) {
      const leftNumber = BigInt(one)
      const rightNumber = BigInt(two)
      return leftNumber < rightNumber ? -1 : 1
    }
    if (numericOne !== numericTwo) return numericOne ? -1 : 1
    return one < two ? -1 : 1
  }
  return Math.sign(a.prerelease.length - b.prerelease.length)
}

export function validateReleaseTarget(version) {
  const parsed = parseVersion(version)
  if (parsed.prerelease.length || parsed.build.length) throw new Error('Release target must be a stable MAJOR.MINOR.PATCH version.')
  return version
}

export function internalVersion(target, build, commit) {
  validateReleaseTarget(target)
  if (!/^[1-9]\d*$/.test(String(build)) || !/^[a-f0-9]{40}$/.test(commit))
    throw new Error('Internal builds require a positive build number and full commit SHA.')
  return `${target}-internal.${build}+${commit.slice(0, 7)}`
}

export function dockerTag(version) {
  parseVersion(version)
  return version.replace('+', '-')
}

export function nextPrerelease(channel, target, versions) {
  validateReleaseTarget(target)
  if (channel !== 'beta' && channel !== 'rc') throw new Error('Only beta and rc prereleases are supported.')
  let latest = 0n
  for (const version of versions) {
    const parsed = parseVersion(version)
    if (parsed.prerelease.length === 2 && parsed.prerelease[0] === channel
      && parsed.major === parseVersion(target).major
      && parsed.minor === parseVersion(target).minor
      && parsed.patch === parseVersion(target).patch) {
      const number = parsed.prerelease[1]
      if (!/^[1-9]\d*$/.test(number)) throw new Error(`Invalid ${channel} sequence: ${version}`)
      const current = BigInt(number)
      if (current > latest) latest = current
    }
  }
  return `${target}-${channel}.${latest + 1n}`
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  try {
    const [command, ...args] = process.argv.slice(2)
    if (command === 'internal') console.log(internalVersion(args[0], args[1], args[2]))
    else if (command === 'docker-tag') console.log(dockerTag(args[0]))
    else if (command === 'next-prerelease')
      console.log(nextPrerelease(args[0], args[1], readFileSync(args[2], 'utf8').split(/\r?\n/).filter(Boolean)))
    else if (command === 'validate-target') console.log(validateReleaseTarget(args[0]))
    else throw new Error('Usage: semver.mjs internal|docker-tag|next-prerelease|validate-target ...')
  } catch (error) {
    console.error(error.message)
    process.exitCode = 1
  }
}
