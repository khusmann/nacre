#' @export
When <- function(condition, yes, otherwise = NULL) {
  structure(
    list(condition = condition, yes = yes, otherwise = otherwise),
    class = "nacre_when"
  )
}
