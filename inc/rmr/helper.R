library(dplyr)
library(ggplot2)
library(shinyalert)

################################################################################
#' annotate_rmr_days
#' 
#' Helper function to annotate RMR days
#' @param df
################################################################################
annotate_rmr_days <- function(df) {
   df_anno <- df %>% group_by(Animal) %>% mutate(Day = ceiling(Time / (24*60))) %>% ungroup()
   df_anno <- df_anno %>% group_by(Animal, Day) %>% summarize(Time = min(Time)+12*60, Label=paste0("Day #", Day)) %>% ungroup()
   return(df_anno %>% unique() %>% filter(Label != 'Day #0'))
}

################################################################################
#' padding_helper
#' 
#' This function i used to pad data to same length in RMR calculations
#' @param df
################################################################################
padding_helper <- function(df) {
   # Find the last row for each group
   df_max_index <- df %>%
   group_by(Group) %>%
   slice(n()) %>%
   ungroup()

   # Function to insert a row after the max index for each group
   insert_row <- function(data, row, after) {
      data <- rbind(data[1:after, ], row, data[(after + 1):nrow(data), ])
      return(data)
   }

   # Initialize a new data frame to store the results
   new_df <- df

   # Loop through each group to insert the new row
   for (i in seq_len(nrow(df_max_index))) {
      row_to_insert <- df_max_index[i, ]
      group_rows <- which(df$Group == df_max_index$Group[i])
      max_index <- max(group_rows)
      new_df <- insert_row(new_df, row_to_insert, max_index)
   }
   return(new_df)
}


################################################################################
#' partition
#' 
#' Helper function to partition data for RMR calculation
#' @param mydf
################################################################################
partition <- function(mydf) {
   df <- mydf
   data <- df %>% group_split(Group)
   df_new <- data.frame()
   new_col_names <- c()
   m <- max(sapply(data, nrow))
   for (i in data) {
      new_col_names <- append(new_col_names, unique(i$Group))
      diff <- m - length(i$Values)
      if (nrow(df_new) == 0) {
         if (length(c(i$Values)) != m) {
           df_new <- data.frame(c(i$Values, rep("NA", diff)))
         } else {
           df_new <- data.frame(c(i$Values))
         }
      } else {
         if (length(c(i$Values)) != m) {
            df_new <- cbind(df_new, c(i$Values, rep("NA", diff)))
         } else {
            df_new <- cbind(df_new, c(i$Values))
         }
      }
   }
   colnames(df_new) <- new_col_names
   df_new
}


################################################################################
#' cv
#' 
#' This function calculates the coefficient of variation for a given data frame
#' @param mydf data frame
#' @param window window size
################################################################################
cv <- function(mydf, window = 2) {
   df <- mydf
   df_new <- data.frame()
   for (i in seq_len(ncol(df))) {
      values <- as.numeric(df[, i])
      covs <- c()
      for (j in seq(from = 1, to = length(values), by = 1)) {
         m <- mean(values[seq(from = j, to = j + window - 1, by = 1)], na.rm = TRUE)
         s <- sd(values[seq(from = j, to = j + window - 1, by = 1)], na.rm = TRUE)
         covs <- append(covs, s / m)
         # find the m index which is lowest in CoV and energy expenditure
      }
      if (nrow(df_new) == 0) {
         df_new <- data.frame(covs)
      } else {
         df_new <- cbind(df_new, covs)
      }
   }
   colnames(df_new) <- names(df)
   df_new
}

################################################################################
#' reformat
#' 
#' This function reformats the calculates RMR accordingly for post processing
#' @param df_new
################################################################################
# df_new, data
reformat <- function(df_new) {
   df_final <- data.frame(HP = c(), Group = c())
   for (i in seq_len(ncol(df_new))) {
      df_tmp <- data.frame(HP=df_new[, i], Group=rep(colnames(df_new)[i], length(df_new[, i]))) #nolint
      df_final <- rbind(df_final, df_tmp)
   }
   df_final
}


