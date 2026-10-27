import { CheckCircle2, Link2, LoaderCircle, RefreshCw, Shield, Trash2 } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { api, date } from '../../api'
import { Badge, Modal } from '../../components/Presentation'
import '../library/catalog.css'

type Mapping = { console: string; platformId: number; slug?: string }
type Config = { url: string; configured: boolean; platformMappings: Mapping[]; autoPublish: boolean; exportRoot?: string; transport?: string }
type Connection = { version?: string; capabilities?: unknown; compatible?: boolean; message?: string; platforms: { id: number; name: string; slug: string }[] }
export type RommJob = { id: string; kind: string; status: string; created: string; finished?: string; error?: string; items: { entryId: string; status: string; error?: string; rommId?: number }[] }
type Remote = { items: { id: number; name: string; platformId: number }[]; total: number }
type Preview = { selected: number; eligible: { id: string; fileName: string }[]; blocked: { id: string; fileName: string; reason: string }[] }
type Props = { fail: (error: unknown) => void }
export function PublishDialog({ ids, close, fail, published }: Props & { ids: string[]; close: () => void; published: () => void }) {
  const [preview, setPreview] = useState<Preview>()
  const [pending, setPending] = useState(false)
  const [consent, setConsent] = useState(false)
  const [error, setError] = useState('')
  useEffect(() => {
    let alive = true
    api<Preview>('/romm/preview', { method: 'POST', body: JSON.stringify({ ids }) }).then(value => { if (alive) setPreview(value) }).catch(error => { if (alive) setError(error instanceof Error ? error.message : String(error)) })
    return () => { alive = false }
  }, [ids])
  return <Modal title="Preview RomM publication" close={() => !pending && close()}><p>Only eligible, checked working copies are exported to the shared RomM library. Original uploads and staging directories are never exposed. Publishing does not delete remote files.</p><p className="small muted">This is a stored-evidence preview. Physical file hashes are revalidated by the worker at transfer time. Related tracks and companion files may expand the selection as one group.</p>{error && <div role="alert" className="notice error">{error}</div>}{!preview && !error && <p role="status">Checking eligibility and platform mappings…</p>}{preview && <><div className="notice subtle"><strong>{preview.selected} selected · {preview.eligible.length} eligible · {preview.blocked.length} blocked</strong></div><details open={preview.blocked.length > 0}><summary>Blocked files and reasons ({preview.blocked.length})</summary><ul>{preview.blocked.map(item => <li key={item.id}><strong>{item.fileName}</strong> — {item.reason}</li>)}</ul></details><details><summary>Eligible files ({preview.eligible.length})</summary><ul>{preview.eligible.map(item => <li key={item.id}>{item.fileName}</li>)}</ul></details><label className="catalog-check consent"><input type="checkbox" checked={consent} onChange={event => setConsent(event.target.checked)} />Publish these {preview.eligible.length} eligible copies, then request RomM scan and metadata matching. Blocked files will not be published.</label><div className="dialog-actions"><button disabled={pending} onClick={close}>Cancel</button><button className="primary" disabled={pending || !preview.eligible.length || !consent} onClick={async () => {
    setPending(true); setError('')
    try { await api('/romm/publish', { method: 'POST', body: JSON.stringify({ ids: preview.eligible.map(item => item.id), confirm: true }) }); published() } catch (error) { setError(error instanceof Error ? error.message : String(error)); fail(error) } finally { setPending(false) }
  }}>{pending ? <LoaderCircle size={16} className="spin" /> : <Link2 size={16} />}Publish eligible copies</button></div></>}</Modal>
}
export function RommJobs({ jobs, retry, pending }: { jobs: RommJob[]; retry: (id: string) => void; pending: boolean }) {
  return <div className="integration-list">{!jobs.length && <p className="muted">No RomM operations yet.</p>}{jobs.map(job => <article className="integration-item" key={job.id}><div className="row spread"><strong>{job.kind}</strong><Badge value={job.status} /></div><p className="small muted">{date(job.created)}{job.finished ? ` → ${date(job.finished)}` : ''}</p>{job.status === 'awaiting-scan' && <p className="small">Copies exported; waiting for RomM scan and exact-hash linking. The worker will check again automatically.</p>}{job.status === 'awaiting-import' && <p className="small">Remote files transferred; waiting for storage preparation before they enter the Library.</p>}{job.error && <p className="notice error">{job.error}</p>}<details><summary>{job.items?.length ?? 0} file results</summary>{job.items?.map((item, index) => <p key={`${item.entryId}-${index}`} className="small break-path">{item.entryId} · {item.status}{item.rommId ? ` · RomM #${item.rommId}` : ''}{item.error ? ` — ${item.error}` : ''}</p>)}</details>{['failed', 'partial', 'completed-with-errors', 'completed-with-warnings', 'interrupted'].includes(job.status) && <button disabled={pending} onClick={() => retry(job.id)}>Retry failed items</button>}</article>)}</div>
}
export default function RommView({ fail }: Props) {
  const [config, setConfig] = useState<Config>()
  const [configError, setConfigError] = useState(false)
  const [token, setToken] = useState('')
  const [connection, setConnection] = useState<Connection>()
  const [jobs, setJobs] = useState<RommJob[]>([])
  const [links, setLinks] = useState<{ entryId: string; rommId: number; status: string; metadata?: unknown; updated?: string }[]>([])
  const [remote, setRemote] = useState<Remote>()
  const [q, setQ] = useState('')
  const [page, setPage] = useState(1)
  const [selected, setSelected] = useState<number[]>([])
  const [linked, setLinked] = useState<string[]>([])
  const [pending, setPending] = useState(false)
  const [notice, setNotice] = useState('')
  const [importing, setImporting] = useState(false)
  const [metadata, setMetadata] = useState(false)
  const [autoConfirm, setAutoConfirm] = useState(false)
  const refresh = useCallback(async () => {
    const [operations, references] = await Promise.all([api<RommJob[]>('/romm/jobs'), api<typeof links>('/romm/links')])
    setJobs(operations); setLinks(references)
  }, [])
  const loadConfig = useCallback(async () => {
    setConfigError(false)
    try { setConfig(await api<Config>('/romm/config')) } catch (error) { setConfigError(true); fail(error) }
  }, [fail])
  useEffect(() => {
    void loadConfig(); refresh().catch(fail)
    const timer = setInterval(() => refresh().catch(fail), 5000)
    return () => clearInterval(timer)
  }, [fail, refresh, loadConfig])
  async function run(work: () => Promise<void>) {
    setPending(true); setNotice('')
    try { await work(); await refresh() } catch (error) { fail(error) } finally { setPending(false) }
  }
  async function browse() { await run(async () => setRemote(await api<Remote>(`/romm/roms?q=${encodeURIComponent(q)}&page=${page}`))) }
  if (!config) return configError ? <section className="panel"><h2>RomM configuration unavailable</h2><p>Check the error above, then retry. No settings have been changed.</p><button onClick={loadConfig}>Retry connection settings</button></section> : <p role="status">Loading RomM integration…</p>
  return <div>
    <section className="panel catalog-hero"><div><span className="eyebrow">YOUR LIBRARY, CONNECTED</span><h2>RomM</h2><p>Publish verified copies, refresh metadata, or bring remote ROMs into this library. Every transfer is explicit and recorded.</p></div><Badge value={config.configured ? 'Configured' : 'Not configured'} /></section>
    {notice && <div role="status" className="notice success"><CheckCircle2 size={18} />{notice}</div>}
    <div className="integration-grid"><section className="panel"><h2>Connection & credentials</h2><form onSubmit={event => { event.preventDefault(); void run(async () => {
      const body = { url: config.url, ...(token ? { token } : {}), platformMappings: config.platformMappings, autoPublish: config.autoPublish }
      await api('/romm/config', { method: 'PUT', body: JSON.stringify(body) })
      setToken(''); setConnection(undefined)
      setConfig(await api<Config>('/romm/config')); setNotice('RomM settings saved. Test the saved connection before publishing.')
    }) }}>
      <label>RomM URL<input type="url" required placeholder="http://romm:8080" value={config.url} onChange={event => setConfig({ ...config, url: event.target.value })} /></label>
      <label>API token<input type="password" autoComplete="new-password" value={token} onChange={event => setToken(event.target.value)} placeholder={config.configured ? 'Saved securely — leave blank to keep' : 'Enter a RomM API token'} /></label>
      <p className="small muted">The saved token is never returned or displayed. A blank token preserves it. Save before testing; your browser only talks to this server.</p>
      <label className="catalog-check"><input type="checkbox" checked={config.autoPublish} disabled={pending} onChange={event => {
        if (event.target.checked) setAutoConfirm(true)
        else setConfig({ ...config, autoPublish: false })
      }} />Automatically publish eligible verified copies</label>
      <p className="small muted">Opt-in only. Eligible checked files with valid platform mappings may be exported without a per-file preview. Unchecked, stale, blocked, unsafe, or incompletely protected files remain excluded. Originals are never exposed; remote files are never automatically deleted. Save to apply this policy.</p>
      <div className="row wrap"><button className="primary" disabled={pending}>Save connection & mappings</button><button type="button" disabled={pending || !config.configured} onClick={() => run(async () => {
        const result = await api<Connection>('/romm/test', { method: 'POST' })
        setConnection(result); setNotice(result.compatible === false ? 'RomM is reachable but lacks required capabilities. Review the connection details.' : 'Saved RomM connection tested successfully.')
      })}>Test saved connection</button></div></form>
      {connection && <div className={`notice ${connection.compatible === false ? 'error' : 'success'}`}><div><strong>Connected · RomM {connection.version || 'version unavailable'}</strong><p>{connection.message || `${connection.platforms.length} platforms available.`}</p><details><summary>Detected capabilities</summary><pre className="catalog-history">{JSON.stringify(connection.capabilities ?? {}, null, 2)}</pre></details></div></div>}
      <h3>Platform mappings</h3><p className="small muted">Map detected console keys (for example NES) to RomM platforms. Unmapped platforms stay blocked.</p>{config.platformMappings.map((mapping, index) => <div className="mapping-row" key={index}><label>Console key<input value={mapping.console} onChange={event => setConfig({ ...config, platformMappings: config.platformMappings.map((value, i) => i === index ? { ...value, console: event.target.value } : value) })} /></label><label>RomM platform{connection ? <select aria-label={`RomM platform ${index + 1}`} value={mapping.platformId} onChange={event => {
        const platform = connection.platforms.find(value => value.id === Number(event.target.value))
        setConfig({ ...config, platformMappings: config.platformMappings.map((value, i) => i === index ? { ...value, platformId: Number(event.target.value), slug: platform?.slug } : value) })
      }}><option value="0">Choose platform</option>{connection.platforms.map(platform => <option key={platform.id} value={platform.id}>{platform.name} ({platform.slug})</option>)}</select> : <input type="number" min="1" value={mapping.platformId || ''} onChange={event => setConfig({ ...config, platformMappings: config.platformMappings.map((value, i) => i === index ? { ...value, platformId: Number(event.target.value) } : value) })} />}</label><button aria-label={`Remove mapping ${index + 1}`} onClick={() => setConfig({ ...config, platformMappings: config.platformMappings.filter((_, i) => i !== index) })}><Trash2 size={16} /></button>{!connection && <label>Platform folder slug<input value={mapping.slug ?? ''} onChange={event => setConfig({ ...config, platformMappings: config.platformMappings.map((value, i) => i === index ? { ...value, slug: event.target.value } : value) })} /></label>}</div>)}<button onClick={() => setConfig({ ...config, platformMappings: [...config.platformMappings, { console: '', platformId: 0, slug: '' }] })}>Add platform mapping</button>
    </section><section className="panel"><h2>Shared-library publication</h2><p className="row"><Shield size={20} />Verified copies only. Never originals or staging.</p><p>Mount the export folder below into RomM as <code>/romm/library</code>. ROM Checker copies eligible files here, asks RomM to scan, and matches hashes for metadata. No ROM upload endpoint is used.</p><p className="mono break-path">{config.exportRoot || 'Export folder configured on the server'}</p><p className="small muted">The export path is managed by ROMCHECKER_ROMM_EXPORT_ROOT. Publication is manual unless you explicitly enable and save automatic publication. Remote files are never automatically deleted.</p><ol><li>Save credentials and platform mappings.</li><li>Test the saved connection and mount the shared folder.</li><li>Select ROMs in Library and choose “Publish to RomM…” to review eligible and blocked files.</li></ol></section>
    <section className="panel"><h2>Import from RomM</h2><p>Remote files are streamed into a new import and added to your one library as unchecked. They must pass verification before publication.</p><div className="row wrap"><label>Search remote ROMs<input value={q} onChange={event => { setQ(event.target.value); setPage(1); setSelected([]) }} /></label><label>Remote page<input type="number" min={1} value={page} onChange={event => { setPage(Math.max(1, Number(event.target.value))); setSelected([]) }} /></label><button disabled={pending || !config.configured} onClick={browse}>Browse RomM</button></div>{remote && <><p className="small muted">{remote.total} remote ROMs · page {page}</p><div className="remote-list">{remote.items.map(item => <label className="catalog-check" key={item.id}><input type="checkbox" checked={selected.includes(item.id)} onChange={() => setSelected(previous => previous.includes(item.id) ? previous.filter(id => id !== item.id) : [...previous, item.id])} /><span>{item.name} <small className="muted">Platform {item.platformId} · #{item.id}</small></span></label>)}</div><button disabled={pending || !selected.length} onClick={() => setImporting(true)}>Import {selected.length} remote ROMs…</button></>}</section>
    <section className="panel"><h2>Linked ROMs & metadata</h2><p>Refresh metadata for explicit links without changing ROM files or implicitly approving them.</p><div className="remote-list">{links.map(link => <label key={link.entryId} className="catalog-check"><input type="checkbox" checked={linked.includes(link.entryId)} onChange={() => setLinked(previous => previous.includes(link.entryId) ? previous.filter(id => id !== link.entryId) : [...previous, link.entryId])} /><span className="break-path">{link.entryId} · RomM #{link.rommId} · {link.status}<small className="muted"> · {date(link.updated)}</small>{link.metadata != null && <details><summary>Metadata</summary><pre className="catalog-history">{JSON.stringify(link.metadata, null, 2)}</pre></details>}</span></label>)}</div>{!links.length && <p className="muted">No linked ROMs yet. Publish eligible files to create links.</p>}<button disabled={pending || !linked.length} onClick={() => setMetadata(true)}><RefreshCw size={16} />Refresh selected metadata…</button></section></div>
    <section className="panel" style={{ marginTop: 22 }}><div className="row spread"><h2>RomM activity & retries</h2><button disabled={pending} onClick={() => run(refresh)}>Refresh activity</button></div><RommJobs jobs={jobs} pending={pending} retry={id => run(async () => { await api(`/romm/jobs/${encodeURIComponent(id)}/retry`, { method: 'POST' }); setNotice('Retry queued for failed items.') })} /></section>
    {importing && <Modal title="Import remote ROMs?" close={() => !pending && setImporting(false)}><p>Download {selected.length} selected ROMs from RomM into a new local import. This uses local disk space. Remote files are unchanged; imported files start unchecked.</p><div className="dialog-actions"><button disabled={pending} onClick={() => setImporting(false)}>Cancel</button><button className="primary" disabled={pending} onClick={() => run(async () => { await api('/romm/import', { method: 'POST', body: JSON.stringify({ romIds: selected, confirm: true }) }); setImporting(false); setSelected([]); setNotice('Remote import queued. Follow progress below; completed files appear in Library.') })}>Confirm import</button></div></Modal>}
    {metadata && <Modal title="Refresh RomM metadata?" close={() => !pending && setMetadata(false)}><p>Request metadata for {linked.length} linked ROMs. ROM files, checks, and approvals are unchanged.</p><div className="dialog-actions"><button disabled={pending} onClick={() => setMetadata(false)}>Cancel</button><button className="primary" disabled={pending} onClick={() => run(async () => { await api('/romm/metadata', { method: 'POST', body: JSON.stringify({ ids: linked, confirm: true }) }); setMetadata(false); setLinked([]); setNotice('Metadata refresh queued.') })}>Confirm metadata refresh</button></div></Modal>}
    {autoConfirm && <Modal title="Enable automatic publication?" close={() => setAutoConfirm(false)}><p>Eligible checked copies may be exported to RomM automatically without a separate preview for each file. Physical hashes and required checks are still revalidated; unchecked, blocked, unsafe, or incompletely protected content cannot bypass the publication policy.</p><p>This does not approve files, expose originals, or delete remote files. Save connection settings after confirming to enable this policy.</p><div className="dialog-actions"><button onClick={() => setAutoConfirm(false)}>Cancel</button><button className="primary" onClick={() => { setConfig({ ...config, autoPublish: true }); setAutoConfirm(false) }}>Confirm auto-publish opt-in</button></div></Modal>}
  </div>
}
