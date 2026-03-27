# nacre

**An extra layer of Shiny for Shiny.**

nacre is a thin rendering layer on top of Shiny that replaces `renderUI` with Solid-style fine-grained DOM bindings. Write your server logic with `reactiveVal` and `reactive` as usual — nacre just changes how reactivity connects to the DOM.

---

## The Problem

Shiny's UI layer has two modes, and both are broken:

**Static inputs** (`sliderInput`, `selectInput`) are uncontrolled. The browser owns the state. The server can only ask the client to change via `updateSliderInput`, `freezeReactiveValue`, etc. You can't drive an input from a `reactiveVal`.

**`renderUI`** is the escape hatch for dynamic content. But it destroys and recreates entire DOM subtrees on every change — causing flicker, lost input state, and expensive round-trips. It's the source of most Shiny performance and UX complaints.

Meanwhile, the reactive engine (`reactiveVal`, `reactive`, `observe`) is excellent. The problem isn't reactivity — it's how reactivity connects to the DOM.

---

## The Idea

One simple rule: **pass a function instead of a value to make any tag attribute reactive.**

The framework calls each reactive function inside its own `observe()`, scoped to that single DOM attribute. When the reactive value changes, only that attribute updates. No VDOM, no diffing, no DOM destruction.

```r
library(shiny)
library(nacre)

runNacreApp(function() {
  count <- reactiveVal(0)
  color <- reactiveVal("black")

  fluidPage(
    tags$h1(
      style = \() paste0("color:", color()),
      \() paste("Count:", count())
    ),
    tags$input(
      type = "range", min = 0, max = 100,
      value = count,
      onInput = \(e) count(as.numeric(e$target$value))
    ),
    tags$button(
      disabled = \() count() == 0,
      onClick = \() count(0),
      "Reset"
    )
  )
})
```

That's it. No new reactivity model. No hooks. No dependency arrays. Just Shiny reactives wired directly to DOM nodes.

---

## Usage

### Full nacre app — `runNacreApp`

When your entire app is nacre. All state is `reactiveVal`, all inputs are controlled. No `ui`/`server` split:

```r
runNacreApp(function() {
  name <- reactiveVal("")

  fluidPage(
    tags$input(type = "text", value = name,
      onInput = event_debounce(\(e) name(e$target$value), 150)),
    tags$p(\() paste("Hello,", name()))
  )
})
```

### Incremental adoption — `nacreOutput` / `renderNacre`

Drop nacre components into an existing Shiny app. Old Shiny inputs and nacre inputs coexist because they share the server function's scope:

```r
ui <- fluidPage(
  # Old Shiny input — untouched
  sliderInput("n", "N", 1, 100, 50),

  # Nacre component
  nacreOutput("filters"),

  # Old Shiny output — untouched
  plotOutput("plot")
)

server <- function(input, output, session) {
  # Nacre state — visible to both nacre and Shiny
  threshold <- reactiveVal(0.5)

  output$filters <- renderNacre({
    tags$div(
      tags$input(
        type = "range", min = 0, max = 1, step = 0.1,
        value = threshold,
        onInput = event_throttle(\(e) threshold(as.numeric(e$target$value)), 100)
      ),
      tags$span(\() paste("Threshold:", threshold()))
    )
  })

  output$plot <- renderPlot({
    mtcars |> head(input$n) |>
      dplyr::filter(mpg > threshold() * 30) |>
      ggplot2::ggplot(ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
  })
}

shinyApp(ui, server)
```

The migration path:

1. Start with a normal Shiny app
2. Drop in one `nacreOutput`/`renderNacre` for a painful `renderUI`
3. Gradually convert more components
4. Eventually switch to `runNacreApp` when the whole app is nacre
5. Old `sliderInput` etc still work at every stage

---

## Core Concepts

### Reactive Attributes

Any tag attribute can be static or reactive:

```r
# Static — set once, never changes
tags$div(class = "panel")

# Reactive — updates when the reactive changes
tags$div(class = \() if (is_active()) "panel active" else "panel")
```

The framework checks `is.function(val)` for each attribute. If it is, it wraps it in an `observe()` that sends a targeted DOM mutation when the value changes. If it isn't, it sets the attribute once during initial render.

Since `reactiveVal` and `reactive` are both functions, they work directly:

```r
name <- reactiveVal("hello")
upper_name <- reactive(toupper(name()))

tags$span(upper_name)   # works — reactive is a function
tags$span(name)         # works — reactiveVal is a function
tags$span(\() name())   # also works — anonymous function
```

### Controlled Inputs

Inputs are controlled by binding their `value` attribute to a `reactiveVal`:

