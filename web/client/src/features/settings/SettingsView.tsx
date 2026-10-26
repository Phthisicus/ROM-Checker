import { FolderOpen, LoaderCircle, Save, ShieldAlert } from 'lucide-react'
import { useEffect, useState, type FormEvent } from 'react'
import { api, type Info, type Settings } from '../../api'
import { Modal } from '../../components/Presentation'

type Props = { info?: Info; fail: (error: unknown) => void; saved: () => void }
export default function SettingsView({ info, fail, saved }: Props) {
  const [settings, setSettings] = useState<Settings>()
  const [consoles, setConsoles] = useState<{ Key: string; Name: string }[]>([])
  const [pending, setPending] = useState(false)
  const [browser, setBrowser] = useState(false)
  const [folders, setFolders] = useState<{ path: string; folders: { name: string; path: string; fullPath: string }[] }>()
  useEffect(() => {
    Promise.all([api<Settings>('/settings'), api<typeof consoles>('/catalog')])
      .then(([value, catalog]) => { setSettings(value); setConsoles(catalog) }).catch(fail)
  }, [fail])
  async function browse(path = '.') {
    try { setFolders(await api(`/folders?path=${encodeURIComponent(path)}`)); setBrowser(true) } catch (error) { fail(error) }
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
    <div className="settings-grid"><section className="panel"><div className="section-heading"><div><h2>Library & organization</h2><p>Configure where files go, without renaming them.</p></div><FolderOpen size={22} /></div>
      <label>Mounted library<input readOnly value={info?.library ?? ''} /><small className="muted">Set ROMCHECKER_LIBRARY on the server to change this root.</small></label>
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
      {toggle('autoDat', 'Automatic DAT references', 'Download libretro verification and release metadata.')}
      {toggle('identifyUnknown', 'Identify unknown formats', 'Try hash-based identification for unknown files.')}
      {toggle('retailOnly', 'Released retail games only', 'Flag demos, prototypes, homebrew, and unconfirmed releases.')}
      {toggle('requireDatMatch', 'Require trusted library matches', 'Do not treat a filename alone as authenticity evidence.')}
      {toggle('strict', 'Strict validation', 'Apply the engine strict checking policy.')}
      {toggle('resumeScans', 'Reuse unchanged local checks', 'Revalidate content with SHA-256; refresh online and AV evidence.')}
    </section><section className="panel"><div className="section-heading"><div><h2>Protection & limits</h2><p>Keep safeguards explicit and resource use bounded.</p></div></div>
      {toggle('defenderScan', `${info?.antivirus ?? 'Antivirus'} scanning`, 'Unavailable or incomplete protection is reported, never assumed clean.')}
      {toggle('protectAppFolders', 'Protect application folders', 'Recommended: avoid breaking installed emulators and games.')}
      {toggle('useFolderHints', 'Use folder hints', 'Use directory names to help resolve ambiguous formats.')}
      <div className="form-grid">{number('hashLimitMB', 'Hash limit (MB)', 1, 1048576)}{number('archiveMaxMB', 'Unpack limit (MB)', 1, 1048576)}{number('archiveMaxEntries', 'Maximum archive entries', 1, 100000)}{number('archiveMaxDepth', 'Nested archive depth', 0, 10)}{number('archiveTimeoutSeconds', 'Archive timeout (seconds)', 10, 3600)}</div>
    </section><section className="panel"><div className="section-heading"><div><h2>Server & privacy</h2><p>Deployment configuration is controlled on the server.</p></div></div>
      <dl className="server-info"><div><dt>Version</dt><dd>{info?.version}</dd></div><div><dt>Source revision</dt><dd className="mono">{info?.commit}</dd></div><div><dt>Platform</dt><dd>{info?.platform}</dd></div><div><dt>Proxy base path</dt><dd>{info?.pathBase || '/'}</dd></div></dl>
      <div className="notice subtle"><ShieldAlert size={20} /><span>Online lookups send hashes and metadata, not ROM uploads. Configure ROMSORTER_VIRUSTOTAL_KEY and ROMSORTER_MALWAREBAZAAR_KEY as server secrets. Keys are never returned to this browser.</span></div>
      <p className="muted">Linux containers use ClamAV, not Windows Defender. Keep virus signatures updated. Use HTTPS and restrict access through your reverse proxy.</p>
      <p className="muted">Workflow unpacking changes files; checking does not move them. Applying a preview always uses the settings saved with that preview.</p>
    </section></div>
    <div className="settings-save"><span className="muted">Settings apply to new operations. Existing previews retain their settings.</span><button className="primary" disabled={pending}>{pending ? <LoaderCircle className="spin" size={17} /> : <Save size={17} />}Save settings</button></div>
    {browser && <Modal title="Choose a DAT folder" close={() => setBrowser(false)}><p className="mono">{folders?.path}</p><button type="button" onClick={() => browse('.')}>Library root</button><div className="folder-browser">{folders?.folders.map(folder => <div className="row spread" key={folder.path}><button type="button" onClick={() => browse(folder.path)}><FolderOpen size={17} />{folder.name}</button><button type="button" onClick={() => { update('datFolder', folder.fullPath); setBrowser(false) }}>Select</button></div>)}</div><p className="small muted">Only directories within the mounted library are available. Links are excluded.</p></Modal>}
  </form>
}
