import { useEffect, useState } from 'react'
import { api, label } from '../../api'
import { Badge } from '../../components/Presentation'
import RommChecklist from './RommChecklist'

export type PublishRules = {
  referenceRequirement: 'eligible' | 'matched'
  consoles: string[]; regions: string[]; categories: string[]; batchIds: string[]
  allowFilenameRegions: boolean; includeUnknownRegions: boolean
}
export const defaultPublishRules: PublishRules = {
  referenceRequirement: 'eligible', consoles: [], regions: [], categories: [], batchIds: [],
  allowFilenameRegions: false, includeUnknownRegions: false,
}
type Options = { consoles: string[]; regions: string[]; categories: string[]; imports: { id: string; name: string }[] }
type Preview = {
  total: number; matched: number; ready: number; excluded: number; pending: number; linked: number; failed: number
  page: number; size: number
  items: { id: string; name: string; files: number; console: string; status: string; reason: string
    regions: { values: string[]; source: string }[] }[]
}
type Filter = 'consoles' | 'regions' | 'categories' | 'batchIds'
type Props = {
  rules: PublishRules; change: (rules: PublishRules) => void; disabled: boolean; consoles: string[]
  autoPublish: boolean; toggleAutoPublish: (enabled: boolean) => void; validityChange: (valid: boolean) => void
}

