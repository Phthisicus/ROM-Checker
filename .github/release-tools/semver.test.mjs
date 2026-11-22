import test from 'node:test'
import assert from 'node:assert/strict'
import { compareVersions, dockerTag, internalVersion, nextPrerelease, parseVersion, validateReleaseTarget } from './semver.mjs'
import { allocateInternalBuild } from './allocate-internal-build.mjs'

const sha = 'd45e67f123456789012345678901234567890123'

test('parses SemVer 2.0.0 and rejects invalid identifiers', () => {
  assert.doesNotThrow(() => parseVersion('1.2.3-rc.2+build.7'))
  for (const version of ['01.2.3', '1.2', '1.2.3-', '1.2.3+build..7', '1.2.3-01'])
    assert.throws(() => parseVersion(version))
})

test('compares prerelease identifiers per SemVer and ignores build metadata', () => {
  assert.ok(compareVersions('1.0.0-alpha.2', '1.0.0-alpha.10') < 0)
  assert.ok(compareVersions('1.0.0-rc.1', '1.0.0') < 0)
  assert.equal(compareVersions('1.0.0+one', '1.0.0+two'), 0)
  assert.ok(compareVersions('1.0.0-1', '1.0.0-alpha') < 0)
})

test('internal versions use the explicit target, persistent counter and short commit', () => {
  assert.equal(internalVersion('0.3.0', 32, sha), '0.3.0-internal.32+d45e67f')
  assert.equal(dockerTag(internalVersion('0.3.0', 32, sha)), '0.3.0-internal.32-d45e67f')
  assert.throws(() => validateReleaseTarget('0.3.0-beta.1'))
  assert.throws(() => internalVersion('0.3.0', 0, sha))
})

test('beta and RC sequences advance independently for the configured target', () => {
  const existing = ['0.3.0-beta.1', '0.3.0-beta.3', '0.3.0-rc.1', '0.4.0-beta.9']
  assert.equal(nextPrerelease('beta', '0.3.0', existing), '0.3.0-beta.4')
  assert.equal(nextPrerelease('rc', '0.3.0', existing), '0.3.0-rc.2')
  assert.equal(nextPrerelease('beta', '0.3.0', []), '0.3.0-beta.1')
})

test('internal build allocation creates and updates the persistent Actions variable', async () => {
  const env = {
    GH_TOKEN: 'fixture-token',
    GITHUB_REPOSITORY: 'Phthisicus/ROM-Checker',
    SOURCE_SHA: '0123456789abcdef0123456789abcdef01234567'
  }
  const calls = []
  const create = await allocateInternalBuild({
    env,
    fetcher: async (url, options = {}) => {
      calls.push({ url, options })
      if (!options.method) return { status: 404, ok: false }
      return { status: 201, ok: true }
    }
  })
  assert.equal(create.number, 32)
  assert.equal(create.version, '0.3.0-internal.32+0123456')
  assert.equal(calls[1].url, 'https://api.github.com/repos/Phthisicus/ROM-Checker/actions/variables')
  assert.equal(calls[1].options.method, 'POST')
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    name: 'ROMCHECKER_INTERNAL_BUILD_NUMBER',
    value: '32'
  })

  calls.length = 0
  const update = await allocateInternalBuild({
    env,
    fetcher: async (url, options = {}) => {
      calls.push({ url, options })
      return options.method
        ? { status: 204, ok: true }
        : { status: 200, ok: true, json: async () => ({ value: '87' }) }
    }
  })
  assert.equal(update.number, 88)
  assert.equal(calls[1].url, 'https://api.github.com/repos/Phthisicus/ROM-Checker/actions/variables/ROMCHECKER_INTERNAL_BUILD_NUMBER')
  assert.equal(calls[1].options.method, 'PATCH')
  assert.deepEqual(JSON.parse(calls[1].options.body), { value: '88' })
})
