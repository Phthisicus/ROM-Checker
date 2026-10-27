import { Gamepad2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { date, url } from '../../api'

export type RommLink = { entryId: string; rommId: number | null; status: string; metadata?: Record<string, unknown> | null; updated?: string }
const text = (value: unknown): string => typeof value === 'string' || typeof value === 'number' ? String(value) : ''
const list = (value: unknown): string => Array.isArray(value) ? value.map(item => typeof item === 'object' && item !== null ? text((item as Record<string, unknown>).name) : text(item)).filter(Boolean).join(', ') : text(value)
export const hasMetadata = (link?: RommLink) => !!link?.metadata && Object.keys(link.metadata).length > 0
export const gameTitle = (fileName: string, link?: RommLink) => text(link?.metadata?.name) || fileName.replace(/\.[^.]+$/, '')
export function Cover({ link, title }: { link?: RommLink; title: string }) {
  const [failed, setFailed] = useState(false)
  useEffect(() => setFailed(false), [link?.entryId, link?.updated])
  return <div className="rom-cover">{hasMetadata(link) && !failed ? <img src={url(`/romm/artwork/${encodeURIComponent(link!.entryId)}`)} alt={`Cover for ${title}`} loading="lazy" referrerPolicy="no-referrer" onError={() => setFailed(true)} /> : <div className="cover-placeholder" role="img" aria-label={`No cover available for ${title}`}><Gamepad2 size={36} /><strong>{gameTitle(title, link)}</strong><span>ROM CHECKER COLLECTION</span></div>}</div>
}
export function RommMetadata({ link, fileName }: { link?: RommLink; fileName: string }) {
  if (!hasMetadata(link)) return <section><h3>RomM metadata</h3><p className="small muted">No linked descriptive metadata is available. Publish and link this ROM or refresh its metadata in Settings → Connections.</p></section>
  const metadata = link!.metadata!
  const extra = metadata.metadatum && typeof metadata.metadatum === 'object' && !Array.isArray(metadata.metadatum) ? metadata.metadatum as Record<string, unknown> : {}
  const fields = [
    ['Genres', list(extra.genres ?? metadata.genres)], ['Platforms', list(extra.platforms ?? metadata.platforms)],
    ['Companies', list(extra.companies ?? metadata.companies)], ['Developers', list(extra.developers ?? metadata.developers)],
    ['Publishers', list(extra.publishers ?? metadata.publishers)], ['Release', text(extra.first_release_date ?? metadata.release_date ?? metadata.release_year)],
    ['Game modes', list(extra.game_modes ?? metadata.game_modes)], ['Franchises', list(extra.franchises ?? metadata.franchises)],
  ].filter(([, value]) => value)
  return <section className="romm-description"><h3>RomM description</h3><div className="romm-detail-heading"><Cover key={link!.entryId} link={link} title={fileName} /><div><h3>{text(metadata.name) || fileName}</h3><p className="small muted">RomM #{link!.rommId ?? 'pending'} · {link!.status} · Updated {date(link!.updated)}</p><p className="romm-summary">{text(metadata.summary) || 'No description supplied by RomM.'}</p></div></div>{fields.length > 0 && <dl className="catalog-evidence">{fields.map(([name, value]) => <div key={name}><dt>{name}</dt><dd>{value}</dd></div>)}</dl>}<p className="small muted">Descriptive metadata is provided by RomM, not verification evidence. Covers are fetched only through this server’s safe artwork proxy.</p></section>
}
