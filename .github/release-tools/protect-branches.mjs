import { execFileSync } from 'node:child_process'

const apply = process.argv.includes('--apply')
const repository = process.env.GITHUB_REPOSITORY ?? 'Phthisicus/ROM-Checker'
if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) throw new Error('Invalid repository name.')
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
console.log(`Target: ${repository}. ${apply ? 'Applying' : 'Previewing'} solo-maintainer branch protection.`)
for (const branch of ['development', 'beta', 'main']) {
  if (!apply) { console.log(branch, JSON.stringify(desired, null, 2)); continue }
  const endpoint = `repos/${repository}/branches/${branch}/protection`
  let existing
  try { existing = JSON.parse(execFileSync('gh', ['api', endpoint], { encoding: 'utf8' })) }
  catch (error) {
    if (!error.stderr?.toString().includes('HTTP 404')) throw error
  }
  if (existing) throw new Error(`${branch} already has protection. Review it in GitHub; this command will not overwrite existing policy.`)
  execFileSync('gh', ['api', '--method', 'PUT', endpoint, '--input', '-'],
    { input: JSON.stringify(desired), encoding: 'utf8', stdio: ['pipe', 'inherit', 'inherit'] })
}
if (!apply) console.log('No settings changed. Add --apply after the workflows are installed on all three branches. Private-repository protection may require GitHub Pro.')
