% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/do_ancova_alternative.R
\name{do_ancova_alternative}
\alias{do_ancova_alternative}
\title{do_ancova_alternative}
\usage{
do_ancova_alternative(
  df_data,
  df_metadata,
  indep_var,
  indep_var2,
  group,
  group2,
  dep_var,
  test_type,
  adjust_method = "bonferroni",
  connected_or_independent_ancova = FALSE,
  num_covariates = 1
)
}
\description{
This function performs multi-way ANCOVA or ANOVA analysis
}
