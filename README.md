# Ferroptosis defence — reproducibility repository

Analysis code, derived data and figure production for a pan-cancer study of cell-intrinsic
ferroptosis defence across 785 cancer cell lines, with external replication in the Sanger
Cell Model Passports panel and TCGA primary tumours.

Clone it, run one command, and every number and figure in the manuscript regenerates —
then a verifier checks each regenerated number against the claim it is supposed to support.

```sh
Rscript run_all.R
```

That runs the analysis, builds the figures, and finishes with the claim check. It exits
non-zero if any claim fails to verify.

---

## Contents

```
R/                  analysis scripts, numbered in execution order
figures/            figure production scripts (rendered output goes to results/figures/)
data/
  MANIFEST.csv      every raw source file: URL, version, SHA-256, licence
  download.R        fetch + checksum-verify the raw data
  raw/              git-ignored; populated by download.R
  derived/          committed derived objects and model outputs (small, text/rds)
results/            git-ignored; everything run_all.R regenerates
docs/
  claims_ledger.md  one row per manuscript claim, with its numbers and provenance
  claim_checks.csv  machine-readable extraction spec for the verifier
  figure_map.csv    every number a figure prints -> its source object
  ROUND2_FINDINGS.md, FOLLOWUP_FINDINGS.md, FINDINGS.md
run_all.R           top-level driver
verify_claims.R     checks the ledger against the regenerated output
renv.lock           exact package versions (174 packages, R 4.5.2)
```

---

## What the paper claims, and where each claim's code lives

Claim IDs are the ledger's. Each row of `docs/claims_ledger.md` states the claim at its verb
ceiling, the analysis that licenses it, the cohort, the numbers, and where it appears.

| ID | Claim, in one line | Code | Figure |
|----|--------------------|------|--------|
| **K1** | KEAP1-altered lines are more resistant to all three inducers; controls are ~4× weaker | `R/10_keap1_exposure_models.R` | 1A |
| **K2** | About half the KEAP1 effect runs through PM_score; the rest reaches drug response otherwise | `R/07`, `R/08`, `R/10` | 1B, 1C |
| **K3** | The classifier separates HIGH from wild-type on both readouts, before any drug model | `R/09_keap1_functional_gate.R` | S1 |
| **K4** | The effect is Lung-concentrated; out-of-Lung it holds for ML210 only | `R/11_keap1_lineage.R` | text |
| **P1** | PC1 of the five-gene panel is unstable: three genes flip sign, PC1/PC2 near-degenerate | `R/03_bootstrap_pca.R` | 2A, S4 |
| **P2** | PM_score (AIFM2+SLC7A11) replaces Defense PC1; two co-regulated genes, not an axis | `R/02_predictors_decomposed.R` | 2B–2D |
| **P3** | DHODH is null in the decomposed model and indistinguishable from random coherent axes | `R/02`, `R/05` | 2C, 4B |
| **P4** | GCH1 is positive in two inducers, opposite in sign to its PC1 loading | `R/02_predictors_decomposed.R` | 2C |
| **P5** | Higher PM_score, less GPX4 dependency; survives control for GPX4's own expression | `R/06_crossarm_specificity.R` | 4A |
| **P6** | GPX4 ranks first of 13,580 genes under PM_score; 0.5% of random axes match | `R/06_crossarm_specificity.R` | 4B |
| **I1** | Iron handling modifies the association, specifically for the direct GPX4 inhibitors | `R/12_iron_interaction.R` | 6 |
| **M1** | The inducers' association is within lineages; the controls' is between them | `R/13_lineage_mundlak.R` | 3B |
| **L1** | No single lineage drives it, but slopes differ substantially between lineages | `R/13_lineage_mundlak.R` | 5A, 5B |
| **L2** | Lineage slope tracks lineage median PM_score — ecologically, not within lines | `R/14_meta_regression.R` | 5C |
| **L3** | No ceiling at high PM_score within the observed range; power is only 15% at +1.0 | `R/15_ceiling.R` | S2 |
| **L4** | Erastin diverges from the two direct inhibitors across four independent analyses | cross-references I1, L1, L2, K4, P2 | — |
| **X1** | The two-gene structure is recovered in the Sanger panel | `R/17_external_replication.R` | 7 |
| **X2** | In tumours the two genes do not co-vary; the claim narrows to AIFM2 | `R/17_external_replication.R` | 7 |
| **X3** | Prognostic scan on PM_score: no consistent direction (exploratory) | `R/16_prognosis.R` | S3 |
| **C1** | Cohort definitions and filter order | `R/01_cohort_reconstruct.R` | Methods |
| **C2** | Lineage-median RSL3 AUC spans 1.82-fold, not the "2-fold" written by hand | `figures/Figure3_production.R` | 3A |

---

## Cohorts