################################################################################
#' get_time_diff
#' 
#' This function get's the time difference (measurement interval length) in minutes
#' @param df
#' @param from
#' @param to
#' @param do_warn
################################################################################
get_time_diff <- function(df, from = 2, to = 3, do_warn=FALSE) {
   id <- df %>% nth(1) %>% select("Animal No._NA")
   # note first time diff might be 0 if sorted ascending and because first measurement point,
   # thus pick 2 or 3, however 2 or 3 might still be 0 depending on the frequency of recordings (multiple per minute...)
   time_diff1 <- df %>% filter(`Animal No._NA` == id) %>% arrange(diff.sec) %>% nth(from) %>% pull(diff.sec)
   time_diff2 <- df %>% filter(`Animal No._NA` == id) %>% arrange(diff.sec) %>% nth(to) %>% pull(diff.sec)

   # better get all time diffs, and unique them, then take the first non-zero as measurement interval length,
   # if we have more than one measurement length which is non-zero, there might be changes in measurement
   # interval length due to e.g. experimental handling of samples / maintenance
   time_diff_all <- df %>% filter(`Animal No._NA` == id) %>% arrange(diff.sec) %>% pull(diff.sec) %>% unique()

   # start of measurement always diff.sec 0, but there should never be different diff.sec in the measurement per animal ID
   if (length(time_diff_all[-1]) > 1) {
      print(time_diff_all)
      print("WARNING: Multiple measurement time intervals detected")
      if (do_warn) {
         shinyalert("Warning:", paste0("Multiple measurement time intervals detected: ", length(time_diff_all[-1]), " which are: ", paste(time_diff_all[-1], collapse=", "), " [s]. This might lead to unexpected behaviour when time-averaging methods are applied."))
      }
   }

   if (time_diff1 != time_diff2) {
      print("WARNING: Time difference different in cohorts!")
      print("This could happen if you do not average cohorts when sampling interval of IC experiments is different between cohorts")
      print("This could also happen if your single IC experiment data has been corrupted or has been recorded discontinously.")
      if (do_warn) {
         shinyalert("Warning:", "Time difference different (measurement interval CHANGING) in cohort for animals. Check your data files. All measurement intervals should be constant per individual cohort (and thus for each animal in the cohort). Measurement intervals can vary between cohorts, which is valid input to the analysis.", type = "warning", showCancelButton = TRUE)
      }
      return(min(time_diff_all[time_diff_all != 0]) / 60)
   } else {
      return(min(time_diff_all[time_diff_all != 0]) / 60)
   }
}

################################################################################
#' get_date_range
#' 
#' This function get's all available dates in the data sets
#' @param df
################################################################################
get_date_range <- function(df) {
 date_first <- df %>% select(Datetime) %>% first() %>% pull()
 date_last <- df %>% select(Datetime) %>% last() %>% pull()
 date_first <- paste(rev(str_split(str_split(date_first, " ")[[1]][1], "/")[[1]]), collapse = "-")
 date_last <- paste(rev(str_split(str_split(date_last, " ")[[1]][1], "/")[[1]]), collapse = "-")
 return(list("date_start" = date_first, "date_end" = date_last))
}


################################################################################
#' check_for_cosmed
#' 
#' Helper function to check for COSMED (.xlsx) data sets
#' @param file
################################################################################
check_for_cosmed <- function(file) {
   if (length(excel_sheets(file)) == 2) {
        if ((excel_sheets(file)[1] == "Data") && (excel_sheets(file)[2] == "Results")) {
            first_col <- read_excel(file) %>% select(1)
            FIELDS_TO_CHECK <-  data.frame(index = c(1, 2, 3, 4, 5, 6), value = c("Last Name", "First Name", "Gender", "Age", "Height (cm)", "Weight (kg)"))
            return(all(apply(FIELDS_TO_CHECK, 1, function(x, output) return(x[2] == (first_col %>% nth(as.integer(x[1])) %>% pull())))))
        }
   }
}

################################################################################
#' calc_heat_production
#' 
#' This function calculates the heat production
#' @param choice
#' @param C1
#' @param variable
#' @param scaleFactor
################################################################################
calc_heat_production <- function(choice, C1, variable, scaleFactor) {
   df <- C1
   switch(choice,
      Lusk = {
         df[[variable]] <- 15.79 * scaleFactor * C1$`VO2(3)_[ml/h]` / 1000 + 5.09 * (C1$`VO2(3)_[ml/h]` / C1$`VO2(3)_[ml/h]`) / 1000
      },
      Heldmaier1 = {
         df[[variable]] <- scaleFactor * C1$`VO2(3)_[ml/h]` * (6 * (C1$`VO2(3)_[ml/h]` / C1$`VO2(3)_[ml/h]`) + 15.3) * 0.278 / 1000 * (3600 / 1000)
      },
      Heldmaier2 = {
         df[[variable]] <- (4.44 + 1.43 * (C1$`VO2(3)_[ml/h]` / C1$`VO2(3)_[ml/h]`)) * scaleFactor * C1$`VO2(3)_[ml/h]` * (3600 / 1000) / 1000
      },
      Weir = {
         df[[variable]] <- 16.3 * scaleFactor * C1$`VO2(3)_[ml/h]` / 1000 + 4.57 * C1$`VCO2(3)_[ml/h]` / 1000
      },
      Elia = {
         df[[variable]] <- 15.8 * scaleFactor * C1$`VO2(3)_[ml/h]` / 1000 + 5.18 * (C1$`VO2(3)_[ml/h]` / C1$`VO2(3)_[ml/h]`)  / 1000
      },
      Brower = {
         df[[variable]] <- 16.07 * scaleFactor * C1$`VO2(3)_[ml/h]` / 1000 + 4.69 *  (C1$`VO2(3)_[ml/h]` / C1$`VO2(3)_[ml/h]`) / 1000
      },
      Ferrannini = {
         df[[variable]] <- 16.37117 * scaleFactor * C1$`VO2(3)_[ml/h]` / 1000 + 4.6057 * C1$`VCO2(3)_[ml/h]` / 1000
      },
      {

      }
   )
   return(df)
}

