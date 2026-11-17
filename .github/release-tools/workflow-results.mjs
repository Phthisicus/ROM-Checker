import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

function entries(results) {
  if (!results || typeof results !== 'object' || Array.isArray(results))
    throw new Error('Workflow results must be a JSON object.')
  return Object.entries(results)
}

function summarize(title, results, expected) {
  const rows = entries(results)
  const failures = []
  for (const [name, status] of Object.entries(expected)) {
    const actual = results[name]?.result
    if (!actual) failures.push(`- ${name}: missing result (expected ${status})`)
    else if (!status.includes(actual)) failures.push(`- ${name}: ${actual} (expected ${status.join(' or ')})`)
  }
  for (const [name] of rows)
    if (!Object.hasOwn(expected, name)) failures.push(`- ${name}: unexpected workflow job`)
  const lines = [`## ${title}`, '', ...rows.map(([name, value]) => `- ${name}: ${value.result ?? 'missing'}`)]
  if (failures.length) {
    lines.push('', '### Required gates not satisfied', ...failures)
    return { passed: false, summary: lines.join('\n') }
  }
  lines.push('', 'All required gates passed.')
  return { passed: true, summary: lines.join('\n') }
}

export function evaluateCiResults(results, eventName, eventAction, priorChecks = 'not-needed') {
  const expected = {
    'release-policy': ['success'],
    dependencies: ['success'],
    application: ['success'],
    'windows-engine': ['success'],
    container: ['success']
  }
  if (eventName === 'pull_request' && eventAction === 'edited') {
    expected.dependencies.push('skipped')
    expected.application.push('skipped')
    expected['windows-engine'].push('skipped')
    expected.container.push('skipped')
  } else if (eventName !== 'pull_request') {
    expected.container = ['skipped']
  }
  const summary = summarize('Required CI checks', results, expected)
  if (eventName === 'pull_request' && eventAction === 'edited' && priorChecks !== 'true') {
    summary.passed = false
    summary.summary = summary.summary.replace(/\n\nAll required gates passed\.$/, '')
    summary.summary += `\n\n### Required gates not satisfied\n- previous-full-checks: ${priorChecks === 'false' ? 'no successful Required checks run exists for this commit' : 'could not verify prior checks'}`
  }
  return summary
}

export function evaluateDeliveryResults(results, branch) {
  const expected = {
    checks: ['success'],
    'development-image': branch === 'development' ? ['success'] : ['skipped'],
    publish: ['beta', 'main'].includes(branch) ? ['success'] : ['skipped']
  }
  if (!['development', 'beta', 'main'].includes(branch))
    throw new Error(`Unsupported delivery branch: ${branch}`)
  return summarize(`Delivery result for ${branch}`, results, expected)
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [, , mode, value, actionOrResults, maybeResults] = process.argv
    const result = mode === 'ci'
      ? evaluateCiResults(JSON.parse(maybeResults), value, actionOrResults, process.argv[6])
      : mode === 'delivery'
        ? evaluateDeliveryResults(JSON.parse(actionOrResults), value)
        : (() => { throw new Error('Usage: workflow-results.mjs ci event action results.json | delivery branch results.json') })()
    console.log(result.summary)
    if (!result.passed) {
      console.error('::error::One or more required workflow gates did not pass.')
      process.exitCode = 1
    }
  } catch (error) {
    console.error(error.message)
    process.exitCode = 1
  }
}

