import assert from 'node:assert/strict'
import { createHash, randomUUID } from 'node:crypto'
import { createServer } from 'node:http'
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawn } from 'node:child_process'

const root = await mkdtemp(join(tmpdir(), 'romchecker-romm-'))
const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const dotnet = process.env.ROMCHECKER_DOTNET || 'dotnet'
const powershell = process.env.ROMCHECKER_POWERSHELL || (process.platform === 'win32' ? 'powershell.exe' : 'pwsh')
const assembly = join(repo, 'web', 'server', 'bin', 'Debug', 'net10.0', 'RomChecker.Web.dll')
const library = join(root, 'legacy')
const storageRoot = join(root, 'storage')
const exportRoot = join(storageRoot, 'romm-library')
await mkdir(library)
const token = 'rmm_fixture_only_not_a_real_secret_1234567890'
const password = 'romm-fixture-app-password'
const logs = []
const children = []
let cookie = ''
let base
let assertions = 0
let scans = 0
let failScan = false
let hashGate
let downloadGate
let failRemoteList = false
const discoveryOffsets = []
const remote = new Map()
const fixture = Buffer.alloc(40976)
fixture.set([0x4e, 0x45, 0x53, 0x1a, 2, 1])
const imported = Buffer.from(fixture)
imported[100] = 23
const hash = (buffer, algorithm) => createHash(algorithm).update(buffer).digest('hex').toUpperCase()
const pause = ms => new Promise(resolve => setTimeout(resolve, ms))
const check = (condition, message) => { assert.ok(condition, message); assertions++ }
async function files(path) {
  let entries
  try { entries = await readdir(path, { withFileTypes: true }) } catch (error) { if (error.code === 'ENOENT') return []; throw error }
  return (await Promise.all(entries.map(entry => entry.isDirectory() ? files(join(path, entry.name)) : join(path, entry.name)))).flat()
}
function metadata(id, name, data, path = '') {
  return { id, name, fs_name: name, fs_path: 'roms/nes', full_path: 'roms/nes/' + name,
    platform_id: 1, platform_slug: 'nes', summary: 'Synthetic RomM metadata fixture', path_cover_small: '/artwork/fixture.png',
    sha1_hash: hash(data, 'sha1'), md5_hash: hash(data, 'md5'), metadatum: { genres: ['Fixture'], companies: ['Synthetic'] },
    files: [{ id: id * 10, file_name: name, file_path: path || 'roms/nes', file_size_bytes: data.length, sha1_hash: hash(data, 'sha1') }],
    data }
}
remote.set(900, metadata(900, 'Imported.nes', imported))
const fixtureServer = createServer(async (request, response) => {
  try {
    if (request.headers.authorization !== `Bearer ${token}`) { response.writeHead(401).end(); return }
    const url = new URL(request.url, 'http://fixture')
    const send = (value, status = 200) => { response.writeHead(status, { 'Content-Type': 'application/json' }); response.end(JSON.stringify(value)) }
    const publicRom = ({ data, ...rest }) => rest
    if (url.pathname === '/openapi.json') return send({ info: { version: 'fixture-only' }, paths: { '/api/tasks/scan': {}, '/api/roms/by-hash': {} } })
    if (url.pathname === '/artwork/fixture.png') {
      response.writeHead(200, { 'Content-Type': 'image/png' })
      response.end(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64'))
      return
    }
    if (url.pathname === '/api/platforms') return send([{ id: 1, name: 'Nintendo Entertainment System', slug: 'nes', fs_slug: 'nes' }])
    if (url.pathname === '/api/tasks/scan') {
      scans++
      if (failScan) { failScan = false; return send({ detail: 'fixture busy' }, 409) }
      for (const path of await files(join(exportRoot, 'roms'))) {
        const data = await readFile(path)
        const id = 100 + remote.size
        remote.set(id, metadata(id, path.split(/[\\/]/).at(-1), data))
      }
      return send({ task_id: 'fixture-scan' }, 202)
    }
    if (url.pathname === '/api/roms/by-hash') {
      if (hashGate && url.searchParams.get('sha1_hash') === hash(fixture, 'sha1')) {
        hashGate.entered = true
        await hashGate.wait
      }
      const found = [...remote.values()].find(rom => rom.sha1_hash.toLowerCase() === url.searchParams.get('sha1_hash')?.toLowerCase())
      return found ? send(publicRom(found)) : send({ detail: 'not found' }, 404)
    }
    if (url.pathname === '/api/roms') {
      if (failRemoteList) return send({ detail: 'fixture unavailable' }, 503)
      const offset = Number(url.searchParams.get('offset') || 0)
      discoveryOffsets.push(offset)
      const limit = Math.min(Number(url.searchParams.get('limit') || 50), 2)
      return send({ items: [...remote.values()].sort((a, b) => a.id - b.id).slice(offset, offset + limit).map(publicRom), total: remote.size })
    }
    const match = url.pathname.match(/^\/api\/roms\/(\d+)(\/content\/.+)?$/)
    if (match) {
      const rom = remote.get(Number(match[1]))
      if (!rom) return send({ detail: 'not found' }, 404)
      if (match[2]) {
        if (downloadGate?.id === rom.id) { downloadGate.entered = true; await downloadGate.wait }
        response.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Length': rom.data.length })
        response.end(rom.data); return
      }
      return send(publicRom(rom))
    }
    send({ detail: 'unknown fixture endpoint' }, 404)
  } catch (error) { response.writeHead(500).end(error.message) }
})
await new Promise(resolve => fixtureServer.listen(0, '127.0.0.1', resolve))
const remoteUrl = `http://127.0.0.1:${fixtureServer.address().port}`
async function port() {
  const server = createServer()
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  const value = server.address().port
  await new Promise(resolve => server.close(resolve))
  return value
}
async function launch(role, listen) {
  const child = spawn(dotnet, [assembly], { cwd: repo, env: { ...process.env,
    ASPNETCORE_URLS: listen, ROMCHECKER_ROLE: role, ROMCHECKER_STORAGE_URL: storageUrl,
    ROMCHECKER_STORAGE_ROOT: storageRoot, ROMCHECKER_STORAGE_TOKEN: 'romm-fixture-storage-token-1234567890',
    ROMCHECKER_STORAGE_RESERVE_BYTES: '0', ROMCHECKER_ROMM_EXPORT_ROOT: exportRoot,
    ROMCHECKER_LIBRARY: library, ROMCHECKER_DATA: join(root, 'data'), ROMCHECKER_ENGINE: repo,
    ROMCHECKER_PASSWORD: password, ROMCHECKER_PATH_BASE: '', ROMCHECKER_POWERSHELL: powershell } })
  children.push(child)
  child.stdout.on('data', data => logs.push(data.toString()))
  child.stderr.on('data', data => logs.push(data.toString()))
  for (let attempt = 0; attempt < 600; attempt++) {
    if (child.exitCode !== null) throw new Error('Fixture process exited: ' + logs.join('').slice(-8000))
    try { if ((await fetch(listen + '/healthz', { signal: AbortSignal.timeout(2000) })).ok) return child } catch { /* Startup probe only. */ }
    await pause(100)
  }
  throw new Error('Fixture server never became healthy: ' + logs.join('').slice(-8000))
}
async function api(path, method = 'GET', body, expected = 200) {
  const response = await fetch(base + '/api' + path, { method, headers: { Cookie: cookie, 'X-RomChecker': '1',
    ...(body === undefined || Buffer.isBuffer(body) ? {} : { 'Content-Type': 'application/json' }) },
    body: body === undefined ? undefined : Buffer.isBuffer(body) ? body : JSON.stringify(body) })
  const text = await response.text()
  assert.equal(response.status, expected, `${method} ${path}: ${text}`)
  return text ? JSON.parse(text) : null
}
async function until(work, predicate, message, attempts = 240) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const result = await work()
    if (predicate(result)) return result
    await pause(250)
  }
  throw new Error('Timed out: ' + message)
}
async function job(action, batchId, settings) {
  const created = await api('/jobs', 'POST', { action, batchId, settings, confirm: true, organize: action === 'verify' }, 202)
  const result = await until(() => api(`/jobs/${created.id}`), value => !['queued', 'running'].includes(value.job.status), action)
  check(['completed', 'completed-with-warnings'].includes(result.job.status), `${action} completed: ${result.job.error}`)
}
async function upload(name, data) {
  const batch = await api('/storage/batches', 'POST', { name })
  const upload = await api(`/storage/batches/${batch.id}/uploads`, 'POST', { path: name + '.nes', size: data.length, modified: 1 })
  await api(`/storage/batches/${batch.id}/uploads/${upload.id}?offset=0`, 'PUT', data)
  await api(`/storage/batches/${batch.id}/prepare`, 'POST', undefined, 202)
  await until(() => api(`/storage/batches/${batch.id}`), value => value.status === 'ready', 'preparation')
  await job('detect', batch.id)
  return batch
}
const settings = { defenderScan: false, autoDat: false, hasheous: 'Off', identifyUnknown: false, onlineCheck: 'Off', requireDatMatch: false,
  retailOnly: false, duplicateMode: 'Report' }
