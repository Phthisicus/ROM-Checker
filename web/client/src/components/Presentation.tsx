import { FolderOpen, LoaderCircle } from 'lucide-react'
import { type ReactNode } from 'react'
import { label, type Job, type Progress } from '../api'
import { actions } from '../features/jobs/actions'
import { Dialog } from '../design-system/Dialog'
import { EmptyState, StatusBadge } from '../design-system/components'

export function Badge({ value }: { value: string }) {
  const tone = /failed|errors|malicious|suspicious|quarantine|corrupt|threat|interrupted/i.test(value) ? 'danger'
    : /warning|unverified|unknown|incomplete|disabled|cancel/i.test(value) ? 'warning'
      : /completed|original|verified|clean|valid|moved/i.test(value) ? 'success' : 'neutral'
  return <StatusBadge tone={tone}>{label(value || 'Unknown')}</StatusBadge>
}
export function Modal({ title, children, close, drawer = false, closeDisabled = false }: { title: string; children: ReactNode; close: () => void; drawer?: boolean; closeDisabled?: boolean }) {
  return <Dialog title={title} onClose={close} variant={drawer ? 'drawer' : 'dialog'} closeDisabled={closeDisabled}>{children}</Dialog>
}
export function Empty({ title, children }: { title: string; children: ReactNode }) {
  return <EmptyState title={title} icon={<FolderOpen size={32} strokeWidth={1.5} />}>{children}</EmptyState>
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
