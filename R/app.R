#' Create a nacre application
#'
#' Builds a Shiny app from a nacre component function. The function is called
#' once at build time to produce the UI tag tree; reactive bindings and event
#' handlers are mounted automatically on the server side.
#'
#' @param fn A zero-argument function that returns a nacre tag tree
#'   (e.g. a `page_sidebar()` call containing reactive attributes and
#'   event handlers).
#' @param ... Additional arguments passed to [shiny::shinyApp()].
#' @return A Shiny app object.
#' @export
nacreApp <- function(fn, ...) {
  # Process the tag tree at build time so the app function's return value
  # (e.g. page_sidebar) becomes the actual document root, preserving proper
  # page-level theming. The server just mounts the reactive observers.
  tag_tree <- fn()
  result <- process_tags(tag_tree)
  ui <- htmltools::attachDependencies(result$tag, nacre_dependency())
  server <- function(input, output, session) {
    nacre_mount_processed(result, session)
  }
  shinyApp(ui, server, ...)
}

#' Create a nacre UI output placeholder
#'
#' Creates a [shiny::uiOutput()] with the nacre JavaScript dependency
#' attached. Use this in a standard Shiny UI to mark where [renderNacre()]
#' should inject its content.
#'
#' @param id The output ID, matching the corresponding `renderNacre` call.
#' @return An HTML tag with the nacre dependency.
#' @export
nacreOutput <- function(id) {
  htmltools::attachDependencies(
    uiOutput(id),
    nacre_dependency()
  )
}

#' Render nacre content inside a Shiny app
#'
#' A render function for use with [nacreOutput()]. Evaluates `expr` to
#' produce a nacre tag tree, processes it, and mounts reactive bindings and
#' event handlers after the UI is flushed.
#'
#' @param expr An expression that returns a nacre tag tree.
#' @param env The environment in which to evaluate `expr`.
#' @param quoted If `TRUE`, `expr` is already a quoted expression.
#' @return A [shiny::renderUI()] result.
#' @export
renderNacre <- function(expr, env = parent.frame(), quoted = FALSE) {
  func <- shiny::exprToFunction(expr, env, quoted)

  renderUI({
    session <- getDefaultReactiveDomain()
    tag_tree <- isolate(func())
    result <- process_tags(tag_tree)

    session$onFlushed(function() {
      nacre_mount_processed(result, session)
    }, once = TRUE)

    result$tag
  })
}
