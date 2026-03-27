library(shiny)
library(nacre)

ToggleApp <- function() {
  show <- reactiveVal(TRUE)

  tags$div(
    tags$button(
      onClick = \() show(!show()),
      "Toggle"
    ),
    When(show,
      tags$div(
        tags$h2("Visible!"),
        tags$p(style = "color:green", "This content is shown")
      ),
      otherwise = tags$p(style = "color:red", "Hidden — showing fallback")
    )
  )
}

nacreApp(ToggleApp)
