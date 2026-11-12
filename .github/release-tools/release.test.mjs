import test from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { calculateVersion, compareVersions, parseVersion, releaseInfo, renderNotes, validateNote } from './release.mjs'
import { buildInfo } from './build-info.mjs'

const sha = 'a'.repeat(40)
const priorSha = 'b'.repeat(40)
const feature = { type: 'feature', title: 'Console-scoped verification', description: 'Check one console without changing the rest of your library.' }
const input = { branch: 'main', tags: [], commits: [], notes: [], fallback: '0.2.0', sha }
test('published build identities reject placeholders and channel/version inconsistencies', () => {
  const env = { VERSION: '1.3.0-development.142', CHANNEL: 'development', REVISION: sha,
    BUILD_NUMBER: '142', BUILD_ATTEMPT: '1', BUILT_UTC: '2026-10-27T20:00:00Z',
    WORKFLOW_URL: 'https://github.com/Phthisicus/ROM-Checker/actions/runs/123' }
  assert.equal(buildInfo(env).buildNumber, 142)
  assert.equal(buildInfo({}).channel, 'local')
  for (const change of [{ REVISION: 'development' }, { BUILD_NUMBER: '0' }, { BUILD_ATTEMPT: '-1' },
    { BUILT_UTC: 'invalid' }, { CHANNEL: 'stable' }, { WORKFLOW_URL: 'https://example.invalid' },
    { VERSION: '1.3.0-development.141' }])
    assert.throws(() => buildInfo({ ...env, ...change }))
  assert.equal(buildInfo({ ...env, VERSION: '1.3.0-beta.2', CHANNEL: 'beta' }).channel, 'beta')
  assert.equal(buildInfo({ ...env, VERSION: '1.3.0', CHANNEL: 'stable' }).version, '1.3.0')
})
test('only release branches can allocate versions', () => {
  for (const branch of ['development', 'feature/test', '']) assert.throws(() => calculateVersion({ ...input, branch }), /Only beta/)
})
test('initial release uses the checked-in version floor', () => {
  assert.equal(calculateVersion(input), '0.2.0')
  assert.equal(calculateVersion({ ...input, branch: 'beta' }), '0.2.0-beta.1')
})
test('stable pushes always get at least a patch; conventional features and breaking changes bump appropriately', () => {
  const options = { ...input, tags: [{ name: 'v1.2.3', sha: priorSha }] }
  assert.equal(calculateVersion(options), '1.2.4')
  assert.equal(calculateVersion({ ...options, notes: [feature] }), '1.3.0')
  assert.equal(calculateVersion({ ...options, commits: [{ subject: 'feat(library): scoped checks', body: '' }] }), '1.3.0')
  assert.equal(calculateVersion({ ...options, commits: [{ subject: 'feat!: replace storage format', body: '' }] }), '2.0.0')
  assert.equal(calculateVersion({ ...options, commits: [{ subject: 'fix: format migration', body: 'BREAKING CHANGE: new schema' }] }), '2.0.0')
  assert.equal(calculateVersion({ ...options, notes: [{ ...feature, type: 'breaking' }] }), '2.0.0')
})
test('beta increments within a release line; promoting multiple betas produces one stable version', () => {
  const tags = [{ name: 'v1.2.3', sha: priorSha }, { name: 'v1.3.0-beta.1', sha: priorSha }, { name: 'v1.3.0-beta.2', sha: priorSha }]
  assert.equal(calculateVersion({ ...input, tags, notes: [feature], branch: 'beta' }), '1.3.0-beta.3')
  assert.equal(calculateVersion({ ...input, tags, notes: [feature] }), '1.3.0')
})
test('reruns reuse reserved tags for their channel and commit, including after newer releases', () => {
  const tags = [{ name: 'v1.3.0', sha }, { name: 'v1.4.0', sha: priorSha }, { name: 'v1.3.0-beta.4', sha }]
  assert.equal(calculateVersion({ ...input, tags }), '1.3.0')
  assert.equal(calculateVersion({ ...input, tags, branch: 'beta' }), '1.3.0-beta.4')
})
test('versions sort numerically with stable after its prereleases', () => {
  assert.ok(compareVersions('v1.2.0-beta.10', 'v1.2.0-beta.2') > 0)
  assert.ok(compareVersions('v1.2.0', 'v1.2.0-beta.10') > 0)
  for (const value of ['1.2', '1.2.3-rc.1', '01.2.3', 'v1.2.3-beta.0']) assert.throws(() => parseVersion(value))
})
test('editorial entries require meaningful content and migration instructions', () => {
  assert.equal(validateNote(feature), feature)
  for (const value of [{}, { ...feature, type: 'unknown' }, { ...feature, title: 'short' },
    { ...feature, title: 'A title\nwith injection' }, { ...feature, type: 'breaking' }, { ...feature, extra: true }])
    assert.throws(() => validateNote(value))
  assert.doesNotThrow(() => validateNote({ ...feature, type: 'breaking', upgrade: 'Back up and migrate the database.' }))
})
test('notes include user-facing highlights, upgrade cautions, limitations and reproducible container identity', () => {
  const plan = { ...input, version: '1.3.0-beta.1', prerelease: true, tag: 'v1.3.0-beta.1', repository: 'owner/repo',
    image: 'ghcr.io/owner/repo', baseline: 'v1.2.3', notes: [{ ...feature, upgrade: 'Map your consoles.', limitations: 'Shared storage is required.' }],
    commits: [{ hash: sha, subject: 'feat: add scoped checks' }] }
  const result = renderNotes(plan, 'sha256:' + 'c'.repeat(64))
  for (const text of ['Beta prerelease', '## Highlights', feature.description, 'Map your consoles.', 'Shared storage is required.',
    'ghcr.io/owner/repo:1.3.0-beta.1', 'sha256:', 'v1.2.3...v1.3.0-beta.1', 'Commit history'])
    assert.ok(result.includes(text), text)
  const stable = renderNotes({ ...plan, prerelease: false, notes: [] }, 'sha256:' + 'c'.repeat(64))
  assert.ok(stable.includes('No editorial feature summary was supplied'))
  assert.ok(!stable.includes('Beta prerelease'))
})
test('promotion policy accepts feature work and same-repository promotions, rejects bypasses', () => {
  const path = resolve('.github/release-tools/policy.mjs')
  const run = (base, head, title, source = 'owner/repo') => spawnSync(process.execPath, [path], {
    env: { ...process.env, PR_BASE: base, PR_HEAD: head, PR_TITLE: title, PR_HEAD_REPO: source, PR_BASE_REPO: 'owner/repo' }
  }).status
  assert.equal(run('development', 'feature/test', 'feat: add a console browser'), 0)
  assert.equal(run('beta', 'development', 'Promote tested development'), 0)
  assert.equal(run('main', 'beta', 'Release tested beta'), 0)
  assert.equal(run('main', 'hotfix/storage', 'fix: recover interrupted imports'), 0)
  assert.notEqual(run('main', 'feature/test', 'feat: bypass beta testing'), 0)
  assert.notEqual(run('beta', 'development', 'Promote external fork', 'attacker/repo'), 0)
  assert.notEqual(run('development', 'feature/test', 'updates'), 0)
})
test('embedded metadata carries channel-specific notes and upgrade requirements without a circular image digest', () => {
  const plan = { ...input, version: '1.3.0', branch: 'main', tag: 'v1.3.0', repository: 'Phthisicus/ROM-Checker',
    image: 'ghcr.io/phthisicus/rom-checker', baseline: null,
    notes: [{ ...feature, upgrade: 'Back up before deploying.', limitations: 'Requires shared storage.' }], commits: [] }
  const stable = releaseInfo(plan)
  assert.equal(stable.channel, 'stable')
  assert.deepEqual(stable.upgradeNotes, ['Back up before deploying.'])
  assert.deepEqual(stable.limitations, ['Requires shared storage.'])
  assert.ok(!stable.notes.includes('@null'))
  assert.ok(!stable.notes.includes('@sha256:'))
  const development = releaseInfo({ ...plan, branch: 'development', version: '1.3.0-development.142', tag: null })
  assert.equal(development.channel, 'development')
  assert.ok(development.notes.includes('Development build'))
  assert.equal(development.releaseUrl, `https://github.com/Phthisicus/ROM-Checker/commit/${sha}`)
})
test('metadata publication reuses image-baked notes and refuses conflicting immutable companions', () => {
  const directory = mkdtempSync(join(tmpdir(), 'romchecker-metadata-tests-'))
  try {
    const docker = join(directory, 'docker')
    const expected = '{"version":"1.3.0","commit":"' + sha + '","channel":"stable","metadataFormatVersion":1,"notes":"Image-baked notes"}\n'
    writeFileSync(join(directory, 'expected.json'), expected)
    writeFileSync(join(directory, 'release-info.json'), '{"notes":"A regenerated plan must not replace image-baked notes"}')
    writeFileSync(docker, `#!${process.execPath}
import { appendFileSync, copyFileSync, readFileSync, writeFileSync } from 'node:fs'
const args = process.argv.slice(2)
appendFileSync(process.env.MOCK_LOG, JSON.stringify(args) + '\\n')
if (args[0] === 'run') process.stdout.write(readFileSync(process.env.MOCK_EXPECTED))
if (args[0] === 'cp') {
  if (process.env.MOCK_CONFLICT === 'true') writeFileSync(args[2], '{"notes":"conflicting notes"}')
  else copyFileSync(process.env.MOCK_EXPECTED, args[2])
}
if (args[0] === 'buildx' && args[1] === 'imagetools' && process.env.MOCK_EXISTING !== 'true') {
  console.error('manifest unknown')
  process.exitCode = 1
}
`)
    chmodSync(docker, 0o755)
    const script = resolve('.github/release-tools/publish-metadata.sh')
    const env = { ...process.env, PATH: `${directory}:${process.env.PATH}`, MOCK_EXPECTED: join(directory, 'expected.json'),
      MOCK_LOG: join(directory, 'calls.jsonl'), IMAGE: 'ghcr.io/phthisicus/rom-checker', VERSION: '1.3.0',
      SOURCE_SHA: sha, CHANNEL: 'stable', BUILD_NUMBER: '143', BUILD_ATTEMPT: '1',
      BUILT_UTC: '2026-11-11T12:00:00Z', WORKFLOW_URL: 'https://github.com/Phthisicus/ROM-Checker/actions/runs/123',
      GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '1' }
    const run = extra => spawnSync('bash', [script], { cwd: directory, env: { ...env, ...extra }, encoding: 'utf8' })
    let result = run({})
    assert.equal(result.status, 0, result.stderr)
    assert.equal(readFileSync(join(directory, 'release-info.json'), 'utf8'), expected)
    let calls = readFileSync(env.MOCK_LOG, 'utf8').trim().split('\n').map(line => JSON.parse(line))
    assert.equal(calls.filter(args => args[0] === 'buildx' && args[1] === 'build').length, 1)
    writeFileSync(env.MOCK_LOG, '')
    result = run({ MOCK_EXISTING: 'true' })
    assert.equal(result.status, 0, result.stderr)
    calls = readFileSync(env.MOCK_LOG, 'utf8').trim().split('\n').map(line => JSON.parse(line))
    assert.equal(calls.filter(args => args[0] === 'buildx' && args[1] === 'build').length, 0, 'Retries must not overwrite metadata')
    assert.notEqual(run({ MOCK_EXISTING: 'true', MOCK_CONFLICT: 'true' }).status, 0)
  } finally { rmSync(directory, { recursive: true, force: true }) }
})
test('real git history yields incremental beta notes and cumulative stable notes; retries are deterministic', () => {
  const directory = mkdtempSync(join(tmpdir(), 'romchecker-release-tests-'))
  try {
    const scripts = join(directory, '.github', 'release-tools')
    const notes = join(directory, '.github', 'release-notes')
    mkdirSync(scripts, { recursive: true }); mkdirSync(notes, { recursive: true })
    copyFileSync(resolve('.github/release-tools/release.mjs'), join(scripts, 'release.mjs'))
    writeFileSync(join(directory, 'version.txt'), '1.0.0\n')
    const git = (...args) => execFileSync('git', args, { cwd: directory, encoding: 'utf8' }).trim()
    const run = (...args) => execFileSync(process.execPath, [join(scripts, 'release.mjs'), ...args], { cwd: directory, encoding: 'utf8' })
    git('init', '--quiet'); git('config', 'user.email', 'fixture@example.invalid'); git('config', 'user.name', 'Release fixture')
    git('add', '.'); git('commit', '--quiet', '-m', 'chore: initial fixture'); git('tag', 'v1.0.0')
    writeFileSync(join(notes, 'feature.json'), JSON.stringify(feature))
    git('add', '.'); git('commit', '--quiet', '-m', 'feat: console scoped checks')
    const first = git('rev-parse', 'HEAD')
    assert.equal(run('development', first, 'owner/repo', '142').trim(), '1.1.0-development.142')
    run('plan', 'beta', first, 'owner/repo')
    const read = () => JSON.parse(readFileSync(join(directory, '.release', 'release-plan.json'), 'utf8'))
    assert.equal(read().version, '1.1.0-beta.1')
    git('tag', 'v1.1.0-beta.1')
    writeFileSync(join(notes, 'fix.json'), JSON.stringify({ ...feature, type: 'fix', title: 'Prevent interrupted transfer duplication' }))
    git('add', '.github'); git('commit', '--quiet', '-m', 'fix: prevent duplicated transfers')
    const second = git('rev-parse', 'HEAD')
    run('plan', 'beta', second, 'owner/repo')
    assert.equal(read().version, '1.1.0-beta.2')
    assert.equal(read().notes.length, 1)
    git('tag', 'v1.1.0-beta.2')
    run('plan', 'beta', second, 'owner/repo')
    assert.equal(read().version, '1.1.0-beta.2')
    run('plan', 'main', second, 'owner/repo')
    assert.equal(read().version, '1.1.0')
    assert.equal(read().notes.length, 2)
    const publishedPath = join(directory, 'published-tags.txt')
    writeFileSync(publishedPath, 'v1.0.0\n')
    run('plan', 'beta', second, 'owner/repo', '.release', publishedPath)
    assert.equal(read().notes.length, 2, 'Unpublished reserved beta tags do not hide changes from later release notes')
    assert.equal(read().baseline, 'v1.0.0')
    run('plan', 'main', second, 'owner/repo')
    git('tag', 'v1.1.0')
    run('plan', 'main', second, 'owner/repo')
    assert.equal(read().version, '1.1.0')
    assert.equal(read().baseline, 'v1.0.0')
    assert.equal(read().notes.length, 2)
    // Future beta comparisons must start from stable, not repeat older beta changes.
    writeFileSync(join(notes, 'maintenance.json'), JSON.stringify({ ...feature, type: 'maintenance' }))
    git('add', '.github'); git('commit', '--quiet', '-m', 'chore: update release workflow')
    run('plan', 'beta', git('rev-parse', 'HEAD'), 'owner/repo')
    assert.equal(read().version, '1.1.1-beta.1')
    assert.equal(read().baseline, 'v1.1.0')
    assert.equal(read().notes.length, 1)
    assert.equal(run('development', first, 'owner/repo', '142').trim(), '1.1.0-development.142',
      'A later stable tag on a descendant must not change an earlier development build version')
    const manifest = join(directory, '.release', 'release-plan.json')
    const packages = join(directory, 'web', 'client')
    mkdirSync(packages, { recursive: true })
    writeFileSync(join(packages, 'package.json'), '{"version":"1.0.0"}')
    writeFileSync(join(packages, 'package-lock.json'), '{"version":"1.0.0","packages":{"":{"version":"1.0.0"}}}')
    run('stamp', manifest)
    assert.equal(JSON.parse(readFileSync(join(packages, 'package-lock.json'))).packages[''].version, read().version)
    assert.equal(readFileSync(join(directory, 'version.txt'), 'utf8').trim(), read().version)
    run('notes', manifest, 'sha256:' + 'c'.repeat(64))
    assert.equal(JSON.parse(readFileSync(join(directory, '.release', 'release-manifest.json'))).sha, git('rev-parse', 'HEAD'))
    assert.ok(readFileSync(join(directory, '.release', 'release-notes.md'), 'utf8').includes('ghcr.io/owner/repo@sha256:'))
    const base = git('rev-parse', 'HEAD')
    writeFileSync(join(notes, 'feature.json'), JSON.stringify({ ...feature, description: 'This modified published note must be rejected.' }))
    git('add', '.github'); git('commit', '--quiet', '-m', 'docs: modify an old note')
    assert.throws(() => run('validate', base), /Command failed/)
    git('restore', '--source', base, '--', '.github/release-notes/feature.json')
    git('add', '.github'); git('commit', '--quiet', '-m', 'docs: restore original note')
    writeFileSync(join(packages, 'example.ts'), 'export const value = true\n')
    git('add', 'web'); git('commit', '--quiet', '-m', 'fix: application change without notes')
    assert.throws(() => run('validate', base), /Command failed/)
  } finally { rmSync(directory, { recursive: true, force: true }) }
})