```r
threshold <- reactiveVal(0.5)

tags$input(
  type = "range", min = 0, max = 1, step = 0.1,
  value = threshold,
  onInput = \(e) threshold(as.numeric(e$target$value))
)
```

The `reactiveVal` is the source of truth. The input reflects it. Setting `threshold(0.5)` from anywhere — an `observeEvent`, a timer, another input's callback — will update the slider.

Multiple inputs can share the same `reactiveVal`:

```r
name <- reactiveVal("")

tags$div(
  tags$input(type = "text", value = name,
    onInput = \(e) name(e$target$value)),
  tags$input(type = "text", value = name,
    onInput = \(e) name(e$target$value)),
  tags$input(type = "text", value = name,
    onInput = \(e) name(e$target$value))
)
```

Type in any one, the other two update. No `updateTextInput`. No `freezeReactiveValue`.

### Optimistic Updates

When a user interacts with an input, the browser updates the DOM locally and immediately. The event is then sent to the server, the `reactiveVal` updates, and the server sends confirmations back. The focused input skips the server confirmation (it already has the right value), while other inputs bound to the same `reactiveVal` get the update.

```
User types "h" in input1
  → input1 shows "h" immediately (browser native)
  → server receives "h", sets name("h")
  → observe() fires for input2 → client updates input2 to "h"
  → observe() fires for input3 → client updates input3 to "h"
  → observe() fires for input1 → client SKIPS (has focus)
```

The client JS is minimal:

```js
Shiny.addCustomMessageHandler('nacre-attr', function(msg) {
  const el = document.getElementById(msg.id);
  if (document.activeElement === el && msg.attr === 'value') {
    return; // don't fight the user
  }
  el[msg.attr] = msg.value;
});
```

---

## Control Flow Primitives

Because the component function runs **once** (like Solid, unlike React), you can't use plain `if`/`else` for conditional rendering — it would only evaluate at setup time. nacre provides five control flow primitives:

### When

Conditional rendering. Replaces `conditionalPanel` and most `renderUI` uses:

```r
logged_in <- reactiveVal(FALSE)

When(logged_in, 
  Dashboard(),
  otherwise = LoginPanel()
)
```

When the condition changes, the old content is torn down (its `observe()` calls destroyed) and the new content is mounted — atomically, in a single DOM swap. No flash of empty space.

### Match / Case

Multi-branch conditional:

```r
tab <- reactiveVal("home")

Match(
  Case(\() tab() == "home",    HomePage()),
  Case(\() tab() == "data",    DataPage()),
  Case(\() tab() == "settings", SettingsPage()),
  Default(NotFoundPage())
)
```

### Each

Dynamic lists. Replaces `renderUI(lapply(...))`:

```r
items <- reactiveVal(list("a", "b", "c"))

tags$ul(
  Each(items, \(item, index) {
    tags$li(\() item())
  }, key = "id")
)
```

Keyed by default — reordering items moves DOM nodes instead of recreating them.

### Portal

Render into a different part of the DOM (modals, tooltips, toasts):

```r
show_modal <- reactiveVal(FALSE)

When(show_modal,
  Portal("modal-root",
    tags$div(class = "modal",
      tags$p("Are you sure?"),
      tags$button("Close", onClick = \() show_modal(FALSE))
    )
  )
)
```

### Catch

Error boundaries for reactive subgraphs:

```r
Catch(
  DataPanel(),
  fallback = \(error) {
    tags$div(class = "error", \() error$message)
  }
)
```

If any `observe()` inside `DataPanel` errors, the fallback renders instead of crashing the session.

---

## Shiny Outputs

nacre handles text, attributes, and dynamic UI natively — but binary artifacts like plots, maps, and interactive tables need Shiny's existing render infrastructure. Rather than rebuilding that, `nacre_output` wraps any Shiny render/output pair so it can be used inline:

```r
nacre_output(render_fn, output_fn, expr, ...)
```

It auto-generates an output ID, wires up the render function, and returns the output tag — all in one call, in the same scope as your `reactiveVal`s:

```r
App <- function() {
  xcol <- reactiveVal("wt")
  ycol <- reactiveVal("mpg")

  fluidPage(
    tags$select(value = xcol, onChange = \(e) xcol(e$target$value),
      tags$option("wt"), tags$option("mpg"), tags$option("hp")
    ),

    nacre_output(renderPlot, plotOutput, {
      ggplot(mtcars, aes(.data[[xcol()]], .data[[ycol()]])) +
        geom_point()
    }),

    nacre_output(DT::renderDT, DT::DTOutput, {
      mtcars |> dplyr::select(all_of(c(xcol(), ycol())))
    })
  )
}
```

