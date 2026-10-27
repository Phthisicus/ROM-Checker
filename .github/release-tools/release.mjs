import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
function git(...args) {
  return execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim()
}
function gh(...args) {
  return execFileSync('gh', args, { cwd: root, encoding: 'utf8' }).trim()
}
export function parseVersion(value) {
  const match = /^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-beta\.([1-9]\d*))?$/.exec(value)
  if (!match) throw new Error(`Invalid release version: ${value}`)
  return { major: Number(match[1]), minor: Number(match[2]), patch: Number(match[3]), beta: match[4] ? Number(match[4]) : null }
}
export function compareVersions(left, right) {
  const a = parseVersion(left), b = parseVersion(right)
  for (const key of ['major', 'minor', 'patch']) if (a[key] !== b[key]) return a[key] - b[key]
  return a.beta === b.beta ? 0 : a.beta === null ? 1 : b.beta === null ? -1 : a.beta - b.beta
}
const baseVersion = version => version.replace(/^v/, '').replace(/-beta\.\d+$/, '')
export function calculateVersion({ branch, tags, commits, notes, fallback, sha }) {
  if (!['beta', 'main'].includes(branch)) throw new Error('Only beta and main can release.')
  const known = tags.filter(tag => /^v\d+\.\d+\.\d+(?:-beta\.\d+)?$/.test(tag.name))
  parseVersion(fallback)
  const existing = known.filter(tag => tag.sha === sha && (parseVersion(tag.name).beta !== null) === (branch === 'beta'))
    .sort((a, b) => compareVersions(b.name, a.name))[0]
  if (existing) return existing.name.slice(1)
  const stable = known.filter(tag => parseVersion(tag.name).beta === null).sort((a, b) => compareVersions(b.name, a.name))[0]
  const prior = parseVersion(stable?.name ?? fallback)
  const breaking = notes.some(note => note.type === 'breaking') || commits.some(commit => /^[a-z]+(?:\([^)]+\))?!:/.test(commit.subject) || /^BREAKING[ -]CHANGE:/m.test(commit.body))
  const feature = notes.some(note => note.type === 'feature') || commits.some(commit => /^feat(?:\([^)]+\))?:/.test(commit.subject))
  // The checked-in version is the initial release floor, not another counter to maintain.
  let version = !stable ? baseVersion(fallback) : breaking ? `${prior.major + 1}.0.0`
    : feature ? `${prior.major}.${prior.minor + 1}.0` : `${prior.major}.${prior.minor}.${prior.patch + 1}`
  if (branch === 'beta') {
    const previews = known.filter(tag => baseVersion(tag.name) === version && parseVersion(tag.name).beta !== null)
    version += `-beta.${1 + Math.max(0, ...previews.map(tag => parseVersion(tag.name).beta))}`
  }
  return version
}
const noteTypes = ['feature', 'improvement', 'fix', 'performance', 'security', 'breaking', 'maintenance']
export function validateNote(note, path = 'release note') {
  if (!note || !noteTypes.includes(note.type)) throw new Error(`${path}: choose a supported type.`)
  for (const key of ['title', 'description']) {
    if (typeof note[key] !== 'string' || note[key].trim().length < 8 || note[key].length > (key === 'title' ? 100 : 4000))
      throw new Error(`${path}: ${key} needs 8-${key === 'title' ? 100 : 4000} characters.`)
  }
  if (/[\r\n]/.test(note.title)) throw new Error(`${path}: title must be a single line.`)
  for (const key of ['upgrade', 'limitations']) {
    if (note[key] !== undefined && (typeof note[key] !== 'string' || note[key].length > 4000))
      throw new Error(`${path}: ${key} must be a string of at most 4000 characters.`)
  }
  if (note.type === 'breaking' && !note.upgrade?.trim()) throw new Error(`${path}: breaking changes require upgrade instructions.`)
  const unexpected = Object.keys(note).filter(key => !['type', 'title', 'description', 'upgrade', 'limitations'].includes(key))
  if (unexpected.length) throw new Error(`${path}: unknown fields: ${unexpected.join(', ')}.`)
  return note
}
function commitsSince(baseline, sha) {
  const text = git('log', '--no-merges', '--format=%H%x1f%s%x1f%b%x1e', baseline ? `${baseline}..${sha}` : sha)
  return text.split('\x1e').filter(value => value.trim()).map(value => {
    const [hash, subject, body] = value.trim().split('\x1f')
    return { hash, subject, body: body ?? '' }
  })
}
function notesSince(baseline, sha) {
  const args = baseline ? ['diff', '--name-only', '--diff-filter=A', baseline, sha] : ['ls-tree', '-r', '--name-only', sha]
  return git(...args).split('\n').filter(path => /^\.github\/release-notes\/[^/]+\.json$/.test(path)).map(path =>
    validateNote(JSON.parse(git('show', `${sha}:${path}`)), path))
}
function localTags() {
  return git('tag', '--list', 'v*').split('\n').filter(Boolean)
    .filter(name => /^v\d+\.\d+\.\d+(?:-beta\.\d+)?$/.test(name))
    .map(name => ({ name, sha: git('rev-list', '-n', '1', name) }))
}
function baselineFor(tags, sha, beta, exclude) {
  // Ancestry, not tag creation time, determines the applicable comparison.
  const eligible = tags.filter(tag => tag.name !== exclude && (beta || parseVersion(tag.name).beta === null))
    .filter(tag => {
      try { git('merge-base', '--is-ancestor', tag.name, sha); return true } catch (error) {
        if (error.status === 1) return false
        throw error
      }
    })
  return eligible.sort((a, b) => compareVersions(b.name, a.name))[0]?.name ?? null
}
function escapeHeading(text) { return text.replace(/[<>\\`*_#[\]]/g, character => '\\' + character) }
export function renderNotes(plan, digest) {
  const sections = [
    ['Highlights', ['feature', 'breaking']],
    ['Improvements', ['improvement', 'performance']],
    ['Fixes', ['fix']],
    ['Security', ['security']],
    ['Maintenance', ['maintenance']]
  ]
  const lines = [`# ROM Checker ${plan.version}`, '',
    plan.prerelease ? '**Beta prerelease — intended for testing, not production. Back up your data before upgrading.**'
      : 'A stable release of ROM Checker, with the following changes since the previous stable release.', '']
  for (const [heading, types] of sections) {
    const notes = plan.notes.filter(note => types.includes(note.type))
    if (!notes.length) continue
    lines.push(`## ${heading}`, '')
    for (const note of notes) lines.push(`### ${escapeHeading(note.title)}`, '', note.description.trim(), '')
  }
  if (!plan.notes.length) lines.push('## Changes', '', 'This release contains the changes listed in the commit history below. No editorial feature summary was supplied.', '')
  const upgrades = [...new Set(plan.notes.map(note => note.upgrade?.trim()).filter(Boolean))]
  const limitations = [...new Set(plan.notes.map(note => note.limitations?.trim()).filter(Boolean))]
  lines.push('## Upgrade notes', '',
    'Back up application data, ROM storage, and configuration. Use the same image version for the application, storage service, and signature updater. Rollback may require restoring the matching data backup.', '')
  for (const text of upgrades) lines.push(text, '')
  if (limitations.length) {
    lines.push('## Known limitations', '')
    for (const text of limitations) lines.push(text, '')
  }
  lines.push('## Container image', '', '```text', `${plan.image}:${plan.version}`, `${plan.image}@${digest}`, '```', '',
    `Source commit: \`${plan.sha}\``, '', 'The release assets contain the image digest, checksums, and machine-readable release manifest. The registry image includes an SBOM and build provenance.', '',
    '<details>', '<summary>Commit history</summary>', '')
  for (const commit of plan.commits.slice(0, 200))
    lines.push(`- ${escapeHeading(commit.subject)} ([${commit.hash.slice(0, 7)}](https://github.com/${plan.repository}/commit/${commit.hash}))`)
  lines.push('', '</details>', '')
  if (plan.baseline) lines.push(`**Full changelog:** https://github.com/${plan.repository}/compare/${plan.baseline}...${plan.tag}`, '')
  else lines.push(`**Source:** https://github.com/${plan.repository}/tree/${plan.tag}`, '')
  return lines.join('\n')
}
function output(name, value) {
  if (process.env.GITHUB_OUTPUT) writeFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`, { flag: 'a' })
}
function readPlan(path) {
  const plan = JSON.parse(readFileSync(path, 'utf8'))
  parseVersion(plan.version)
  if (!/^[a-f0-9]{40}$/.test(plan.sha) || !/^[\w.-]+\/[\w.-]+$/.test(plan.repository)
    || plan.tag !== `v${plan.version}` || plan.image !== `ghcr.io/${plan.repository.toLowerCase()}`
    || !['beta', 'main'].includes(plan.branch) || plan.prerelease !== (plan.branch === 'beta')
    || plan.prerelease !== (parseVersion(plan.version).beta !== null))
    throw new Error('Invalid release manifest.')
  return plan
}
export function run(command, args) {
  if (command === 'validate') {
    const directory = join(root, '.github', 'release-notes')
    for (const name of readdirSync(directory).filter(name => name.endsWith('.json')))
      validateNote(JSON.parse(readFileSync(join(directory, name), 'utf8')), name)
    if (args[0]) {
      const base = args[0]
      const changed = git('diff', '--name-status', `${base}...HEAD`).split('\n')
      if (changed.some(line => /^[MD]\t\.github\/release-notes\/.*\.json$/.test(line)))
        throw new Error('Published release notes are append-only. Add a new entry instead of changing an existing one.')
      if (changed.some(line => /\t(?:web\/|RomSorter|Dockerfile|compose\.yml|\.github\/(?:workflows\/|release-tools\/|dependabot\.yml))/.test(line))
        && !changed.some(line => /^A\t\.github\/release-notes\/[^/]+\.json$/.test(line)))
        throw new Error('Add a feature-focused .github/release-notes/*.json entry for this change.')
    }
    console.log('Release-note entries are valid.')
  } else if (command === 'development') {
    const [sha, repository, number] = args
    if (!/^[a-f0-9]{40}$/.test(sha) || !/^[\w.-]+\/[\w.-]+$/.test(repository) || !/^[1-9]\d*$/.test(number))
      throw new Error('Invalid development build source.')
    const tags = localTags()
    const baseline = baselineFor(tags, sha, false)
    const version = calculateVersion({ branch: 'main', tags: tags.filter(tag => tag.name === baseline), commits: commitsSince(baseline, sha),
      notes: notesSince(baseline, sha), fallback: readFileSync(join(root, 'version.txt'), 'utf8').trim(), sha })
    output('version', `${version}-development.${number}`)
    output('image', `ghcr.io/${repository.toLowerCase()}`)
    console.log(`${version}-development.${number}`)
  } else if (command === 'plan') {
    const [branch, sha, repository, directory = '.release', publishedFile] = args
    if (!/^[\w.-]+\/[\w.-]+$/.test(repository) || !/^[a-f0-9]{40}$/.test(sha)) throw new Error('Invalid release source.')
    const tags = localTags()
    const stableBase = baselineFor(tags, sha, false)
    const commits = commitsSince(stableBase, sha)
    const notes = notesSince(stableBase, sha)
    const version = calculateVersion({ branch, tags, commits, notes, sha, fallback: readFileSync(join(root, 'version.txt'), 'utf8').trim() })
    const tag = 'v' + version
    const published = publishedFile ? new Set(readFileSync(publishedFile, 'utf8').trim().split(/\r?\n/)) : null
    const baseline = baselineFor(published ? tags.filter(tag => published.has(tag.name)) : tags, sha, branch === 'beta', tag)
    const plan = { version, tag, branch, prerelease: branch === 'beta', sha, repository,
      image: `ghcr.io/${repository.toLowerCase()}`, baseline, notes: notesSince(baseline, sha), commits: commitsSince(baseline, sha) }
    mkdirSync(directory, { recursive: true })
    writeFileSync(join(directory, 'release-plan.json'), JSON.stringify(plan, null, 2) + '\n')
    for (const key of ['version', 'tag', 'image']) output(key, plan[key])
    console.log(JSON.stringify(plan, null, 2))
  } else if (command === 'reserve') {
    const plan = readPlan(args[0])
    let remote
    try { remote = JSON.parse(gh('api', `repos/${plan.repository}/git/ref/tags/${plan.tag}`)) }
    catch (error) { if (!error.stderr?.toString().includes('HTTP 404')) throw error }
    if (remote) {
      const sha = remote.object.type === 'tag'
        ? JSON.parse(gh('api', `repos/${plan.repository}/git/tags/${remote.object.sha}`)).object.sha : remote.object.sha
      if (sha !== plan.sha) throw new Error('Release version already belongs to another commit.')
      console.log(`Reusing reserved ${plan.tag} for this commit.`)
    } else {
      gh('api', '--method', 'POST', `repos/${plan.repository}/git/refs`, '-f', `ref=refs/tags/${plan.tag}`, '-f', `sha=${plan.sha}`)
    }
  } else if (command === 'stamp') {
    const plan = readPlan(args[0])
    writeFileSync(join(root, 'version.txt'), plan.version + '\n')
    for (const name of ['package.json', 'package-lock.json']) {
      const path = join(root, 'web', 'client', name)
      const value = JSON.parse(readFileSync(path, 'utf8'))
      value.version = plan.version
      if (value.packages?.['']) value.packages[''].version = plan.version
      writeFileSync(path, JSON.stringify(value, null, 2) + '\n')
    }
  } else if (command === 'notes') {
    const [file, digest] = args
    const plan = readPlan(file)
    if (!/^sha256:[a-f0-9]{64}$/.test(digest)) throw new Error('Invalid image digest.')
    const directory = dirname(file)
    writeFileSync(join(directory, 'release-notes.md'), renderNotes(plan, digest))
    writeFileSync(join(directory, 'release-manifest.json'), JSON.stringify({ ...plan, digest }, null, 2) + '\n')
    writeFileSync(join(directory, 'image-digest.txt'), `${plan.image}@${digest}\n`)
  } else if (command === 'publish') {
    const plan = readPlan(args[0])
    const directory = dirname(args[0])
    let release
    try { release = JSON.parse(gh('api', `repos/${plan.repository}/releases/tags/${plan.tag}`)) }
    catch (error) { if (!error.stderr?.toString().includes('HTTP 404')) throw error }
    if (!release) {
      gh('release', 'create', plan.tag, '--repo', plan.repository, '--verify-tag', '--draft', '--title',
        `ROM Checker ${plan.version}${plan.prerelease ? ' — Beta' : ''}`, '--notes-file', join(directory, 'release-notes.md'),
        ...(plan.prerelease ? ['--prerelease'] : []))
    } else if (!release.draft) {
      if (release.prerelease !== plan.prerelease) throw new Error('Published release channel does not match.')
      const asset = release.assets.find(asset => asset.name === 'release-manifest.json')
      if (!asset) throw new Error('Published release has no immutable release manifest. Review it manually; refusing to replace assets.')
      const saved = gh('api', `repos/${plan.repository}/releases/assets/${asset.id}`,
        '-H', 'Accept: application/octet-stream')
      const manifest = JSON.parse(saved)
      const current = JSON.parse(readFileSync(join(directory, 'release-manifest.json'), 'utf8'))
      if (manifest.sha !== plan.sha || manifest.digest !== current.digest) throw new Error('Published release assets are immutable.')
      console.log('Release already published with the same commit and image digest.')
      return
    }
    gh('release', 'upload', plan.tag, '--repo', plan.repository, '--clobber',
      ...['release-manifest.json', 'image-digest.txt', 'SHA256SUMS'].map(name => join(directory, name)))
    const head = JSON.parse(gh('api', `repos/${plan.repository}/git/ref/heads/${plan.branch}`)).object.sha
    gh('release', 'edit', plan.tag, '--repo', plan.repository, '--draft=false', `--prerelease=${plan.prerelease}`,
      `--latest=${!plan.prerelease && head === plan.sha}`, '--notes-file', join(directory, 'release-notes.md'))
  } else {
    throw new Error('Usage: release.mjs validate [base] | development sha owner/repo build-number | plan branch sha owner/repo [directory] [published-tags.txt] | reserve/stamp/publish plan.json | notes plan.json digest')
  }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { run(process.argv[2], process.argv.slice(3)) }
  catch (error) { console.error(error.message); process.exitCode = 1 }
}
