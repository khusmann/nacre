# Plan: `nacre_output` — Inline Shiny Outputs

## Goal

Add `nacre_output()` so that standard Shiny render/output pairs (`renderPlot`/`plotOutput`, `DT::renderDT`/`DT::DTOutput`, etc.) can be used inline in nacre tag trees without manual ID wiring.

## API

```r
nacre_output(render_fn, output_fn, expr, ...)
```

- `render_fn` — a Shiny render function (e.g. `renderPlot`)
- `output_fn` — matching UI output function (e.g. `plotOutput`)
- `expr` — expression passed to `render_fn` (unquoted, uses standard NSE)
- `...` — extra args forwarded to `output_fn` (e.g. `height = "400px"`)

Returns the output tag (result of `output_fn(id, ...)`), ready to be placed in a nacre tag tree.

## Design

`nacre_output` needs to:

1. Generate a unique output ID via `nacre_next_id()`
2. Get the current session
3. Register the render function on `session$output` using the generated ID
4. Return the output UI tag

The key subtlety: `render_fn` expects an expression, not a value. We need to capture `expr` and pass it to `render_fn` correctly with NSE. The cleanest approach is to capture the expression and evaluate the `render_fn(expr)` call in the caller's environment.

### Implementation

```r
nacre_output <- function(render_fn, output_fn, expr, ...,
                         env = parent.frame()) {
  id <- nacre_next_id()
  session <- getDefaultReactiveDomain()
  expr_q <- substitute(expr)
  session$output[[id]] <- eval(as.call(list(substitute(render_fn), expr_q)), env)
  output_fn(session$ns(id), ...)
}
```

Key details:
- `substitute(expr)` captures the expression before evaluation
- We build the call `render_fn(expr)` as a language object and eval in the caller's env, so `render_fn`'s NSE (e.g. `renderPlot`'s `exprToFunction`) sees the original expression
- `session$ns(id)` ensures module namespacing works correctly
- `...` is forwarded to `output_fn` for sizing, classes, etc.

### Integration with process_tags

No changes needed to `process_tags` or `mount.R`. The output tag returned by `output_fn()` is a normal `shiny.tag` — Shiny's output binding JS handles it automatically. The render function is registered on `session$output` immediately, so by the time the tag reaches the browser, the output is ready.

### Integration with When / control flow

When `nacre_output()` is used inside a `When()` branch, the output tag is processed when the branch activates. Shiny's output system handles the lifecycle — when the branch is swapped out and the DOM element is removed, Shiny automatically unbinds the output. No special cleanup is needed beyond what `When` already does.

## Changes

| File | Change |
|------|--------|
| `R/nacre_output.R` | Add `nacre_output()` function |
| `R/process_tags.R` | No changes needed |
| `R/mount.R` | No changes needed |
| `inst/js/nacre.js` | No changes needed |
| `examples/output.R` | New example |
| `NAMESPACE` | Export `nacre_output` |

## Example

```r
# examples/output.R
library(shiny)
library(bslib)
library(nacre)
library(ggplot2)

OutputApp <- function() {
  xcol <- reactiveVal("wt")
  ycol <- reactiveVal("mpg")
  columns <- names(mtcars)

  page_fluid(
    theme = bs_theme(bootswatch = "minty"),
    card(
      card_header("Scatter Plot Explorer"),
      card_body(
        layout_columns(
          col_widths = c(6, 6),
          tags$div(
            tags$label("X axis", class = "form-label"),
            tags$select(
              class = "form-select",
              value = xcol,
              onChange = \(value) xcol(value),
              lapply(columns, \(col) tags$option(value = col, col))
            )
          ),
          tags$div(
            tags$label("Y axis", class = "form-label"),
            tags$select(
              class = "form-select",
              value = ycol,
              onChange = \(value) ycol(value),
              lapply(columns, \(col) tags$option(value = col, col))
            )
          )
        ),
        nacre_output(renderPlot, plotOutput, {
          ggplot(mtcars, aes(.data[[xcol()]], .data[[ycol()]])) +
            geom_point(size = 3) +
            theme_minimal()
        }),
        tags$p(
          class = "text-muted text-center mt-2",
          \() paste("Plotting", xcol(), "vs", ycol())
        )
      )
    )
  )
}

nacreApp(OutputApp)
```

## Edge Cases to Verify

1. **Module namespacing** — `session$ns(id)` must be used so the output ID matches inside modules
2. **Multiple outputs** — each call gets a unique ID from `nacre_next_id()`
3. **Inside `When()` branches** — output should render when branch activates, Shiny unbinds when DOM is removed
4. **Third-party outputs** — `DT::renderDT`/`DT::DTOutput`, `leaflet::renderLeaflet`/`leaflet::leafletOutput`, etc. should work since the mechanism is generic
5. **Extra args** — `nacre_output(renderPlot, plotOutput, { ... }, height = "200px")` should forward `height` to `plotOutput`
