import { useId, useState } from 'react'

type Props = {
  title: string
  choices: { id: string; name: string }[]
  selected: string[]
  change: (selected: string[]) => void
  disabled: boolean
  empty: string
  scope?: { any: boolean; change: (any: boolean) => void }
}

export default function RommChecklist({ title, choices, selected, change, disabled, empty, scope }: Props) {
  const id = useId()
  const [query, setQuery] = useState('')
  const available = new Set(choices.map(choice => choice.id))
  const values = [...choices, ...selected.filter(value => !available.has(value))
    .map(value => ({ id: value, name: `${value} (not currently available)` }))]
  const shown = values.filter(value => value.name.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()))
  const invalid = scope && !scope.any && !selected.length
  return <fieldset className="romm-checklist" disabled={disabled}>
    <legend>{title}</legend>
    <div className="row spread romm-checklist-heading">
      <span className="small muted" aria-live="polite">{scope?.any ? 'Unrestricted' : `${selected.length} selected`}</span>
      {scope && <span className="small muted">Publishing filter</span>}
    </div>
    {scope && <div className="romm-scope">
      <label className="catalog-check"><input type="radio" name={`${id}-scope`} checked={scope.any}
        onChange={() => { scope.change(true); change([]) }} />Any {title.toLowerCase()}</label>
      <label className="catalog-check"><input type="radio" name={`${id}-scope`} checked={!scope.any}
        onChange={() => scope.change(false)} />Selected {title.toLowerCase()}</label>
    </div>}
    {!scope?.any && <>
      <label className="romm-checklist-search" htmlFor={`${id}-search`}>Search {title.toLowerCase()}
        <input id={`${id}-search`} name={`${title} search`} type="search" autoComplete="off" value={query} onChange={event => setQuery(event.target.value)} />
      </label>
      <div className="row wrap romm-checklist-actions">
        <button type="button" disabled={disabled || !shown.length || shown.every(value => selected.includes(value.id))}
          onClick={() => change([...new Set([...selected, ...shown.map(value => value.id)])])}>Select all shown</button>
        <button type="button" disabled={disabled || !selected.length} onClick={() => change([])}>Clear selection</button>
      </div>
      {invalid && <p className="small notice error" role="alert">Select at least one option or choose Any {title.toLowerCase()}.</p>}
      <div className="romm-checklist-options">
        {shown.map(value => <label className="catalog-check romm-choice" key={value.id}>
          <input type="checkbox" name={title} value={value.id} checked={selected.includes(value.id)} onChange={event =>
            change(event.target.checked ? [...selected, value.id] : selected.filter(item => item !== value.id))} />
          <span>{value.name}</span>
        </label>)}
      </div>
      {!values.length ? <p className="small muted">{empty}</p>
        : !shown.length && <p className="small muted">No matching options. Your selections are unchanged.</p>}
    </>}
  </fieldset>
}
