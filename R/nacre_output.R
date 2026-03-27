nacreApp <- function(fn, ...) {
  ui <- fluidPage(nacreOutput("nacre-app"))
  server <- function(input, output, session) {
    output[["nacre-app"]] <- renderNacre(fn())
  }
  shinyApp(ui, server, ...)
}

nacreOutput <- function(id) {
  htmltools::attachDependencies(
    uiOutput(id),
    nacre_dependency()
  )
}

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
