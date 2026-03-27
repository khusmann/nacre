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

#' @export
nacreOutput <- function(id) {
  htmltools::attachDependencies(
    uiOutput(id),
    nacre_dependency()
  )
}

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
