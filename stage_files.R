#!/usr/bin/env Rscript
###############################################################################
## stage_files.R — assemble the Zenodo deposit from a verified raw tree.
##
##   Rscript zenodo_deposit/stage_files.R              stage into zenodo_deposit/files/
##   Rscript zenodo_deposit/stage_files.R --check      verify a staged folder, copy nothing
##   Rscript zenodo_deposit/stage_files.R --out DIR    stage somewhere else (e.g. an external disk)
##
## Copies the 17 raw source files named in data/MANIFEST.csv out of FERRO_RAW
## (default ../Data) into a single flat folder ready to upload, verifying each
## file's SHA-256 BEFORE and AFTER the copy.
##
## WHY VERIFY TWICE. Before, because staging a file that is already wrong would
## publish the wrong file under a checksum that says it is right. After, because
## a 1.8 GB copy that silently truncates is a thing that happens, and the whole
## value of the deposit is that its contents are provably the bytes the paper
## was computed from.
##
## FLAT ON PURPOSE. Zenodo records have no directories. Every filename in the
## manifest is unique, so the Holes/ and psets/ structure is reconstructed on
## download from MANIFEST.csv's `subdir` column rather than encoded in the
## deposit. data/download.R does that automatically.
##
## UNCOMPRESSED ON PURPOSE. Gzipping would shrink the upload substantially --
## the 1.8 GB TSV compresses hard -- and would change every checksum, so the
## manifest would no longer verify the file the analysis actually read. The
## deposit exists to be verifiable, not to be small.
##
## This script copies ~5.4 GB. It does not upload anything.
###############################################################################

if (!requireNamespace("digest", quietly = TRUE))
  stop("package 'digest' is required.  install.packages('digest')")

args <- commandArgs(trailingOnly = TRUE)
CHECK_ONLY <- any(args == "--check")
OUT_ARG    <- if (any(args == "--out")) args[which(args == "--out") + 1L] else NA_character_

ROOT <- local({
  fa <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  here <- if (length(fa) >= 1L)
    dirname(normalizePath(sub("^--file=", "", fa[length(fa)]), winslash = "/"))
  else getwd()
  cand <- c(normalizePath(file.path(here, ".."), winslash = "/", mustWork = FALSE),
            normalizePath(here, winslash = "/", mustWork = FALSE),
            normalizePath(getwd(), winslash = "/", mustWork = FALSE))
  hit <- cand[file.exists(file.path(cand, "run_all.R"))]
  if (!length(hit)) stop("Cannot locate the repository root (the folder holding run_all.R).")
  hit[1]
})

MANIFEST <- file.path(ROOT, "data", "MANIFEST.csv")
RAW      <- Sys.getenv("FERRO_RAW", unset = normalizePath(file.path(ROOT, "..", "Data"),
                                                          winslash = "/", mustWork = FALSE))
OUTDIR   <- if (!is.na(OUT_ARG)) OUT_ARG else file.path(ROOT, "zenodo_deposit", "files")

mf <- read.csv(MANIFEST, stringsAsFactors = FALSE)
cat(sprintf("manifest : %s  (%d files, %.2f GB)\n", MANIFEST, nrow(mf), sum(mf$bytes) / 1024^3))
cat(sprintf("source   : %s\n", RAW))
cat(sprintf("staging  : %s%s\n\n", OUTDIR, if (CHECK_ONLY) "   [--check: verifying only]" else ""))

if (!CHECK_ONLY) dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

src_of <- function(i) {
  d <- if (nzchar(mf$subdir[i])) file.path(RAW, mf$subdir[i]) else RAW
  file.path(d, mf$file[i])
}
sha <- function(p) digest::digest(p, algo = "sha256", file = TRUE)

status <- character(nrow(mf)); note <- character(nrow(mf))

