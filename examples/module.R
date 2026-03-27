library(shiny)
library(nacre)


Counter <- function(count) {
  tags$div(
    tags$h2(\() paste("Count:", count())),
    tags$input(
      type = "range", min = 0, max = 100,
      value = count,
      onInput = \(value) count(as.numeric(value))
    ),
    tags$button(
      disabled = \() count() == 0,
      onClick = \() count(0),
      "Reset"
    )
  )
}

# A nacre component used inside a Shiny module
counterUI <- function(id) {
  ns <- NS(id)
  tagList(
    nacreOutput(ns("counter")),
    verbatimTextOutput(ns("debug"))
  )
}

counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    count <- reactiveVal(0)
    output$counter <- renderNacre(Counter(count))
    output$debug <- renderText(paste("Server sees:", count()))
  })
}

# Two instances of the same module on one page
ui <- fluidPage(
  h1("Nacre + Shiny Modules"),
  fluidRow(
    column(6, h3("Module A"), counterUI("a")),
    column(6, h3("Module B"), counterUI("b"))
  )
)

server <- function(input, output, session) {
  counterServer("a")
  counterServer("b")
}

shinyApp(ui, server)
