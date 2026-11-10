import { CheckCircle2, Info, LoaderCircle, ShieldAlert, TriangleAlert, X } from 'lucide-react'
import { useId, useState, type ButtonHTMLAttributes, type ComponentPropsWithRef, type HTMLAttributes, type ReactElement, type ReactNode } from 'react'

export type Tone = 'neutral' | 'info' | 'success' | 'warning' | 'danger'
type Size = 'sm' | 'md' | 'lg'
type ButtonProps = ComponentPropsWithRef<'button'> & {
  variant?: 'secondary' | 'primary' | 'ghost' | 'danger'
  size?: Size
  loading?: boolean
}

export function Button({ variant = 'secondary', size = 'md', loading = false, disabled, type = 'button', className = '', children, ...props }: ButtonProps) {
  return <button {...props} type={type} className={`ds-button ds-button--${variant} ds-control--${size} ${className}`} disabled={disabled || loading} aria-busy={loading || props['aria-busy']}>
    {loading && <LoaderCircle size={16} className="spin" aria-hidden="true" />}{children}
  </button>
}

export function IconButton({ label, children, className = '', ...props }: Omit<ButtonProps, 'children' | 'aria-label'> & { label: string; children: ReactNode }) {
  return <Button variant="ghost" {...props} aria-label={label} className={`ds-icon-button ${className}`}>{children}</Button>
}

export function StatusBadge({ tone = 'neutral', children, className = '', ...props }: HTMLAttributes<HTMLSpanElement> & { tone?: Tone }) {
  return <span {...props} className={`badge ${tone} ds-badge ${className}`}>{children}</span>
}

type FieldProps = { label: string; hint?: string; error?: string }
function descriptionIds(id: string, describedBy: string | undefined, hint?: string, error?: string) {
  return [describedBy, hint && `${id}-hint`, error && `${id}-error`].filter(Boolean).join(' ') || undefined
}

export function TextInput({ label, hint, error, id, className = '', ...props }: ComponentPropsWithRef<'input'> & FieldProps) {
  const generated = useId()
  const fieldId = id ?? generated
  return <div className="ds-field">
    <label htmlFor={fieldId}>{label}</label>
    <input {...props} id={fieldId} className={`ds-input ${className}`} aria-invalid={error ? true : props['aria-invalid']} aria-describedby={descriptionIds(fieldId, props['aria-describedby'], hint, error)} />
    {hint && <span id={`${fieldId}-hint`} className="ds-field-hint">{hint}</span>}
    {error && <span id={`${fieldId}-error`} className="ds-field-error">{error}</span>}
  </div>
}

export function Select({ label, hint, error, id, className = '', children, ...props }: ComponentPropsWithRef<'select'> & FieldProps) {
  const generated = useId()
  const fieldId = id ?? generated
  return <div className="ds-field">
    <label htmlFor={fieldId}>{label}</label>
    <select {...props} id={fieldId} className={`ds-input ${className}`} aria-invalid={error ? true : props['aria-invalid']} aria-describedby={descriptionIds(fieldId, props['aria-describedby'], hint, error)}>{children}</select>
    {hint && <span id={`${fieldId}-hint`} className="ds-field-hint">{hint}</span>}
    {error && <span id={`${fieldId}-error`} className="ds-field-error">{error}</span>}
  </div>
}

const noticeIcons = { neutral: Info, info: Info, success: CheckCircle2, warning: TriangleAlert, danger: ShieldAlert }
export function Notice({ tone = 'info', children, onDismiss, dismissLabel = 'Dismiss notification', className = '' }: { tone?: Tone; children: ReactNode; onDismiss?: () => void; dismissLabel?: string; className?: string }) {
  const Icon = noticeIcons[tone]
  return <div className={`notice ds-notice ${tone} ${className}`} role={tone === 'danger' ? 'alert' : 'status'} aria-atomic="true">
    <Icon size={18} aria-hidden="true" /><div className="ds-notice-content">{children}</div>
    {onDismiss && <IconButton label={dismissLabel} onClick={onDismiss}><X size={16} aria-hidden="true" /></IconButton>}
  </div>
}

export function LoadingState({ children = 'Loading...', className = '' }: { children?: ReactNode; className?: string }) {
  return <div className={`ds-loading ${className}`} role="status" aria-live="polite"><LoaderCircle size={18} className="spin" aria-hidden="true" /><span>{children}</span></div>
}

export function Skeleton({ className = '' }: { className?: string }) {
  return <span className={`ds-skeleton ${className}`} aria-hidden="true" />
}

export function EmptyState({ title, children, icon, action }: { title: string; children: ReactNode; icon?: ReactNode; action?: ReactNode }) {
  return <div className="empty ds-empty">{icon && <span className="ds-empty-icon" aria-hidden="true">{icon}</span>}<h3>{title}</h3><p>{children}</p>{action && <div className="ds-empty-action">{action}</div>}</div>
}

export function Table({ caption, children, className = '', ...props }: HTMLAttributes<HTMLTableElement> & { caption: string }) {
  return <div className="ds-table-scroll" role="region" aria-label={caption} tabIndex={0}><table {...props} className={`ds-table ${className}`}><caption className="sr-only">{caption}</caption>{children}</table></div>
}

export function NavigationItem({ current = false, className = '', children, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { current?: boolean }) {
  return <button type="button" {...props} className={`nav-item ds-navigation-item ${current ? 'selected' : ''} ${className}`} aria-current={current ? 'page' : undefined}>{children}</button>
}

/* The trigger remains a real control, not an extra keyboard stop. */
export function Tooltip({ content, children }: { content: string; children: ReactElement<ButtonHTMLAttributes<HTMLButtonElement>, 'button'> }) {
  const id = useId()
  const [visible, setVisible] = useState(false)
  const describedBy = [children.props['aria-describedby'], visible && id].filter(Boolean).join(' ') || undefined
  return <span className="ds-tooltip-anchor" onMouseEnter={() => setVisible(true)} onMouseLeave={() => setVisible(false)} onFocus={() => setVisible(true)} onBlur={() => setVisible(false)} onKeyDown={event => {
    if (event.key === 'Escape' && visible) { event.stopPropagation(); setVisible(false) }
  }}>
    <children.type {...children.props} aria-describedby={describedBy} />
    {visible && <span id={id} role="tooltip" className="ds-tooltip">{content}</span>}
  </span>
}
