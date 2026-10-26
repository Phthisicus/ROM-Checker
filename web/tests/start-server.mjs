import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawn } from 'node:child_process'

const root = mkdtempSync(join(tmpdir(), 'romchecker-browser-'))
const library = join(root, 'library')
mkdirSync(library)
const fixture = Buffer.alloc(40976)
fixture.set([0x4e, 0x45, 0x53, 0x1a, 2, 1])
writeFileSync(join(library, 'Browser fixture.nes'), fixture)
const repository = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const storageRoot = join(root, 'storage')
const storageToken = 'browser-fixture-only-storage-service-token'
const executable = process.env.ROMCHECKER_DOTNET || 'dotnet'
const assembly = join(repository, 'web', 'server', 'bin', 'Debug', 'net10.0', 'RomChecker.Web.dll')
const storage = spawn(executable, [assembly], {
  stdio: 'inherit', env: { ...process.env, ASPNETCORE_URLS: 'http://127.0.0.1:5298',
    ROMCHECKER_ROLE: 'storage', ROMCHECKER_PATH_BASE: '', ROMCHECKER_STORAGE_ROOT: storageRoot,
    ROMCHECKER_STORAGE_TOKEN: storageToken, ROMCHECKER_STORAGE_RESERVE_BYTES: '0', ROMCHECKER_SMB_HOSTS: '' },
})
storage.on('error', error => { console.error(error); process.exitCode = 1 })
let healthy = false
for (let attempt = 0; attempt < 100; attempt++) {
  try { healthy = (await fetch('http://127.0.0.1:5298/healthz')).ok; if (healthy) break } catch { /* Startup probe. */ }
  await new Promise(resolve => setTimeout(resolve, 100))
}
if (!healthy) { storage.kill(); throw new Error('Browser storage fixture did not become healthy') }
const child = spawn(process.env.ROMCHECKER_DOTNET || 'dotnet',
  [join(repository, 'web', 'server', 'bin', 'Debug', 'net10.0', 'RomChecker.Web.dll')], {
    stdio: 'inherit', env: {
      ...process.env, ASPNETCORE_URLS: 'http://127.0.0.1:5299',
      ROMCHECKER_ROLE: '', ROMCHECKER_STORAGE_ROOT: storageRoot,
      ROMCHECKER_STORAGE_URL: 'http://127.0.0.1:5298', ROMCHECKER_STORAGE_TOKEN: storageToken,
      ROMCHECKER_ENGINE: repository, ROMCHECKER_LIBRARY: library, ROMCHECKER_DATA: join(root, 'data'),
      ROMCHECKER_PATH_BASE: '/roms', ROMCHECKER_TRUSTED_PROXIES: '',
      ROMCHECKER_PASSWORD: 'browser-fixture-password',
      ROMCHECKER_POWERSHELL: process.env.ROMCHECKER_POWERSHELL || (process.platform === 'win32' ? 'powershell.exe' : 'pwsh'),
    },
  })
child.on('error', error => { console.error(error); process.exitCode = 1 })
child.on('exit', code => {
  storage.once('exit', () => { rmSync(root, { recursive: true, force: true }); process.exit(code ?? 0) })
  storage.kill()
})
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal))