const storageUrl = `http://127.0.0.1:${await port()}`
try {
  const storageProcess = await launch('storage', storageUrl)
  base = `http://127.0.0.1:${await port()}`
  let application = await launch('', base)
  const login = await fetch(base + '/api/login', { method: 'POST', headers: { 'X-RomChecker': '1', 'Content-Type': 'application/json' }, body: JSON.stringify({ password }) })
  assert.equal(login.status, 200)
  cookie = login.headers.get('set-cookie').split(';')[0]
  const allocationId = randomUUID().replaceAll('-', '')
  async function allocate(name) {
    return fetch(storageUrl + '/internal/batches', { method: 'POST',
      headers: { Authorization: 'Bearer romm-fixture-storage-token-1234567890', 'Content-Type': 'application/json', 'Idempotency-Key': allocationId },
      body: JSON.stringify({ name }) })
  }
  const allocation = await (await allocate('Restart-safe allocation')).json()
  const repeatedAllocation = await (await allocate('Restart-safe allocation')).json()
  check(allocation.id === allocationId && repeatedAllocation.id === allocation.id,
    'Interrupted batch-allocation retries reuse the same storage import rather than orphaning another batch')
  check((await allocate('Different allocation')).status === 409, 'Allocation keys cannot be reused for a different import')
  const storageExited = new Promise(resolve => storageProcess.once('exit', resolve))
  storageProcess.kill()
  await storageExited
  await launch('storage', storageUrl)
  check((await (await allocate('Restart-safe allocation')).json()).id === allocationId,
    'Storage allocation keys persist across a storage-process restart')
  await api(`/storage/batches/${allocationId}`, 'DELETE', undefined, 204)
  await api('/romm/config', 'PUT', { url: remoteUrl, token, platformMappings: [{ console: 'NES', platformId: 1, slug: 'nes' }] }, 204)
  const config = await api('/romm/config')
  check(config.configured && !JSON.stringify(config).includes(token), 'Connection never exposes its API token')
  const connection = await api('/romm/test', 'POST')
  check(connection.compatible && connection.platforms[0].id === 1, 'Capability and platform negotiation use real HTTP')
  const batch = await upload('Checked fixture', fixture)
  await api('/catalog/refresh', 'POST')
  let catalog = await api('/catalog')
  let entry = catalog.items.find(item => item.batchId === batch.id)
  check(!!entry, 'Existing import migrates to canonical library')
  const preview = await api('/romm/preview', 'POST', { ids: [entry.id] })
  check(preview.eligible.length === 0 && preview.blocked.length === 1, 'Unchecked ROM cannot be published')
  await api('/romm/publish', 'POST', { ids: [entry.id], confirm: true }, 409)
  await job('verify', batch.id, settings)
  // Fixture-only antivirus evidence: actual scanner availability is covered by engine tests.
  // The protocol test must exercise strict publication policy without requiring host AV.
  const manifestPath = join(storageRoot, 'batches', batch.id, 'processed', '_RomSorter', 'collection.json')
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'))
  for (const row of manifest) {
    row.AntivirusStatus = 'Completed - no detections'
    row.CheckPolicy = { ...row.CheckPolicy, DefenderScan: true }
  }
  await writeFile(manifestPath, JSON.stringify(manifest))
  await api('/catalog/refresh', 'POST')
  catalog = await api('/catalog')
  entry = catalog.items.find(item => item.batchId === batch.id)
  check(entry.checkedUtc?.length > 0, 'Completed checks survive catalog reconciliation')
  const review = await api('/romm/preview', 'POST', { ids: [entry.id] })
  check(review.blocked.length === 1, 'Checked files without a reference still require explicit review')
  await api('/catalog/approve', 'POST', { ids: [entry.id], sha256: { [entry.id]: entry.sha256 }, reason: 'Synthetic NES fixture: accept missing reference after completed local checks.', confirm: true })
  const after = await api('/romm/preview', 'POST', { ids: [entry.id] })
  check(after.eligible.length === 1, 'Checked policy-eligible ROM is publishable')
  const savedConnection = { url: remoteUrl, platformMappings: [{ console: 'NES', platformId: 1, slug: 'nes' }] }
  const options = await api('/romm/publish-options')
  check(options.regions.includes('Europe') && options.imports.some(item => item.id === batch.id) && options.consoles.includes('NES'),
    'Rule options expose normalized regions, console keys and named imports')
  const strictRules = { referenceRequirement: 'matched', consoles: ['NES'], regions: [], categories: [], batchIds: [batch.id] }
  const strictPreview = await api('/romm/auto-publish/preview', 'POST', { rules: strictRules })
  check(strictPreview.total === 1 && strictPreview.excluded === 1 && strictPreview.items[0].reason.includes('reference match'),
    'Reference-only rules exclude manually approved files without a reference')
  check((await api('/romm/config')).publishRules.referenceRequirement === 'eligible' && (await api('/romm/jobs')).length === 0,
    'Draft rule preview neither persists settings nor queues publication')
  await api('/romm/auto-publish/preview', 'POST', { page: 0 }, 400)
  await api('/romm/auto-publish/preview', 'POST', { size: 201 }, 400)
  await api('/romm/auto-publish/preview', 'POST', { rules: { regions: ['Atlantis'] } }, 400)
  await api('/romm/config', 'PUT', { ...savedConnection, publishRules: { referenceRequirement: 'unchecked' } }, 400)
  const readyRules = { referenceRequirement: 'eligible', consoles: ['NES'], regions: [], categories: [], batchIds: [batch.id] }
  const readyPreview = await api('/romm/auto-publish/preview', 'POST', { rules: readyRules, size: 1 })
  check(readyPreview.ready === 1 && readyPreview.items[0].files === 1 && readyPreview.size === 1,
    'Preview evaluates complete games and returns bounded paginated results')
  hashGate = { entered: false, wait: null, release: null }
  hashGate.wait = new Promise(resolve => { hashGate.release = resolve })
  await api('/romm/config', 'PUT', { ...savedConnection, autoPublish: true, publishRules: readyRules }, 204)
  await until(async () => hashGate.entered, entered => entered, 'automatic publication reaches transfer')
  const automatic = (await api('/romm/jobs')).find(item => item.automatic)
  check(automatic?.kind === 'publish' && automatic.items[0].entryId === entry.id,
    'Scheduler durably queues automatic publication using the saved rules')
  check((await api('/romm/auto-publish/preview', 'POST', { rules: readyRules })).pending === 1,
    'Preview distinguishes pending work from games ready to queue')
  await api('/romm/config', 'PUT', { ...savedConnection, autoPublish: true, publishRules: strictRules }, 204)
  hashGate.release()
  hashGate = undefined
  await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === automatic.id && item.status === 'completed-with-errors'), 'changed rule gate')
  check((await files(join(exportRoot, 'roms'))).length === 0, 'Rules changed during remote lookup block staged export promotion')
  const failedPreview = await api('/romm/auto-publish/preview', 'POST', { rules: readyRules })
  check(failedPreview.failed === 1 && failedPreview.ready === 0, 'Failed automatic work requires explicit retry rather than endless requeueing')
  await api('/romm/config', 'PUT', { ...savedConnection, autoPublish: true, publishRules: readyRules }, 204)
  hashGate = { entered: false, wait: null, release: null }
  hashGate.wait = new Promise(resolve => { hashGate.release = resolve })
  await api(`/romm/jobs/${automatic.id}/retry`, 'POST')
  await until(async () => hashGate.entered, entered => entered, 'automatic retry reaches transfer')
  await api('/romm/config', 'PUT', { ...savedConnection, autoPublish: false, publishRules: readyRules }, 204)
  hashGate.release()
  hashGate = undefined
  await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === automatic.id && item.status === 'completed-with-errors'), 'disabled auto-publish gate')
  check((await files(join(exportRoot, 'roms'))).length === 0, 'Disabling automatic publication prevents an in-flight new export')
  await api('/romm/config', 'PUT', { ...savedConnection, autoPublish: true, publishRules: readyRules }, 204)
  failScan = true
  const publish = await api(`/romm/jobs/${automatic.id}/retry`, 'POST')
  const failed = await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === publish.id && item.status === 'failed'), 'scan conflict')
  check(failed.find(item => item.id === publish.id).error.length > 0, 'Remote scan failure is explicit and retryable')
  check((await api('/catalog?syncStatus=failed')).ids.includes(entry.id), 'Failed publication is visible in the canonical synchronization filter')
  await api('/romm/config', 'PUT', { ...savedConnection, autoPublish: false, publishRules: strictRules }, 204)
  await api(`/romm/jobs/${publish.id}/retry`, 'POST')
  await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === publish.id && item.status === 'completed'), 'publish and metadata linking')
  const links = await api('/romm/links')
  check(links.some(link => link.entryId === entry.id && link.metadata.summary === 'Synthetic RomM metadata fixture'), 'Exact hash links imported descriptive metadata')
  const artwork = await fetch(base + `/api/romm/artwork/${entry.id}`, { headers: { Cookie: cookie } })
  check(artwork.ok && artwork.headers.get('content-type') === 'image/png' && (await artwork.arrayBuffer()).byteLength > 0,
    'Linked cover artwork is fetched through the authenticated same-origin proxy')
  const publishedFiles = await files(join(exportRoot, 'roms'))
  check(publishedFiles.length === 1 && hash(await readFile(publishedFiles[0]), 'sha256') === entry.sha256, 'Published copy matches checked bytes; retries create no duplicates')
  const manual = await api('/romm/publish', 'POST', { ids: [entry.id], confirm: true })
  check(!manual.automatic, 'Manual publication remains explicitly confirmed and independent of automatic filters')
  await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === manual.id && item.status === 'completed'), 'manual publication with restrictive automatic rules')
  check((await files(join(exportRoot, 'roms'))).length === 1, 'Manual publication reuses current remote content without duplicate copies')
  const linkedPreview = await api('/romm/auto-publish/preview', 'POST', { rules: readyRules })
  check(linkedPreview.linked === 1 && linkedPreview.ready === 0, 'Preview distinguishes current links from new publication candidates')
  await api('/romm/config', 'PUT', { ...savedConnection }, 204)
  check((await api('/romm/config')).publishRules.referenceRequirement === 'matched', 'Older configuration clients preserve saved rules when omitting them')
  const exited = new Promise(resolve => application.once('exit', resolve))
  application.kill()
  await exited
  application = await launch('', base)
  check((await api('/romm/config')).publishRules.referenceRequirement === 'matched'
    && (await api('/romm/jobs')).some(item => item.id === automatic.id && item.automatic),
  'Saved rules and automatic job provenance survive an application restart')
  const original = join(storageRoot, 'batches', batch.id, 'originals', 'Checked fixture.nes')
  check(hash(await readFile(original), 'sha256') === hash(fixture, 'sha256'), 'Publishing preserves original uploads')
  const history = await api(`/catalog/${entry.id}/history`)
  check(JSON.stringify(history).includes('romm-exported'), 'Publication is recorded in canonical audit history')
  const receive = await api('/romm/import', 'POST', { romIds: [900], confirm: true })
  const received = await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === receive.id && item.status === 'completed'), 'remote import')
  const importBatch = received.find(item => item.id === receive.id).items[0].batchId
  await until(() => api(`/storage/batches/${importBatch}`), value => value.status === 'ready', 'remote preparation')
  await api('/catalog/refresh', 'POST')
  const incoming = (await api('/catalog')).items.find(item => item.batchId === importBatch)
  check(incoming && incoming.console === 'NES' && !incoming.checkedUtc, 'RomM received files are automatically console-detected and enter the same library unchecked')
  const incomingPreview = await api('/romm/preview', 'POST', { ids: [incoming.id] })
  check(incomingPreview.eligible.length === 0, 'Imported metadata never bypasses verification')
  check((await api('/romm/links')).some(link => link.entryId === incoming.id && link.rommId === 900 && link.status === 'linked'),
    'Completed inbound imports establish exact-content links without approving files')
  await api('/romm/import', 'POST', { romIds: [900], confirm: true }, 409)
  await api('/romm/sync', 'POST', { ids: [], confirm: true }, 409)
  await api('/romm/config', 'PUT', { ...savedConnection, sync: { autoImport: true, platformIds: [] } }, 400)
  await api('/romm/config', 'PUT', { ...savedConnection, sync: { autoImport: true, platformIds: [2] } }, 400)
  await api('/romm/config', 'PUT', { ...savedConnection, sync: { intervalMinutes: 0 } }, 400)
  const baselineBatches = (await api('/storage/batches')).length
  remote.set(902, metadata(902, 'Existing content with another name.nes', fixture))
  const discoveredBytes = Buffer.from(imported)
  discoveredBytes[100] = 55
  remote.set(903, metadata(903, 'Discovered.nes', discoveredBytes))
  remote.set(904, metadata(904, 'Same discovered content.nes', discoveredBytes))
  const excludedBytes = Buffer.from(imported)
  excludedBytes[100] = 66
  remote.set(905, { ...metadata(905, 'Unselected platform.nes', excludedBytes), platform_id: 2 })
  const unhashed = metadata(906, 'Missing hashes.nes', excludedBytes)
  unhashed.files[0].sha1_hash = ''
  remote.set(906, unhashed)
  const syncSettings = { autoImport: true, platformIds: [1], refreshMetadata: true, intervalMinutes: 1 }
  await api('/romm/config', 'PUT', { ...savedConnection, sync: syncSettings }, 204)
  const firstSync = await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.kind === 'sync' && item.finished), 'automatic discovery scheduling')
  check(firstSync.some(item => item.kind === 'sync' && item.automatic), 'Opted-in discovery is scheduled automatically')
  const discoveryJobs = await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.kind === 'import'
    && item.automatic && item.items.some(file => file.rommId === 903) && item.status === 'completed'), 'automatic inbound completion')
  const discoveryJob = discoveryJobs.find(item => item.kind === 'import' && item.items.some(file => file.rommId === 903))
  check(discoveryJob.items[0].remoteSnapshot.files[0].sha1 === hash(discoveredBytes, 'sha1')
    && discoveryJob.items[0].remoteSnapshot.fingerprint.length === 64, 'Import identity evidence persists with the durable work')
  const discoveryBatch = discoveryJob.items[0].batchId
  const discoveredEntry = (await api('/catalog')).items.find(item => item.batchId === discoveryBatch)
  check(discoveredEntry && !discoveredEntry.checkedUtc && !discoveredEntry.publishEligible, 'Automatically imported games remain unchecked and ineligible')
  check((await api('/storage/batches')).length === baselineBatches + 1,
    'Local duplicates, remote aliases and concurrent identical remote content do not create extra imports')
  check(discoveryOffsets.includes(2) && discoveryOffsets.includes(4),
    'Discovery follows offset pagination even when RomM caps pages below the requested size')
  check(!(await api('/romm/jobs')).some(item => item.kind === 'import' && item.items.some(file => file.rommId === 905 || file.rommId === 906)),
    'Unselected platforms and games without exact file hashes are never automatically imported')
  check((await api('/romm/conflicts')).some(item => item.rommId === 906 && /hashes/.test(item.detail)),
    'Missing remote hash evidence is an explicit reviewable conflict')
  async function syncNow() {
    const queued = await api('/romm/sync', 'POST', { ids: [], confirm: true })
    return (await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === queued.id && item.finished), 'explicit reconciliation pass'))
      .find(item => item.id === queued.id)
  }
  await api('/romm/conflicts/906', 'POST', { action: 'keep-local', confirm: true }, 204)
  await syncNow()
  check((await api('/romm/conflicts')).some(item => item.rommId === 906 && item.status === 'ignored'),
    'Unindexed remote games can be explicitly ignored without pretending their hashes are complete')
  remote.set(906, metadata(906, 'Missing hashes.nes', excludedBytes))
  await syncNow()
  await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.kind === 'import'
    && item.items.some(file => file.rommId === 906) && item.status === 'completed'), 'repaired remote hash evidence')
  check(!(await api('/romm/conflicts')).some(item => item.rommId === 906),
    'A repaired and scanned remote game can import after its earlier missing-evidence conflict')
  await syncNow()
  check((await api('/storage/batches')).length === baselineBatches + 2, 'Repeated discovery reuses completed content instead of creating duplicates')
  remote.get(900).summary = 'Manual metadata update'
  const manualMetadata = await api('/romm/metadata', 'POST', { ids: [incoming.id], confirm: true })
  await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === manualMetadata.id && item.status === 'completed'),
    'manual refresh of existing exact-content link')
  check((await api('/romm/links')).some(link => link.entryId === incoming.id && link.rommId === 900 && link.metadata.summary === 'Manual metadata update'),
    'Manual metadata refresh uses the existing remote identity even for unchecked imports')
  remote.get(900).summary = 'Scheduled metadata update'
  const previousSyncIds = new Set((await api('/romm/jobs')).filter(item => item.kind === 'sync').map(item => item.id))
  await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.kind === 'sync' && !previousSyncIds.has(item.id) && item.finished),
    'scheduled metadata reconciliation', 480)
  check((await api('/romm/links')).some(link => link.entryId === incoming.id && link.metadata.summary === 'Scheduled metadata update'),
    'Metadata refresh runs on its saved schedule without a per-game request')
  check(!(await api(`/catalog/${incoming.id}`)).checkedUtc, 'Scheduled descriptive metadata does not change verification')
  const beforeRestart = (await api('/romm/jobs')).filter(item => item.kind === 'sync').length
  const syncExited = new Promise(resolve => application.once('exit', resolve))
  application.kill()
  await syncExited
  application = await launch('', base)
  await pause(12000)
  check((await api('/romm/jobs')).filter(item => item.kind === 'sync').length === beforeRestart,
    'Persistent schedule does not run immediately again after a restart')
  await syncNow()
  check((await api('/storage/batches')).length === baselineBatches + 2, 'Remote identity and alias deduplication survive restart')
  const changedRemoteBytes = Buffer.from(imported)
  changedRemoteBytes[100] = 77
  remote.set(900, metadata(900, 'Imported.nes', changedRemoteBytes))
  const conflictingMetadata = await api('/romm/metadata', 'POST', { ids: [incoming.id], confirm: true })
  await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === conflictingMetadata.id && item.status === 'completed-with-errors'),
    'manual metadata identity conflict')
  check((await api('/romm/links')).some(link => link.entryId === incoming.id && link.metadata.summary === 'Scheduled metadata update'),
    'Manual refresh cannot overwrite the metadata baseline of changed remote files')
  await syncNow()
  check((await api('/romm/conflicts')).some(item => item.rommId === 900 && item.status === 'conflict' && /Remote files/.test(item.detail)),
    'Changed remote content becomes a conflict instead of silently replacing local files')
  check(hash(await readFile(join(storageRoot, 'batches', importBatch, 'processed', incoming.relativePath)), 'sha256') === incoming.sha256,
    'Remote changes preserve the original local copy')
  await api('/romm/conflicts/900', 'POST', { action: 'keep-local', confirm: false }, 400)
  await api('/romm/conflicts/900', 'POST', { action: 'keep-local', confirm: true }, 204)
  await syncNow()
  check((await api('/romm/conflicts')).some(item => item.rommId === 900 && item.status === 'ignored'), 'Keeping local content suppresses only the current remote version')
  changedRemoteBytes[100] = 78
  remote.set(900, metadata(900, 'Imported.nes', changedRemoteBytes))
  await syncNow()
  check((await api('/romm/conflicts')).some(item => item.rommId === 900 && item.status === 'conflict'), 'A further remote change reopens a previously ignored conflict')
  const separate = await api('/romm/import', 'POST', { romIds: [900], confirm: true, importChanged: true })
  const separateJobs = await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === separate.id && item.status === 'completed'), 'separate changed version import')
  const separateBatch = separateJobs.find(item => item.id === separate.id).items[0].batchId
  check(separateBatch !== importBatch && !(await api('/catalog')).items.find(item => item.batchId === separateBatch).checkedUtc,
    'Explicit remote-version import creates a separate unchecked copy and preserves old history')
  remote.delete(903)
  await syncNow()
  check((await api('/romm/conflicts')).some(item => item.rommId === 903 && item.status === 'conflict'), 'Missing remote games become conflicts without local deletion')
  check((await api(`/storage/batches/${discoveryBatch}`)).prepared, 'Remote deletion never removes the managed local import')
  remote.set(903, metadata(903, 'Discovered.nes', discoveredBytes))
  await syncNow()
  check(!(await api('/romm/conflicts')).some(item => item.rommId === 903), 'Restoring matching content and rechecking clears a conflict')
  const separateEntry = (await api('/catalog')).items.find(item => item.batchId === separateBatch)
  const separatePath = join(storageRoot, 'batches', separateBatch, 'processed', separateEntry.relativePath)
  const savedSeparateBytes = await readFile(separatePath)
  await rm(separatePath)
  await syncNow()
  check((await api('/romm/conflicts')).some(item => item.rommId === 900 && /missing/i.test(item.detail)),
    'Missing physical local files produce a conflict rather than redownload or remote deletion')
  await writeFile(separatePath, savedSeparateBytes)
  await api('/catalog/refresh', 'POST')
  const locallyChanged = Buffer.from(savedSeparateBytes)
  locallyChanged[101] = 99
  await writeFile(separatePath, locallyChanged)
  await syncNow()
  check((await api('/romm/conflicts')).some(item => item.rommId === 900 && /Local/.test(item.detail)), 'Physical local edits are detected even before a catalog refresh')
  await writeFile(separatePath, savedSeparateBytes)
  await api('/catalog/refresh', 'POST')
  await syncNow()
  check(!(await api('/romm/conflicts')).some(item => item.rommId === 900), 'Restoring the original local bytes permits safe metadata linking again')
  const conflictsBeforeOutage = (await api('/romm/conflicts')).length
  failRemoteList = true
  const outage = await syncNow()
  check(outage.status === 'failed' && (await api('/romm/conflicts')).length === conflictsBeforeOutage,
    'Remote outages are failed jobs, not inferred file deletions or new conflicts')
  failRemoteList = false
  const blockedBytes = Buffer.from(imported)
  blockedBytes[100] = 88
  remote.set(907, metadata(907, 'Policy checkpoint.nes', blockedBytes))
  await api('/romm/config', 'PUT', { ...savedConnection, sync: { ...syncSettings, autoImport: false } }, 204)
  await syncNow()
  check(!(await api('/romm/jobs')).some(item => item.kind === 'import' && item.items.some(file => file.rommId === 907)),
    'Metadata-only scheduling never imports newly discovered remote games')
  await api('/romm/config', 'PUT', { ...savedConnection, sync: syncSettings }, 204)
  downloadGate = { id: 907, entered: false, wait: null, release: null }
  downloadGate.wait = new Promise(resolve => { downloadGate.release = resolve })
  await syncNow()
  await until(async () => downloadGate.entered, entered => entered, 'automatic download reaches checkpoint')
  await api('/romm/config', 'PUT', { ...savedConnection, sync: { ...syncSettings, autoImport: false, refreshMetadata: false } }, 204)
  downloadGate.release()
  downloadGate = undefined
  const disabledJobs = await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.kind === 'import'
    && item.items.some(file => file.rommId === 907) && item.status === 'completed-with-errors'), 'disabled inbound checkpoint')
  const disabledBatch = disabledJobs.find(item => item.kind === 'import' && item.items.some(file => file.rommId === 907)).items[0].batchId
  check(!(await api(`/storage/batches/${disabledBatch}`)).prepared, 'Disabling inbound automation during a transfer prevents unchecked data being prepared')
  const damaged = metadata(901, 'Mismatched.nes', imported)
  damaged.files[0].sha1_hash = '0'.repeat(40)
  remote.set(901, damaged)
  const badImport = await api('/romm/import', 'POST', { romIds: [901], confirm: true })
  const badJobs = await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === badImport.id && item.status === 'completed-with-errors'), 'bad remote hash')
  const badBatch = badJobs.find(item => item.id === badImport.id).items[0].batchId
  check((await api(`/storage/batches/${badBatch}`)).status === 'uploading', 'Hash-mismatched receive is not prepared or trusted')
  await api(`/romm/jobs/${badImport.id}/retry`, 'POST')
  await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === badImport.id && item.status === 'completed-with-errors'), 'bad completed-upload retry')
  check((await api(`/storage/batches/${badBatch}`)).status === 'uploading', 'Retry cannot bypass remote hash validation by reusing a completed chunk upload')
  const changed = Buffer.from(fixture)
  changed[100] = 45
  await writeFile(join(storageRoot, 'batches', batch.id, 'processed', entry.relativePath), changed)
  const staleResponse = await fetch(base + '/api/romm/publish', { method: 'POST',
    headers: { Cookie: cookie, 'X-RomChecker': '1', 'Content-Type': 'application/json' },
    body: JSON.stringify({ ids: [entry.id], confirm: true }) })
  check([200, 409].includes(staleResponse.status), 'Changed bytes are rejected either during queue validation or by the worker')
  if (staleResponse.status === 200) {
    const stalePublish = await staleResponse.json()
    await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === stalePublish.id && ['completed-with-errors', 'failed'].includes(item.status)), 'physical fingerprint gate')
  }
  check(hash(await readFile(publishedFiles[0]), 'sha256') === hash(fixture, 'sha256'), 'Changed bytes cannot overwrite the previously checked RomM export')
  await api('/romm/config', 'PUT', { url: remoteUrl + '/other-server', platformMappings: [{ console: 'NES', platformId: 1, slug: 'nes' }] }, 400)
  check((await api('/romm/config')).url === remoteUrl + '/', 'Credentials are not silently forwarded when the server URL changes')
  const db = await readFile(join(root, 'data', 'romchecker.db'))
  check(!db.includes(Buffer.from(token)), 'Persisted connection credentials are protected at rest')
  check(scans >= 2, 'Fixture exercised failed scan and retry')
  console.log(`PASS: ${assertions} RomM integration assertions (local protocol fixture; no real RomM server)`)
} catch (error) {
  console.error(logs.join('').slice(-12000))
  throw error
} finally {
  hashGate?.release()
  downloadGate?.release()
  for (const child of children.reverse()) {
    if (child.exitCode === null) {
      const exited = new Promise(resolve => child.once('exit', resolve))
      child.kill()
      await exited
    }
  }
  await new Promise(resolve => fixtureServer.close(resolve))
  await rm(root, { recursive: true, force: true })
}
