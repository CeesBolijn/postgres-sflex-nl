# resource_path — the resource tree

`relation.resource.resource_path` is an `ltree` that says where a resource sits
in the tree, coarse to specific. `resource_uid` stays the stable key that logs,
plans and lookups reference; the path is the classification and may change
when a machine moves or is renamed.

## level order

```
site . line_type . role . vendor . model . width . serial
```

| level | example | meaning |
|---|---|---|
| site | `dokkum`, `bad_hersfeld` | production location (tenant) |
| line_type | `sheet`, `roll` | the production line type (`relation.production_line.line_type`) |
| role | `printer`, `nester`, `cutter`, `coater`, `laminator` | what the resource does — the step it serves |
| vendor | `durst`, `printfactory`, `zund` | maker |
| model | `p5`, `g3` | model |
| width | `350`, `250` | width in cm |
| serial | `32768` | the machine itself |

Examples: `dokkum.sheet.printer.durst.p5.350.32768`,
`dokkum.sheet.nester.printfactory.durst.p5.350` (a software resource: no
serial, the last levels say which printer it nests for).

Rules:
- labels are `A-Z a-z 0-9 _` (and `-` from PostgreSQL 16); no dots or spaces
  inside a label, so `bad_hersfeld`, not `bad hersfeld`
- the order is fixed; a level that does not apply is simply the end of the
  path (a nester has no serial), never skipped in the middle
- new values at any level are data, not code: nothing reads a specific label

## querying

```sql
-- everything under a branch
where r.resource_path <@ 'dokkum.sheet.printer'
-- the printers of one vendor anywhere
where r.resource_path ~ '*.printer.durst.*'
-- how deep
nlevel(r.resource_path)
-- the site of a resource
subpath(r.resource_path, 0, 1)
```

Indexes: `uq_resource_path` (btree, partial on not null) for equality and
sorting, `idx_resource_path_gist` for `<@`, `@>`, `~`.

## where else the path lives

- `action.lane.resource_paths` (`ltree[]`) — a lane of a production plan is one
  or more interchangeable resources; the lane records their paths as they were
  when the plan was made (a snapshot, so a later move does not rewrite
  history). The first element is the primary one: it names the lane and
  decides its tenant. Material lanes of the nest plan leave it null. Matching:
  `resource_path = any (lane.resource_paths)`; tree queries on the array with
  `resource_paths @> 'dokkum.sheet'` (contains an ancestor) via the
  `gist__ltree_ops` index.
- `action.cutoff_time.rule_path` is **not** this tree: an ltree of ids
  (`tenant.line.material`); same type, different tree.
- `action.non_working_times.rule_path` is still text with the same id shape.