| Name | n | Definition |
|---|---|---|
| `COHORT_ALL` | **785** | All QC-passing cancer lines with expression. Nine `Non-Cancerous` lines dropped. |
| `COHORT_COMPLETE` | **752** | Complete expression + AUC + covariates. **Canonical for every model.** |
| `COHORT_FIG1` | **707** | Lineage-filtered subset for the landscape panel. Not a model n. |
| CRISPR overlap | **567** | `COHORT_COMPLETE` ∩ lines with Chronos data. |

**The filter order matters and is not interchangeable.** `COHORT_FIG1` is built by tallying
lineage sizes over **all 785 lines**, keeping the 17 lineages with n ≥ 15, and **then** dropping
lines with a missing RSL3 AUC. That gives **17 lineages and 707 lines**.

Reversing the two steps — complete cases first, then tally — gives **16 lineages and 695 lines**.
That variant is not used. Both numbers are computed in `figures/Figure3_production.R` and printed
in the panel caption, so the difference can never again be mistaken for a discrepancy.

One consequence worth expecting: a lineage is admitted on its full-cohort size but drawn on lines
that have an RSL3 AUC, so one lineage (Bone) plots 12 boxes under a "≥ 15" heading. The caption
says so.

---

## Stale-number registry

These appear in earlier drafts and reproduce on **no live cohort**. Finding one in an output
means you have found a bug, not a result.

| Stale | Should be | Why it is wrong |
|---|---|---|
| **784** | 785 | Pre-dates dropping the nine non-cancerous lines. |
| **708** | 707 | The Figure 1A filter applied to the retired 794-line cohort. |
| **591** | 590 / 567 | Superseded CRISPR overlap count. |
| **β = 0.05412** | 0.056660 | From a 26 May 2026 run whose covariate build differed (Lipid coefficient ~10× larger). Its carrier file was deleted. |
| **r = 0.506** | 0.503 (`Iron_PC1`) or 0.401 (seven-gene mean-z) | DepMap's PM_score–iron correlation, typed as a literal into the external-replication script and never computed. Reproduces from no cohort: 785 → 0.5044, 752 → 0.5031, 707 → 0.5010. That script now computes its DepMap column instead of quoting it. |

Two further corrections made while building this repository, both caught by `verify_claims.R`
and both fixed in the **ledger**, since the analysis was right and the transcription was not:

- **K2**, ρ at which the ACME crosses zero for ML210: ledger said 0.32, data says 0.3147 → **0.31**.
- **L3**, fifth-quintile slope: ledger said +0.061, data says 0.06047 → **+0.060**.

And one ambiguity clarified rather than corrected: **P2**'s "max VIF 1.90" is the maximum across
*all* model terms (HIF_score, erastin model). Among the four decomposed predictors the maximum is
**1.43**. The ledger now says both.

---

## Reproducing

### Requirements

R ≥ 4.5. Exact package versions are in `renv.lock` (174 packages, generated on R 4.5.2) and
in `docs/package_versions.csv` for reading without a JSON parser.

```r
install.packages("renv")
renv::restore()          # reproduce the exact environment
```

`renv.lock` is committed as the version **pin**. The repository deliberately does **not** ship an
auto-activating `.Rprofile`: renv activation switches to an empty project library, so a fresh
clone would fail to run until a long install completed. Restore the environment if you want the
exact versions; otherwise the pipeline runs against your own library.

### Commands

```sh
Rscript run_all.R                    # analysis + figures + verification
Rscript run_all.R --analysis         # analysis only
Rscript run_all.R --figures          # figures only
Rscript run_all.R --verify           # verification only
Rscript run_all.R --from 12          # resume at stage 12

Rscript verify_claims.R --self-test  # prove the verifier can fail, then verify
Rscript verify_claims.R --coverage   # also report unchecked ledger numbers

Rscript data/download.R --list       # what the raw data is, and where it comes from
Rscript data/download.R              # fetch + verify
Rscript data/download.R --verify-only
```

### Two tiers, and which one you are on

**Tier 1 — reproduce (default).** `data/raw/` is empty. The eleven stages that read a
genome-scale source table are skipped and their committed outputs in `data/derived/` are used.
Everything else recomputes. All 135 claim checks run. **Runtime ~3 minutes.**

**Tier 2 — re-derive from source.** Run `data/download.R` first. All eighteen stages run for
real. **Runtime ~40 minutes** for the analysis plus the download; stage 00 peaks around 16 GB of
memory on the TCGA expression matrix.

`results/_PROVENANCE.csv` records, per file, whether this machine recomputed it or inherited it
from `data/derived/`. `verify_claims.R` prints the same distinction per claim, so "verified"
never silently means "verified against the file I shipped".

### Hardware assumptions

Tier 1 needs ~2 GB of RAM and about 200 MB of disk beyond the clone. Tier 2 needs ~16 GB of RAM
and ~6 GB of disk for `data/raw/`. Timings above are from a Windows 11 machine with R 4.5.2;
nothing is parallelised, so wall time scales with single-core speed.

---

## The verifier

`verify_claims.R` is the point of this repository. It reads `docs/claims_ledger.md`, and for each
recorded quantity checks **two** things:

