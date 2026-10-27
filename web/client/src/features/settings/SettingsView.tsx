import { FolderOpen, LoaderCircle, Save, ShieldAlert } from 'lucide-react'
import { useEffect, useState, type FormEvent } from 'react'
import { api, url, type Info, type Settings, type UpdateResult } from '../../api'
import { Modal } from '../../components/Presentation'

type Props = { info?: Info; fail: (error: unknown) => void; saved: () => void }
export default function SettingsView({ info, fail, saved }: Props) {
  const [settings, setSettings] = useState<Settings>()
  const [consoles, setConsoles] = useState<{ Key: string; Name: string }[]>([])
  const [pending, setPending] = useState(false)
  const [checking, setChecking] = useState(false)
  const [updateResult, setUpdateResult] = useState<UpdateResult>()
  const [integrations, setIntegrations] = useState<{ virusTotal: boolean; malwareBazaar: boolean; approvedSmbHosts: string[] }>()
  const [browser, setBrowser] = useState(false)
  const [folders, setFolders] = useState<{ path: string; folders: { name: string; path: string; fullPath: string }[] }>()
  useEffect(() => {
    api<NonNullable<typeof integrations>>('/settings/integrations').then(setIntegrations).catch(fail)
    Promise.all([api<Settings>('/settings'), api<typeof consoles>('/consoles')])
      .then(([value, catalog]) => { setSettings(value); setConsoles(catalog) }).catch(fail)
  }, [fail])
  async function browse(path = '.') {
    try { setFolders(await api(`/folders?path=${encodeURIComponent(path)}`)); setBrowser(true) } catch (error) { fail(error) }
  }
  async function checkUpdates() {
    setChecking(true); setUpdateResult(undefined)
    try { setUpdateResult(await api<UpdateResult>('/updates/check', { method: 'POST' })) }
    catch (error) { fail(error) } finally { setChecking(false) }
  }
  const update = <K extends keyof Settings>(key: K, value: Settings[K]) => setSettings(previous => previous ? { ...previous, [key]: value } : previous)
  async function submit(event: FormEvent) {
    event.preventDefault(); setPending(true)
    try { setSettings(await api<Settings>('/settings', { method: 'PUT', body: JSON.stringify(settings) })); saved() }
    catch (error) { fail(error) } finally { setPending(false) }
  }
  if (!settings) return <p className="row muted"><LoaderCircle className="spin" size={20} />Loading settings...</p>
  const toggle = (key: keyof Settings, title: string, text: string) => <label className="toggle-row" key={key}><span><strong>{title}</strong><small>{text}</small></span><input type="checkbox" role="switch" checked={settings[key] === true} onChange={e => update(key, e.target.checked)} /></label>
  const number = (key: keyof Settings, title: string, min: number, max: number) => <label key={key}>{title}<input type="number" min={min} max={max} required value={String(settings[key])} onChange={e => update(key, Number(e.target.value))} /></label>
  return <form onSubmit={submit}>
    <section className="panel"><h2>Version & updates</h2>
      <dl className="server-info">
        <div><dt>Application version</dt><dd>{info?.version}</dd></div>
        <div><dt>Build / attempt</dt><dd>{info?.buildNumber ?? 'Local'} / {info?.buildAttempt ?? '-'}</dd></div>
        <div><dt>Channel</dt><dd>{info?.channel ?? 'Local'}</dd></div>
        <div><dt>Built (UTC)</dt><dd>{info?.builtUtc ?? 'Local source build'}</dd></div>
        <div><dt>Source revision</dt><dd className="mono">{info?.commit}</dd></div>
        <div><dt>Database schema</dt><dd>{info?.schema ? `${info.schema.version} (supported ${info.schema.minimumSupported}-${info.schema.maximumSupported})` : 'Unavailable'}</dd></div>
      </dl>
      <p className="small">Back up application data and storage before upgrading. An older image may require restoring a matching database backup. Containers predating schema checks cannot enforce downgrade protection.</p>
      <div className="row"><button type="button" disabled={checking} onClick={checkUpdates}>{checking ? 'Checking...' : 'Check for updates'}</button>
        <a href={url('/diagnostics/build')} download>Download build diagnostics</a>
        {info?.workflowUrl && <a href={info.workflowUrl} target="_blank" rel="noreferrer">Build workflow</a>}</div>
      <p className="small muted">Opt-in checks contact GitHub Container Registry only when requested, compare this channel only, and never deploy or change data.</p>
      {updateResult && <div role="status" className={`notice ${updateResult.schemaCompatible === false ? 'error' : updateResult.status === 'available' ? 'success' : 'subtle'}`}><span>{updateResult.message}{updateResult.version && ` Version ${updateResult.version} · Build ${updateResult.buildNumber}`}</span></div>}
    </section>
    <section className="panel"><h2>Simple by default. Detailed when you need it.</h2><p>Import ROMs into one Library and choose what to verify. The verification dialog lets you change checks for one run without changing these defaults.</p>
      {toggle('defenderScan', `${info?.antivirus ?? 'Antivirus'} scanning`, 'Recommended. Incomplete protection holds affected working copies for review.')}
      {toggle('autoDat', 'Automatic DAT references', 'Download console reference lists; ROM files are not uploaded.')}
      {toggle('identifyUnknown', 'Identify unknown formats', 'Optional online fingerprint lookup for files without a known console.')}
      <p className="small">Library verification uses console folders, preserves required related files, and reports duplicates without deleting them. Advanced Expert settings below do not change these safeguards.</p></section>
    <section className="panel"><h2>Connections & privacy</h2><p>Reference services receive fingerprints and platform metadata—not ROM files. Keep this application behind HTTPS when accessed beyond localhost.</p>
      <dl className="server-info"><div><dt>VirusTotal</dt><dd>{integrations ? integrations.virusTotal ? 'API key configured' : 'Not configured · optional' : 'Loading...'}</dd></div><div><dt>MalwareBazaar</dt><dd>{integrations ? integrations.malwareBazaar ? 'API key configured' : 'Not configured · optional' : 'Loading...'}</dd></div>
        <div><dt>Network shares</dt><dd>{integrations?.approvedSmbHosts.length ? integrations.approvedSmbHosts.join(', ') : 'No approved servers configured'}</dd></div></dl>
      <p className="small">An administrator configures API keys and approved network-share servers on the server. Secrets are never returned to this browser. Share credentials are used for a live connection, not saved to disk.</p></section>
    <details><summary>Advanced engine & server settings</summary><div className="settings-grid"><section className="panel"><div className="section-heading"><div><h2>Server library & organization</h2><p>Configure Expert workspace previews. No files are moved by changing settings.</p></div><FolderOpen size={22} /></div>
      <label>Server library<input readOnly value={info?.library ?? ''} /><small className="muted">Set ROMCHECKER_LIBRARY on the server to change this root.</small></label>
      <div className="form-grid"><label>Console filter<select value={settings.console} onChange={e => update('console', e.target.value)}><option value="All">All consoles (automatic)</option>{consoles.map(c => <option key={c.Key} value={c.Key}>{c.Name}</option>)}</select></label>
        <label>Sorting layout<select value={settings.layout} onChange={e => update('layout', e.target.value)}>{['ByConsole', 'Validity', 'Emulator', 'Frontend', 'RetroArch', 'Classic'].map(layout => <option key={layout}>{layout}</option>)}</select></label>
        <label>Duplicate handling<select value={settings.duplicateMode} onChange={e => update('duplicateMode', e.target.value)}><option value="Move">Move to duplicates folder</option><option value="Report">Report only (sort normally)</option><option value="Off">Disable duplicate detection</option></select></label></div>
      {toggle('sortByCategory', 'Separate classifications', 'Keep non-original categories organized.')}
      {toggle('moveCompanions', 'Move companion files', 'Keep matching saves, patches, artwork, and manuals together.')}
      {toggle('keepGameFolders', 'Keep game folders intact', 'Preserve extracted game directory structure.')}
      {toggle('cleanEmptyFolders', 'Remove empty source folders', 'Only after completed moves.')}
      {toggle('moveBSandST', 'Separate BS / Sufami Turbo', 'Classify these releases separately.')}
    </section><section className="panel"><div className="section-heading"><div><h2>Verification & evidence</h2><p>Choose the sources behind each verdict.</p></div></div>
      <label>Custom DAT folder<div className="row"><input placeholder="Optional path inside the library" value={settings.datFolder} onChange={e => update('datFolder', e.target.value)} /><button type="button" onClick={() => browse()}>Browse</button></div></label>
      <div className="form-grid"><label>Hasheous lookup<select value={settings.hasheous} onChange={e => update('hasheous', e.target.value)}>{['Off', 'Unverified', 'All'].map(value => <option key={value}>{value}</option>)}</select></label>
        <label>Online malware lookup<select value={settings.onlineCheck} onChange={e => update('onlineCheck', e.target.value)}>{['Off', 'Risky', 'Unverified', 'All'].map(value => <option key={value}>{value}</option>)}</select></label></div>
      {toggle('retailOnly', 'Released retail games only', 'Flag demos, prototypes, homebrew, and unconfirmed releases.')}
      {toggle('requireDatMatch', 'Require trusted library matches', 'Do not treat a filename alone as authenticity evidence.')}
      {toggle('strict', 'Strict validation', 'Apply the engine strict checking policy.')}
      {toggle('resumeScans', 'Reuse unchanged local checks', 'Revalidate content with SHA-256; refresh online and AV evidence.')}
    </section><section className="panel"><div className="section-heading"><div><h2>Protection & limits</h2><p>Keep safeguards explicit and resource use bounded.</p></div></div>
      {toggle('protectAppFolders', 'Protect application folders', 'Recommended: avoid breaking installed emulators and games.')}
      {toggle('useFolderHints', 'Use folder hints', 'Use directory names to help resolve ambiguous formats.')}
      <div className="form-grid">{number('hashLimitMB', 'Hash limit (MB)', 1, 1048576)}{number('archiveMaxMB', 'Unpack limit (MB)', 1, 1048576)}{number('archiveMaxEntries', 'Maximum archive entries', 1, 100000)}{number('archiveMaxDepth', 'Nested archive depth', 0, 10)}{number('archiveTimeoutSeconds', 'Archive timeout (seconds)', 10, 3600)}</div>
    </section><section className="panel"><div className="section-heading"><div><h2>Server & privacy</h2><p>Deployment configuration is controlled on the server.</p></div></div>
      <dl className="server-info"><div><dt>Platform</dt><dd>{info?.platform}</dd></div><div><dt>Proxy base path</dt><dd>{info?.pathBase || '/'}</dd></div></dl>
      <div className="notice subtle"><ShieldAlert size={20} /><span>Online lookups send hashes and metadata, not ROM uploads. Configure ROMSORTER_VIRUSTOTAL_KEY and ROMSORTER_MALWAREBAZAAR_KEY as server secrets. Keys are never returned to this browser.</span></div>
      <p className="muted">Linux containers use ClamAV, not Windows Defender. Keep virus signatures updated. Use HTTPS and restrict access through your reverse proxy.</p>
      <p className="muted">Guided Verify & organize moves eligible working copies after checks. Check only never moves ROMs. Expert workflow extraction requires explicit approval; applying a preview uses its saved settings.</p>
    </section></div></details>
    <div className="settings-save"><span className="muted">Settings apply to new operations. Existing previews retain their settings.</span><button className="primary" disabled={pending}>{pending ? <LoaderCircle className="spin" size={17} /> : <Save size={17} />}Save settings</button></div>
    {browser && <Modal title="Choose a DAT folder" close={() => setBrowser(false)}><p className="mono">{folders?.path}</p><button type="button" onClick={() => browse('.')}>Library root</button><div className="folder-browser">{folders?.folders.map(folder => <div className="row spread" key={folder.path}><button type="button" onClick={() => browse(folder.path)}><FolderOpen size={17} />{folder.name}</button><button type="button" onClick={() => { update('datFolder', folder.fullPath); setBrowser(false) }}>Select</button></div>)}</div><p className="small muted">Only directories within the mounted library are available. Links are excluded.</p></Modal>}
  </form>
}