export default function RommPublishRules({ rules, change, disabled, consoles, autoPublish, toggleAutoPublish, validityChange }: Props) {
  const [restricted, setRestricted] = useState<Record<Filter, boolean>>(() => ({
    consoles: rules.consoles.length > 0, regions: rules.regions.length > 0,
    categories: rules.categories.length > 0, batchIds: rules.batchIds.length > 0,
  }))
  const valid = (Object.keys(restricted) as Filter[]).every(field => !restricted[field] || rules[field].length > 0)
  useEffect(() => { validityChange(valid) }, [valid, validityChange])
  const [options, setOptions] = useState<Options>()
  const [optionsError, setOptionsError] = useState('')
  const [preview, setPreview] = useState<{ key: string; value: Preview }>()
  const [previewError, setPreviewError] = useState('')
  const [loading, setLoading] = useState(false)
  const key = JSON.stringify(rules)
  const current = valid && preview?.key === key ? preview.value : undefined
  async function loadOptions() {
    setOptionsError('')
    try { setOptions(await api<Options>('/romm/publish-options')) }
    catch (error) { setOptionsError(error instanceof Error ? error.message : String(error)) }
  }
  useEffect(() => { void loadOptions() }, [])
  async function showPreview(page = 1) {
    setLoading(true); setPreviewError('')
    try {
      const value = await api<Preview>('/romm/auto-publish/preview', {
        method: 'POST', body: JSON.stringify({ rules, page, size: 25 }),
      })
      setPreview({ key, value })
    } catch (error) { setPreviewError(error instanceof Error ? error.message : String(error)) }
    finally { setLoading(false) }
  }
  function choose(field: Filter, title: string, values: { id: string; name: string }[]) {
    return <RommChecklist title={title} choices={values} selected={rules[field]} disabled={disabled}
      empty="No options available yet. Saved selections are retained."
      change={selected => change({ ...rules, [field]: selected })}
      scope={{ any: !restricted[field], change: any => setRestricted(previous => ({ ...previous, [field]: !any })) }} />
  }
  const named = (values: string[]) => values.map(value => ({ id: value, name: value }))
  return <section className="panel romm-section">
    <span className="eyebrow">ROM CHECKER TO ROMM</span>
    <h2>Publish to RomM</h2>
    <label className="catalog-check romm-automation"><input type="checkbox" disabled={disabled} checked={autoPublish}
      onChange={event => toggleAutoPublish(event.target.checked)} />Automatically publish eligible verified copies</label>
    <h3>Automatic publishing rules</h3>
    <p>Each filter must match; within a filter, any checked value matches. Choose Any to leave a filter unrestricted.
      Manual publishing still requires its own preview and confirmation.</p>
    <p className="small muted">Unchecked, unsafe, stale, or incomplete games always stay blocked. Primary game files must match the filters;
      companion files stay with their game and must still pass all required checks. Nothing here deletes or replaces existing RomM files.</p>
    {optionsError && <div role="alert" className="notice error">{optionsError}<button type="button" onClick={loadOptions}>Retry rule options</button></div>}
    <fieldset className="romm-reference" disabled={disabled}><legend>Reference requirement</legend>
      <label className="catalog-check"><input type="radio" name="romm-reference" checked={rules.referenceRequirement === 'eligible'}
        onChange={() => change({ ...rules, referenceRequirement: 'eligible' })} />All policy-eligible files, including explicitly approved files</label>
      <label className="catalog-check"><input type="radio" name="romm-reference" checked={rules.referenceRequirement === 'matched'}
        onChange={() => change({ ...rules, referenceRequirement: 'matched' })} />Reference matches only (approval is not enough)</label>
    </fieldset>
    <div className="romm-rule-grid">
      {choose('consoles', 'Consoles', named([...new Set([...(options?.consoles ?? []), ...consoles])].sort()))}
      {choose('categories', 'Game categories', (options?.categories ?? []).map(value => ({ id: value, name: label(value) })))}
      {choose('batchIds', 'Imports', options?.imports ?? [])}
      <div className="romm-region-group">
        {choose('regions', 'Regions', named(options?.regions ?? []))}
        <div className="romm-region-options">
        <p className="small muted">Region options only apply when Selected regions is active.</p>
        <label className="catalog-check"><input type="checkbox" disabled={disabled} checked={rules.allowFilenameRegions}
          onChange={event => change({ ...rules, allowFilenameRegions: event.target.checked })} />Allow filename-inferred regions</label>
        <label className="catalog-check"><input type="checkbox" disabled={disabled} checked={rules.includeUnknownRegions}
          onChange={event => change({ ...rules, includeUnknownRegions: event.target.checked })} />Include unknown or disallowed-source regions</label>
        <details><summary>How regions are determined</summary><p className="small muted">Regions come from checked DAT/hash-match titles, otherwise from filename tags.
          Filename inference is not verification evidence. Multi-region games match any selected region.
          World is a separate value, not every region. Unknown or filename-only regions are held for review by default.</p></details>
        </div>
      </div>
    </div>
    <p className="small muted">Preview uses draft rules and saved platform mappings, without saving or transferring files.
      Save RomM settings to apply changes. Rules are rechecked before export; existing exports remain available.</p>
    <button type="button" disabled={disabled || loading || !valid} onClick={() => showPreview()}>Preview draft publishing rules</button>
    {loading && <p role="status">Evaluating publishing rules...</p>}
    {previewError && <p role="alert" className="notice error">{previewError}</p>}
    {current && <div>
      <p role="status">{current.total} games · {current.matched} match rules · {current.ready} ready · {current.excluded} excluded · {current.pending} pending · {current.linked} linked · {current.failed} need retry</p>
      <div className="integration-list">{current.items.map(group => <article className="integration-item" key={group.id}>
        <div className="row spread"><strong>{group.name}</strong><Badge value={group.status} /></div>
        <p className="small">{group.console} · {group.files} files · {group.reason}</p>
        <p className="small muted">{group.regions.map(region => `${region.values.join(', ') || 'Unknown region'} (${region.source})`).join('; ')}</p>
      </article>)}</div>
      {current.total > current.size && <div className="row">
        <button type="button" disabled={loading || current.page <= 1} onClick={() => showPreview(current.page - 1)}>Previous preview page</button>
        <span>Page {current.page} of {Math.ceil(current.total / current.size)}</span>
        <button type="button" disabled={loading || current.page * current.size >= current.total} onClick={() => showPreview(current.page + 1)}>Next preview page</button>
      </div>}
    </div>}
  </section>
}
