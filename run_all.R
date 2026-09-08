#!/usr/bin/env Rscript
###############################################################################
## run_all.R — regenerate every number and figure in the manuscript.
##
##   Rscript run_all.R              full pipeline, then figures, then verify
##   Rscript run_all.R --analysis   analysis only
##   Rscript run_all.R --figures    figures only (needs results/ populated)
##   Rscript run_all.R --verify     claim verification only
##   Rscript run_all.R --from 06    resume at stage 06
##
## TIERS. Stage 00 rebuilds data/derived/ from data/raw/ and is SKIPPED unless
## data/raw/ has been populated by data/download.R. Every later stage runs from
## the committed derived objects, so a fresh clone reproduces the whole paper
## without downloading 5.5 GB. Downloading is for auditing the derived objects
## themselves, not for reproducing the results.
##
## IDEMPOTENCE. Deleting results/ and rerunning reproduces it byte-identically
## apart from timestamps in report headers. The seed is fixed here and re-set by
## _paths.R inside each stage, so stages are reproducible individually too.
##
## Each stage runs in its own R session. A stage cannot leak objects into the
## next, and a failure names exactly one script.
###############################################################################

SEED <- 1L
set.seed(SEED)
Sys.setenv(FERRO_SEED = SEED)

ROOT <- local({
  fa <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(fa) >= 1L)
    dirname(normalizePath(sub("^--file=", "", fa[length(fa)]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
})
stopifnot(file.exists(file.path(ROOT, "run_all.R")))

args     <- commandArgs(trailingOnly = TRUE)
only     <- function(f) any(args == f)
from_arg <- if (any(grepl("^--from$", args)))
  args[which(args == "--from") + 1L] else NA_character_

do_analysis <- !only("--figures") && !only("--verify")
do_figures  <- !only("--analysis") && !only("--verify")
do_verify   <- !only("--analysis") && !only("--figures")

RESULTS <- file.path(ROOT, "results")
DERIVED <- file.path(ROOT, "data", "derived")
dir.create(RESULTS, showWarnings = FALSE, recursive = TRUE)

## ---------------------------------------------------------------------------
## Seed results/ from the committed outputs
## ---------------------------------------------------------------------------
## Stages that need data/raw/ are skipped on a fresh clone, but later stages read
## their output by bare filename out of results/. Seeding those files first is
## what makes the skip work instead of cascading into a missing-file error.
##
## Every seeded file is recorded in results/_PROVENANCE.csv and then OVERWRITTEN
## the moment its producing stage actually runs, so the record always says which
## numbers this machine recomputed and which came out of the repository. Without
## that record the two are indistinguishable on disk, which is precisely how a
## stale intermediate survives a rerun and gets reported as a fresh result.
seed_results <- function() {
  cand <- list.files(DERIVED, full.names = TRUE)
  cand <- cand[!grepl("\\.(R|md)$", cand)]
  ## master.rds and the other primary inputs are read through R2/DERIVED
  ## directly; only files a stage reads by bare name need to be here.
  seeded <- character(0)
  for (p in cand) {
    tgt <- file.path(RESULTS, basename(p))
    if (!file.exists(tgt)) { file.copy(p, tgt); seeded <- c(seeded, basename(p)) }
  }
  seeded
}
seeded_files <- seed_results()
prov_path <- file.path(RESULTS, "_PROVENANCE.csv")

## An existing record is kept and extended rather than overwritten: on a rerun
## nothing new is seeded, and clobbering the file would erase the distinction
## between what this machine computed and what it inherited.
prov_tbl <- if (file.exists(prov_path)) {
  read.csv(prov_path, stringsAsFactors = FALSE)
} else {
  data.frame(file = character(0), origin = character(0),
             recomputed_here = logical(0), stringsAsFactors = FALSE)
}

new_seed <- setdiff(seeded_files, prov_tbl$file)
if (length(new_seed))
  prov_tbl <- rbind(prov_tbl,
                    data.frame(file = new_seed, origin = "committed (data/derived)",
                               recomputed_here = FALSE, stringsAsFactors = FALSE))
prov_tbl <- prov_tbl[order(prov_tbl$file), , drop = FALSE]
write.csv(prov_tbl, prov_path, row.names = FALSE)

cat(sprintf("results/: %d file(s) seeded from data/derived/ this run, %d tracked in total\n",
            length(seeded_files), nrow(prov_tbl)))

## Called after each stage that actually ran, to flip its outputs to recomputed.
mark_recomputed <- function(before) {
  now <- list.files(RESULTS)
  changed <- now[!(now %in% names(before)) |
                 vapply(now, function(f) {
                   k <- file.path(RESULTS, f)
                   !(f %in% names(before)) || !identical(unname(before[f]), file.mtime(k))
                 }, logical(1))]
  if (!file.exists(prov_path) || !length(changed)) return(invisible(NULL))
  pv <- read.csv(prov_path, stringsAsFactors = FALSE)
  new <- setdiff(changed, pv$file)
  if (length(new))
    pv <- rbind(pv, data.frame(file = new, origin = "regenerated",
                               recomputed_here = TRUE, stringsAsFactors = FALSE))
  pv$origin[pv$file %in% changed] <- "regenerated"
  pv$recomputed_here[pv$file %in% changed] <- TRUE
  write.csv(pv[order(pv$file), , drop = FALSE], prov_path, row.names = FALSE)
  invisible(NULL)
}
snapshot <- function() {
  fs <- list.files(RESULTS)
  setNames(file.mtime(file.path(RESULTS, fs)), fs)
}

## ---------------------------------------------------------------------------
## Stages, in execution order. The `needs` column is documentation, not
## dispatch: the order below IS the dependency order, and a stage that reads a
## file an earlier stage has not written fails loudly on its own.
## ---------------------------------------------------------------------------
## `raw` marks stages that read a large source table through src() and therefore
## cannot run without data/raw/. That is most of them: this project's models are
## fit on genome-scale CRISPR, expression and mutation matrices, and no amount of
## repository design makes a 430 MB dependency optional.
##
## What IS optional is the download, because every one of these stages has its
## output committed under data/derived/. A fresh clone skips them, and the
## figures and the claim verifier read the committed outputs instead. Running
## them re-derives those outputs into results/, which then shadows the committed
## copies everywhere downstream. Both paths reproduce the paper; only the second
## one re-proves it from source.
STAGES <- data.frame(
  id     = c("00", "01", "02", "03", "04", "05", "06", "07", "08",
             "09", "10", "11", "12", "13", "14", "15", "16", "17"),
  script = c("00_build_derived.R",
             "01_cohort_reconstruct.R",
             "02_predictors_decomposed.R",
             "03_bootstrap_pca.R",
             "04_crispr_genomewide_null.R",
             "05_axis_level_null.R",
             "06_crossarm_specificity.R",
             "07_mediation_acme.R",
             "08_mediation_sensitivity.R",
             "09_keap1_functional_gate.R",
             "10_keap1_exposure_models.R",
             "11_keap1_lineage.R",
             "12_iron_interaction.R",
             "13_lineage_mundlak.R",
             "14_meta_regression.R",
             "15_ceiling.R",
             "16_prognosis.R",
             "17_external_replication.R"),
  claims = c("—", "C1, C2", "P2, P3, P4", "P1", "P3", "P3, P6", "P5, P6",
             "K2", "K2", "K3", "K1, K2", "K4", "I1", "M1, L1", "L2", "L3",
             "X3", "X1, X2"),
  raw    = c(TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, FALSE,
             TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE),
  stringsAsFactors = FALSE)

raw_dir   <- file.path(ROOT, "data", "raw")
raw_files <- list.files(raw_dir, recursive = TRUE, pattern = "[^/]$")
have_raw  <- length(raw_files) > 0L

if (!is.na(from_arg)) STAGES <- STAGES[STAGES$id >= from_arg, , drop = FALSE]

rscript <- file.path(R.home("bin"),
                     if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

banner <- function(...) cat(sprintf("\n%s\n%s\n%s\n", strrep("=", 72),
                                    sprintf(...), strrep("=", 72)))

run_script <- function(path, label) {
  t0 <- Sys.time()
  st <- system2(rscript, shQuote(path), stdout = "", stderr = "")
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (st != 0L) {
    cat(sprintf("\n!! %s FAILED (exit %d) after %.1fs\n", label, st, secs))
    cat("   Pipeline halted. Fix this stage before continuing; later stages read\n")
    cat("   its output and would fail or, worse, silently use a stale file.\n")
    quit(status = 1L)
  }
  secs
}

log <- data.frame()

## ---------------------------------------------------------------------------
## Analysis
## ---------------------------------------------------------------------------
if (do_analysis) {
  banner("FERROPTOSIS DEFENCE — ANALYSIS   (seed %d, R %s)", SEED, getRversion())
  for (i in seq_len(nrow(STAGES))) {
    s <- STAGES[i, ]
    path <- file.path(ROOT, "R", s$script)

    if (s$raw && !have_raw) {
      cat(sprintf("-- %s  %-34s SKIPPED  (needs data/raw/; committed output used)\n",
                  s$id, s$script))
      log <- rbind(log, data.frame(stage = s$id, script = s$script,
                                   claims = s$claims, seconds = NA, status = "skipped-no-raw"))
      next
    }
    if (!file.exists(path))
      stop("missing stage script: ", path)

    banner("%s  %s   [claims: %s]", s$id, s$script, s$claims)
    before <- snapshot()
    secs <- run_script(path, s$script)
    mark_recomputed(before)
    log <- rbind(log, data.frame(stage = s$id, script = s$script,
                                 claims = s$claims, seconds = secs, status = "ok"))
  }
}

## ---------------------------------------------------------------------------
## Figures
## ---------------------------------------------------------------------------
if (do_figures) {
  banner("FIGURES")
  secs <- run_script(file.path(ROOT, "figures", "make_all_figures.R"), "make_all_figures.R")
  log <- rbind(log, data.frame(stage = "fig", script = "make_all_figures.R",
                               claims = "all", seconds = secs, status = "ok"))
}

## ---------------------------------------------------------------------------
## Verification — the point of the repository
## ---------------------------------------------------------------------------
verify_status <- NA_integer_
if (do_verify) {
  banner("CLAIM VERIFICATION")
  t0 <- Sys.time()
  verify_status <- system2(rscript, shQuote(file.path(ROOT, "verify_claims.R")),
                           stdout = "", stderr = "")
  log <- rbind(log, data.frame(stage = "verify", script = "verify_claims.R",
                               claims = "all",
                               seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")),
                               status = if (verify_status == 0L) "PASS" else "FAIL"))
}

## ---------------------------------------------------------------------------
## Summary
## ---------------------------------------------------------------------------
banner("SUMMARY")
if (nrow(log)) {
  for (i in seq_len(nrow(log)))
    cat(sprintf("  %-6s %-34s %-14s %8s  %s\n", log$stage[i], log$script[i],
                log$claims[i],
                if (is.na(log$seconds[i])) "-" else sprintf("%.1fs", log$seconds[i]),
                log$status[i]))
  write.csv(log, file.path(RESULTS, "run_all_log.csv"), row.names = FALSE)
}
if (!have_raw && do_analysis) {
  n_skip <- sum(log$status == "skipped-no-raw", na.rm = TRUE)
  cat(sprintf(paste0(
    "\n  data/raw/ is empty, so %d of %d analysis stages were skipped and their\n",
    "  committed outputs in data/derived/ were used instead. The figures and the\n",
    "  claim verifier read those, so the paper still reproduces end to end.\n\n",
    "  To re-derive them from the original source data (~5.5 GB, ~40 min):\n",
    "    Rscript data/download.R      # fetch + SHA-256 verify against MANIFEST\n",
    "    Rscript run_all.R            # every stage now runs for real\n"),
    n_skip, nrow(STAGES)))
}

if (!is.na(verify_status) && verify_status != 0L) {
  cat("\n  CLAIM VERIFICATION FAILED. See results/claim_verification.csv.\n")
  cat("  A mismatch is a finding, not a nuisance: do not widen the tolerance.\n")
  quit(status = 1L)
}
cat("\n  Done.\n")
