# Runnable test entrypoint (non-package project):
#   Rscript tests/testthat.R
library(testthat)
library(here)
testthat::test_dir(here::here("tests", "testthat"), stop_on_failure = TRUE)