for (i in seq_len(nrow(mf))) {
  s <- src_of(i); t <- file.path(OUTDIR, mf$file[i])
  cat(sprintf("[%2d/%2d] %-58s %8.1f MB  ", i, nrow(mf), mf$file[i], mf$bytes[i] / 1024^2))
  flush.console()

  if (CHECK_ONLY) {
    if (!file.exists(t)) { status[i] <- "MISSING"; cat("MISSING\n"); next }
    h <- sha(t)
    status[i] <- if (identical(h, mf$sha256[i])) "OK" else "MISMATCH"
    cat(status[i], "\n"); next
  }

  ## Already staged and correct? Leave it alone -- this makes the script
  ## resumable, which matters when one file is 1.8 GB.
  if (file.exists(t) && file.info(t)$size == mf$bytes[i] && identical(sha(t), mf$sha256[i])) {
    status[i] <- "OK (already staged)"; cat("already staged\n"); next
  }
  if (!file.exists(s)) {
    status[i] <- "SOURCE MISSING"
    note[i] <- s
    cat("SOURCE MISSING\n"); next
  }
  ## Verify the source before trusting it.
  if (!identical(sha(s), mf$sha256[i])) {
    status[i] <- "SOURCE MISMATCH"; note[i] <- s
    cat("SOURCE FAILS CHECKSUM\n"); next
  }
  ok <- file.copy(s, t, overwrite = TRUE)
  if (!ok) { status[i] <- "COPY FAILED"; cat("COPY FAILED\n"); next }
  ## And verify what actually landed.
  status[i] <- if (identical(sha(t), mf$sha256[i])) "OK" else "COPY CORRUPTED"
  cat(status[i], "\n")
}

bad <- which(!grepl("^OK", status))
cat(sprintf("\n%d of %d files OK\n", sum(grepl("^OK", status)), nrow(mf)))

if (length(bad)) {
  cat("\n", strrep("!", 72), "\nNOT READY TO UPLOAD\n\n", sep = "")
  for (i in bad) {
    cat(sprintf("  %-58s %s\n", mf$file[i], status[i]))
    if (nzchar(note[i])) cat(sprintf("      expected at %s\n", note[i]))
    if (status[i] %in% c("MISSING", "SOURCE MISSING"))
      cat(sprintf("      get it from %s\n", mf$url[i]))
  }
  cat("\nDo not upload a partial deposit: a record whose checksums do not match\n")
  cat("its own manifest is worse than no record at all.\n")
  cat(strrep("!", 72), "\n", sep = "")
  quit(status = 1L)
}

if (!CHECK_ONLY) {
  ## SHA256SUMS in the standard coreutils format, so anyone can run
  ##   sha256sum -c SHA256SUMS
  ## without R, without this repository, and without trusting either.
  ##
  ## Written through a binary connection to force LF endings. A plain
  ## writeLines() on Windows emits CRLF, and coreutils then reads every filename
  ## with a trailing \r and reports "FAILED open or read" for all 17 files --
  ## a checksum file that looks authoritative and verifies nothing.
  con_sums <- file(file.path(OUTDIR, "SHA256SUMS"), open = "wb")
  writeLines(sprintf("%s  %s", mf$sha256, mf$file), con_sums, sep = "\n")
  close(con_sums)
  for (f in c("README_DEPOSIT.md", "zenodo.json"))
    file.copy(file.path(ROOT, "zenodo_deposit", f), file.path(OUTDIR, f), overwrite = TRUE)
  file.copy(MANIFEST, file.path(OUTDIR, "MANIFEST.csv"), overwrite = TRUE)

  tot <- sum(file.info(list.files(OUTDIR, full.names = TRUE))$size, na.rm = TRUE)
  cat(sprintf("\nstaged %d files, %.2f GB, in %s\n",
              length(list.files(OUTDIR)), tot / 1024^3, OUTDIR))
  cat("\nNext:\n")
  cat("  1. Create the deposit on Zenodo and upload everything in that folder.\n")
  cat("     Files over ~1 GB upload far more reliably through the API than the\n")
  cat("     browser; see README_DEPOSIT.md.\n")
  cat("  2. Publish, then put the record ID in data/zenodo_record.txt.\n")
  cat("  3. Rscript data/download.R   -- now fetches and verifies automatically.\n")
}
