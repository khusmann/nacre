# Architecture

## File Layout

```
R/
  app.R           nacreApp, nacreOutput, renderNacre
  primitives.R    When, Each, Index, Match/Case/Default, Output
  event.R         event_immediate, event_throttle, event_debounce
  process_tags.R  Tag tree walker — extracts reactive bindings, events, control flows
  mount.R         Mounts processed tags into a Shiny session (observers, lifecycle)
  nacre-package.R Package-level imports

inst/js/
  nacre.js        Client-side message handlers (vanilla JS, no build step)

examples/
  controlled_inputs.R  Controlled inputs bound to one reactiveVal
  todo.R               Todo app (Each, Index, When, dynamic lists)
  temperature.R        Bidirectional temperature converter (controlled inputs)
  module.R             Shiny module integration
```

## Two-Phase Rendering

nacre splits rendering into two phases: **process** and **mount**.

### Phase 1: `process_tags`

Walks the tag tree recursively and produces:

- **`tag`** — A clean HTML tag tree with all functions removed. Reactive
  attributes are replaced by stable auto-generated element IDs. Control-flow
  nodes become `<div style="display:contents">` placeholders.
- **`bindings`** — List of `{id, attr, fn}` for each reactive attribute.
- **`events`** — List of `{id, event, handler, mode, ms, leading, coalesce}` for
  each event callback.
- **`control_flows`** — List of `{type, id, ...}` for each `When`, `Each`,
  `Index`, or `Match` node.
- **`shiny_outputs`** — List of `{id, render_call}` for each `Output` node.

The tag tree is now plain HTML that can be sent to the client. All reactive
wiring is deferred to mount.

### Phase 2: `nacre_mount_processed`

Takes the output of `process_tags` and a Shiny `session`, then wires up:

1. **Reactive bindings** — Each binding gets an `observe()` that sends
   `nacre-attr` messages when the reactive value changes.
2. **Event handlers** — Each event gets an `observeEvent()` on a namespaced
   input ID (`nacre_ev_{id}_{event}`). The handler is dispatched based on its
   formal argument count (0, 1, or 2 args). Event registration is sent to the
   client as a `nacre-events` message.
3. **Shiny outputs** — Each output's render call is assigned to
   `session$output[[id]]`.
4. **Control-flow nodes** — Each node gets an `observe()` that manages its
   lifecycle (see below).

Returns a mount handle with `$tag` (the processed HTML) and `$destroy()` (tears
down all observers).

## Control Flow Lifecycle

Each control-flow type manages a `current_mount` — a mount handle from a
recursive `nacre_mount_processed` call.

**When** — Observes the condition. On change: destroys the current mount,
processes the active branch, sends a `nacre-swap` message, mounts the new
branch.

**Match** — Same pattern, but iterates cases to find the first truthy condition.

