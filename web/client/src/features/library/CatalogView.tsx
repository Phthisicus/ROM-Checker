import { ArrowLeft, ArrowRight, Gamepad2, Grid2X2, List, LoaderCircle, Search, ShieldCheck, SlidersHorizontal, Upload, X } from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { api, bytes, date, type Job, type Progress, type Settings } from '../../api'
import { Badge, Modal } from '../../components/Presentation'
import { Button, EmptyState, Notice, Skeleton, StatusBadge } from '../../design-system/components'
import { PublishDialog } from '../integrations/RommView'
import { Cover, gameTitle, RommMetadata, type RommLink } from './RommMetadata'
import { closeLibraryFile, libraryRoute, useRoute } from '../../navigation'
import './catalog.css'

export type CatalogEntry = {
  id: string; batchId: string; collectionId: string; fileName: string; console: string; consoleName: string
  category: string; relativePath: string; length: number; sha256: string; checkedUtc?: string
  checkStatus: string; referenceStatus: string; integrityStatus: string; security: string
  regions?: { values: string[]; source: string }
  organization: string; holdReason?: string; publishEligible: boolean; publishBlockReason?: string
  evidence: Record<string, unknown>; approval?: unknown; duplicateOf?: string; syncStatus?: string
}
type Group = { key: string; name: string; total: number; checked: number; attention: number; ids: string[] }
export type CatalogPage = { items: CatalogEntry[]; total: number; filtered: number; page: number; size: number; groups: Group[]; consoles?: { key: string; name: string }[]; ids: string[]; categories: string[]; counts: Record<string, number> }
type Props = { advanced?: boolean; activity: () => void; fail: (error: unknown) => void; imports: () => void; active?: Job; progress: Progress | null; jobs: Job[]; changed: () => Promise<unknown> }
const checkNames = { defenderScan: 'Local antivirus', autoDat: 'Download reference lists', identifyUnknown: 'Online identification', requireDatMatch: 'Require reference match to organize', strict: 'Strict integrity validation', resumeScans: 'Reuse unchanged local checks', sortByCategory: 'Organize by category' } as const
const emptyFilters = { q: '', console: '', category: '', checks: '', reference: '', attention: '', publication: '', syncStatus: '', duplicates: '' }
export function finding(item: CatalogEntry) {
  if (/failed|incomplete|threat|suspicious|malicious|corrupt|missing/i.test(`${item.integrityStatus} ${item.security} ${item.organization}`))
    return { text: 'Needs attention', tone: 'warning' }
  if (item.checkStatus !== 'checked') return { text: 'Unchecked', tone: 'neutral' }
  if (item.holdReason) return { text: 'Needs attention', tone: 'warning' }
  return { text: 'Checked', tone: 'success' }
}
export default function CatalogView({ advanced, activity, fail, imports, active, progress, jobs, changed }: Props) {
  const { params } = useRoute()
  const [data, setData] = useState<CatalogPage>()
  const jobStateKey = JSON.stringify(jobs.map(({ id, status }) => ({ id, status })).sort((left, right) => left.id.localeCompare(right.id)))
  const filters = Object.fromEntries(Object.keys(emptyFilters).map(key => [key, params.get(key) ?? ''])) as typeof emptyFilters
  const setFilters = (value: typeof emptyFilters) => libraryRoute({ ...value, page: '', file: '' })
  const [links, setLinks] = useState<Record<string, RommLink>>({})
  const [view, setView] = useState(() => localStorage.getItem('romchecker-library-view') === 'table' ? 'table' : 'covers')
  const [coverSize, setCoverSize] = useState(() => localStorage.getItem('romchecker-cover-size') === 'small' ? 'small' : 'comfortable')
  const sort = params.get('sort') || 'name'
  const [initialSort] = useState(() => !params.has('sort') ? localStorage.getItem('romchecker-library-sort') : null)
  useEffect(() => {
    if (initialSort) libraryRoute({ sort: initialSort }, true)
  }, [initialSort])
  const requestedPage = Number(params.get('page'))
  const page = Number.isFinite(requestedPage) ? Math.min(2147483647, Math.max(1, Math.floor(requestedPage))) : 1
  const setPage = (value: number) => libraryRoute({ page: String(value) })
  const [selected, setSelected] = useState<string[]>([])
  const [loading, setLoading] = useState(true)
  const [catalogError, setCatalogError] = useState('')
  const [catalogRetry, setCatalogRetry] = useState(0)
  const [pending, setPending] = useState(false)
  const [notice, setNotice] = useState('')
  const [file, setFile] = useState<CatalogEntry>()
  const [copies, setCopies] = useState<CatalogEntry[]>()
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [saveName, setSaveName] = useState('')
  const [savingView, setSavingView] = useState(false)
  const [savedViews, setSavedViews] = useState<{ name: string; query: Record<string, string> }[]>(() => {
    try {
      const values: unknown = JSON.parse(localStorage.getItem('romchecker-saved-views') ?? '[]')
      return Array.isArray(values) ? values.filter((value): value is { name: string; query: Record<string, string> } =>
        typeof value?.name === 'string' && value.query && typeof value.query === 'object'
        && Object.values(value.query).every(item => typeof item === 'string')).slice(0, 20) : []
    } catch { return [] }
  })
  const opener = useRef<HTMLButtonElement | null>(null)
  const [history, setHistory] = useState<unknown>()
  const [scope, setScope] = useState<{ ids: string[]; title: string }>()
  const [settings, setSettings] = useState<Settings>()
  const [organize, setOrganize] = useState(true)
  const [consent, setConsent] = useState(false)
  const [scopeLimit, setScopeLimit] = useState(1000)
  const [publish, setPublish] = useState<string[]>()
  const [approval, setApproval] = useState(false)
  const [reason, setReason] = useState('')
  const query = new URLSearchParams([...Object.entries(filters).filter(([, value]) => value !== ''), ['page', String(page)], ['sort', sort]]).toString()
  const fileId = params.get('file') ?? ''
  function openFile(item: CatalogEntry) {
    opener.current = document.activeElement instanceof HTMLButtonElement ? document.activeElement : null
    libraryRoute({ file: item.id })
  }
  function closeFile() {
    closeLibraryFile()
    setFile(undefined)
    opener.current?.focus()
  }
  useEffect(() => {
    if (!fileId) { setFile(undefined); return }
    let alive = true
    setFile(previous => previous?.id === fileId ? previous : undefined)
    api<CatalogEntry>(`/catalog/${encodeURIComponent(fileId)}`).then(value => { if (alive) setFile(value) }).catch(error => { if (alive) fail(error) })
    return () => { alive = false }
  }, [fileId, jobStateKey, fail])
  useEffect(() => {
    let alive = true
    api<RommLink[]>('/romm/links').then(values => { if (alive) setLinks(Object.fromEntries(values.map(link => [link.entryId, link]))) }).catch(error => { if (alive) fail(error) })
    return () => { alive = false }
  }, [jobStateKey, fail])
  const refresh = useCallback(async () => {
    const result = await api<CatalogPage>(`/catalog?${query}`)
    setData(result)
    setSelected(previous => previous.filter(id => result.ids.includes(id)))
  }, [query])
  useEffect(() => {
    let alive = true
    setLoading(true)
    api<CatalogPage>(`/catalog?${query}`).then(value => {
      if (alive) { setData(value); setSelected(previous => previous.filter(id => value.ids.includes(id))); setCatalogError('') }
    }).catch(error => { if (alive) setCatalogError(error instanceof Error ? error.message : String(error)) }).finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [query, jobStateKey, fail, catalogRetry])
  useEffect(() => {
    setHistory(undefined); setCopies(undefined); setApproval(false); setReason('')
  }, [fileId, advanced])
  useEffect(() => {
    if (!file) return
    let alive = true
    api<CatalogEntry[]>(`/catalog/${encodeURIComponent(file.id)}/copies`).then(value => { if (alive) setCopies(value) }).catch(fail)
    if (advanced) api<unknown>(`/catalog/${encodeURIComponent(file.id)}/history`).then(value => { if (alive) setHistory(value) }).catch(fail)
    return () => { alive = false }
  }, [file, advanced, fail])
  function filter(key: keyof typeof filters, value: string) { libraryRoute({ [key]: value, page: '', file: '' }, key === 'q'); setSelected([]) }
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
  const consoleName = data?.groups.find(group => group.key === filters.console)?.name || filters.console
  const extraFilters = [filters.category, filters.reference, filters.publication, filters.syncStatus, filters.duplicates].filter(Boolean).length
  function saveViews(values: typeof savedViews) { setSavedViews(values); localStorage.setItem('romchecker-saved-views', JSON.stringify(values)) }
  return <div className="catalog-workspace collection-browser">
    <div className="library-intro"><div>{filters.console ? <button className="text-button" onClick={() => filter('console', '')}><ArrowLeft size={16} />All consoles</button> : <span className="eyebrow">ROM COLLECTION</span>}<h2>{consoleName || 'All ROMs'}</h2><p>{data ? `${data.total.toLocaleString()} ROM files` : 'Loading your collection...'}</p></div><Button variant="primary" size="lg" onClick={imports}><Upload size={17} aria-hidden="true" />Add games</Button></div>
    {catalogError && data && <Notice tone="danger" className="catalog-load-notice">{catalogError}<Button size="sm" onClick={() => { setLoading(true); setCatalogRetry(value => value + 1) }}>Retry</Button></Notice>}
    {notice && <Notice tone="success">{notice}</Notice>}
    {active && <div className="library-progress" role="status"><LoaderCircle size={17} className="spin" /><div><strong>{progress?.Phase || 'Checking your collection'}</strong><span>{progress ? `${progress.Done} of ${progress.Total} ${progress.Unit} · ${progress.Detail}` : 'Work continues while you browse.'}</span></div><button onClick={activity}>View activity <ArrowRight size={15} /></button></div>}
    <div className="library-quickviews" role="group" aria-label="Collection views" aria-busy={loading && !data}>
      <button aria-pressed={!filters.checks && !filters.attention && !filters.publication} onClick={() => setFilters({ ...emptyFilters, console: filters.console })}>All ROMs <span>{data?.total.toLocaleString() ?? '—'}</span></button>
      <button aria-pressed={filters.checks === 'unchecked'} onClick={() => setFilters({ ...emptyFilters, console: filters.console, checks: 'unchecked' })}>Unchecked <span>{data?.counts.unchecked?.toLocaleString() ?? '—'}</span></button>
      <button aria-pressed={filters.attention === 'true'} onClick={() => setFilters({ ...emptyFilters, console: filters.console, attention: 'true' })}>Needs attention <span>{data?.counts.attention?.toLocaleString() ?? '—'}</span></button>
      <button aria-pressed={filters.publication === 'eligible'} onClick={() => setFilters({ ...emptyFilters, console: filters.console, publication: 'eligible' })}>Ready for RomM <span>{data?.counts.eligible?.toLocaleString() ?? '—'}</span></button>
    </div>
    {!filters.console && !!data?.groups.length && <section className="console-browser" aria-labelledby="console-browser-heading"><div className="console-browser-heading"><h3 id="console-browser-heading">Browse consoles</h3><span>{data.groups.length.toLocaleString()} {data.groups.length === 1 ? 'system' : 'systems'}</span></div><div className="console-shelf">{data.groups.map(group => <button className="console-tile" key={group.key} onClick={() => filter('console', group.key)}><span className="console-monogram">{group.key === '-' ? <Gamepad2 size={20} aria-hidden="true" /> : group.key.slice(0, 4)}</span><strong>{group.name}</strong><span className="console-tile-meta"><span>{group.total.toLocaleString()} ROM files · {group.checked.toLocaleString()} checked</span>{group.attention > 0 && <StatusBadge tone="warning">{group.attention.toLocaleString()} need attention</StatusBadge>}</span><ArrowRight size={16} aria-hidden="true" /></button>)}</div></section>}
    <section className="catalog-results" aria-busy={loading}>
      <div className="library-toolbar">
        <label className="library-search"><Search size={19} /><input aria-label="Search library" placeholder="Search your collection..." value={filters.q} onChange={event => filter('q', event.target.value)} /></label>
        <label className="toolbar-field"><span>Status</span><select aria-label="Check status" value={filters.checks} onChange={event => filter('checks', event.target.value)}><option value="">All statuses</option><option value="unchecked">Unchecked</option><option value="checked">Checked</option></select></label>
        <label className="toolbar-field"><span>Sort by</span><select aria-label="Sort library" value={sort} onChange={event => { libraryRoute({ sort: event.target.value, page: '' }); localStorage.setItem('romchecker-library-sort', event.target.value) }}><option value="name">Name A–Z</option><option value="name-desc">Name Z–A</option><option value="console">Console</option><option value="checked">Last checked</option><option value="size">File size</option></select></label>
        <button onClick={() => setFiltersOpen(true)} aria-label="Open library filters"><SlidersHorizontal size={17} />Filters{extraFilters > 0 && ` (${extraFilters})`}</button>
        <div className="view-segment" role="group" aria-label="Library display"><button aria-label="Cover grid" aria-pressed={view === 'covers'} onClick={() => { setView('covers'); localStorage.setItem('romchecker-library-view', 'covers') }}><Grid2X2 size={18} /></button><button aria-label="List view" aria-pressed={view === 'table'} onClick={() => { setView('table'); localStorage.setItem('romchecker-library-view', 'table') }}><List size={18} /></button></div>
      </div>
      <div className="library-results-heading"><h3>{consoleName || 'All ROMs'} <span>{data?.filtered.toLocaleString() ?? '—'} files</span></h3><div className="row wrap">
        {view === 'covers' && <label className="cover-size">Cover size<select aria-label="Cover size" value={coverSize} onChange={event => { setCoverSize(event.target.value); localStorage.setItem('romchecker-cover-size', event.target.value) }}><option value="small">Compact</option><option value="comfortable">Comfortable</option></select></label>}
        <button className="text-button" disabled={loading || !visible.length} onClick={() => setSelected(previous => allVisible ? previous.filter(id => !visible.includes(id)) : [...new Set([...previous, ...visible])])}>{allVisible ? 'Deselect page' : 'Select page'}</button>
        <details className="action-menu"><summary>More actions</summary><div>
          <button disabled={pending || loading || !data?.filtered} onClick={() => verify(data!.ids, consoleName || 'Filtered library')}>Check {data?.filtered ?? 0} filtered files</button>
          <button disabled={pending || loading || !data?.total} onClick={async () => {
            setPending(true)
            try { const all = await api<CatalogPage>('/catalog'); await verify(all.ids, 'Entire library') } catch (error) { fail(error) } finally { setPending(false) }
          }}>Check entire library</button>
          <button disabled={pending} onClick={() => run(async () => { await api('/catalog/refresh', { method: 'POST' }); setNotice('Catalog refreshed. Checks were not rerun.') })}>Refresh catalog</button>
          <button onClick={() => setSavingView(true)} disabled={savedViews.length >= 20}>Save this view</button>
          <button onClick={() => { setFilters(emptyFilters); setSelected([]) }}>Clear filters</button>
        </div></details>
      </div></div>
      {savedViews.length > 0 && <div className="saved-views" aria-label="Saved library views">{savedViews.map((saved, index) => <span key={index}><button onClick={() => libraryRoute({ ...emptyFilters, sort: '', page: '', file: '', ...saved.query })}>{saved.name}</button><button className="saved-view-remove" aria-label={`Remove saved view ${saved.name}`} onClick={() => saveViews(savedViews.filter((_, position) => position !== index))}><X size={14} aria-hidden="true" /></button></span>)}</div>}
      {selected.length > 0 && <fieldset disabled={loading || pending} className="catalog-selection selection-bar row wrap" aria-label="Library selection actions"><strong>{selected.length} selected files</strong><button onClick={() => verify([...selected], `${selected.length} selected files`)} className="primary"><ShieldCheck size={16} />Check selected</button><button onClick={() => setPublish([...selected])}>Publish to RomM…</button><details className="action-menu"><summary>Selection</summary><div><button onClick={() => setSelected(data?.ids ?? [])}>Select all {data?.filtered ?? 0} filtered</button><button onClick={() => setSelected([])}>Clear selection</button></div></details><span className="small muted">Selection spans pages; actions target files, not game titles.</span></fieldset>}
      {catalogError && !data ? <div className="catalog-error-state"><Notice tone="danger">{catalogError}</Notice><Button onClick={() => { setLoading(true); setCatalogRetry(value => value + 1) }}>Retry loading collection</Button></div> : loading && !data ? <div className="cover-skeletons" role="status" aria-label="Loading library"><span className="sr-only">Loading ROM files…</span>{Array.from({ length: 6 }, (_, index) => <Skeleton key={index} className="catalog-cover-skeleton" />)}</div> : !data?.total ? <EmptyState className="empty-state collection-empty" title="No ROM files yet" icon={<Gamepad2 size={36} />} action={<Button variant="primary" onClick={imports}><Upload size={17} aria-hidden="true" />Add games</Button>}>Add a folder of ROMs or connect a network share. Your original files stay protected.</EmptyState> : !data.filtered ? <EmptyState className="empty-state" title="No ROM files match" icon={<Search size={30} />} action={<Button onClick={() => setFilters(emptyFilters)}>Clear filters</Button>}>Try a different search or reset your filters to see more of your collection.</EmptyState> : view === 'covers' ? <div className={`catalog-cover-grid size-${coverSize}`} aria-label="ROM cover grid">{data.items.map(item => {
        const status = finding(item)
        return <article className={`catalog-cover-card ${selected.includes(item.id) ? 'is-selected' : ''}`} key={item.id}><div className="game-art"><button className="cover-open" aria-label={`Open ${item.fileName}`} onClick={() => openFile(item)}><Cover link={links[item.id]} title={item.fileName} /></button><label className="card-select"><input type="checkbox" aria-label={`Select ${item.fileName}`} checked={selected.includes(item.id)} onChange={() => toggle(item.id)} /><span className="sr-only">Select ROM file</span></label><span className={`game-status ${status.tone}`}>{status.text}</span></div><button className="game-title" aria-label={item.fileName} onClick={() => openFile(item)}>{gameTitle(item.fileName, links[item.id])}</button><p>{item.consoleName}</p><small className="game-file">{item.fileName}</small>{advanced && <div className="row wrap"><Badge value={item.referenceStatus || 'Unknown'} /><Badge value={item.publishEligible ? 'Eligible' : 'Blocked'} /></div>}</article>
      })}</div> : <div className="catalog-table-scroll"><table className="catalog-table clean-table"><caption className="sr-only">ROM files with separate verification and publication states</caption><thead><tr><th>Select</th><th>Game / ROM file</th><th>Console</th><th>Status</th><th>RomM</th>{advanced && <><th>Reference</th><th>Integrity</th><th>Security</th></>}</tr></thead><tbody>{data.items.map(item => <tr key={item.id}><td><input type="checkbox" aria-label={`Select ${item.fileName}`} checked={selected.includes(item.id)} onChange={() => toggle(item.id)} /></td><td><button className="text-button catalog-file" aria-label={item.fileName} onClick={() => openFile(item)}>{gameTitle(item.fileName, links[item.id])}</button><small>{item.fileName} · {bytes(item.length)}</small></td><td>{item.consoleName}</td><td><span className={`game-status inline ${finding(item).tone}`}>{finding(item).text}</span></td><td>{item.publishEligible ? 'Ready to publish' : 'Blocked'}<small>{item.publishBlockReason}</small><small>{item.syncStatus || 'Not published'}</small></td>{advanced && <><td><Badge value={item.referenceStatus || 'Unknown'} /></td><td><Badge value={item.integrityStatus || 'Not checked'} /></td><td><Badge value={item.security || 'Not checked'} /></td></>}</tr>)}</tbody></table></div>}
      {!!data?.filtered && <div className="row spread catalog-pagination"><span className="small muted">{data.filtered} matching / {data.total} total · Page {data.page} of {Math.max(1, Math.ceil(data.filtered / data.size))}</span><div className="row"><button disabled={loading || page <= 1} onClick={() => setPage(page - 1)}>Previous</button><button disabled={loading || page * data.size >= data.filtered} onClick={() => setPage(page + 1)}>Next</button></div></div>}
    </section>
    {filtersOpen && <Modal drawer title="Filter your collection" close={() => setFiltersOpen(false)}><p>Refine your view without changing files or checks.</p>
      <label>Console<select value={filters.console} onChange={event => filter('console', event.target.value)}><option value="">All consoles</option>{(data?.consoles ?? data?.groups)?.map(group => <option key={group.key} value={group.key}>{group.name}</option>)}{filters.console && !(data?.consoles ?? data?.groups)?.some(group => group.key === filters.console) && <option value={filters.console}>{filters.console}</option>}</select></label>
      <label>Category<select value={filters.category} onChange={event => filter('category', event.target.value)}><option value="">All categories</option>{data?.categories.map(category => <option key={category}>{category}</option>)}</select></label>
      <label>Reference match<select value={filters.reference} onChange={event => filter('reference', event.target.value)}><option value="">Any reference</option><option value="matched">Matched</option><option value="unmatched">Unmatched</option><option value="modified">Modified / hack</option></select></label>
      <label>Publication<select value={filters.publication} onChange={event => filter('publication', event.target.value)}><option value="">Any eligibility</option><option value="eligible">Eligible</option><option value="blocked">Blocked</option></select></label>
      <label>RomM sync<select value={filters.syncStatus} onChange={event => filter('syncStatus', event.target.value)}><option value="">Any sync status</option><option value="not-published">Not published</option><option value="linked">Linked</option><option value="awaiting-scan">Awaiting scan</option><option value="stale">Stale</option><option value="failed">Failed</option></select></label>
      <label>Exact copies<select value={filters.duplicates} onChange={event => filter('duplicates', event.target.value)}><option value="">All files</option><option value="true">Has exact copies</option><option value="false">No exact copies</option></select></label>
      <label className="catalog-check"><input type="checkbox" checked={filters.attention === 'true'} onChange={event => filter('attention', event.target.checked ? 'true' : '')} />Needs attention / blocked</label>
      <div className="dialog-actions"><button onClick={() => setFilters(emptyFilters)}>Reset filters</button><button className="primary" onClick={() => setFiltersOpen(false)}>Show results</button></div></Modal>}
    {savingView && <Modal title="Save library view" close={() => setSavingView(false)}><label>View name<input maxLength={60} value={saveName} onChange={event => setSaveName(event.target.value)} placeholder="For example: Unchecked SNES" /></label><p>Stores your filters and sort order in this browser. No files are changed.</p><button className="primary" disabled={!saveName.trim() || savedViews.length >= 20} onClick={() => { saveViews([...savedViews, { name: saveName.trim(), query: { ...filters, sort } }]); setSaveName(''); setSavingView(false) }}>Save view</button></Modal>}
    {scope && settings && <Modal title={`Verify ${scope.ids.length} ROMs`} close={() => !pending && setScope(undefined)}>
      <p><strong>Scope: {scope.title}</strong>. This explicit selection spans imports where needed; it never inherits the last opened import. Related tracks may be checked together.</p>
      <label>After verification<select value={String(organize)} onChange={event => setOrganize(event.target.value === 'true')}><option value="true">Organize eligible working copies</option><option value="false">Check only — do not move files</option></select></label>
      <p>Original uploads remain unchanged. Failed checks and unresolved identities are held for review; no automatic deletion or repair.</p>
      <div className="notice subtle"><span>Using your saved verification policy. Local antivirus: {settings.defenderScan ? 'enabled' : 'disabled'}. Online services: {online ? 'enabled; consent required below' : 'disabled'}. Strict integrity: {settings.strict ? 'enabled' : 'disabled'}.</span></div>
      {advanced && <details><summary>Individual checks for this run</summary>{Object.entries(checkNames).map(([key, title]) => <label className="catalog-check" key={key}><input type="checkbox" checked={!!settings[key as keyof Settings]} onChange={event => setSettings({ ...settings, [key]: event.target.checked })} />{title}</label>)}
        <label>Online identity<select value={settings.hasheous} onChange={event => setSettings({ ...settings, hasheous: event.target.value })}>{['Off', 'Unverified', 'All'].map(value => <option key={value}>{value}</option>)}</select></label>
        <label>Online malware checks<select value={settings.onlineCheck} onChange={event => setSettings({ ...settings, onlineCheck: event.target.value })}>{['Off', 'Risky', 'Unverified', 'All'].map(value => <option key={value}>{value}</option>)}</select></label>
      </details>}
      <p className="small muted">Required tracks and companion files are included, up to {scopeLimit.toLocaleString()} files. Larger selections must be split or adjusted in Advanced mode.</p>
      {advanced && <details><summary>Related-file scope safeguard</summary><p className="small">Verification includes required tracks and companion files, even across imports. Choose an explicit maximum for the expanded scope; larger selections should be split into multiple runs.</p><label>Maximum files including companions<input type="number" min={Math.max(1, scope.ids.length)} max={100000} value={scopeLimit} onChange={event => setScopeLimit(Number(event.target.value))} /></label></details>}
      {online && <label className="catalog-check consent"><input type="checkbox" checked={consent} onChange={event => setConsent(event.target.checked)} />I consent to enabled services receiving hashes and platform metadata, not ROM files. Reference lists may be downloaded.</label>}
      <div className="dialog-actions"><button disabled={pending} onClick={() => setScope(undefined)}>Cancel</button><button className="primary" disabled={pending || !!online && !consent || scopeLimit < scope.ids.length || scopeLimit > 100000 || !Number.isInteger(scopeLimit)} onClick={() => run(async () => {
        await api('/catalog/verify', { method: 'POST', body: JSON.stringify({ ids: scope.ids, settings, organize, maxSelection: scopeLimit, confirm: true }) })
        setScope(undefined); setSelected([]); setNotice('Verification queued. Multi-import operations run sequentially; results stay in your library.')
      })}>Queue verification</button></div>
    </Modal>}
    {file && <Modal drawer title={gameTitle(file.fileName, links[file.id])} close={() => !pending && closeFile()}>
      <div className="game-detail-hero"><Cover link={links[file.id]} title={file.fileName} /><div><span className="eyebrow">{file.consoleName}</span><h3>{gameTitle(file.fileName, links[file.id])}</h3><span className={`game-status inline ${finding(file).tone}`}>{finding(file).text}</span><p className="small muted">Last checked {date(file.checkedUtc)}</p><button className="primary" disabled={pending} onClick={() => verify([file.id], file.fileName)}><ShieldCheck size={17} />Check ROM</button></div></div>
      <p className="small">Checked means checks ran, not a guarantee of safety. Reference identity, integrity and security remain separate.</p>
      {file.regions && <p className="small">Regions: {file.regions.values.join(', ') || 'Unknown'} · Source: {file.regions.source}. Region metadata is not verification evidence.</p>}
      <RommMetadata link={links[file.id]} fileName={file.fileName} />
      <section className="detail-section"><h3>Verification summary</h3><div className="file-evidence">{[['Reference identity', file.referenceStatus], ['Integrity', file.integrityStatus], ['Security', file.security], ['Organization', file.organization]].map(([key, value]) => <div key={key}><span>{key}</span><strong>{value || 'Not checked'}</strong></div>)}</div>
      {file.holdReason && <div className="notice error"><span>{file.holdReason}</span></div>}<p className="small muted">A reference mismatch can be a hack or translation, not necessarily corruption. Original uploads are never automatically repaired or deleted.</p></section>
      <section className="detail-section"><h3>RomM publication</h3><p><strong>{file.publishEligible ? 'Eligible to publish' : 'Publication blocked'}</strong> · {file.syncStatus || 'Not published'}</p>{!file.publishEligible && <p className="small">{file.publishBlockReason || 'Complete required checks before publication.'}</p>}<button disabled={pending} onClick={() => setPublish([file.id])}>Preview publication</button><p className="small muted">The preview explains blocks; it cannot bypass verification requirements.</p></section>
      <section className="detail-section"><h3>Files & exact copies</h3><p className="small muted">Each row is a separate catalog file with its own checks and publication decision. Only identical SHA-256 content is grouped here; revisions are not merged by filename.</p>
      {copies === undefined ? <p>Loading files...</p> : copies.map(copy => <div className="related-file" key={copy.id}><button className="text-button" disabled={copy.id === file.id} onClick={() => openFile(copy)}>{copy.fileName}</button><span>{bytes(copy.length)} · {finding(copy).text}</span><small className="mono break-path">{copy.relativePath}</small><small>{copy.id === file.id ? 'Selected file' : 'Exact content copy'} · {copy.publishEligible ? 'Publish eligible' : copy.publishBlockReason || 'Publication blocked'}</small></div>)}</section>
      {file.duplicateOf && <p>Duplicate of: {file.duplicateOf}. No content is deleted automatically.</p>}
      {file.approval != null && <div className="notice subtle"><span>An explicit approval exists for this content hash. It does not bypass security checks.</span></div>}
      {advanced && <><details><summary>Evidence, hashes & current location</summary><p className="mono break-path">{file.relativePath}</p><dl className="catalog-evidence">{Object.entries({ SHA256: file.sha256, ...file.evidence }).map(([key, value]) => <div key={key}><dt>{key}</dt><dd>{typeof value === 'object' ? JSON.stringify(value) : String(value ?? 'Not available')}</dd></div>)}</dl></details>
      <details><summary>Check & approval history</summary><pre className="catalog-history">{history === undefined ? 'Loading history…' : JSON.stringify(history, null, 2)}</pre>{file.approval != null && <pre className="catalog-history">{JSON.stringify(file.approval, null, 2)}</pre>}</details>
      <button disabled={file.checkStatus !== 'checked' || !file.sha256} onClick={() => setApproval(!approval)}>Review explicit approval</button></>}
      {advanced && approval && <section className="panel"><h3>Approve this exact SHA-256</h3><p>This records your reason against the current content hash for an intentional modification or a supported known internal mismatch. It cannot bypass security findings, incomplete protection, required dependencies, or conflicts. Replaced content needs a new review.</p><code className="break-path">{file.sha256}</code><label>Approval reason<input value={reason} onChange={event => setReason(event.target.value)} placeholder="For example: intentional translation patch" maxLength={1000} /></label><button className="primary" disabled={pending || !reason.trim()} onClick={() => run(async () => {
        await api('/catalog/approve', { method: 'POST', body: JSON.stringify({ ids: [file.id], sha256: { [file.id]: file.sha256 }, reason: reason.trim(), confirm: true }) })
        closeFile(); setNotice('Approval saved for the reviewed content hash.')
      })}>Record approval</button></section>}
    </Modal>}
    {publish && <PublishDialog ids={publish} close={() => setPublish(undefined)} fail={fail} published={() => { setPublish(undefined); setSelected([]); setNotice('RomM publication queued. Follow progress in Activity.'); void refresh() }} />}
  </div>
}
