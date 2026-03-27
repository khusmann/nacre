# -- Conditional rendering ------------------------------------------------

#' @export
When <- function(condition, yes, otherwise = NULL) {
  structure(
    list(condition = condition, yes = yes, otherwise = otherwise),
    class = "nacre_when"
  )
}

# -- List rendering -------------------------------------------------------

#' @export
Each <- function(items, fn) {
  # TODO: implement keyed-by-identity rendering (reorder DOM nodes instead

  # of recreating) to preserve per-item state across list mutations.
  structure(
    list(items = items, fn = fn),
    class = "nacre_each"
  )
}

#' @export
Index <- function(items, fn) {
  # TODO: implement incremental add/remove instead of full rebuild on
  # length change, so existing slots keep their observers.
  structure(
    list(items = items, fn = fn),
    class = "nacre_index"
  )
}

# -- Pattern matching -----------------------------------------------------

#' @export
Case <- function(condition, content) {
  list(condition = condition, content = content)
}

#' @export
Default <- function(content) {
  list(condition = function() TRUE, content = content)
}

#' @export
Match <- function(...) {
  cases <- list(...)
  structure(
    list(cases = cases),
    class = "nacre_match"
  )
}

# -- Shiny output wrapper -------------------------------------------------

#' @export
Output <- function(render_fn, output_fn, expr, ...,
                   env = parent.frame()) {
  id <- nacre_next_id()
  expr_q <- substitute(expr)
  render_call <- eval(as.call(list(substitute(render_fn), expr_q)), env)
  result <- list(
    id = id,
    output_tag = output_fn(id, ...),
    render_call = render_call
  )
  class(result) <- "nacre_output"
  result
}

#' @export
PlotOutput <- function(expr, ..., env = parent.frame()) {
  Output(renderPlot, plotOutput, expr, ..., env = env)
}

#' @export
TableOutput <- function(expr, ..., env = parent.frame()) {
  Output(renderTable, tableOutput, expr, ..., env = env)
}

#' @export
DTOutput <- function(expr, ..., env = parent.frame()) {
  if (!requireNamespace("DT", quietly = TRUE)) {
    stop("Package 'DT' is required for DTOutput(). Install it with install.packages('DT').")
  }
  Output(DT::renderDT, DT::DTOutput, expr, ..., env = env)
}

# -- Portal (stub) --------------------------------------------------------

#' @export
Portal <- function(target, content) {
  structure(
    list(target = target, content = content),
    class = "nacre_portal"
  )
}

# -- Error boundary (stub) -----------------------------------------------

#' @export
Catch <- function(content, fallback) {
  structure(
    list(content = content, fallback = fallback),
    class = "nacre_catch"
  )
}
