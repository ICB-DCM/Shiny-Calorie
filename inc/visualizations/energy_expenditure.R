################################################################################
#' energy_expenditure
#' 
#' This function calculates the energy expenditure
#' @param finalC1 input data
#' @param finalC1meta combined metadata
#' @param input shiny input
#' @param output shiny output
#' @param session shiny session
#' @param global_data dictionary to store variables session-based for users
#' @param scaleFactor used to scale energy expenditure units correctly
#' @examples 
#' energy_expenditure(values, full_metadata, input, output, session, global_data, 1)
#' @export
################################################################################
energy_expenditure <- function(finalC1, finalC1meta, input, output, session, global_data, scaleFactor) {
	# get metadata
	metadatafile <- get_metadata_datapath(input, session, global_data)


	# only join data frame if not already joined 
	if (!is.null(getSession(session$token, global_data)[["is_EnergyExpenditure_calculated"]])) {
		data_and_metadata <- getSession(session$token, global_data)[["EE_df"]]
		finalC1 <- data_and_metadata$data
		true_metadata <- data_and_metadata$metadata
	} else {
		finalC1$Animals <- as.factor(`$`(finalC1, "Animal No._NA"))
		data_and_metadata <- enrich_with_metadata(finalC1, finalC1meta, input$havemetadata, metadatafile)
		finalC1 <- data_and_metadata$data
		true_metadata <- data_and_metadata$metadata
		storeSession(session$token, "EE_df", data_and_metadata, global_data)
	}

	# Select sexes
	if (!is.null(input$checkboxgroup_gender)) {
		if ("Sex" %in% names(finalC1)) {
			finalC1 <- finalC1 %>% filter(Sex %in% c(input$checkboxgroup_gender))
		}
	}

	# filter conditions
	if (input$with_grouping) {
		my_var <- input$condition_type
		if (!is.null(input$select_data_by) && !is.null(input$condition_type)) {
			finalC1 <- finalC1 %>% filter((!!sym(my_var)) == input$select_data_by)
		}
	}

	# default from UI
	light_on <- input$light_cycle_start 
	light_off <- input$light_cycle_stop

	# otherwise take from metadata sheet  
	if (input$havemetadata) {
		light_on <- as.integer(get_constants(metadatafile) %>% filter(if_any(everything(), ~str_detect(., "light_on"))) %>% select(2) %>% pull())
		light_off <- as.integer(get_constants(metadatafile) %>% filter(if_any(everything(), ~str_detect(., "light_off"))) %>% select(2) %>% pull())
	}

	# force override if metadata was available
	if (input$override_metadata_light_cycle) {
		light_on <- input$light_cycle_start
		light_off <- input$light_cycle_stop
	}

	convert <- function(x) {
		splitted <- strsplit(as.character(x), " ")
		paste(splitted[[1]][2], ":00", sep = "")
	}

	# when zeitgeber time should be used  
	if (input$use_zeitgeber_time) {
		finalC1 <- zeitgeber_zeit(finalC1, light_off)
		num_days <- floor(max(finalC1$running_total.hrs.halfhour) / 24)
		if (input$only_full_days_zeitgeber) {
			finalC1 <- finalC1 %>% filter(running_total.hrs.halfhour > 0, running_total.hrs.halfhour < (24*num_days))
		} 
		finalC1$DayCount <- ceiling((finalC1$running_total.hrs.halfhour / 24) + 1)
		finalC1$NightDay <- ifelse((finalC1$running_total.hrs %% 24) < 12, "Night", "Day")
	} else {
		finalC1$Datetime2 <- lapply(finalC1$Datetime, convert)
		finalC1$NightDay <- ifelse(hour(hms(finalC1$Datetime2)) * 60 + minute(hms(finalC1$Datetime2)) < (light_on * 60), "Day", "Night")
		finalC1$NightDay <- as.factor(finalC1$NightDay)
		finalC1 <- finalC1 %>% mutate(Datetime4 = as.POSIXct(Datetime, format = "%d/%m/%Y %H:%M")) %>% mutate(Datetime4 = as.Date(Datetime4)) %>% group_by(`Animal No._NA`) %>% mutate(DayCount = dense_rank(Datetime4)) %>% ungroup()
	}

	finalC1 <- finalC1 %>% filter(NightDay %in% input$light_cycle)
	colors <- as.factor(`$`(finalC1, "Animal No._NA"))
	finalC1$Animals <- colors

	# FIXME: Is this correct if beginning of measurement is excluded for temperature selection?
	# Should be correct, as temperature is selected afterwards!
	day_annotations <- annotate_zeitgeber_zeit(finalC1, 0, "HP2", input$with_facets)
	finalC1 <- day_annotations$df_annotated

	convert <- function(x) {
		splitted <- strsplit(as.character(x), " ")
		paste(splitted[[1]][2], ":00", sep = "")
	}
	finalC1$Datetime2 <- lapply(finalC1$Datetime, convert)

	# corrected filtering for day and night based on light cycle information
	finalC1 <- finalC1 %>% select(-Datetime2)

	# create input select fields for animals and days
	days_and_animals_for_select <- get_days_and_animals_for_select_alternative(finalC1)
	
	# select days
	selected_days <- getSession(session$token, global_data)[["selected_days"]]
	if (is.null(selected_days)) {
		output$select_day <- renderUI({
			selectInput("select_day", "Select day(s):", choices = days_and_animals_for_select$days, selected = days_and_animals_for_select$days, multiple = TRUE)
		})
		selected_days = days_and_animals_for_select$days
		storeSession(session$token, "selected_days", selected_days, global_data)
	} else {
		output$select_day <- renderUI({
			selectInput("select_day", "Select day(s):", choices = days_and_animals_for_select$days, selected = selected_days, multiple = TRUE)
		})
	}

	# select animals
	selected_animals <- getSession(session$token, global_data)[["selected_animals"]]
	if (is.null(selected_animals)) {
		output$select_animal <- renderUI({
			selectInput("select_animal", "Select animal(s):", choices = days_and_animals_for_select$animals, selected = days_and_animals_for_select$animals, multiple = TRUE)
		})
		selected_animals = days_and_animals_for_select$animals
		storeSession(session$token, "selected_animals", selected_animals, global_data)
	} else {
		output$select_animal <- renderUI({
			selectInput("select_animal", "Select animal(s):", choices = days_and_animals_for_select$animals, selected = selected_animals, multiple = TRUE)
		})
	}

	# store selected animals and days in session
	selected_days <- getSession(session$token, global_data)[["selected_days"]]
	selected_animals <- getSession(session$token, global_data)[["selected_animals"]]

	# filter for selected days and animals in data set
	finalC1 <- finalC1 %>% filter(DayCount %in% selected_days)
	finalC1 <- finalC1 %>% filter(`Animal No._NA` %in% selected_animals)

	# trim times from end and beginning of measurements   
	if (input$curate) {
		finalC1 <- finalC1 %>% filter(running_total.hrs.halfhour >= min(running_total.hrs.halfhour) + input$exclusion_start, running_total.hrs.halfhour <= (max(finalC1$running_total.hrs.halfhour) - input$exclusion_end))
	}

	finalC1 <- finalC1 %>% filter(DayCount %in% intersect(selected_days, levels(as.factor(finalC1$DayCount))))

	# Day Night filtering
	finalC1$NightDay <- ifelse((finalC1$running_total.hrs %% 24) < 12, "Night", "Day")
	finalC1 <- finalC1 %>% filter(NightDay %in% input$light_cycle)
	finalC1$NightDay <- as.factor(finalC1$NightDay)

	# Select temperature
	if (!is.null(input$select_temperature)) {
		if (input$select_temperature) {
			finalC1 <- finalC1[finalC1$`Temp_[°C]` >= (input$temperature_mean-input$temperature_deviation) & finalC1$`Temp_[°C]` <= (input$temperature_mean+input$temperature_deviation), ]
		}
	}

	# if we do not have metadata, this comes from some non-clean TSE headers
	if (!input$havemetadata) { finalC1$`Animal.No.` <- finalC1$Animals }

	# add smoothing
	gam_model <- NULL
	grouped_gam <- NULL
	df_to_plot <- finalC1
	if (input$add_average_with_se) {
		if (input$with_facets) {
			if (!is.null(input$facets_by_data_one)) {
				signal <- "HP2"
				group = input$facets_by_data_one
				# Fit GAM for each group
				grouped_gam <- df_to_plot %>%
				group_by(!!sym(group)) %>%
				group_map(~ {
					group_value <- .y[[group]][1]
					gam_model <- mgcv::gam(as.formula(paste(signal, " ~ s(running_total.hrs.halfhour, k = ", as.numeric(input$averaging_method_with_facets_basis_functions), ", bs = 'cr')")), data= .x)
					pred <- predict(gam_model, se.fit = TRUE)
					.x %>%
					mutate(
						fit = pred$fit,
						upper = pred$fit + input$averaging_method_with_facets_confidence_levels * pred$se.fit,
						lower = pred$fit - input$averaging_method_with_facets_confidence_levels * pred$se.fit,
						trend = group_value
					)
				}) %>%
				bind_rows()  # Combine predictions for all groups
			}
		} else {
			gam_model <- mgcv::gam(df_to_plot[["HP2"]] ~ s(running_total.hrs.halfhour, k=input$averaging_method_with_facets_basis_functions, bs=input$averaging_method_with_facets_basis_function), data=df_to_plot)
			pred <- predict(gam_model, se.fit=TRUE)
			df_to_plot <- df_to_plot %>% mutate(fit=pred$fit, upper = fit + input$averaging_method_with_facets_confidence_levels * pred$se.fit, lower = fit - input$averaging_method_with_facets_confidence_levels * pred$se.fit)
		}
	}
	finalC1 <- df_to_plot

	# calculate running averages
	if (input$running_average > 0) {
		p <- ggplot(data = finalC1, aes_string(x = "running_total.hrs.halfhour", y = "HP2", color = "Animals", group = "Animals"))
		if (input$running_average_method == "Mean") {
		p <- p + geom_line(aes(y = rollmean(HP2, input$running_average, na.pad = TRUE)), group = "Animals")
		} else if (input$running_average_method == "Max") {
		p <- p + geom_line(aes(y = rollmax(HP2, input$running_average, na.pad = TRUE)), group = "Animals")
		} else if (input$running_average_method == "Median") {
		p <- p + geom_line(aes(y = rollmedian(HP2, input$running_average, na.pad = TRUE)), group = "Animals")
		} else if (input$running_average_method == "Sum") {
		p <- p + geom_line(aes(y = rollsum(HP2, input$running_average, na.pad = TRUE)), group = "Animals")
		} else {
		p <- p + geom_line(aes(y = HP2), group = "Animals")
		}
	} else {
		p <- ggplot(data = finalC1, aes_string(x = "running_total.hrs.halfhour", y = "HP2", color = "Animals", group = "Animals"))
		p <- p + geom_line()
	}

	p2 <- NULL
	# add statistics panel if relevant data (RMR) has been calculated before
	if (!getSession(session$token, global_data)[["is_RMR_calculated"]]) {
		shinyalert("Error:", "Resting metabolic rate needs to be calculated before!")
		# FIXME: Temporary... this should be corrected, as it leads to dim(x) error when switching from RMR/TEE to the EE panel
		return()
	} else {
		EE <- getSession(session$token, global_data)[["TEE_and_RMR"]]
		EE <- EE %>% filter(TEE == "non-RMR") %>% select(-TEE) 
		storeSession(session$token, "selected_indep_var", "Genotype", global_data)
		add_anova_ancova_panel(input, output, session, global_data, true_metadata, EE, metadatafile, paste0("Heat production [", input$kj_or_kcal, "/day]"), "EE")

		if (input$windowed_plot == TRUE) {
			# offset is minimum value for time (on x-axis)
			offset <- min(finalC1$running_total.hrs.halfhour)
			# windowed time trace plot
			window_plot <- add_windowed_plot(input, output, session, global_data, true_metadata, metadatafile, df_to_plot, "EE", offset, "HP")
			p2 <- window_plot$plot
			p2 <- p2 + ggtitle("Average heat production in window") + xlab(paste0("Heat production [", input$kj_or_kcal, "/day"))
			annotations_window_plot <<- window_plot$annotations
		}
	}

	# add means
	if (input$wmeans) {
		p <- p + geom_smooth(method = input$wmeans_choice)
	}

	# add stats
	if (input$wstats) {
		p <- p + stat_cor(method = input$wmethod)
	}

	# set x-axis label
	if (input$use_zeitgeber_time) {
		p <- p + xlab("Zeitgeber time [h]")
	} else {
		p <- p + xlab("Time [h]")
	}

	mylabel <- NULL
	# display unit correctly on y-axis label
	if (input$kj_or_kcal == "mW") {
		p <- p + ylab(paste("Heat production [", input$kj_or_kcal, "[J/s]", sep = " "))
		mylabel <- paste("Heat production [", input$kj_or_kcal, "[J/s]", sep = " ")
	} else {
		p <- p + ylab(paste("Heat production [", input$kj_or_kcal, "/h]", sep = " "))
		mylabel <- paste("Heat production [", input$kj_or_kcal, "/h]", sep = " ")
	}

	# add light cycle annotation
	lights <- data.frame(x = finalC1["running_total.hrs.halfhour"], y = finalC1["HP2"])
	colnames(lights) <- c("x", "y")

	if (input$timeline) {
		if (!is.null(input$only_full_days_zeitgeber)) {
			if (input$only_full_days_zeitgeber == TRUE) {
				my_lights <- draw_day_night_rectangles(lights, p, light_on, light_off, 0, input$light_cycle_day_color, input$light_cycle_night_color, input$light_cycle, input$only_full_days_zeitgeber)
				p <- p + my_lights
			} else {
				my_lights <- draw_day_night_rectangles(lights, p, light_on, light_off, 0, input$light_cycle_day_color, input$light_cycle_night_color, input$light_cycle)
				p <- p + my_lights
			}
		}
	}

	# add title
	p <- p + ggtitle(paste0("Heat production [", input$kj_or_kcal, "/h]", " using equation ", pretty_print_equation(input$myp)))

	# TODO: This can be factored out -> refactor to method
	# group with group from metadata
	if (input$with_facets) {
		if (!is.null(input$facets_by_data_one)) {
			if (input$orientation == "Horizontal") {
				p <- p + facet_grid(as.formula(paste(".~", input$facets_by_data_one)), scales="free_x")
				if (!is.null(input$facet_medians)) {
					if (!input$facet_medians) {
						p2 <- p2 + facet_grid(as.formula(paste(".~", input$facets_by_data_one)), scales="free_x")
					} else {
						if (!is.null(input$facet_medians_in_one_plot)) {
							if (!input$facet_medians_in_one_plot) {
								p2 <- p2 + facet_grid(as.formula(paste(".~", input$facets_by_data_one)), scales="free_x")
							}
						}
					}
				}
			} else {
				p <- p + facet_grid(as.formula(paste(input$facets_by_data_one, "~.")), scales="free_y")
				if (!is.null(input$facet_medians)) {
					if (!input$facet_medians) {
						p2 <- p2 + facet_grid(as.formula(paste(input$facets_by_data_one, "~.")), scales="free_y")
					} else {
						if (!is.null(input$facet_medians_in_one_plot)) {
							if (!input$facet_medians_in_one_plot) {
								p2 <- p2 + facet_grid(as.formula(paste(input$facets_by_data_one, "~.")), scales="free_y")
							}
						}
					}
				}
			}
		}
	}

	# add trend lines: 
	# TODO: Can also be factored out to remove code duplication
	if (input$add_average_with_se) {
		if (input$with_facets) {
			if (!is.null(input$facets_by_data_one)) {
				grouped_gam$trend <- as.factor(grouped_gam$trend)
				if (!is.null(input$add_average_with_se_one_plot)) {
					if (input$add_average_with_se_one_plot) {
						p <- ggplot(data = df_to_plot, aes_string(y = "HP2", x = "running_total.hrs.halfhour"))
						p <- p + geom_ribbon(data = grouped_gam, aes(ymin = lower, ymax = upper, group = trend, color=trend, fill=trend), alpha =input$averaging_method_with_facets_alpha_level) 
						p <- p + labs(colour=input$facets_by_data_one, fill=input$facets_by_data_one)
						# set y-axis label
						p <- p + ylab(pretty_print_variable(mylabel, metadatafile))
						# set x-axis label
						if (input$use_zeitgeber_time) {
							p <- p + xlab("Zeitgeber time [h]")
						} else {
							p <- p + xlab("Time [h]")
						}
						# add back timeline
						if (input$timeline) {
							if (!is.null(input$only_full_days_zeitgeber)) {
								if (input$only_full_days_zeitgeber == TRUE) {
									my_lights <- draw_day_night_rectangles(lights, p, light_on, light_off, 0, input$light_cycle_day_color, input$light_cycle_night_color, input$light_cycle, input$only_full_days_zeitgeber)
									p <- p + my_lights
								} else {
									my_lights <- draw_day_night_rectangles(lights, p, light_on, light_off, 0, input$light_cycle_day_color, input$light_cycle_night_color, input$light_cycle)
									p <- p + my_lights
								}
							}
						}
					} else {
						p <- p + geom_ribbon(data = grouped_gam, aes(ymin = lower, ymax = upper, group = trend, color=trend, fill=trend), alpha =input$averaging_method_with_facets_alpha_level) 
					}
				}
			}
		} else {
				p <- p + geom_ribbon(aes(ymin=lower, ymax=upper), alpha=input$averaging_method_with_facets_alpha_level, fill=input$averaging_method_with_facets_color)
		}
	}

	# if we have full days based on zeitgeber time, we kindly switch to Full Day annotation instead of Day
	if (input$only_full_days_zeitgeber) {
		day_annotations$annotations <- day_annotations$annotations %>% mutate(label=gsub("Day", "Full Day", label))
	}

	light_offset <- -12
	# add day annotations and indicators vertical lines
	p <- p + geom_text(data=day_annotations$annotations, aes(x = x+light_offset+2, y = y, label=label), vjust=1.5, hjust=0.5, size=4, color="black")
	# indicate new day
	p <- p + geom_vline(xintercept = as.numeric(seq(light_offset+24, length(unique(days_and_animals_for_select$days))*24+light_offset, by=24)), linetype="dashed", color="black")
	# indicate night start
	p <- p + geom_vline(xintercept = as.numeric(seq(light_offset+12, length(unique(days_and_animals_for_select$days))*24+light_offset, by=24)), linetype="dashed", color="gray")
	# re-center at 0
	p <- p + scale_x_continuous(expand = c(0, 0), limits = c(min(lights$x), max(lights$x)))
	#p <- p + scale_y_continuous(expand = c(0, 0), limits = c(min(lights$y), max(lights$y)))
	p <- ggplotly(p) %>% config(displaylogo = FALSE, modeBarButtons = list(c("toImage", get_new_download_buttons()), list("zoom2d", "pan2d", "select2d", "lasso2d", "zoomIn2d", "zoomOut2d", "autoScale2d"), list("hoverClosestCartesian", "hoverCompareCartesian")))

	if (input$windowed_plot == TRUE) {
		if (!is.null(p2)) {
			p2 <- ggplotly(p2) %>% config(displaylogo = FALSE, modeBarButtons = list(c("toImage", get_new_download_buttons()), list("zoom2d", "pan2d", "select2d", "lasso2d", "zoomIn2d", "zoomOut2d", "autoScale2d"), list("hoverClosestCartesian", "hoverCompareCartesian")))
		}
	}

	# create LME model UI
	EE_for_model <- getSession(session$token, global_data)[["TEE_and_RMR"]]
	if (!is.null(EE_for_model)) {
		EE_for_model <- EE_for_model %>% filter(TEE == "non-RMR") %>% select(-TEE) 
		EE_for_model <- EE_for_model %>% full_join(y = true_metadata, by = c("Animals")) %>% na.omit() 
		create_lme_model_ui(input, output, true_metadata, EE_for_model, "EE", session, global_data)
	}
	# store plot and indicate EnergyExpenditure has been calculated
	storeSession(session$token, "plot_for_ee", p, global_data)
	storeSession(session$token, "is_EnergyExpenditure_calculated", TRUE, global_data)
	storeSession(session$token, "plot_for_ee_window", p2, global_data)
	storeSession(session$token, "is_EE_window_calculated", length(p2) > 0, global_data)
	return(list("window_plot"=p2, "plot"=p))
}
