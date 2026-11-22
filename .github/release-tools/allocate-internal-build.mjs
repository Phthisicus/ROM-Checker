import { readFileSync, writeFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { dockerTag, internalVersion, validateReleaseTarget } from './semver.mjs'

export async function allocateInternalBuild({ env = process.env, fetcher = fetch } = {}) {
  if (!env.GH_TOKEN || !/^[\w.-]+\/[\w.-]+$/.test(env.GITHUB_REPOSITORY ?? ''))
    throw new Error('GitHub Actions repository credentials are missing.')
  if (!/^[a-f0-9]{40}$/.test(env.SOURCE_SHA ?? '')) throw new Error('Internal build source SHA is invalid.')
  const headers = {
    Accept: 'application/vnd.github+json',
    Authorization: `Bearer ${env.GH_TOKEN}`,
    'X-GitHub-Api-Version': '2022-11-28'
  }
  const collection = `https://api.github.com/repos/${env.GITHUB_REPOSITORY}/actions/variables`
  const variable = `${collection}/ROMCHECKER_INTERNAL_BUILD_NUMBER`
  const config = JSON.parse(readFileSync('.github/release-config.json', 'utf8'))
  const target = validateReleaseTarget(config.nextRelease)
  const seed = Number(config.internalBuildSeed)
  if (!Number.isSafeInteger(seed) || seed < 0) throw new Error('Invalid internal build seed.')

  const response = await fetcher(variable, { headers })
  let current
  if (response.status === 404) current = seed
  else {
    if (!response.ok) throw new Error(`Could not read persistent build number (${response.status}).`)
    const value = await response.json()
    current = Number(value.value)
  }
  if (!Number.isSafeInteger(current) || current < seed) throw new Error('Persistent internal build number is invalid or below its migration seed.')
  const number = current + 1
  if (!Number.isSafeInteger(number)) throw new Error('Internal build number is exhausted.')

  const update = await fetcher(response.status === 404 ? collection : variable, {
    method: response.status === 404 ? 'POST' : 'PATCH',
    headers: { ...headers, 'Content-Type': 'application/json' },
    body: JSON.stringify(response.status === 404
      ? { name: 'ROMCHECKER_INTERNAL_BUILD_NUMBER', value: String(number) }
      : { value: String(number) })
  })
  if (!update.ok) throw new Error(`Could not persist internal build number (${update.status}).`)
  const version = internalVersion(target, number, env.SOURCE_SHA)
  return { number, version, tag: dockerTag(version) }
}

async function main() {
  const build = await allocateInternalBuild()
  writeFileSync(process.env.GITHUB_OUTPUT,
    `build_number=${build.number}\nversion=${build.version}\ndocker_tag=${build.tag}\n`)
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)
  main().catch(error => {
    console.error(error.message)
    process.exitCode = 1
  })