**Each** — Keyed by identity (like Solid's `For`). The callback receives each
item as a **plain value** and an optional index: `fn(item)` or `fn(item, i)`.
Currently destroys and recreates all items on any list change. Future: the `by`
argument will extract a comparable key from each item, enabling DOM node reuse —
kept items have their nodes reordered, new items are mounted, removed items are
destroyed. Needs a new client-side `nacre-reorder` message to insert, remove,
and reorder individual child nodes by ID.

**Index** — Keyed by position (like Solid's `Index`). The callback receives each
item as a **reactive accessor** (`reactiveVal`) and an optional index:
`fn(item)` or `fn(item, i)` where `i` is a fixed integer. If the length is
stable, each slot's `reactiveVal` is updated in place so existing observers fire
with the new values without DOM recreation. Currently does a full rebuild when
list length changes. Future: incremental add/remove — grow by appending new
slots, shrink by destroying trailing slots.

## Client-Side Protocol

`nacre.js` registers three Shiny custom message handlers:

### `nacre-attr`

```js
{id: "nacre-3", attr: "textContent", value: "Count: 42"}
```

Sets a DOM property or attribute. Special-cased properties: `value`, `disabled`,
`checked`, `selected`, `textContent` are set as JS properties (not HTML
attributes). Skips the update if the target element has focus and the attribute
is `value` (optimistic update).

### `nacre-swap`

```js
{id: "nacre-5", html: "<li>new content</li>"}
```

Calls `Shiny.unbindAll` on the element, replaces `innerHTML`, then calls
`Shiny.bindAll` to initialize any Shiny outputs in the new content.

### `nacre-events`

```js
[
  {
    id: "nacre-2",
    event: "input",
    inputId: "nacre_ev_nacre-2_input",
    mode: "throttle",
    ms: 100,
    leading: true,
    coalesce: true,
  },
];
```

For each entry, attaches a DOM event listener on the element. The listener reads
the element's `value` and sends it as a Shiny input via
`Shiny.setInputValue(inputId, {value, id}, {priority: "event"})`.

If `mode` is set, wraps the listener in a throttle or debounce. When `coalesce`
is true, the rate limiter also gates on server idle state (via
`Shiny.shinyapp.$idleTimeout`), so events never queue faster than the server can
process them.

## Remaining Work

### `Each` — keyed reordering

Currently destroys and recreates all items on any list change. The callback
already receives plain values (not accessors), matching the target Solid `For`
semantics. Needs:

- `by` argument evaluation — extract comparable keys, diff old vs new.
- Per-item mount handles instead of one mount for the whole list.
- Diff old vs new keys to reorder, add, and remove individual items.
- New `nacre-reorder` client-side message to insert, remove, and reorder child
  nodes by ID (since `nacre-swap` replaces innerHTML wholesale).

### `Index` — incremental add/remove

Currently does a full rebuild when list length changes. Needs:

- Per-slot mount handles instead of one mount for the whole list.
- When list grows: append new slots, leave existing ones untouched.
- When list shrinks: destroy trailing slots.
- Same-length updates already work (reactiveVal in-place update).

### `Portal` (planned)

Not yet implemented. Would render content into a different DOM target. Needs
`process_tags` handling and client-side support.

### `Catch` (planned)

Not yet implemented. Would provide error boundaries: if any `observe()` inside
the content tree errors, tear it down and render a fallback.

### Controlled input: optimistic updates

When a user types into a focused input, the server echoes the value back through
the reactive binding. Without care, this echo can cause cursor jumping or
overwrite characters the user typed while the server was processing. Conversely,
programmatic updates (e.g. clearing an input after form submission) must always
apply, even while the element is focused.

**Sequence numbers** solve this. Each event payload includes an incrementing
`__nacre_seq`. The R event observer stores it on
`session$userData$nacre_current_sequence` and registers `session$onFlushed` to
clear it after the flush completes. Binding observers attach the sequence to
`nacre-attr` messages when present. On the client, `nacre-attr` for `value` on a
focused element uses the sequence to decide:

- **Stale echo** (sequence < client's latest sent) → skip.
- **Current echo, same value** (sequence ≥ latest sent, `el.value === msg.value`)
  → no-op skip (avoids cursor position reset).
- **Server transform** (sequence ≥ latest sent, different value) → apply (e.g.
  server uppercases input).
- **Programmatic update** (no sequence) → always apply.

Key design points:

- **`onFlushed` for cleanup.** The sequence is stored as a plain (non-reactive)
  session variable so binding observers can read it without creating a reactive
  dependency. `session$onFlushed(once = TRUE)` clears it after the entire reactive
  chain settles — derived reactives and chained observers all see the sequence
  within the same flush, but the next flush starts clean.

- **Cross-element updates.** The R side stores both the sequence and the source
  element ID. Binding observers only attach the sequence when `b$id` matches the
  event source. If a button click's handler clears a text input, the text input's
  binding sees a different source and omits the sequence — so the client treats it
  as a programmatic update and applies it. Without this, the button's sequence
  (e.g. 1) would be compared against the text input's independent counter (e.g. 5)
  and incorrectly rejected as stale.

- **Multiple events in one flush.** If two event observers run in the same flush,
  the later one's sequence overwrites the earlier. This is correct — it means all
  bindings in that flush are tagged with the latest sequence, which is the most
  conservative (least likely to be considered stale).

- **`__nacre_seq` is excluded** from the `event_obj` passed to user handlers, so
  it is an internal-only field.

### Reactive child validation

Reactive children should return text only. Currently no validation — non-text
returns silently produce unexpected output.

### Testing

No test suite yet. Key areas: `process_tags` extraction, observer lifecycle for
each control-flow primitive, rate-limiting metadata propagation,
`nacreOutput`/`renderNacre` integration, module scoping.
