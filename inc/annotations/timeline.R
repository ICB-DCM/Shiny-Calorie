library(ggplot2)

################################################################################
#' draw_day_night_rectangles
#'
#' This function inks the day with a light color and night with a darker color
#' @param df data frame
#' @param p plot object
#' @param light_start start of light cycle
#' @param light_end end of light cycle
#' @param light_offset offset of light cycle from start of day (for zeitgeber time always 0)
#' @param day_color color for light phase (day)
#' @param night_color color for dark phase (night)
#' @param light_cycle choose Day or Night 
#' @param only_full_days_zeitgeber full days or not using zeitgeber time
################################################################################
draw_day_night_rectangles <- function(df, p, light_start = 5, light_end = 17, light_offset = 0, day_color = "yellow", night_color = "grey", light_cycle = c("Day", "Night"), only_full_days_zeitgeber=TRUE) {
   # day/night assumed to be always of length 12 (light_end-light_start should always be 12)
   intervals <- seq(0, max(df$x, na.rm=T), (light_end - light_start))

   # first_night_start = min(df$x, na.rm=T)+light_end-(-min(df$x, na.rm=T)+light_start)
   first_night_start = 0

   # zeitgeber zeit assumes to start with night not day
   light_on <- TRUE

   color <- day_color
   # if only Night select, we need to start with night color (assuming light_on is FALSE)
   if (length(light_cycle) == 1) {
      if (light_cycle == "Night") {
         light_on <- FALSE
         color <- day_color
      } 
      if (light_cycle == "Day") {
         light_on <- FALSE
         color <- night_color
      }
   } else {
      light_on <- FALSE
   }

   # first interval is night, color this accordingly
   lapply(intervals, function(item) { p <<- p + annotate("rect", xmin = item - (light_end - light_start) + light_offset, xmax = item + light_offset, ymin = min(df$y), ymax = max(df$y), fill = color, alpha = 0.1); if (light_on) { color <<- day_color; light_on <<- FALSE }  else {  color <<- night_color; light_on <<- TRUE}; }) # nolint: semicolon_linter, brace_linter.

   # start offset assumed before daylight start (light_start): night
   p <- p + annotate("rect", xmin=0, xmax=light_offset, ymin = min(df$y), ymax = max(df$y), fill=night_color, alpha=0.1)

   # end offset assumed after daylight stop (light_stop): night
   xmin_last_rect <- intervals[length(intervals)]
   if ((intervals[length(intervals)] + light_offset) > max(df$x)) { 
      xmin_last_rect <- intervals[length(intervals)-1] 
      xmax_last_rect <- max(df$x, na.rm=T)
   }

   # if we have overhanging days (incomplete days) color it either as day or night accordingly
   fill_color_last <- night_color
   if ((length(intervals) %% 2 == 0)) {
      fill_color_last <- day_color
   }
   p <- p + annotate("rect", xmin=xmin_last_rect+light_offset, xmax=max(df$x), ymin = min(df$y), ymax = max(df$y), fill=fill_color_last, alpha=0.1)

   # first interval might be not full if not aligns with light cycle
   xmax_first_rect <- min(df$x, na.rm=T)

   # xmin_first_rect <- xmax_first_rect
   if (xmax_first_rect > 0) {
      xmax_first_rect = first_night_start
   } 

   # stitch together all rects for overlay onto plot
   p <- p + annotate("rect", xmin=xmax_first_rect, xmax=first_night_start, ymin=min(df$y), ymax=max(df$y), fill=day_color, alpha=0.1)

   # regular intervals, set set limits for these
   p <- p + ylim(min(df$y), max(df$y))
   p <- p + scale_x_continuous(expand = c(0, 0), limits = c(min(df$x), max(df$x)))
   p <- p + scale_y_continuous(expand = c(0, 0), limits = c(min(df$y), max(df$y)))
}
