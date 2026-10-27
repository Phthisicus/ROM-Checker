import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
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
      const found = [...remote.values()].find(rom => rom.sha1_hash.toLowerCase() === url.searchParams.get('sha1_hash')?.toLowerCase())
      return found ? send(publicRom(found)) : send({ detail: 'not found' }, 404)
    }
    if (url.pathname === '/api/roms') return send({ items: [...remote.values()].map(publicRom), total: remote.size })
    const match = url.pathname.match(/^\/api\/roms\/(\d+)(\/content\/.+)?$/)
    if (match) {
      const rom = remote.get(Number(match[1]))
      if (!rom) return send({ detail: 'not found' }, 404)
      if (match[2]) { response.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Length': rom.data.length }); response.end(rom.data); return }
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
async function until(work, predicate, message) {
  for (let attempt = 0; attempt < 240; attempt++) {
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
  await launch('storage', storageUrl)
  base = `http://127.0.0.1:${await port()}`
  await launch('', base)
  const login = await fetch(base + '/api/login', { method: 'POST', headers: { 'X-RomChecker': '1', 'Content-Type': 'application/json' }, body: JSON.stringify({ password }) })
  assert.equal(login.status, 200)
  cookie = login.headers.get('set-cookie').split(';')[0]
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
  failScan = true
  const publish = await api('/romm/publish', 'POST', { ids: [entry.id], confirm: true })
  const failed = await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === publish.id && item.status === 'failed'), 'scan conflict')
  check(failed.find(item => item.id === publish.id).error.length > 0, 'Remote scan failure is explicit and retryable')
  check((await api('/catalog?syncStatus=failed')).ids.includes(entry.id), 'Failed publication is visible in the canonical synchronization filter')
  await api(`/romm/jobs/${publish.id}/retry`, 'POST')
  await until(() => api('/romm/jobs'), jobs => jobs.some(item => item.id === publish.id && item.status === 'completed'), 'publish and metadata linking')
  const links = await api('/romm/links')
  check(links.some(link => link.entryId === entry.id && link.metadata.summary === 'Synthetic RomM metadata fixture'), 'Exact hash links imported descriptive metadata')
  const artwork = await fetch(base + `/api/romm/artwork/${entry.id}`, { headers: { Cookie: cookie } })
  check(artwork.ok && artwork.headers.get('content-type') === 'image/png' && (await artwork.arrayBuffer()).byteLength > 0,
    'Linked cover artwork is fetched through the authenticated same-origin proxy')
  const publishedFiles = await files(join(exportRoot, 'roms'))
  check(publishedFiles.length === 1 && hash(await readFile(publishedFiles[0]), 'sha256') === entry.sha256, 'Published copy matches checked bytes; retries create no duplicates')
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
