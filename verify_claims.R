#!/usr/bin/env Rscript
###############################################################################
## verify_claims.R — check every recorded claim against the regenerated output.
##
##   Rscript verify_claims.R              verify; exit 1 on any FAIL
##   Rscript verify_claims.R --self-test  prove the verifier can fail, then verify
##   Rscript verify_claims.R --coverage   also list ledger numbers with no check
##
## HOW IT WORKS, AND WHY IT IS TWO FILES
##
## docs/claims_ledger.md is prose. Extracting "+0.1743" from a sentence is easy;
## knowing that it should come from the estimate column of the BINARY_EXPANDED /
## RSL3 / "ALT - REF" row of exposure_models_contrasts.csv is not inferable from
## the prose at all. So the extraction lives in docs/claim_checks.csv, one row per
## checked quantity, giving the source file and an R expression that pulls the
## value out of it.
##
## That split creates a new failure mode: the check table could drift away from
## the ledger and keep passing against its own stale copy of a number. So every
## check is verified TWICE:
##
##   1. LEDGER MATCH  the value string in claim_checks.csv must literally appear
##                    in the corresponding claim's section of claims_ledger.md.
##                    If someone edits the ledger and not the check table (or the
##                    reverse), this fails.
##   2. DATA MATCH    the value must equal the regenerated output, at the
##                    precision the ledger quotes it to.
##
## TOLERANCE IS THE LEDGER'S OWN PRECISION. "+0.1743" is checked to four decimal
## places, "42" to zero, "1.8199" to four. The observed value is rounded to that
## many places and compared exactly. There is no epsilon and no flag to add one.
## If a number does not survive its own stated precision, the honest options are
## to fix the analysis or to restate the claim -- not to widen the window.
##
## WHERE THE OBSERVED VALUES COME FROM. results/ first, then data/derived/. On a
## machine that has run the full pipeline every value is recomputed; on a fresh
## clone the stages needing 5.5 GB of raw data are skipped and their committed
## outputs are used. The report names the source for every row, so "verified"
## never silently means "verified against the file I shipped".
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
SELF_TEST <- any(args == "--self-test")
COVERAGE  <- any(args == "--coverage")

