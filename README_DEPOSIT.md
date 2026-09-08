# Source data for the ferroptosis defence analysis

This record holds the **17 unmodified source files** that a pan-cancer analysis of
cell-intrinsic ferroptosis defence was computed from: DepMap 25Q2, the CTRPv2 PharmacoSet,
Sanger Cell Model Passports, and TCGA PanCanAtlas. 5.40 GB in total.

**Nothing here is original data.** Every file is redistributed unchanged from its provider,
under that provider's licence, so that the analysis can be re-derived from source rather than
from an intermediate somebody has to take on trust. The providers are credited below and each
file's origin is recorded in `MANIFEST.csv`.

## What this is for

The analysis code lives in a separate repository, which also carries the derived score matrices
and model outputs it needs. **You do not need this record to reproduce the paper** — the code
repository regenerates every number and figure on its own, in about three minutes.

You need this record only to re-derive those intermediates from source: to answer "is
`master.rds` really what the raw DepMap tables say it is?" rather than "what does the paper
conclude?". That is an audit, and it is the reason these files are archived rather than merely
cited.

- Code: see the *Related identifiers* on this record.
- With this record downloaded, `Rscript run_all.R` runs all 18 analysis stages instead of 7.

## Using it

Put the record ID in `data/zenodo_record.txt` in the code repository and run:

```sh
Rscript data/download.R
```

That fetches every file, restores the `Holes/` and `psets/` subdirectories the pipeline expects,
and verifies each file's SHA-256 against `MANIFEST.csv`. **On any mismatch it stops and names the
file, and there is no flag to override it** — a truncated download does not look broken, it looks
like a slightly different answer.

To check the files without R, or without trusting the repository:

```sh
sha256sum -c SHA256SUMS
```

## Why the files are uncompressed

Several would compress hard; the 1.8 GB TSV especially. They are archived uncompressed anyway,
because gzipping changes every checksum, and the manifest would then no longer verify the bytes
the analysis actually read. This record exists to be verifiable, not to be small.

## Contents

| file | MB | source | version |
|---|---:|---|---|
| `EBPlusPlusAdjustPANCAN_IlluminaHiSeq_RNASeqV2.geneExp.tsv` | 1795.3 | TCGA PanCanAtlas | 2018 freeze |
| `rnaseq_all_20260323.zip` | 1148.5 | Cell Model Passports | 2026-03-23 |
| `mc3.v0.2.8.PUBLIC.maf.gz` | 718.4 | TCGA MC3 | v0.2.8 |
| `all_thresholded.by_genes_whitelisted.tsv` | 561.6 | TCGA PanCanAtlas GISTIC | 2018 freeze |
| `OmicsExpressionProteinCodingGenesTPMLogp1.csv` | 497.4 | DepMap Public | 25Q2 |
| `CRISPRGeneEffect.csv` | 410.5 | DepMap Public | 25Q2 |
| `OmicsSomaticMutations.csv` | 340.1 | DepMap Public | 25Q2 |
| `PSet_CTRPv2.rds` | 38.8 | CTRPv2 PharmacoSet | v2.0 |
| `merged_sample_quality_annotations.tsv` | 8.1 | TCGA PanCanAtlas QC | 2018 freeze |
| `Drug_sensitivity_AUC_(CTD^2)_subsetted.csv` | 5.6 | DepMap (CTD²/CTRP AUC) | 25Q2 |
| `TCGA-CDR-SupplementalTableS1.xlsx` | 2.8 | TCGA-CDR (Liu et al. 2018) | 2018 |
| `model_list_20260619.csv` | 0.9 | Cell Model Passports | 2026-06-19 |
| `TCGA_mastercalls.abs_tables_JSedit.fixed.txt` | 0.9 | TCGA ABSOLUTE purity | 2018 freeze |
| `Model.csv` | 0.7 | DepMap Public | 25Q2 |
| `sample_info.csv` | 0.4 | DepMap legacy | legacy |
| `Cell_lines_annotations_20181226.txt` | 0.3 | CCLE legacy annotations | 2018-12-26 |
| `OmicsGlobalSignatures.csv` | 0.1 | DepMap Public | 25Q2 |

Also included: `MANIFEST.csv` (per-file source, version, URL, SHA-256, licence, and which
analysis consumes it) and `SHA256SUMS`.

## Attribution and licences

Each file remains under its provider's licence. **Nothing here is relicensed.** Redistribution is
under the terms below; if you reuse these files, cite the original providers, not this record.

**DepMap (9 files, CC BY 4.0)** — Broad Institute DepMap Public 25Q2. Please cite the DepMap
release and the Broad Institute. <https://depmap.org>

**CTRPv2 PharmacoSet (1 file, CC BY 4.0)** — Cancer Therapeutics Response Portal v2.0, packaged
via ORCESTRA/PharmacoDB, Zenodo DOI [10.5281/zenodo.7826870](https://doi.org/10.5281/zenodo.7826870).

**Cell Model Passports (2 files, Wellcome Sanger Institute)** — <https://cellmodelpassports.sanger.ac.uk>.
Redistributed here under the Sanger Institute's data-sharing terms; users should consult those
terms directly for onward reuse.

**TCGA PanCanAtlas (5 files, NIH open access)** — open-access tier only; no controlled-access
data is included. <https://gdc.cancer.gov/about-data/publications/pancanatlas>. The clinical
endpoints file is Supplemental Table S1 of Liu *et al.*, *Cell* 173:400–416 (2018).

## Release identification

DepMap 25Q2 is identified from `Model.csv`, which carries the two columns 25Q2 introduced
(`PediatricModelType`, `ModelIDAlias`) and lacks all four 25Q3 tracking columns. The analysis
re-checks this at run time and prints a loud mismatch banner if the mutation calls and the cohort
ever disagree on release, so a future swap cannot pass unnoticed.
