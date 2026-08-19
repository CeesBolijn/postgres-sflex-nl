# catalog.formula — versioned formulas

A formula is a small program the evaluator (`evaluate_many_nas`) runs over a
set of variables: an ordered list of `name = expression` lines in
`formula_json`, e.g. `["gross_sqm = sqm / (1 - waste_perc)",
"impact = gross_sqm * seconds_per_sqm"]`. The xbom names which formula an
item uses; the manifest evaluates it with the spec's amount, width, height and
the item's `param_json`.

## the table

| column | meaning |
|---|---|
| `formula_id` | identity, the row key; nothing outside this table refers to it |
| `formula_code` | the name the formula is known by; **every version shares the code**; this is what `catalog.xbom.formula_code` refers to |
| `formula_json` | the lines, in evaluation order |
| `formula_level` | evaluation order across formulas: level 0 first; a level 1 formula may use the results of level 0 |
| `version` | 1, 2, 3 … per code; `unique (formula_code, version)` |
| `status` | `draft` → `pending-approval` → `active` → `archived` |
| `created_at` | **the moment this version starts to apply** — set when it becomes active, not when the draft is typed |

Constraints: at most one `active` per code (`uq_formula_code_active`);
`status` is one of the four; the as-of lookup has an index on
`(formula_code, created_at desc)` for active/archived rows.

## which version applies

The version that applies at a moment `T` is the newest row of the code with
`created_at <= T` and status `active` or `archived`. `archived` counts:
a version that was active in June still applies to everything made in June.
`draft` and `pending-approval` never apply.

```sql
select * from catalog.get_formula(array['gross-sqm', 'print-impact'], p_at => '2026-06-10');
```

returns one row per code, ordered by `formula_level` (lowest first) so the
caller evaluates them in that order. `p_at` defaults to `now()`; a third
parameter `p_statuses` (default `{active,archived}`) lets a preview ask for
`{draft}` or `{pending-approval,active,archived}`.

The caller decides `T`: the order date when recalculating an old order,
`now()` for a new calculation. The manifest stores the *result* of the
evaluation (`spec_unit_manifest`), so an old manifest is never rewritten by a
new formula version — recomputing it with the same `T` gives the same answer.

## how mutations go

**Rows are never updated once they apply, and never deleted.** History is
rows, not overwritten values.

| you want to | you do |
|---|---|
| a new formula | `insert` version 1 as `draft` |
| change a formula that is active | `insert` a new row with the same `formula_code`, `version = max + 1`, status `draft`, and the changed `formula_json` — the active row is not touched |
| edit a draft | `update formula_json` on the draft row itself; a draft has never applied, so editing it in place loses nothing. The same for `pending-approval` |
| submit for approval | `update status = 'pending-approval'` |
| approve / activate | one transaction: `update` the current `active` of that code to `archived`; `update` the new one to `active` **and `created_at = now()`** (or the moment it should start applying). From now on `get_formula(now())` returns the new one; `get_formula(<earlier>)` still returns the old one |
| roll back | do not flip statuses back: `insert` a new version with the old `formula_json` and activate it — the timeline stays honest |
| retire a code | archive the active version without activating a new one; from that moment `get_formula(now())` returns nothing for the code, older `T` still resolve |
| change the code name | that is a new code: new rows under the new name, xbom rows repointed; the old code archives. Codes are identifiers, not labels |

`formula_level` and `formula_code` are properties of the code, not of a
version: give every version of a code the same level.

## the crud

`catalog.crud_formula(p_param_json jsonb, p_no_results boolean)` — one call,
set-based over `jsonb_array_elements`, one element per intended row:

```json
[
  { "formula_code": "gross-sqm", "formula_json": ["gross_sqm = sqm / (1 - waste_perc)"], "formula_level": 0 },
  { "formula_id": 17, "status": "pending-approval" },
  { "formula_id": 18, "status": "active" }
]
```

- an element without `formula_id` inserts a new version of its code
  (`version = coalesce(max(version), 0) + 1`, status `draft`)
- an element with `formula_id` and `formula_json` updates that row **only if**
  its status is `draft` or `pending-approval` — otherwise the call refuses
  (`raise exception`), because that row applies or has applied
- an element with `formula_id` and `status = 'active'` archives the current
  active row of the same code and activates this one with `created_at =
  coalesce(element.created_at, now())`, in the same statement set
- `ON CONFLICT DO UPDATE` is not used here: a version is a new row by design;
  the only in-place writes are the draft edit and the status flips

(The function is not written yet; this is the contract it will follow.)

## reading from the xbom

```sql
-- the applying formula per xbom row of these option codes, at T
select x.option_code, x.item_code, x.scope, f.version, f.formula_json
from catalog.xbom x
join catalog.get_formula(
         (select array_agg(distinct x2.formula_code) from catalog.xbom x2 where x2.option_code = any ($codes)),
         $t) f
  on f.formula_code = x.formula_code
where x.option_code = any ($codes)
order by f.formula_level, x.sort_order;
```

`catalog.xbom` is versioned the same way (`version`, `status`, `created_at`);
the same as-of rule applies there, with its own helper when it is needed.

## do not

- do not `update formula_json` on an `active` or `archived` row — insert a version
- do not `delete` — archive
- do not set `created_at` on a draft to the drafting moment and leave it there
  when activating — that back-dates the version
- do not put the version in the code (`gross-sqm-v2`); the code is stable,
  the version is a column