ROOT <- local({
  fa <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(fa) >= 1L)
    dirname(normalizePath(sub("^--file=", "", fa[length(fa)]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
})
stopifnot(file.exists(file.path(ROOT, "run_all.R")))

LEDGER  <- file.path(ROOT, "docs", "claims_ledger.md")
CHECKS  <- file.path(ROOT, "docs", "claim_checks.csv")
RESULTS <- Sys.getenv("FERRO_OUT", unset = file.path(ROOT, "results"))
DERIVED <- file.path(ROOT, "data", "derived")

## --------------------------------------------------------------------------
## Ledger parsing — split into claim sections keyed by ID
## --------------------------------------------------------------------------
read_ledger_sections <- function(path) {
  ln <- readLines(path, warn = FALSE)
  ## Rows are "## K1 — title" / "## P2 — title" etc.
  hd <- grep("^##\\s+([A-Z][0-9]+)\\s", ln)
  if (!length(hd)) stop("no claim sections found in ", path)
  ids <- sub("^##\\s+([A-Z][0-9]+)\\s.*$", "\\1", ln[hd])
  ends <- c(hd[-1] - 1L, length(ln))
  sec <- Map(function(a, b) paste(ln[a:b], collapse = "\n"), hd, ends)
  names(sec) <- ids
  ## A claim ID appearing twice would make "which section" ambiguous.
  if (anyDuplicated(ids)) stop("duplicate claim IDs in ledger: ",
                               paste(unique(ids[duplicated(ids)]), collapse = ", "))
  sec
}

## Every number in a claim's Numbers/Claim text, for the coverage report.
ledger_numbers <- function(txt) {
  m <- regmatches(txt, gregexpr("[-+−]?[0-9]+\\.?[0-9]*", txt))[[1]]
  unique(m)
}

## --------------------------------------------------------------------------
## Precision: how many decimals does the ledger quote this to?
## --------------------------------------------------------------------------
decimals_of <- function(s) {
  s <- gsub("[^0-9.]", "", s)
  if (!grepl("\\.", s)) return(0L)
  nchar(sub("^[0-9]*\\.", "", s))
}
as_num <- function(s) as.numeric(gsub("[^0-9.eE+-]", "", gsub("−", "-", s)))

## --------------------------------------------------------------------------
## Load a source object from results/ then data/derived/
## --------------------------------------------------------------------------
.cache <- new.env(parent = emptyenv())
load_source <- function(fname) {
  key <- fname
  if (!is.null(.cache[[key]])) return(.cache[[key]])
  cands <- c(file.path(RESULTS, fname), file.path(DERIVED, fname))
  hit <- cands[file.exists(cands)]
  if (!length(hit))
    return(list(data = NULL, where = NA_character_,
                err = paste0("source file not found: ", fname)))
  p <- hit[1]
  d <- tryCatch({
    if (grepl("\\.rds$", p, ignore.case = TRUE)) readRDS(p)
    else read.csv(p, stringsAsFactors = FALSE, check.names = FALSE)
  }, error = function(e) NULL)
  where <- if (dirname(normalizePath(p, winslash = "/")) ==
               normalizePath(RESULTS, winslash = "/", mustWork = FALSE))
             "results" else "data/derived"
  out <- list(data = d, where = where, err = if (is.null(d)) "could not read" else NA_character_)
  .cache[[key]] <- out
  out
}

## --------------------------------------------------------------------------
## Run the checks
## --------------------------------------------------------------------------
run_checks <- function(checks, sections) {
  n <- nrow(checks)
  out <- data.frame(claim_id = checks$claim_id, quantity = checks$quantity,
                    expected = checks$ledger_value,
                    observed = rep(NA_character_, n),
                    dp = NA_integer_, source_file = checks$source_file,
                    read_from = NA_character_, in_ledger = NA,
                    status = NA_character_, detail = "",
                    stringsAsFactors = FALSE)

  for (i in seq_len(n)) {
    id  <- checks$claim_id[i]
    val <- trimws(checks$ledger_value[i])
    dp  <- decimals_of(val)
    out$dp[i] <- dp

    ## ---- 1. does this value actually appear in the ledger row? -------------
    sec <- sections[[id]]
    if (is.null(sec)) {
      out$in_ledger[i] <- FALSE
      out$status[i] <- "FAIL"
      out$detail[i] <- paste0("no section '", id, "' in claims_ledger.md")
      next
    }
    ## Compare on the bare digits so "+0.1743" matches "+0.1743" and "0.1743",
    ## and a unicode minus in the ledger matches an ASCII one in the check table.
    norm <- function(z) gsub("−", "-", z, fixed = TRUE)
    bare <- sub("^[+]", "", norm(val))
    found <- grepl(bare, norm(sec), fixed = TRUE)
    out$in_ledger[i] <- found

    ## ---- 2. does the regenerated output agree? -----------------------------
    srcf <- load_source(checks$source_file[i])
    if (!is.na(srcf$err)) {
      out$status[i] <- "ERROR"; out$detail[i] <- srcf$err; next
    }
    out$read_from[i] <- srcf$where
    obs <- tryCatch(eval(parse(text = checks$expr[i]), list(d = srcf$data)),
                    error = function(e) e)
    if (inherits(obs, "error")) {
      out$status[i] <- "ERROR"
      out$detail[i] <- paste0("expr failed: ", conditionMessage(obs)); next
    }
    raw_len <- length(obs)
    obs <- suppressWarnings(as.numeric(obs))
    if (raw_len != 1L) {
      out$status[i] <- "ERROR"
      out$detail[i] <- sprintf("expr returned %d values, expected exactly 1 (filter too loose or too tight)",
                               raw_len)
      next
    }
    if (!is.finite(obs)) {
      out$status[i] <- "ERROR"
      out$detail[i] <- "expr returned a single non-finite value (NA/NaN) — column or level name likely wrong"
      next
    }

    exp_num <- as_num(val)
    obs_r   <- round(obs, dp)
    out$observed[i] <- formatC(obs_r, format = "f", digits = dp)
    agree   <- isTRUE(all.equal(obs_r, round(exp_num, dp), tolerance = 0))

    if (!found) {
      out$status[i] <- "FAIL"
      out$detail[i] <- "value not found in its ledger section (check table has drifted)"
    } else if (agree) {
      out$status[i] <- "PASS"
    } else {
      out$status[i] <- "FAIL"
      out$detail[i] <- sprintf("expected %s, observed %s (raw %.10g) at %d dp",
                               val, out$observed[i], obs, dp)
    }
  }
  out
}

report <- function(res, title) {
  cat(sprintf("\n%s\n%s\n%s\n", strrep("=", 100), title, strrep("=", 100)))
  cat(sprintf("%-6s %-44s %12s %12s %-6s %s\n",
              "claim", "quantity", "expected", "observed", "src", "status"))
  cat(strrep("-", 100), "\n")
  for (i in seq_len(nrow(res))) {
    cat(sprintf("%-6s %-44s %12s %12s %-6s %s\n",
                res$claim_id[i], substr(res$quantity[i], 1, 44),
                res$expected[i], ifelse(is.na(res$observed[i]), "-", res$observed[i]),
                ifelse(is.na(res$read_from[i]), "-",
                       ifelse(res$read_from[i] == "results", "res", "der")),
                res$status[i]))
    if (res$status[i] != "PASS" && nzchar(res$detail[i]))
      cat(sprintf("%-6s   -> %s\n", "", res$detail[i]))
  }
  tab <- table(factor(res$status, levels = c("PASS", "FAIL", "ERROR")))
  cat(strrep("-", 100), "\n")
  cat(sprintf("%d checks: %d PASS, %d FAIL, %d ERROR\n",
              nrow(res), tab[["PASS"]], tab[["FAIL"]], tab[["ERROR"]]))
  invisible(tab)
}

## --------------------------------------------------------------------------
## Self-test — a verifier that has never failed has not been tested
## --------------------------------------------------------------------------
## Plants a value that is wrong at the ledger's own precision, in a copy of the
## real fixture, and confirms the verifier reports FAIL for it and PASS for its
## untouched neighbours. If this ever comes back green, the verifier is broken
## and every PASS it has ever printed is worthless.
self_test <- function(sections) {
  cat(sprintf("\n%s\nSELF-TEST\n%s\n", strrep("=", 100), strrep("=", 100)))
  fixdir <- file.path(ROOT, "tests", "fixtures")
  dir.create(fixdir, showWarnings = FALSE, recursive = TRUE)

  real <- load_source("pm_threeway_iron.csv")
  if (is.na(real$err) && !is.null(real$data)) {
    bad <- real$data
    row <- which(bad$predictor == "PM_score" & bad$model == "raw_iron")
    stopifnot(length(row) == 1L)
    orig <- bad$estimate[row]
    bad$estimate[row] <- orig + 0.001          # wrong in the 4th dp, plausible-looking
    f <- file.path(fixdir, "pm_threeway_iron.csv")
    write.csv(bad, f, row.names = FALSE)
    cat(sprintf("planted: pm_threeway_iron.csv PM_score/raw_iron estimate %.6f -> %.6f\n",
                orig, bad$estimate[row]))
  } else {
    cat("cannot run self-test: pm_threeway_iron.csv unavailable\n"); return(1L)
  }

  checks <- read.csv(CHECKS, stringsAsFactors = FALSE, colClasses = "character")
  probe  <- checks[checks$source_file == "pm_threeway_iron.csv" &
                     grepl("PM_score raw iron", checks$quantity), , drop = FALSE]
  stopifnot(nrow(probe) >= 2L)

  ## Point the loader at the fixture directory for this run only.
  old_res <- RESULTS; old_der <- DERIVED
  RESULTS <<- fixdir; DERIVED <<- fixdir
  rm(list = ls(.cache), envir = .cache)
  res <- run_checks(probe, sections)
  RESULTS <<- old_res; DERIVED <<- old_der
  rm(list = ls(.cache), envir = .cache)

  report(res, "SELF-TEST — against a deliberately corrupted fixture")

  ## The corrupted quantity must FAIL. Quantities the corruption does not touch
  ## (the SE, the t) must still PASS, or the verifier is simply failing
  ## everything and would be equally useless.
  est_row <- grepl("three-way term", res$quantity)
  other   <- !est_row
  ok <- any(res$status[est_row] == "FAIL") && all(res$status[other] == "PASS")
  cat(sprintf("\nself-test %s: corrupted value %s, untouched neighbours %s\n",
              if (ok) "PASSED" else "FAILED",
              paste(unique(res$status[est_row]), collapse = "/"),
              paste(unique(res$status[other]), collapse = "/")))
  if (!ok) {
    cat("\nTHE VERIFIER DID NOT DETECT A PLANTED ERROR. Do not trust any PASS\n")
    cat("it reports until this is fixed.\n")
    return(1L)
  }
  unlink(f)
  0L
}

## --------------------------------------------------------------------------
## Main
## --------------------------------------------------------------------------
if (!file.exists(LEDGER)) stop("ledger not found: ", LEDGER)
if (!file.exists(CHECKS)) stop("check table not found: ", CHECKS)

sections <- read_ledger_sections(LEDGER)
checks   <- read.csv(CHECKS, stringsAsFactors = FALSE, colClasses = "character")
checks   <- checks[nzchar(trimws(checks$claim_id)), , drop = FALSE]

cat(ferro <- sprintf("claims ledger : %s (%d claim sections)\n", basename(LEDGER), length(sections)))
cat(sprintf("check table   : %s (%d checks)\n", basename(CHECKS), nrow(checks)))
cat(sprintf("results       : %s\n", RESULTS))

st_status <- 0L
if (SELF_TEST) st_status <- self_test(sections)

res <- run_checks(checks, sections)
tab <- report(res, "CLAIM VERIFICATION")

dir.create(RESULTS, showWarnings = FALSE, recursive = TRUE)
write.csv(res, file.path(RESULTS, "claim_verification.csv"), row.names = FALSE)
cat(sprintf("\n[saved] %s\n", file.path("results", "claim_verification.csv")))

## Where did the numbers come from?
if (any(!is.na(res$read_from))) {
  w <- table(res$read_from)
  cat(sprintf("read from: %s\n",
              paste(sprintf("%s %d", names(w), as.integer(w)), collapse = ", ")))
  if (isTRUE(unname(w["data/derived"]) > 0))
    cat("  'der' rows were verified against committed outputs, not against numbers\n",
        "  recomputed on this machine. Populate data/raw/ and rerun run_all.R to\n",
        "  re-derive them from source.\n", sep = "")
}

## Coverage: ledger numbers with no check pointing at them.
if (COVERAGE) {
  cat(sprintf("\n%s\nCOVERAGE\n%s\n", strrep("=", 100), strrep("=", 100)))
  for (id in names(sections)) {
    nums <- ledger_numbers(sections[[id]])
    have <- gsub("−", "-", trimws(checks$ledger_value[checks$claim_id == id]))
    have <- sub("^[+]", "", have)
    miss <- setdiff(sub("^[+]", "", gsub("−", "-", nums)), have)
    cat(sprintf("  %-4s %2d checked, %2d unchecked numeric token(s) in section text\n",
                id, length(have), length(miss)))
  }
  cat("\n  Unchecked tokens include sample sizes, p values quoted in prose and\n")
  cat("  numbers that are part of a name. This count is a floor on what a fuller\n")
  cat("  check table could cover, not a defect list.\n")
}

fail <- tab[["FAIL"]] + tab[["ERROR"]]
if (st_status != 0L) {
  cat("\nSELF-TEST FAILED — verifier is not trustworthy.\n"); quit(status = 2L)
}
if (fail > 0L) {
  cat(sprintf("\n%d check(s) did not pass. A mismatch is a finding: fix the analysis\n", fail))
  cat("or restate the claim. Do not widen the tolerance.\n")
  quit(status = 1L)
}
cat("\nAll claims verified.\n")
