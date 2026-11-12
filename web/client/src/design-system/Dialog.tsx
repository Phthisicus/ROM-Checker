import { X } from 'lucide-react'
import { useEffect, useId, useRef, type ReactNode } from 'react'
import { IconButton } from './components'

export function Dialog({ title, children, onClose, variant = 'dialog', description, closeDisabled = false }: {
  title: string; children: ReactNode; onClose: () => void; variant?: 'dialog' | 'drawer'; description?: string; closeDisabled?: boolean
}) {
  const dialog = useRef<HTMLDialogElement>(null)
  const titleId = useId()
  const descriptionId = useId()
  useEffect(() => {
    const node = dialog.current!
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null
    node.showModal()
    return () => { node.close(); if (opener?.isConnected) opener.focus() }
  }, [])
  return <dialog ref={dialog} className={`ds-dialog ${variant === 'drawer' ? 'file-drawer ds-drawer' : ''}`}
    aria-labelledby={titleId} aria-describedby={description ? descriptionId : undefined}
    onCancel={event => { event.preventDefault(); if (!closeDisabled) onClose() }}>
    <div className="dialog-heading"><h2 id={titleId}>{title}</h2><IconButton label="Close dialog" disabled={closeDisabled} onClick={onClose}><X size={20} aria-hidden="true" /></IconButton></div>
    {description && <p id={descriptionId} className="muted">{description}</p>}
    {children}
  </dialog>
}
