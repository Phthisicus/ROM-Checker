import { FolderOpen, LoaderCircle, X } from 'lucide-react'
import { useEffect, useRef, type ReactNode } from 'react'
import { label, type Job, type Progress } from '../api'
import { actions } from '../features/jobs/actions'

export function Badge({ value }: { value: string }) {
  const tone = /failed|malicious|suspicious|quarantine|corrupt|threat|interrupted/i.test(value) ? 'danger'
    : /warning|unverified|unknown|incomplete|disabled|cancel/i.test(value) ? 'warning'
      : /completed|original|verified|clean|valid|moved/i.test(value) ? 'success' : 'neutral'
  return <span className={`badge ${tone}`}>{label(value || 'Unknown')}</span>
}
export function Modal({ title, children, close, drawer = false }: { title: string; children: ReactNode; close: () => void; drawer?: boolean }) {
  const dialog = useRef<HTMLDialogElement>(null)
  useEffect(() => { const node = dialog.current!; node.showModal(); return () => node.close() }, [])
  return <dialog ref={dialog} className={drawer ? 'file-drawer' : undefined} onCancel={close} aria-label={title}>
    <div className="dialog-heading"><h2>{title}</h2><button className="icon-button" aria-label="Close dialog" onClick={close}><X size={20} /></button></div>
    {children}
  </dialog>
}
export function Empty({ title, children }: { title: string; children: ReactNode }) {
  return <div className="empty"><FolderOpen size={38} strokeWidth={1.3} /><h3>{title}</h3><p>{children}</p></div>
}
export function ProgressCard({ job, progress }: { job: Job; progress?: Progress | null }) {
  return <div className="progress-card">
    <div className="row spread"><span className="row"><LoaderCircle className="spin" size={18} /><strong>{actions[job.action]}</strong></span><Badge value={job.status} /></div>
    <p>{progress?.Phase ?? 'Preparing job...'}</p>
    <progress aria-label="Job progress" max={100} value={progress && progress.Percent >= 0 ? progress.Percent : undefined} />
    <div className="row spread small muted"><span>{progress?.Detail || 'Progress will appear as work begins.'}</span>
      <span>{progress && progress.SecondsRemaining >= 0 ? `~${Math.ceil(progress.SecondsRemaining / 60)} min remaining` : 'Estimating...'}</span></div>
    {progress?.Current && <p className="mono truncate small" title={progress.Current}>{progress.Current}</p>}
  </div>
}