Under the hood:

```r
nacre_output <- function(render_fn, output_fn, expr, ...) {
  id <- nacre_auto_id()
  observe({ output[[id]] <- render_fn(expr, ...) })
  output_fn(id)
}
```

Works with any render/output pair — `renderPlot`/`plotOutput`, `renderLeaflet`/`leafletOutput`, `renderPlotly`/`plotlyOutput`, custom outputs. No registry, no magic. You pass both functions explicitly.

Convenience aliases for common pairs are optional:

```r
nacre_plot <- function(expr, ...) nacre_output(renderPlot, plotOutput, expr, ...)
```

---

## Event Rate Limiting

Two functions for controlling event frequency. A bare callback is always immediate.

### event_debounce

Waits until the user pauses for the specified duration. Good for text input:

```r
tags$input(
  type = "text",
  value = name,
  onInput = event_debounce(\(e) name(e$target$value), 150)
)
```

### event_throttle

Fires at most every N milliseconds while the event is active. Good for sliders and continuous interactions:

```r
tags$input(
  type = "range",
  value = threshold,
  onInput = event_throttle(\(e) threshold(as.numeric(e$target$value)), 100)
)
```

Passing `0` to either function disables rate limiting.

There are no implicit defaults. If you write a bare `\()` callback, it fires on every event. You add rate limiting explicitly when you want it.

---

## How It Works Internally

### Initial Render

The component function runs once. The framework walks the tag tree and:

1. For each element, sends a `create` message to the client
2. For each static attribute, sends a one-time `attr` message
3. For each reactive attribute (function), creates an `observe()` that sends `attr` messages when the value changes
4. For each control flow node (`When`, `Each`, etc.), creates an `observe()` that manages DOM structural changes

```r
# Pseudocode: framework processes a tag
build_element <- function(tag) {
  el_id <- new_id()
  send_client(list(op = "create", id = el_id, tag = tag$name))

  for (attr_name in names(tag$attribs)) {
    val <- tag$attribs[[attr_name]]
    if (is.function(val)) {
      observe({
        send_client(list(
          op = "attr", id = el_id,
          attr = attr_name, value = val()
        ))
      })
    } else {
      send_client(list(
        op = "attr", id = el_id,
        attr = attr_name, value = val
      ))
    }
  }
}
```

### On State Change

When a `reactiveVal` changes:

1. Shiny's reactive graph invalidates dependent `observe()` calls
2. Each fires independently, producing a targeted DOM mutation
3. Each mutation is a small message: `{op: "attr", id: "span_3", attr: "textContent", value: "Count: 42"}`
4. Client applies each mutation directly — no diffing, no tree reconstruction

### Component Lifecycle

When a `When` or `Match` swaps content:

1. The outgoing branch's `observe()` calls are destroyed via `o$destroy()`
2. The incoming branch's tag tree is built (creating new `observe()` calls)
3. The client receives a single `swap` message with the new content

No orphaned observers polluting the reactive graph.

---

## Comparison

### vs renderUI

| | renderUI | nacre |
|---|---|---|
| Granularity | Entire subtree | Single attribute |
| DOM stability | Destroyed & recreated | Persistent, surgically patched |
| Input state | Lost on re-render | Preserved |
| Server work | Build full HTML | Format one value |
| Wire traffic | Full HTML string | Tiny JSON message |
| Flicker | Yes | No |

### vs Sparkle (React VDOM approach)

| | Sparkle | nacre |
|---|---|---|
| Reactivity model | New (use_state, use_memo) | Existing (reactiveVal, reactive) |
| Rendering | VDOM diff per component | observe() per attribute |
| Component function | Re-runs on every change | Runs once |
| Learning curve | Learn React model | One new concept |
| Server work per update | Rebuild VDOM, diff, serialize | Fire affected observe() calls |
| Wire traffic | VDOM patch | Individual attr mutations |

### vs Shiny (current)

| | Shiny today | nacre |
|---|---|---|
| Inputs | Uncontrolled (browser owns state) | Controlled (reactiveVal owns state) |
| Dynamic UI | renderUI (destroy/recreate) | Functions-as-attributes |
| Driving inputs | updateSliderInput + freezeReactiveValue | Just set the reactiveVal |
| Server code | Identical | Identical |
| Reactive engine | reactiveVal, reactive, observe | Same |

---

## Full API Surface

### From Shiny (unchanged)

- `reactiveVal()` — readable/writable reactive state
- `reactive()` — derived reactive computation
- `observe()` — side effects
- `observeEvent()` — event-driven side effects
- `tags$*` — HTML elements
- `renderPlot`, `renderTable`, etc. — existing outputs (still work)

