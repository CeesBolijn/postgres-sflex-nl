# data group layout: grid, col-span and responsive classes

Reference for the layout classes in `json/data_group/*.json`. Source:
Tailwind 4 docs (responsive-design, grid-column, grid-template-columns,
detecting-classes-in-source-files), checked August 2026.

## two keys

| key | on | means | typical value |
|---|---|---|---|
| `fields_class_name` | every block with a `field_config` (block, tooltip section, group, label options) | the grid the fields are rendered in | `grid grid-cols-6 gap-1` |
| `ui.class_name` | a field | the class of that field's own cell | `col-span-3 text-right` |

`fields_class_name` opens the grid, each field's `ui.class_name` says how many
columns it takes. Fields without `col-span-*` take one column. A plain
`class_name` elsewhere is always the class of that element itself
(`row_options.class_name`), never the grid of its fields.

## grid basics

| class | css | meaning |
|---|---|---|
| `grid` | `display: grid` | the section becomes a grid |
| `grid-cols-<n>` | `grid-template-columns: repeat(n, minmax(0, 1fr))` | n equal columns |
| `gap-1` | `gap: 0.25rem` (4px) | space between cells |
| `col-span-<n>` | `grid-column: span n / span n` | the field takes n columns |
| `col-span-full` | `grid-column: 1 / -1` | the whole row |
| `col-start-<n>` / `col-end-<n>` | `grid-column-start/end: n` | fixed position, rarely needed |

Any integer works for `<n>` in Tailwind 4 (no 1–12 limit). Fields fill the
grid left to right, top to bottom, in `ui.order`; a field that does not fit
on the current row wraps to the next one. Keep the spans of one row adding up
to `grid-cols-<n>`, otherwise a row ends with a hole.

## mobile first

- unprefixed = every width: `col-span-6`
- prefixed = that width **and up**: `md:col-span-3`
- later (wider) prefixes win over earlier ones, so read left to right as
  "start full width, then narrower as there is more room":
  `col-span-6 md:col-span-3 xl:col-span-2`
- there is **no `xs`** prefix; the unprefixed class is the smallest size
- `max-md:` = below that width only; `md:max-xl:` = a range

### viewport breakpoints (`sm:` … `2xl:`) — the size of the browser window

| prefix | from | css |
|---|---|---|
| `sm:` | 40rem / 640px | `@media (width >= 40rem)` |
| `md:` | 48rem / 768px | `@media (width >= 48rem)` |
| `lg:` | 64rem / 1024px | `@media (width >= 64rem)` |
| `xl:` | 80rem / 1280px | `@media (width >= 80rem)` |
| `2xl:` | 96rem / 1536px | `@media (width >= 96rem)` |

## container queries (`@sm:` … `@7xl:`) — the size of the widget

A data group is rendered in a sidebar, a tooltip, a half page or a full page.
The window width says nothing about the room a widget has, the width of its
own container does. That is what container queries measure, so **prefer these
in data groups**.

1. put `@container` in the block's `fields_class_name` (next to `grid …`)
2. use `@md:`, `@2xl:` … in the `ui.class_name` of the fields inside it

```json
"fields_class_name": "@container grid grid-cols-6 gap-1"
...
"ui": { "class_name": "col-span-6 @md:col-span-3 @2xl:col-span-2" }
```

Read: full width when the section is narrow, half from 448px, a third from
672px. Container variants work the same as viewport ones: mobile first,
`@max-md:` for below, `@sm:@max-md:` for a range.

| prefix | container from | css |
|---|---|---|
| `@3xs:` | 16rem / 256px | `@container (width >= 16rem)` |
| `@2xs:` | 18rem / 288px | `@container (width >= 18rem)` |
| `@xs:` | 20rem / 320px | `@container (width >= 20rem)` |
| `@sm:` | 24rem / 384px | `@container (width >= 24rem)` |
| `@md:` | 28rem / 448px | `@container (width >= 28rem)` |
| `@lg:` | 32rem / 512px | `@container (width >= 32rem)` |
| `@xl:` | 36rem / 576px | `@container (width >= 36rem)` |
| `@2xl:` | 42rem / 672px | `@container (width >= 42rem)` |
| `@3xl:` | 48rem / 768px | `@container (width >= 48rem)` |
| `@4xl:` | 56rem / 896px | `@container (width >= 56rem)` |
| `@5xl:` | 64rem / 1024px | `@container (width >= 64rem)` |
| `@6xl:` | 72rem / 1152px | `@container (width >= 72rem)` |
| `@7xl:` | 80rem / 1280px | `@container (width >= 80rem)` |

Note the scale differs from the viewport one: `@md` is 448px, `md:` is 768px.

Named containers (`@container/main` … `@md/main:col-span-2`) measure a
specific ancestor instead of the nearest one; only needed with nested grids
that must follow the outer width. One-off sizes: `@min-[475px]:col-span-2`.

## the class must exist

Tailwind generates css only for class names it finds as plain text in the
scanned source files. The data group json lives in the database, not in the
front-end source, so a class used only there is **not generated** unless it is
safelisted in the front-end css:

```css
@source inline("{@md:,@2xl:,}col-span-{1..12}");
```

Rule: only use classes that are already in use (below) or that are safelisted.
Never build class names from data.

### classes in use today

`grid` `gap-1` `grid-cols-{1,3,4,5,6,7,8,9,12}` `col-span-{1..6,12}`
`col-span-full` `md:col-span-{1,2,3,4}` `@container` `@2xl:col-span-{1,2,3}`
`hidden` `text-xs` `text-right` `font-medium` `font-semibold`

## how to lay out a section

- pick a column count that divides well: `grid-cols-6` (halves, thirds) or
  `grid-cols-12` (also quarters); the whole file should use as few different
  counts as possible
- long text (names, references) gets a wide span, numbers a narrow one and
  `text-right`
- narrow: everything full width; from `@md`: two per row; from `@2xl`: three
  or four per row — one recipe, reused everywhere
- a hidden field (`ui.hidden: true`) takes no cell, so it needs no span
- a `group` (repeated block over `data_field`) is its own grid: it repeats
  its `fields_class_name` grid per item and its fields span inside that grid
