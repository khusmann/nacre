#' Throttle an event callback
#'
#' Fires at most every \code{ms} milliseconds while the event is active.
#' With \code{coalesce = TRUE} (the default), also waits for the server to
#' finish processing before sending the next event, so the effective rate is
#' \code{max(ms, server_processing_time)}.
#'
#' @param fn An event handler function.
#' @param ms Minimum interval in milliseconds between events.
#' @param leading If \code{TRUE} (default), fire immediately on the first
#'   event. If \code{FALSE}, wait for the timer before firing.
#' @param coalesce If \code{TRUE} (default), also gate on server idle so
#'   events never queue faster than the server can process them.
#' @return A wrapped handler.
#' @export
event_throttle <- function(fn, ms, leading = TRUE, coalesce = TRUE) {
  structure(fn, class = c("nacre_rate_limited", "function"),
            mode = "throttle", ms = ms, leading = leading, coalesce = coalesce)
}

#' Debounce an event callback
#'
#' Waits until the user pauses for \code{ms} milliseconds before firing.
#' With \code{coalesce = TRUE} (the default), also waits for the server to
#' finish processing, so events never queue up.
#'
#' @param fn An event handler function.
#' @param ms Quiet period in milliseconds before firing.
#' @param coalesce If \code{TRUE} (default), also gate on server idle so
#'   events never queue faster than the server can process them.
#' @return A wrapped handler.
#' @export
event_debounce <- function(fn, ms, coalesce = TRUE) {
  structure(fn, class = c("nacre_rate_limited", "function"),
            mode = "debounce", ms = ms, coalesce = coalesce)
}