################################################################################
#' convert_to_days
################################################################################
convert_to_days <- function(x) {
   splitted <- strsplit(as.character(x), " ")
   paste(splitted[[1]][1])
}


################################################################################
#' filter_full_days_alternative
#' 
#' This function filters for full days
#' @param
#' @param threshold
#' @param cohort_list
################################################################################
filter_full_days_alternative <- function(df, threshold, cohort_list) {
   df_filtered <- df %>% mutate(Datetime4 = as.POSIXct(Datetime, format = "%d/%m/%Y %H:%M")) %>% mutate(Datetime4 = as.Date(Datetime4)) %>% group_by(Datetime4) %>% filter(n_distinct(hour) >= (24 * ((100-threshold)/100))) %>% ungroup()
   # based on Animal ID we need to subtract the offset 
   df_filtered <- df_filtered %>% group_by(`Animal No._NA`) %>% mutate(running_total.hrs = running_total.hrs - min(running_total.hrs, na.rm = TRUE)) %>% ungroup()
   df_filtered <- df_filtered %>% group_by(`Animal No._NA`) %>% mutate(running_total.hrs.halfhour = running_total.hrs.halfhour - min(running_total.hrs.halfhour, na.rm = TRUE)) %>% ungroup()
   df_filtered <- df_filtered %>% group_by(`Animal No._NA`) %>% mutate(running_total.sec = running_total.sec - min(running_total.sec, na.rm = TRUE)) %>% ungroup()
   return(df_filtered)
}

################################################################################
#' filter_full_days
#' 
#' This function filters for full days
#' @param df
#' @param time_diff
#' @param threshold
################################################################################
filter_full_days <- function(df, time_diff, threshold) {
   df$DaysCount <- lapply(df$Datetime, convert_to_days)
   df$`Animal No._NA` <- as.factor(df$`Animal No._NA`)
   splitted <- df %>% group_by(`Animal No._NA`) %>% group_split(`Animal No._NA`)
   ls <- c()
   for (s in splitted) { # for each animal
      ls <- append(ls, lapply(s %>% group_split(DaysCount), nrow)) # count hours for days
   }

   df_final <- NULL
   for (s in splitted) {
      df_part <- s %>% group_by(DaysCount) %>% mutate(FullDay = length(`Animal No._NA`))
      df_part <- df_part %>% filter(FullDay > (threshold / 100) * 60 * 24 / time_diff)
      df_final <- bind_rows(df_final, df_part)
   }
   df_final <- df_final %>% select(-c("FullDay"))
   df_final <- df_final %>% ungroup()
   df_final <- df_final %>% select(-c("DaysCount"))
   return(df_final)
}

################################################################################
#' convert_to_day_only
################################################################################
convert_to_day_only <- function(x) {
   splitted <- strsplit(as.character(x), "/")
   paste(splitted[[1]][1], splitted[[1]][2], splitted[[1]][3], sep = "-")
}

################################################################################
#' trim_front_end
#' 
#' This function trims time series data at front and end
#' @param df
#' @param end_trim
#' @param front_trim
################################################################################
trim_front_end <- function(df, end_trim, front_trim) {
   df$Date <- lapply(df$Datetime, convert_to_days)
   df$Date <- lapply(df$Date, convert_to_day_only)
   splitted <- df %>% group_by(`Animal No._NA`) %>% group_split(`Animal No._NA`)
   df_final <- NULL

   for (s in splitted) {
      last_row <- s %>% arrange(Date) %>% nth(nrow(s)) %>% select(Date) %>% pull() # assumed last date for animal
      first_row <- s %>% arrange(Date) %>% nth(1) %>% select(Date) %>% pull() # assumed first date for animal

      hours_start <- s %>% filter(Date == first_row[[1]][1]) %>% select(hour) %>% unique() %>% nth(1) %>% pull()

      hours_end <- s %>% filter(Date == last_row[[1]][1]) %>% select(hour) %>% unique() %>% last() %>% pull()

      df_filtered <- s %>% filter(!((Date == last_row[[1]][1] & hour > (hours_end - end_trim)) | (Date == first_row[[1]][1] & hour < (hours_start + front_trim))))
      df_filtered <- df_filtered %>% ungroup()
      df_filtered <- df_filtered %>% arrange(Datetime2)
      df_filtered <- df_filtered %>% select(-c("Date"))
      df_final <- bind_rows(df_final, df_filtered)
   }
   return(df_final)
}
