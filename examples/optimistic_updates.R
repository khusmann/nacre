library(shiny)
library(bslib)
library(nacre)

OptimisticUpdates <- function() {
  text <- reactiveVal("")
  max_chars <- 10L

  page_fluid(
    card(
      card_header("Optimistic Update Tests"),
      card_body(
        tags$h6("1. Programmatic clear"),
        tags$p(class = "text-muted", "Type something, click Clear. Input should empty."),
        tags$div(
          class = "input-group mb-3",
          tags$input(type = "text", class = "form-control",
            placeholder = "Type here...",
            value = text, onInput = \(event) text(event$value)),
          tags$button(class = "btn btn-outline-secondary",
            onClick = \() text(""), "Clear")
        ),

        tags$h6(paste0("2. Server transform (max ", max_chars, " chars)")),
        tags$p(class = "text-muted", "Type past the limit. Server truncates to 10 chars."),
        tags$input(type = "text", class = "form-control mb-3",
          value = \() substr(text(), 1, max_chars),
          onInput = \(event) text(event$value)),

        tags$h6("3. Server echo (mirror)"),
        tags$p(class = "text-muted", "Read-only mirror. Should always match server state."),
        tags$input(type = "text", class = "form-control mb-3",
          value = text, disabled = \() TRUE),

        tags$p(
          class = "text-muted",
          \() paste0("Server value (", nchar(text()), " chars): \"", text(), "\"")
        )
      )
    )
  )
}

nacreApp(OptimisticUpdates)