### New in nacre

| Function | Purpose |
|---|---|
| `runNacreApp(fn)` | Run a full nacre app |
| `nacreOutput(id)` / `renderNacre(expr)` | Drop nacre into an existing Shiny app |
| `When(condition, yes, otherwise)` | Conditional rendering |
| `Match(Case(...), ..., Default(...))` | Multi-branch conditional |
| `Each(reactive_list, fn, key)` | Dynamic lists |
| `Portal(target_id, content)` | Render elsewhere in DOM |
| `Catch(content, fallback)` | Error boundary |
| `nacre_output(render_fn, output_fn, expr, ...)` | Inline Shiny output (any render/output pair) |
| `event_debounce(fn, ms)` | Debounce an event callback |
| `event_throttle(fn, ms)` | Throttle an event callback |

That's it. Ten functions on top of existing Shiny.

---

## Example: Full Dashboard

```r
library(shiny)
library(nacre)

runNacreApp(function() {
  # State — all reactiveVals
  dataset <- reactiveVal("mtcars")
  threshold <- reactiveVal(0)
  selected_col <- reactiveVal(NULL)
  show_settings <- reactiveVal(FALSE)

  # Derived — all reactive()
  df <- reactive(get(dataset()))
  cols <- reactive(names(df()))
  filtered <- reactive(df() |> dplyr::filter(.data[[selected_col()]] > threshold()))
  row_count <- reactive(nrow(filtered()))

  # Auto-select first column when dataset changes
  observe({
    selected_col(cols()[1])
    threshold(0)
  })

  fluidPage(
    tags$header(
      tags$h1(\() paste("Exploring:", dataset())),
      tags$button(
        \() if (show_settings()) "Hide Settings" else "Show Settings",
        onClick = \() show_settings(!show_settings())
      )
    ),

    When(show_settings,
      tags$div(class = "settings",
        tags$select(
          value = dataset,
          onChange = \(e) dataset(e$target$value),
          tags$option("mtcars"),
          tags$option("iris"),
          tags$option("airquality")
        ),
        tags$select(
          value = selected_col,
          onChange = \(e) selected_col(e$target$value),
          Each(cols, \(col) tags$option(value = col, col))
        ),
        tags$input(
          type = "range",
          min = 0, max = 100,
          value = threshold,
          onInput = event_throttle(
            \(e) threshold(as.numeric(e$target$value)), 100
          )
        )
      )
    ),

    tags$main(
      tags$p(\() paste("Showing", row_count(), "of", nrow(df()), "rows")),
      tags$p(
        class = \() if (row_count() == 0) "warning" else "",
        \() if (row_count() == 0) "No rows match the filter." else ""
      ),

      nacre_output(renderPlot, plotOutput, {
        ggplot(filtered(), aes(.data[[selected_col()]], .data[["mpg"]])) +
          geom_point()
      })
    )
  )
})
```

---

## Implementation Plan

### Phase 1: Core rendering

- Auto-inject nacre client JS when reactive attributes are detected
- Functions-as-attributes → `observe()` binding
- Client-side message handler for attr updates
- Optimistic update handling (skip focused element)

### Phase 2: Controlled inputs

- Text, range, select, checkbox, radio
- `onInput`, `onChange`, `onClick` event forwarding
- `event_debounce`, `event_throttle`

### Phase 3: Control flow

- `When` / `Match` / `Case` with observer lifecycle management
- `Each` with keyed list diffing
- `Portal`
- `Catch`

### Phase 4: Shiny integration

- `runNacreApp` for full nacre apps
- `nacreOutput` / `renderNacre` for incremental adoption in existing Shiny apps
- `nacre_output` for inline Shiny render/output pairs
- Coexistence with regular Shiny inputs and outputs
- Module support (`NS()` scoping)

---

## Design Principles

1. **No new reactivity model.** `reactiveVal` and `reactive` are the API. No signals, no hooks, no dependency arrays.

2. **Functions-as-attributes is the only new concept.** If you know Shiny, you can learn nacre in five minutes.

3. **Surgical updates.** One reactive changes, one DOM attribute updates. Nothing else is touched.

4. **Explicit rate limiting.** No hidden debounce or throttle. You add `event_debounce` or `event_throttle` when you want it. A bare callback is immediate.

5. **Controlled inputs by default.** The `reactiveVal` is the source of truth. The DOM reflects it.

6. **Existing Shiny outputs still work.** `renderPlot`, `renderTable`, `renderUI` — use them alongside nacre. Migrate incrementally.

7. **Small API.** Ten new functions. Everything else is Shiny you already know.
