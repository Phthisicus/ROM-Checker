import test from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { calculateVersion, compareVersions, parseVersion, renderNotes, validateNote } from './release.mjs'

const sha = 'a'.repeat(40)
const priorSha = 'b'.repeat(40)
const feature = { type: 'feature', title: 'Console-scoped verification', description: 'Check one console without changing the rest of your library.' }
const input = { branch: 'main', tags: [], commits: [], notes: [], fallback: '0.2.0', sha }
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
