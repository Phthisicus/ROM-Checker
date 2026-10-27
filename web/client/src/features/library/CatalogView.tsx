import { CheckCircle2, Gamepad2, LoaderCircle, RefreshCw, Search, ShieldCheck, Upload } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { api, bytes, date, type Job, type Progress, type Settings } from '../../api'
import { Badge, Modal, ProgressCard } from '../../components/Presentation'
import { PublishDialog } from '../integrations/RommView'
import { Cover, hasMetadata, RommMetadata, type RommLink } from './RommMetadata'
import './catalog.css'

export type CatalogEntry = {
  id: string; batchId: string; collectionId: string; fileName: string; console: string; consoleName: string
  category: string; relativePath: string; length: number; sha256: string; checkedUtc?: string
  checkStatus: string; referenceStatus: string; integrityStatus: string; security: string
  organization: string; holdReason?: string; publishEligible: boolean; publishBlockReason?: string
  evidence: Record<string, unknown>; approval?: unknown; duplicateOf?: string; syncStatus?: string
}
type Group = { key: string; name: string; total: number; checked: number; attention: number; ids: string[] }
export type CatalogPage = { items: CatalogEntry[]; total: number; filtered: number; page: number; size: number; groups: Group[]; ids: string[]; categories: string[]; counts: Record<string, number> }
type Props = { fail: (error: unknown) => void; imports: () => void; active?: Job; progress: Progress | null; jobs: Job[]; changed: () => Promise<unknown> }
const checkNames = { defenderScan: 'Local antivirus', autoDat: 'Download reference lists', identifyUnknown: 'Online identification', requireDatMatch: 'Require reference match to organize', strict: 'Strict integrity validation', resumeScans: 'Reuse unchanged local checks', sortByCategory: 'Organize by category' } as const
export default function CatalogView({ fail, imports, active, progress, jobs, changed }: Props) {
  const [data, setData] = useState<CatalogPage>()
  const [filters, setFilters] = useState({ q: '', console: '', category: '', checks: '', reference: '', attention: '', publication: '', syncStatus: '' })
  const [links, setLinks] = useState<Record<string, RommLink>>({})
  const [view, setView] = useState<'table' | 'covers'>('table')
  const [page, setPage] = useState(1)
  const [selected, setSelected] = useState<string[]>([])
  const [loading, setLoading] = useState(true)
  const [pending, setPending] = useState(false)
  const [notice, setNotice] = useState('')
  const [file, setFile] = useState<CatalogEntry>()
  const [history, setHistory] = useState<unknown>()
  const [scope, setScope] = useState<{ ids: string[]; title: string }>()
  const [settings, setSettings] = useState<Settings>()
  const [organize, setOrganize] = useState(true)
  const [consent, setConsent] = useState(false)
  const [scopeLimit, setScopeLimit] = useState(1000)
  const [publish, setPublish] = useState<string[]>()
  const [approval, setApproval] = useState(false)
  const [reason, setReason] = useState('')
  const query = new URLSearchParams([...Object.entries(filters).filter(([, value]) => value !== ''), ['page', String(page)]]).toString()
  useEffect(() => {
    let alive = true
    api<RommLink[]>('/romm/links').then(values => { if (alive) setLinks(Object.fromEntries(values.map(link => [link.entryId, link]))) }).catch(error => { if (alive) fail(error) })
    return () => { alive = false }
  }, [jobs, fail])
  const refresh = useCallback(async () => {
    const result = await api<CatalogPage>(`/catalog?${query}`)
    setData(result)
    setSelected(previous => previous.filter(id => result.ids.includes(id)))
  }, [query])
  useEffect(() => {
    let alive = true
    setLoading(true)
    api<CatalogPage>(`/catalog?${query}`).then(value => {
      if (alive) { setData(value); setSelected(previous => previous.filter(id => value.ids.includes(id))) }
    }).catch(error => { if (alive) fail(error) }).finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [query, jobs, fail])
  useEffect(() => {
    setHistory(undefined); setApproval(false); setReason('')
    if (!file) return
    let alive = true
    api<unknown>(`/catalog/${encodeURIComponent(file.id)}/history`).then(value => { if (alive) setHistory(value) }).catch(fail)
    return () => { alive = false }
  }, [file?.id, fail])
  function filter(key: keyof typeof filters, value: string) { setFilters(previous => ({ ...previous, [key]: value })); setPage(1); setSelected([]) }
  async function run(work: () => Promise<void>) {
    setPending(true); setNotice('')
    try { await work(); await refresh(); await changed() } catch (error) { fail(error) } finally { setPending(false) }
  }
  async function verify(ids: string[], title: string) {
    if (!ids.length) return
    setPending(true)
    try { setSettings(await api<Settings>('/settings')); setOrganize(true); setConsent(false); setScopeLimit(Math.min(100000, Math.max(1000, ids.length))); setScope({ ids: [...ids], title }) }
    catch (error) { fail(error) } finally { setPending(false) }
  }
  const online = settings && (settings.autoDat || settings.identifyUnknown || settings.hasheous !== 'Off' || settings.onlineCheck !== 'Off')
  const visible = data?.items.map(item => item.id) ?? []
  const allVisible = visible.length > 0 && visible.every(id => selected.includes(id))
  const toggle = (id: string) => setSelected(previous => previous.includes(id) ? previous.filter(value => value !== id) : [...previous, id])
  return <div className="catalog-workspace">
    <section className="catalog-hero panel"><div><span className="eyebrow">ONE LIBRARY. EVERY IMPORT.</span><h2>Your games, together.</h2><p>Browse every imported ROM in one place. Checks, evidence, and publishing always have an explicit scope.</p></div><div className="row wrap"><button onClick={imports}><Upload size={16} />Import ROMs</button><button disabled={pending} onClick={() => run(async () => { await api('/catalog/refresh', { method: 'POST' }); setNotice('Library refreshed. Existing checks are not rerun.') })}><RefreshCw size={16} />Refresh catalog</button></div></section>
    {notice && <div className="notice success" role="status"><CheckCircle2 size={18} />{notice}</div>}
    {active && <details className="panel compact-progress"><summary><LoaderCircle size={16} className="spin" /> Operation in progress · {progress?.Phase || active.action} · Library remains available</summary><ProgressCard job={active} progress={progress} /></details>}
    <div className="catalog-stats" aria-label="Library summary">{[['All ROMs', data?.total ?? 0], ['Checked', data?.counts.checked ?? 0], ['Needs attention', data?.counts.attention ?? 0], ['Publish eligible', data?.counts.eligible ?? 0]].map(([name, value]) => <div className="panel" key={name}><span>{name}</span><strong>{value.toLocaleString()}</strong></div>)}</div>
    <section aria-label="Consoles" className="catalog-consoles">{data?.groups.map(group => <div className={`panel console-card ${filters.console === group.key ? 'chosen' : ''}`} key={group.key}><button className="console-filter" aria-pressed={filters.console === group.key} onClick={() => filter('console', filters.console === group.key ? '' : group.key)}><Gamepad2 size={23} /><strong>{group.name}</strong><span>{group.total} ROMs · {group.checked} checked</span><small>{group.attention} need attention</small></button><button disabled={pending || loading || !group.ids.length} onClick={() => verify(group.ids, group.name)}>Verify console</button></div>)}</section>
    <section className="panel catalog-results" aria-busy={loading}>
      <div className="section-heading"><div><h2>All ROMs</h2><p>Identity is not security clearance. Unchecked files cannot be published.</p></div><button disabled={pending || !data?.total} onClick={async () => {
        setPending(true)
        try { const all = await api<CatalogPage>('/catalog'); await verify(all.ids, 'Entire library') } catch (error) { fail(error) } finally { setPending(false) }
      }}><ShieldCheck size={16} />Verify entire library</button></div>
      <div className="catalog-filters"><label className="catalog-search"><Search size={16} /><input aria-label="Search library" placeholder="Search names, paths, or evidence…" value={filters.q} onChange={event => filter('q', event.target.value)} /></label>
        <label>Console<select value={filters.console} onChange={event => filter('console', event.target.value)}><option value="">All consoles</option>{data?.groups.map(group => <option key={group.key} value={group.key}>{group.name}</option>)}</select></label>
        <label>Category<select value={filters.category} onChange={event => filter('category', event.target.value)}><option value="">All categories</option>{data?.categories.map(category => <option key={category}>{category}</option>)}</select></label>
        <label>Checks<select value={filters.checks} onChange={event => filter('checks', event.target.value)}><option value="">Any check status</option><option value="unchecked">Unchecked</option><option value="checked">Checked</option></select></label>
        <label>Reference<select value={filters.reference} onChange={event => filter('reference', event.target.value)}><option value="">Any reference</option><option value="matched">Matched</option><option value="unmatched">Unmatched</option><option value="modified">Modified / hack</option></select></label>
        <label>Publication<select value={filters.publication} onChange={event => filter('publication', event.target.value)}><option value="">Any eligibility</option><option value="eligible">Eligible</option><option value="blocked">Blocked</option></select></label>
        <label>RomM sync<select value={filters.syncStatus} onChange={event => filter('syncStatus', event.target.value)}><option value="">Any sync status</option><option value="not-published">Not published</option><option value="linked">Linked</option><option value="awaiting-scan">Awaiting scan</option><option value="stale">Stale</option><option value="failed">Failed</option></select></label>
        <label className="catalog-check"><input type="checkbox" checked={!!filters.attention} onChange={event => filter('attention', event.target.checked ? 'true' : '')} />Needs attention</label>
        <button onClick={() => { setFilters({ q: '', console: '', category: '', checks: '', reference: '', attention: '', publication: '', syncStatus: '' }); setPage(1); setSelected([]) }}>Clear filters</button>
      </div>
      <div className="row wrap catalog-view-toggle" role="group" aria-label="Library display"><button aria-pressed={view === 'table'} onClick={() => setView('table')}>Table view</button><button aria-pressed={view === 'covers'} disabled={!Object.values(links).some(hasMetadata)} onClick={() => setView('covers')}>Cover grid</button><span className="small muted">Covers and descriptions appear when linked RomM metadata is available.</span></div>
      <fieldset disabled={loading || pending} className="catalog-selection row wrap" aria-label="Library selection actions"><strong>{selected.length} selected</strong><button disabled={!visible.length} onClick={() => setSelected(previous => allVisible ? previous.filter(id => !visible.includes(id)) : [...new Set([...previous, ...visible])])}>{allVisible ? 'Deselect visible page' : 'Select visible page'}</button><button disabled={!data?.filtered} onClick={() => setSelected(data?.ids ?? [])}>Select all {data?.filtered ?? 0} filtered</button><button disabled={!selected.length} onClick={() => setSelected([])}>Clear selection</button><button className="primary" disabled={!selected.length} onClick={() => verify(selected, 'Selected ROMs')}>Verify selection</button><button disabled={!data?.filtered} onClick={() => verify(data!.ids, filters.category ? `Category: ${filters.category}` : 'Filtered library')}>Verify filtered scope</button><button disabled={!selected.length} onClick={() => setPublish([...selected])}>Publish to RomM…</button></fieldset>
      {loading && !data ? <p role="status">Loading your library…</p> : !data?.total ? <div className="empty-state"><Gamepad2 size={36} /><h3>Your library starts with an import</h3><p>Upload a folder or import from a network share. Every import joins this permanent library.</p><button className="primary" onClick={imports}>Import ROMs</button></div> : !data.filtered ? <p className="empty-state">No ROMs match these filters. Clear filters to browse your library.</p> : view === 'covers' ? <div className="catalog-cover-grid" aria-label="ROM cover grid">{data.items.map(item => <article className="catalog-cover-card" key={item.id}><Cover link={links[item.id]} title={item.fileName} /><label className="catalog-check"><input type="checkbox" aria-label={`Select ${item.fileName}`} checked={selected.includes(item.id)} onChange={() => toggle(item.id)} /><span>Select ROM</span></label><button className="text-button catalog-file" onClick={() => setFile(item)}>{item.fileName}</button><p className="small muted">{item.consoleName} · {item.category}</p><dl className="cover-findings">{[['Checks', item.checkStatus], ['Reference', item.referenceStatus], ['Integrity', item.integrityStatus], ['Security', item.security], ['Organization', item.organization], ['RomM sync', item.syncStatus], ['Publication', item.publishEligible ? 'Eligible' : 'Blocked']].map(([name, value]) => <div key={name}><dt>{name}</dt><dd><Badge value={value || 'Unknown'} /></dd></div>)}</dl></article>)}</div> : <div className="catalog-table-scroll"><table className="catalog-table"><caption className="sr-only">Library ROMs and separate verification findings</caption><thead><tr><th>Select</th><th>ROM / console</th><th>Checks</th><th>Reference</th><th>Integrity</th><th>Security</th><th>Organization</th><th>RomM sync</th><th>Publication</th></tr></thead><tbody>{data.items.map(item => <tr key={item.id}><td><input type="checkbox" aria-label={`Select ${item.fileName}`} checked={selected.includes(item.id)} onChange={() => toggle(item.id)} /></td><td><button className="text-button catalog-file" onClick={() => setFile(item)}>{item.fileName}</button><small>{item.consoleName} · {item.category} · {bytes(item.length)}</small></td><td><Badge value={item.checkStatus || 'Unchecked'} /></td><td><Badge value={item.referenceStatus || 'Unknown'} /></td><td><Badge value={item.integrityStatus || 'Not checked'} /></td><td><Badge value={item.security || 'Not checked'} /></td><td><Badge value={item.organization || 'Pending'} /></td><td><Badge value={item.syncStatus || 'Not published'} /></td><td><Badge value={item.publishEligible ? 'Eligible' : 'Blocked'} /><small>{item.publishBlockReason}</small></td></tr>)}</tbody></table></div>}
      {!!data?.filtered && <div className="row spread catalog-pagination"><span className="small muted">{data.filtered} matching / {data.total} total · Page {data.page} of {Math.max(1, Math.ceil(data.filtered / data.size))}</span><div className="row"><button disabled={loading || page <= 1} onClick={() => setPage(page - 1)}>Previous</button><button disabled={loading || page * data.size >= data.filtered} onClick={() => setPage(page + 1)}>Next</button></div></div>}
    </section>
    {scope && settings && <Modal title={`Verify ${scope.ids.length} ROMs`} close={() => !pending && setScope(undefined)}>
      <p><strong>Scope: {scope.title}</strong>. This explicit selection spans imports where needed; it never inherits the last opened import. Related tracks may be checked together.</p>
      <label>After verification<select value={String(organize)} onChange={event => setOrganize(event.target.value === 'true')}><option value="true">Organize eligible working copies</option><option value="false">Check only — do not move files</option></select></label>
      <p>Original uploads remain unchanged. Failed checks and unresolved identities are held for review; no automatic deletion or repair.</p>
      <details open><summary>Checks for this run</summary>{Object.entries(checkNames).map(([key, title]) => <label className="catalog-check" key={key}><input type="checkbox" checked={!!settings[key as keyof Settings]} onChange={event => setSettings({ ...settings, [key]: event.target.checked })} />{title}</label>)}
        <label>Online identity<select value={settings.hasheous} onChange={event => setSettings({ ...settings, hasheous: event.target.value })}>{['Off', 'Unverified', 'All'].map(value => <option key={value}>{value}</option>)}</select></label>
        <label>Online malware checks<select value={settings.onlineCheck} onChange={event => setSettings({ ...settings, onlineCheck: event.target.value })}>{['Off', 'Risky', 'Unverified', 'All'].map(value => <option key={value}>{value}</option>)}</select></label>
      </details>
      <details><summary>Related-file scope safeguard</summary><p className="small">Verification includes required tracks and companion files, even across imports. Choose an explicit maximum for the expanded scope; larger selections should be split into multiple runs.</p><label>Maximum files including companions<input type="number" min={Math.max(1, scope.ids.length)} max={100000} value={scopeLimit} onChange={event => setScopeLimit(Number(event.target.value))} /></label></details>
      {online && <label className="catalog-check consent"><input type="checkbox" checked={consent} onChange={event => setConsent(event.target.checked)} />I consent to enabled services receiving hashes and platform metadata, not ROM files. Reference lists may be downloaded.</label>}
      <div className="dialog-actions"><button disabled={pending} onClick={() => setScope(undefined)}>Cancel</button><button className="primary" disabled={pending || !!online && !consent || scopeLimit < scope.ids.length || scopeLimit > 100000 || !Number.isInteger(scopeLimit)} onClick={() => run(async () => {
        await api('/catalog/verify', { method: 'POST', body: JSON.stringify({ ids: scope.ids, settings, organize, maxSelection: scopeLimit, confirm: true }) })
        setScope(undefined); setSelected([]); setNotice('Verification queued. Multi-import operations run sequentially; results stay in your library.')
      })}>Queue verification</button></div>
    </Modal>}
    {file && <Modal drawer title={file.fileName} close={() => !pending && setFile(undefined)}>
      <p>{file.consoleName} · {file.category} · {bytes(file.length)}</p><p className="mono break-path">{file.relativePath}</p>
      <RommMetadata link={links[file.id]} fileName={file.fileName} />
      <div className="file-evidence">{[['Check status', file.checkStatus], ['Reference identity', file.referenceStatus], ['Integrity', file.integrityStatus], ['Security', file.security], ['Organization', file.organization], ['RomM sync', file.syncStatus || 'Not published'], ['Publication', file.publishEligible ? 'Eligible' : file.publishBlockReason || 'Blocked']].map(([key, value]) => <div key={key}><span>{key}</span><strong>{value || 'Not checked'}</strong></div>)}</div>
      <p>{file.holdReason}</p><p className="small muted">Checked {date(file.checkedUtc)}. A reference mismatch can be a hack or translation, not necessarily corruption. Identity and malware findings remain separate.</p>
      {file.duplicateOf && <p>Duplicate of: {file.duplicateOf}. No content is deleted automatically.</p>}
      {file.approval != null && <div className="notice subtle"><div><strong>Explicit content-bound approval</strong><pre className="catalog-history">{JSON.stringify(file.approval, null, 2)}</pre></div></div>}
      <details open><summary>Evidence, hashes & metadata</summary><dl className="catalog-evidence">{Object.entries({ SHA256: file.sha256, ...file.evidence }).map(([key, value]) => <div key={key}><dt>{key}</dt><dd>{typeof value === 'object' ? JSON.stringify(value) : String(value ?? 'Not available')}</dd></div>)}</dl></details>
      <details><summary>Check & approval history</summary><pre className="catalog-history">{history === undefined ? 'Loading history…' : JSON.stringify(history, null, 2)}</pre></details>
      <div className="dialog-actions"><button disabled={pending} onClick={() => verify([file.id], file.fileName)}>Verify this ROM</button><button disabled={file.checkStatus !== 'checked' || !file.sha256} onClick={() => setApproval(!approval)}>Review explicit approval</button></div>
      {approval && <section className="panel"><h3>Approve this exact SHA-256</h3><p>This records your reason against the current content hash for an intentional modification or a supported known internal mismatch. It cannot bypass security findings, incomplete protection, required dependencies, or conflicts. Replaced content needs a new review.</p><code className="break-path">{file.sha256}</code><label>Approval reason<input value={reason} onChange={event => setReason(event.target.value)} placeholder="For example: intentional translation patch" maxLength={1000} /></label><button className="primary" disabled={pending || !reason.trim()} onClick={() => run(async () => {
        await api('/catalog/approve', { method: 'POST', body: JSON.stringify({ ids: [file.id], sha256: { [file.id]: file.sha256 }, reason: reason.trim(), confirm: true }) })
        setFile(undefined); setNotice('Approval saved for the reviewed content hash.')
      })}>Record approval</button></section>}
    </Modal>}
    {publish && <PublishDialog ids={publish} close={() => setPublish(undefined)} fail={fail} published={() => { setPublish(undefined); setSelected([]); setNotice('RomM publication queued. Follow progress and retries in Integrations.'); void refresh() }} />}
  </div>
}
