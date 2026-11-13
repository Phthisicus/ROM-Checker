import { execFileSync } from 'node:child_process'

const branches = ['development', 'beta', 'main']
const args = process.argv.slice(2)
const apply = args.includes('--apply')
const branchIndex = args.indexOf('--branch')
const selected = branchIndex < 0 ? null : args[branchIndex + 1]
const repository = process.env.GITHUB_REPOSITORY || 'Phthisicus/ROM-Checker'
if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) throw new Error('Invalid repository name.')
if (args.some((arg, index) => !['--apply', '--confirm-emergency-access', '--branch'].includes(arg) && !(branchIndex >= 0 && index === branchIndex + 1))
  || (branchIndex >= 0 && !branches.includes(selected))
  || (apply && (!selected || !args.includes('--confirm-emergency-access'))))
  throw new Error('Use --apply --branch development|beta|main --confirm-emergency-access after preview and establishing emergency access.')

const desired = {
  required_status_checks: { strict: true, contexts: ['Required checks'] },
  enforce_admins: true,
  required_pull_request_reviews: {
    dismiss_stale_reviews: true,
    require_code_owner_reviews: false,
    required_approving_review_count: 0
  },
  restrictions: null,
  required_conversation_resolution: true,
  allow_force_pushes: false,
  allow_deletions: false
}
function api(endpoint) {
  return JSON.parse(execFileSync('gh', ['api', endpoint], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }))
}
function conforms(protection) {
  const checks = protection.required_status_checks
  const reviews = protection.required_pull_request_reviews
  return checks?.strict === true && checks.contexts?.includes('Required checks')
    && protection.enforce_admins?.enabled === true
    && reviews?.required_approving_review_count === 0
    && protection.required_conversation_resolution?.enabled === true
    && protection.allow_force_pushes?.enabled === false
    && protection.allow_deletions?.enabled === false
}
console.log(`Target: ${repository}. ${apply ? `Applying to ${selected}` : 'Previewing'} solo-maintainer branch protection.`)
console.log(JSON.stringify(desired, null, 2))
const failures = []
function check(label, fn) {
  try { fn(); console.log(`OK: ${label}`) }
  catch (error) {
    const detail = error.stderr?.toString().trim() || error.message
    failures.push(`${label}: ${detail}`)
    console.error(`BLOCKED: ${label}: ${detail}`)
  }
}
check('Actions permissions', () => {
  if (!api(`repos/${repository}/actions/permissions`).enabled) throw new Error('Actions are disabled.')
})
check('CI workflow enabled', () => {
  if (api(`repos/${repository}/actions/workflows/ci.yml`).state !== 'active') throw new Error('CI workflow is not active.')
})
check('Existing repository rulesets', () => {
  const rulesets = api(`repos/${repository}/rulesets?per_page=100`)
  if (rulesets.length) throw new Error('Review existing rulesets manually before applying protection.')
})
for (const branch of branches) {
  check(`${branch} branch and protection permission`, () => {
    const info = api(`repos/${repository}/branches/${branch}`)
    if (info.protected) {
      const protection = api(`repos/${repository}/branches/${branch}/protection`)
      if (branch === selected) throw new Error('Branch already protected; refusing to overwrite it.')
      if (!conforms(protection)) throw new Error('Existing protection differs from the required policy; review it manually.')
      console.log(`${branch} already has the required baseline; existing protection will not be changed.`)
      return
    }
    try {
      api(`repos/${repository}/branches/${branch}/protection`)
      throw new Error('Branch already has protection; refusing to overwrite it.')
    } catch (error) {
      if (!error.stderr?.toString().includes('HTTP 404')) throw error
    }
  })
  check(`${branch} CI workflow`, () => {
    const file = api(`repos/${repository}/contents/.github/workflows/ci.yml?ref=${branch}`)
    const source = Buffer.from(file.content, 'base64').toString('utf8')
    if (!/^\s{2}pull_request:\s*$/m.test(source) || !/^\s{4}name:\s*Required checks\s*$/m.test(source))
      throw new Error('Required PR check is missing from this branch.')
  })
}
if (failures.length) {
  console.error('Preflight failed. No settings changed.')
  process.exitCode = 1
} else if (apply) {
  if (api(`repos/${repository}/branches/${selected}`).protected)
    throw new Error(`${selected} became protected during preflight; refusing to overwrite it.`)
  execFileSync('gh', ['api', '--method', 'PUT', `repos/${repository}/branches/${selected}/protection`, '--input', '-'],
    { input: JSON.stringify(desired), encoding: 'utf8', stdio: ['pipe', 'inherit', 'inherit'] })
  console.log(`Applied ${selected}. Verify it and test blocking before proceeding to the next branch.`)
} else {
  console.log('No settings changed. Establish emergency access and apply one branch at a time.')
}
