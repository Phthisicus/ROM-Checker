import { AlertTriangle, ArrowLeft, CheckCircle2, Download, FolderOpen, Gamepad2, HardDrive, LoaderCircle, Network, Play, Search, Settings2, Shield, Trash2, Upload, X } from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { api, bytes, busy as jobBusy, completed, label, type Detail, type Job, type Progress, type Settings } from '../../api'
import { Modal } from '../../components/Presentation'
import type { StartJob } from '../../workspace'
import StorageView from './StorageView'
import { downloadUrl, uploadFolder, type Batch, type TransferProgress } from './transfers'
import './collections.css'

export type CollectionFile = {
  CollectionId: string; GroupId: string; FileName: string; Console: string; ConsoleName: string
  ConsoleFolder: string; RelativePath: string; Length: number; Category: string; Reason: string
  Notes: string; Threats: string; Explanation: string; Organization: string; HoldReason: string
  CheckedUtc: string; Header: string; Security: string; IntegrityStatus: string; AntivirusStatus: string
  MalwareStatus: string; OnlineMalwareStatus: string; Authenticity: string; DatMatch: string; HashMatch: string; DatStrength: string
  SHA256: string; SHA1: string; MD5: string; CRC32: string; Sources: string
}
type ConsoleGroup = { key: string; name: string; folder: string; total: number; checkedFiles: number; attention: number; organized: number; ids: string[] }
type CollectionPage = { detected: boolean; total: number; filtered: number; page: number; size: number; checkedFiles: number; attention: number; organized: number; datMatches: number; onlineMatches: number; threats: number; groups: ConsoleGroup[]; items: CollectionFile[] }
type Capacity = { availableBytes: number; reserveBytes: number; preparationBytes: number; originalBytes: number; processingBytes: number }
type Props = { batchId: string; select: (id: string) => void; start: StartJob; jobs: Job[]; progress: Progress | null; fail: (error: unknown) => void; recovery: () => void }
export const verificationText = (file: CollectionFile) => !file.CheckedUtc ? 'Not checked' : file.HoldReason ? 'Needs attention' : 'Checks completed'
export default function CollectionsView({ batchId, select, start, jobs, progress, fail, recovery }: Props) {
  const [enabled, setEnabled] = useState<boolean>()
  const [collections, setCollections] = useState<Batch[]>([])
  const [data, setData] = useState<CollectionPage>()
  const [capacity, setCapacity] = useState<Capacity>()
  const [name, setName] = useState('')
  const [pending, setPending] = useState(false)
  const [message, setMessage] = useState('')
  const [transfer, setTransfer] = useState<TransferProgress>()
  const [selected, setSelected] = useState<string[]>([])
  const [q, setQ] = useState('')
  const [consoleKey, setConsole] = useState('')
  const [filter, setFilter] = useState('')
  const [page, setPage] = useState(1)
  const [collapsed, setCollapsed] = useState<string[]>([])
  const [file, setFile] = useState<CollectionFile>()
  const [deleting, setDeleting] = useState(false)
  const [renaming, setRenaming] = useState(false)
  const [network, setNetwork] = useState(false)
  const [options, setOptions] = useState<{ ids?: string[]; count: number }>()
  const [settings, setSettings] = useState<Settings>()
  const [preset, setPreset] = useState('organize')
  const [onlineConsent, setOnlineConsent] = useState(false)
  const [latest, setLatest] = useState<Detail>()
  const uploadInput = useRef<HTMLInputElement>(null)
  const controller = useRef<AbortController | null>(null)
  const detectionStarted = useRef('')
  const collection = collections.find(item => item.id === batchId)
  const active = jobs.find(jobBusy)
  const currentActivity = jobs.find(job => job.request.batchId === batchId)
  const locked = pending || !!active || !!collection && ['processing', 'preparing', 'importing'].includes(collection.status)
  const ready = collection?.status === 'ready'
  const refresh = useCallback(async () => setCollections(await api<Batch[]>('/storage/batches')), [])
  useEffect(() => {
    api<{ enabled: boolean }>('/storage/config').then(value => {
      setEnabled(value.enabled)
      if (value.enabled) refresh().catch(fail)
    }).catch(fail)
    return () => controller.current?.abort()
  }, [refresh, fail])
  useEffect(() => {
    setData(undefined); setCapacity(undefined); setSelected([]); setFile(undefined); setTransfer(undefined)
    setQ(''); setConsole(''); setFilter(''); setPage(1); setLatest(undefined)
  }, [batchId])
  useEffect(() => {
    if (!enabled) return
    let alive = true
    let loaded = false
    async function update() {
      try {
        const list = await api<Batch[]>('/storage/batches')
        if (!alive) return
        setCollections(list)
        const current = list.find(item => item.id === batchId)
        if (current?.prepared && !loaded) {
          const value = await api<CollectionPage>(`/collections/${batchId}/files?q=${encodeURIComponent(q)}&console=${encodeURIComponent(consoleKey)}&filter=${filter}&page=${page}`)
          if (alive) { setData(value); loaded = true }
        }
      } catch (error) { if (alive) fail(error) }
    }
    void update()
    const timer = setInterval(update, 3000)
    return () => { alive = false; clearInterval(timer) }
  }, [enabled, batchId, q, consoleKey, filter, page, currentActivity?.id, currentActivity?.status, refresh, fail])
  useEffect(() => {
    if (!collection || ['preparing', 'importing', 'processing'].includes(collection.status)) return
    let alive = true
    api<Capacity>(`/storage/batches/${batchId}/capacity`).then(value => { if (alive) setCapacity(value) }).catch(fail)
    return () => { alive = false }
  }, [batchId, collection?.status, collection?.bytes, currentActivity?.status, fail])
  useEffect(() => {
    if (!currentActivity) return
    let alive = true
    api<Detail>(`/jobs/${currentActivity.id}`).then(value => { if (alive) setLatest(value) }).catch(fail)
    return () => { alive = false }
  }, [currentActivity?.id, currentActivity?.status, fail])
  useEffect(() => {
    if (data?.detected) { detectionStarted.current = ''; return }
    if (ready && data && !data.detected && !locked && detectionStarted.current !== batchId) {
      detectionStarted.current = batchId
      void start('detect', { batchId })
    }
  }, [ready, data, locked, batchId, start])
  async function run(work: () => Promise<void>) {
    setPending(true); setMessage('')
    try { await work(); await refresh() } catch (error) { fail(error) }
    finally { setPending(false) }
  }
  async function upload(files: File[]) {
    if (!files.length || locked) return
    if (collection?.prepared) { fail(new Error('Prepared collections are sealed. Upload additional ROMs into a new collection.')); return }
    const abort = new AbortController(); controller.current = abort
    setPending(true); setMessage('')
    let id = batchId
    try {
      if (!collection) {
        const folder = files[0].webkitRelativePath.split('/')[0] || 'Uploaded ROMs'
        const result = await api<Batch>('/storage/batches', { method: 'POST', body: JSON.stringify({ name: name.trim() || folder }) })
        id = result.id; select(id); await refresh()
      }
      await uploadFolder(id, files, abort.signal, setTransfer)
      await api(`/storage/batches/${id}/prepare`, { method: 'POST' })
      setMessage('Upload complete. Preparing your working copy, then detecting consoles. Originals remain unchanged.')
    } catch (error) {
      if (abort.signal.aborted) setMessage('Upload paused. Re-select the same folder in this collection to resume. Completed chunks are retained.')
      else fail(error)
    } finally { controller.current = null; setPending(false); await refresh().catch(fail) }
  }
  async function prepareVerification(ids?: string[]) {
    setPending(true)
    try {
      setSettings({ ...await api<Settings>('/settings'), datFolder: '', console: 'All', layout: 'ByConsole', duplicateMode: 'Report', retailOnly: false })
      setPreset('organize'); setOnlineConsent(false)
      setOptions({ ids, count: ids?.length ?? data?.total ?? 0 })
    } catch (error) { fail(error) } finally { setPending(false) }
  }
  const hasOnline = settings && (settings.autoDat || settings.hasheous !== 'Off' || settings.identifyUnknown || settings.onlineCheck !== 'Off')
  const busyHere = active?.request.batchId === batchId
  const selectedIds = new Set(selected)
  const visibleGroups = data?.groups.filter(group => !consoleKey || group.key === consoleKey) ?? []
  function toggleGroup(group: ConsoleGroup) {
    const all = group.ids.every(id => selectedIds.has(id))
    setSelected(previous => all ? previous.filter(id => !group.ids.includes(id)) : [...new Set([...previous, ...group.ids])])
  }
  const fileInput = <input ref={uploadInput} aria-label="Upload ROM folder" className="folder-input" type="file" multiple
    {...{ webkitdirectory: '' }} disabled={locked || !!collection?.prepared} onChange={event => {
      const files = Array.from(event.target.files ?? []); event.target.value = ''; void upload(files)
    }} />
  if (enabled === false) return <section className="panel"><h2>Collections need the storage service</h2><p>An administrator must configure collection storage. The server library is still available in the Expert workspace.</p></section>
  if (enabled === undefined) return <p role="status"><LoaderCircle className="spin" size={18} /> Connecting to your collections...</p>
  return <div className="collections-workspace">
    {fileInput}
    {!collection ? <>
      <section className="collection-hero panel" onDragOver={event => event.preventDefault()} onDrop={event => {
        event.preventDefault()
        if ([...event.dataTransfer.items].some(item => item.webkitGetAsEntry?.()?.isDirectory)) {
          setMessage('For a folder upload, use Choose folder below so the browser preserves every subfolder.'); return
        }
        void upload(Array.from(event.dataTransfer.files))
      }}>
        <div className="hero-symbol"><Upload size={30} /></div><div><span className="eyebrow">YOUR NEXT COLLECTION STARTS HERE</span><h2>A folder full of games. A little more order.</h2>
          <p>Upload mixed-console ROMs. We group them by console, explain the findings, and organize verified working copies. Your originals stay untouched.</p></div>
        <label>Collection name <span className="muted">(optional)</span><input value={name} onChange={event => setName(event.target.value)} maxLength={120} placeholder="For example, My retro collection" /></label>
        <div className="row wrap"><button className="primary" disabled={locked} onClick={() => uploadInput.current?.click()}><Upload size={17} />Upload ROMs / Choose folder</button>
          <button disabled={locked} onClick={() => setNetwork(!network)}><Network size={17} />Import from network share</button></div>
        <p className="small muted">You can also drop individual files here. Folder picking preserves subfolders. ROMs stay on your own storage; online verification is optional.</p>
      </section>
      <div className="section-heading"><div><h2>Your collections</h2><p>Continue where you left off.</p></div><span>{collections.length} collection{collections.length === 1 ? '' : 's'}</span></div>
      {collections.length === 0 && <div className="panel empty-state"><Gamepad2 size={30} /><h3>No collections yet</h3><p>Choose a folder above to get started. No files are moved from your computer.</p></div>}
      <div className="collection-grid">{collections.map(item => <button className="collection-card panel" key={item.id} onClick={() => select(item.id)}>
        <div className="row spread"><FolderOpen size={23} /><span className="status-pill">{label(item.status === 'ready' ? 'Ready to open' : item.status)}</span></div>
        <h3>{item.name}</h3><p>{item.files.toLocaleString()} files · {bytes(item.bytes)} originals</p><span className="text-button">Open collection →</span>
      </button>)}</div>
    </> : <>
      <div className="row spread"><button disabled={pending} onClick={() => select('')}><ArrowLeft size={16} />All collections</button>
        <div className="row wrap"><button disabled={locked} onClick={() => { setName(collection.name); setRenaming(true) }}>Rename</button>
          <button className="danger-button" disabled={locked} onClick={() => setDeleting(true)}><Trash2 size={16} />Delete collection</button></div></div>
      <section className="panel collection-heading">
        <div className="section-heading"><div><span className="eyebrow">YOUR COLLECTION</span><h2>{collection.name}</h2><p>{collection.files.toLocaleString()} files · {bytes(collection.bytes)} originals · Consoles detected: {data?.groups.filter(group => group.key !== '-').length ?? 0}</p></div>
          <button className="primary" disabled={locked || !ready || !data?.detected || !data.total} onClick={() => prepareVerification()}><Play size={16} />Verify everything</button></div>
        <div className="journey" aria-label="Collection workflow">{['Upload', 'Detect consoles', 'Verify', 'Organize', 'Download'].map((step, index) => <span key={step} className={(index === 0 && collection.files > 0 || index === 1 && data?.detected || index === 2 && data?.checkedFiles || index === 3 && data?.organized) ? 'step-done' : ''}>{index + 1}. {step}</span>)}</div>
        <p className="small"><Shield size={14} /> Original uploads are preserved. Console grouping is provisional until verification. Nothing is deleted automatically.</p>
        {collection.error && <div className="notice error" role="alert"><AlertTriangle size={18} />{collection.error}</div>}
        {!collection.prepared && <div className="upload-collection">
          <p>{collection.status === 'uploading' ? 'Continue or resume this upload by choosing the same folder. Once prepared, this collection is sealed; add more ROMs in a new collection.' : 'Preparing or importing files. You can leave this page and return later.'}</p>
          <div className="row wrap"><button disabled={locked || collection.status !== 'uploading'} onClick={() => uploadInput.current?.click()}><Upload size={16} />Upload / resume folder</button>
            <button disabled={locked || !collection.files || !['uploading', 'failed'].includes(collection.status)} onClick={() => run(async () => { await api(`/storage/batches/${batchId}/prepare`, { method: 'POST' }) })}>Finish import & detect consoles</button>
            <button disabled={locked || collection.files > 0} onClick={() => setNetwork(!network)}><Network size={16} />Network share</button></div>
        </div>}
        {capacity && <details><summary><HardDrive size={14} /> Storage & retention</summary><p>Originals: {bytes(capacity.originalBytes)} · Working copy and reports: {bytes(capacity.processingBytes)} · Free disk space: {bytes(capacity.availableBytes)}</p>
          {!collection.prepared && <p>Preparation needs approximately {bytes(capacity.preparationBytes)} extra, plus {bytes(capacity.reserveBytes)} reserved free space. Incomplete uploads must finish first.</p>}
          <p>Files remain until you explicitly delete this collection. Deletion also removes reports and undo journals.</p></details>}
      </section>
      {transfer && <section className="panel" role="status"><h3>{transfer.done === transfer.total ? 'Upload complete' : 'Uploading your ROMs'}</h3><progress aria-label="Upload progress" max={Math.max(1, transfer.totalBytes)} value={transfer.bytes} /><p>{transfer.done} / {transfer.total} files · {bytes(transfer.bytes)} / {bytes(transfer.totalBytes)}</p><p className="break-path">{transfer.file}</p>
        {controller.current && <button onClick={() => controller.current?.abort()}>Pause upload</button>}</section>}
      {busyHere && <section className="panel operation-progress" role="status"><div className="row"><LoaderCircle className="spin" size={19} /><h3>{active.action === 'detect' ? 'Detecting consoles' : 'Checking your collection'}</h3></div>
        <p>{progress?.Phase || 'Starting…'}{progress?.Detail ? ` · ${progress.Detail}` : ''}</p>
        {progress && progress.Total > 0 ? <progress max={progress.Total} value={progress.Done} /> : <p className="muted">Working · remaining time unknown</p>}
        {progress?.Elapsed != null && <p className="small">{Math.round(progress.Elapsed)} seconds elapsed · {progress.SecondsRemaining > 0 ? `about ${Math.ceil(progress.SecondsRemaining)} seconds remaining` : 'No reliable remaining-time estimate yet'}</p>}
        <p className="small">Related disc tracks and companion files are checked together. The local antivirus may inspect the entire working copy. File-moving operations finish safely before another operation can start.</p></section>}
      {latest && !jobBusy(latest.job) && <section className={`notice ${completed(latest.job) ? 'subtle' : 'error'}`} role="status"><span>{completed(latest.job) ? latest.job.action === 'detect' ? 'Console grouping ready. Choose what to verify below.' : `Operation complete. ${latest.summary?.Count ?? 0} files processed. Your original uploads are unchanged.` : latest.job.error || 'Operation did not finish. Review Activity and undo journals before retrying.'}</span></section>}
      {!!latest?.summary?.ServiceIssues?.length && <section className="notice error" role="alert"><AlertTriangle size={18} /><div><strong>Some services did not complete</strong>{latest.summary.ServiceIssues.map(issue => <p key={issue}>{issue}</p>)}<p>These are application issues, not proof that a ROM is defective. See Activity for technical details.</p></div></section>}
      {data?.detected ? <>
        <div className="collection-stats" aria-label="Collection summary">{[
          ['Checked', data.checkedFiles], ['DAT matches', data.datMatches], ['Online matches', data.onlineMatches],
          ['Needs attention', data.attention], ['Threats / suspicious', data.threats], ['Organized', data.organized],
        ].map(([title, value]) => <div className="panel" key={title}><strong>{value}</strong><span>{title}</span></div>)}</div>
        <section className="panel">
          <div className="section-heading"><div><h2>ROMs by console</h2><p>Check individual files, a console, or everything. Results stay here.</p></div>
            <button disabled={locked} onClick={() => start('detect', { batchId })}>Refresh console detection</button></div>
          <div className="collection-filters"><label className="search-field"><Search size={16} /><input aria-label="Search ROMs" placeholder="Search ROMs or findings" value={q} onChange={event => { setQ(event.target.value); setPage(1) }} /></label>
            <select aria-label="Filter console" value={consoleKey} onChange={event => { setConsole(event.target.value); setPage(1) }}><option value="">All consoles</option>{data.groups.map(group => <option value={group.key} key={group.key}>{group.name}</option>)}</select>
            <select aria-label="Filter results" value={filter} onChange={event => { setFilter(event.target.value); setPage(1) }}><option value="">All files</option><option value="attention">Needs attention</option><option value="unchecked">Unchecked</option><option value="progress">In progress</option><option value="completed">Checks completed</option></select></div>
          <p className="small muted">Identity, integrity, and security are separate findings. A reference match is not malware clearance.</p>
          {data.filtered === 0 && <p className="empty-state">No files match these filters. Change your search or filters to see more.</p>}
          {visibleGroups.map(group => {
            const rows = data.items.filter(item => item.Console === group.key)
            const closed = collapsed.includes(group.key)
            return <section className="console-section" key={group.key} aria-label={group.name}>
              <div className="console-heading"><div className="row"><input type="checkbox" aria-label={`Select ${group.name}`} disabled={locked} checked={group.ids.every(id => selectedIds.has(id))} onChange={() => toggleGroup(group)} />
                <button className="console-toggle" aria-expanded={!closed} onClick={() => setCollapsed(previous => closed ? previous.filter(key => key !== group.key) : [...previous, group.key])}><Gamepad2 size={20} /><strong>{group.name}</strong><span>{closed ? '+' : '−'}</span></button></div>
                <span className="small">{group.total} files · {group.checkedFiles} checked · {group.attention} need attention</span>
                <div className="row wrap"><button disabled={locked || !ready} onClick={() => prepareVerification(group.ids)}>Verify console</button>
                  {ready && !locked && group.organized > 0 && group.folder && <a className="button" href={downloadUrl(batchId, group.folder)} download><Download size={15} />Console ZIP</a>}</div></div>
              {!closed && <>{rows.length === 0 ? <button onClick={() => { setConsole(group.key); setPage(1) }}>Show files for this console</button> : rows.map(row => {
                const working = busyHere && active?.action === 'verify' && (!active.request.selection || active.request.selection.includes(row.CollectionId) || data.items.some(other => other.GroupId === row.GroupId && active.request.selection?.includes(other.CollectionId)))
                const processingThisFile = working && progress?.Current?.includes(row.FileName)
                return <div className="rom-row" key={row.CollectionId}>
                  <input aria-label={`Select ${row.FileName}`} type="checkbox" disabled={locked} checked={selectedIds.has(row.CollectionId)} onChange={event => setSelected(previous => event.target.checked ? [...previous, row.CollectionId] : previous.filter(id => id !== row.CollectionId))} />
                  <button className="rom-name" onClick={() => setFile(row)}><strong>{row.FileName}</strong><small>{bytes(row.Length)} · {row.CheckedUtc ? label(row.Category) : 'Provisional console detection'}</small></button>
                  <div className="rom-status"><span className={`status-pill ${row.HoldReason ? 'needs-review' : row.CheckedUtc ? 'checked' : ''}`}>{processingThisFile ? 'Checking this file…' : working ? 'In verification batch' : verificationText(row)}</span><small>{row.Organization || 'Pending'}</small></div>
                  <div className="row"><button aria-label={`Verify ${row.FileName}`} disabled={locked || !ready} onClick={() => prepareVerification([row.CollectionId])}><Play size={14} />Verify</button>
                    {ready && !locked && <a className="icon-button" aria-label={`Download ${row.FileName}`} href={downloadUrl(batchId, row.RelativePath)} download><Download size={17} /></a>}</div>
                </div>
              })}</>}
            </section>
          })}
          <div className="row spread"><span className="small">{data.filtered.toLocaleString()} matching files · Page {page} / {Math.max(1, Math.ceil(data.filtered / data.size))}</span><div className="row"><button disabled={page === 1} onClick={() => setPage(page - 1)}>Previous</button><button disabled={page * data.size >= data.filtered} onClick={() => setPage(page + 1)}>Next</button></div></div>
        </section>
        {selected.length > 0 && <div className="selection-bar"><span><strong>{selected.length}</strong> files selected · required companions are included automatically</span><div className="row"><button onClick={() => setSelected([])}>Clear</button><button className="primary" disabled={locked || !ready} onClick={() => prepareVerification(selected)}>Verify selected</button></div></div>}
        <section className="panel"><div className="section-heading"><div><h2>Take your collection with you</h2><p>Full downloads include pending and held files, reports, and recovery journals. Console ZIPs contain files already organized in that console folder.</p></div><Download size={22} /></div>
          <div className="row wrap">{ready && !locked && <a className="button primary" href={downloadUrl(batchId, '')} download>Download complete collection</a>}<button disabled={locked} onClick={recovery}>Undo changes & recovery</button></div></section>
      </> : ready && <section className="panel"><h3>Get your ROMs ready</h3><p>Detecting consoles groups files without moving them or claiming they are verified.</p><button disabled={locked} onClick={() => start('detect', { batchId })}>Detect consoles</button></section>}
    </>}
    {message && <div className="notice subtle" role="status">{message}</div>}
    {network && <section className="panel"><div className="section-heading"><h2>Network share import</h2><button aria-label="Close network import" onClick={() => setNetwork(false)}><X size={16} /></button></div><p>Create an empty collection below, connect to an approved share, then finish the import in the collection workspace.</p>
      <StorageView batchId={batchId} select={select} start={start} active={locked} fail={fail} importOnly /></section>}
    {renaming && collection && <Modal title="Rename collection" close={() => setRenaming(false)}><form onSubmit={event => { event.preventDefault(); void run(async () => {
      await api(`/storage/batches/${batchId}/rename`, { method: 'POST', body: JSON.stringify({ name }) }); setRenaming(false)
    }) }}><label>Collection name<input value={name} required maxLength={120} onChange={event => setName(event.target.value)} /></label><button className="primary" disabled={pending}>Save name</button></form></Modal>}
    {deleting && collection && <Modal title={`Delete ${collection.name}?`} close={() => setDeleting(false)}><div className="notice error"><Trash2 size={20} />This permanently removes original uploads, working copies, reports, and undo journals. This cannot be undone.</div><p>Downloaded files elsewhere are unaffected. Make sure you have a backup.</p>
      <button className="danger-button" disabled={pending} onClick={() => run(async () => { await api(`/storage/batches/${batchId}`, { method: 'DELETE' }); setDeleting(false); select('') })}>Permanently delete this collection</button></Modal>}
    {options && settings && <Modal title={`Verify ${options.count} selected file${options.count === 1 ? '' : 's'}`} close={() => setOptions(undefined)}>
      <p>Related tracks and companion files are included automatically. Your original uploads will not change.</p>
      <label>What should happen after checking?<select aria-label="Verification preset" value={preset} onChange={event => setPreset(event.target.value)}>
        <option value="organize">Verify & organize — Recommended</option><option value="check">Check only — Do not move files</option><option value="custom">Custom checks & organization</option></select></label>
      <p>{preset === 'check' ? 'Results are saved in this collection. No ROM files are moved.' : 'Eligible working copies are automatically organized into console folders. Unresolved identities, failed enabled checks, unsafe content, and integrity findings are held for review. No files are deleted or overwritten.'}</p>
      <div className="check-overview"><p><Shield size={16} />Local antivirus: <strong>{settings.defenderScan ? 'Enabled' : 'Skipped'}</strong></p><p>Reference downloads: <strong>{settings.autoDat ? 'Enabled' : 'Skipped'}</strong> · Online identity: <strong>{settings.hasheous === 'Off' && !settings.identifyUnknown ? 'Skipped' : 'Enabled'}</strong></p><p>Optional online malware checks: <strong>{settings.onlineCheck === 'Off' ? 'Skipped' : 'Enabled when API keys are configured'}</strong></p></div>
      <details open={preset === 'custom'}><summary><Settings2 size={15} />Advanced checks</summary><div className="advanced-checks">
        {(['defenderScan', 'autoDat', 'identifyUnknown', 'requireDatMatch', 'strict', 'resumeScans', 'sortByCategory'] as const).map(key => <label className="row" key={key}><input type="checkbox" checked={settings[key]} onChange={event => setSettings({ ...settings, [key]: event.target.checked })} />{{
          defenderScan: 'Scan with local antivirus', autoDat: 'Download console reference lists', identifyUnknown: 'Identify unknown files online', requireDatMatch: 'Require a reference match to organize', strict: 'Strict integrity validation', resumeScans: 'Reuse unchanged local checks (fingerprints revalidated)', sortByCategory: 'Separate non-retail classifications inside console folders',
        }[key]}</label>)}
        <label>Online identity<select aria-label="Online identity" value={settings.hasheous} onChange={event => setSettings({ ...settings, hasheous: event.target.value })}>{['Off', 'Unverified', 'All'].map(value => <option key={value}>{value}</option>)}</select></label>
        <label>Online malware checks<select aria-label="Online malware checks" value={settings.onlineCheck} onChange={event => setSettings({ ...settings, onlineCheck: event.target.value })}>{['Off', 'Risky', 'Unverified', 'All'].map(value => <option key={value}>{value}</option>)}</select></label>
        <p className="small">Per-run choices do not change Settings. Console folders and related sets are preserved. Duplicate content is reported, not deleted or relocated. Archives remain packed; use the Expert workspace to approve extraction before refreshing detection.</p>
      </div></details>
      {hasOnline && <label className="consent"><input type="checkbox" checked={onlineConsent} onChange={event => setOnlineConsent(event.target.checked)} /><span>I understand enabled services may receive file fingerprints and platform metadata—not ROM files. Reference lists may be downloaded.</span></label>}
      <button className="primary" disabled={locked || !!hasOnline && !onlineConsent} onClick={async () => {
        setOptions(undefined); setSelected([])
        await start('verify', { batchId, settings, selection: options.ids, organize: preset !== 'check', confirm: true })
      }}><Play size={16} />{preset === 'check' ? 'Start checking' : 'Verify & organize working copies'}</button>
    </Modal>}
    {file && <Modal drawer title={file.FileName} close={() => setFile(undefined)}><div className="row wrap"><Gamepad2 size={20} /><strong>{file.ConsoleName}</strong><span>{bytes(file.Length)}</span></div>
      <div className={`notice ${file.HoldReason ? 'error' : 'subtle'}`}>{file.HoldReason ? <AlertTriangle size={18} /> : <CheckCircle2 size={18} />}<span>{verificationText(file)} · {file.Organization || 'Pending'}{file.HoldReason ? ` — ${file.HoldReason}` : ''}</span></div>
      <p>{file.Explanation}</p><p>{file.CheckedUtc ? file.Reason : 'Choose Verify to run checks. This console assignment is provisional.'}</p>
      <div className="file-evidence">{[['Identity', file.Authenticity || 'Not checked'], ['Integrity', file.IntegrityStatus || 'Not checked'], ['Antivirus', file.AntivirusStatus || 'Not checked'], ['Online malware checks', file.OnlineMalwareStatus || 'Not checked'], ['Security', file.MalwareStatus || 'Not checked']].map(([key, value]) => <div key={key}><span>{key}</span><strong>{value}</strong></div>)}</div>
      {file.Threats && <div className="notice error">{file.Threats}</div>}{file.Notes && <p>{file.Notes}</p>}
      <p className="small">An unusual structure is not proof that a ROM is unusable. Reference identity is separate from security. No automatic repair or deletion is performed.</p>
      <details><summary>Technical evidence & current location</summary><dl className="file-paths">{(['RelativePath', 'Category', 'Header', 'DatMatch', 'DatStrength', 'HashMatch', 'Sources', 'SHA256', 'SHA1', 'MD5', 'CRC32', 'CheckedUtc'] as const).map(key => <div key={key}><dt>{key}</dt><dd className="mono">{file[key] || 'Not available / not applicable'}</dd></div>)}</dl></details>
      <div className="dialog-actions"><button disabled={locked || !ready} onClick={() => { const id = file.CollectionId; setFile(undefined); void prepareVerification([id]) }}>Verify this ROM</button>{ready && !locked && <a className="button" href={downloadUrl(batchId, file.RelativePath)} download>Download current file</a>}</div></Modal>}
  </div>
}
