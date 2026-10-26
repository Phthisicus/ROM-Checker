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
const child = spawn(process.env.ROMCHECKER_DOTNET || 'dotnet',
  [join(repository, 'web', 'server', 'bin', 'Debug', 'net10.0', 'RomChecker.Web.dll')], {
    stdio: 'inherit', env: {
      ...process.env, ASPNETCORE_URLS: 'http://127.0.0.1:5299',
      ROMCHECKER_ENGINE: repository, ROMCHECKER_LIBRARY: library, ROMCHECKER_DATA: join(root, 'data'),
      ROMCHECKER_PATH_BASE: '/roms', ROMCHECKER_TRUSTED_PROXIES: '',
      ROMCHECKER_PASSWORD: 'browser-fixture-password',
      ROMCHECKER_POWERSHELL: process.env.ROMCHECKER_POWERSHELL || (process.platform === 'win32' ? 'powershell.exe' : 'pwsh'),
    },
  })
child.on('error', error => { console.error(error); process.exitCode = 1 })
child.on('exit', code => { rmSync(root, { recursive: true, force: true }); process.exit(code ?? 0) })
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal))