1. **Ledger match** — the value in `docs/claim_checks.csv` must literally appear in that claim's
   section of the ledger. This catches the check table drifting away from the prose.
2. **Data match** — the value must equal the regenerated output, **at the precision the ledger
   quotes it to**. `+0.1743` is checked to four decimals, `42` to zero.

There is no epsilon and no flag to widen one. If a number does not survive its own stated
precision, the honest options are to fix the analysis or restate the claim.

**The self-test is not optional.** A verifier that has never failed has not been tested — that is
how the VEP vocabulary mismatch and the rank-deficiency issue got through. `--self-test` plants a
value that is wrong in the fourth decimal into a copy of a real fixture, and asserts that the
verifier reports FAIL for the corrupted quantity **and** PASS for its untouched neighbours. A
verifier that fails everything is as useless as one that fails nothing.

Current state: **135 checks, 135 PASS**, covering all 21 claim IDs.

---

## Data policy

No raw DepMap, CTRP, Cell Model Passports or TCGA file is committed. Redistribution terms differ
per provider and some prohibit mirroring. `data/MANIFEST.csv` records, for each of 17 source files
(5.4 GB total): the filename, source, version tag, landing-page URL, byte count, **SHA-256**,
access date, licence, and which analysis consumes it.

`data/download.R` verifies every file against that checksum. **On a mismatch it stops and names
the file, and there is no flag to make it proceed** — a truncated or wrong-version download does
not look broken, it looks like a slightly different answer.

Most manifest entries are marked `fetch = manual`. A direct URL is recorded only where one has
been verified to work: the DepMap portal serves its files behind a Cloudflare Turnstile check, and
the PanCanAtlas and Cell Model Passports per-file links are not stable across releases. Writing
plausible-looking direct URLs that had never been tested would produce a script that appears to
automate the download and in fact 404s — the same class of silent failure the checksums exist to
catch. So the manifest gives the landing page and the exact filename, and `download.R` tells you
where to put the file and then proves you got the right one.

Files under `data/derived/` are **derived** objects — score matrices and model outputs computed
from those sources — not copies of source data.

Versions used: **DepMap 25Q2 Public**; **CTRPv2.0** PharmacoSet via ORCESTRA/PharmacoDB
(Zenodo DOI [10.5281/zenodo.7826870](https://zenodo.org/records/7826870)); Cell Model Passports
release 2026-06-19 (model list) and 2026-03-23 (RNA-seq); TCGA PanCanAtlas 2018 freeze with MC3
v0.2.8.

---

## Reproducibility guarantees, and their limits

- **Seeds.** Each stage sets its own fixed, documented seed in its own source (the bootstrap PCA
  uses 20260813). `run_all.R` sets seed 1 and exports it, and every report header records it.
  An earlier version of `R/_paths.R` also called `set.seed()`, which silently **overrode** the
  stages' own seeds and changed the bootstrap loadings by up to 2.6. The test caught it; the line
  is gone and the file now records the seed without setting it.
- **Idempotence.** Deleting `results/` and rerunning reproduces it byte-identically apart from
  timestamps in report headers. Verified by running the pipeline twice from clean: 29 of 30 CSV
  outputs byte-identical, and all 10 text reports identical once the `run:` line is removed. The
  one exception is `results/run_all_log.csv`, which records per-stage wall-clock timings by design.
  That test found a real defect: `exactRLRT`'s simulation-based p values were unseeded, so
  erastin's random-slopes p came back as 0.2010 on one run and 0.2088 on the next while the
  statistic stayed at 0.434 — and ledger row L1 quotes that p as 0.20. `R/13_lineage_mundlak.R`
  now seeds immediately before the call.
- **No hardcoded numbers in figures.** Every displayed value is `sprintf`-ed from the fitted
  object or read from the source CSV. Where a literal must stay — a cohort filter, a conventional
  threshold — it is paired with a `stopifnot` against the live data. `docs/figure_map.csv` lists
  all 287 displayed quantities with their sources.
- **`coord_cartesian()`, never `scale_*_continuous(limits =)`.** `limits=` drops out-of-range rows
  *before* statistics are computed, so a boxplot or smoother can change silently when the window
  changes. There are zero `limits=` calls in `figures/`.
- **What is not guaranteed.** Tier 2 is the less-exercised path. Bit-identical output across
  different BLAS implementations or R minor versions is not claimed; the claim checks are at the
  ledger's stated precision, which is where the manuscript's numbers live.

---

## Citation

> Ryan, H. (2026). *Cell-intrinsic ferroptosis defence across cancer cell lines: a two-gene
> plasma-membrane score.* Manuscript in preparation.

Software archive: **DOI to be assigned on Zenodo release** — placeholder, not yet minted.
Do not cite a DOI for this repository until it appears here.

## Licence

Code: **MIT** (see `LICENSE`). Data licences are those of the original providers and are **not**
relicensed here; `data/MANIFEST.csv` names the licence for each source.
