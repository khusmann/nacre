nacre_mount <- function(tag_tree, session) {
  result <- process_tags(tag_tree)
  nacre_mount_processed(result, session)
}

nacre_mount_processed <- function(result, session) {
  observers <- list()

  # Set up event listeners
  if (length(result$events) > 0L) {
    event_msgs <- lapply(result$events, function(ev) {
      input_id <- paste0("nacre_ev_", ev$id, "_", ev$event)
      handler <- ev$handler
      nformals <- length(formals(handler))

      obs <- observeEvent(session$input[[input_id]], {
        ev_data <- session$input[[input_id]]
        if (nformals == 0L) {
          handler()
        } else if (nformals == 1L) {
          handler(ev_data$value)
        } else {
          handler(ev_data$value, ev_data$id)
        }
      }, ignoreInit = TRUE)
      observers[[length(observers) + 1L]] <<- obs

      list(
        id = ev$id,
        event = ev$event,
        inputId = session$ns(input_id)
      )
    })
    session$sendCustomMessage("nacre-events", event_msgs)
  }

  # Set up reactive attribute bindings
  lapply(result$bindings, function(b) {
    obs <- observe({
      val <- b$fn()
      session$sendCustomMessage("nacre-attr", list(
        id = b$id,
        attr = b$attr,
        value = val
      ))
    })
    observers[[length(observers) + 1L]] <<- obs
  })

  # Set up Shiny outputs
  for (so in result$shiny_outputs) {
    session$output[[so$id]] <- so$render_call
  }

  # Set up control flow nodes
  cf_envs <- list()

  for (cf in result$control_flows) {
    if (cf$type == "when") {
      local({
        current_mount <- NULL
        cf_id <- cf$id
        cf_condition <- cf$condition
        cf_yes <- cf$yes
        cf_otherwise <- cf$otherwise
        env <- environment()

        obs <- observe({
          active <- isTRUE(cf_condition())
          branch <- if (active) cf_yes else cf_otherwise

          # Destroy previous branch
          if (!is.null(env$current_mount)) {
            env$current_mount$destroy()
            env$current_mount <- NULL
          }

          if (!is.null(branch)) {
            processed <- process_tags(branch)

            # Swap first so elements exist in DOM
            session$sendCustomMessage("nacre-swap", list(
              id = cf_id,
              html = as.character(processed$tag)
            ))

            # Then mount observers/events
            env$current_mount <- nacre_mount_processed(
              processed, session
            )
          } else {
            session$sendCustomMessage("nacre-swap", list(
              id = cf_id,
              html = ""
            ))
          }
        })
        observers[[length(observers) + 1L]] <<- obs
        cf_envs[[length(cf_envs) + 1L]] <<- env
      })
    }
  }

  list(
    tag = result$tag,
    destroy = function() {
      for (obs in observers) obs$destroy()
      for (env in cf_envs) {
        if (!is.null(env$current_mount)) env$current_mount$destroy()
      }
    }
  )
}
