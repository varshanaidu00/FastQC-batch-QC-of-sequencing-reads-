# FastQC-batch-QC-of-sequencing-reads-
# FastQC Batch QC

A lightweight Bash pipeline for running [FastQC](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
on multiple `.fastq.gz` files and generating a tab-delimited QC summary.

## Features

- Runs FastQC on every `.fastq.gz` file in an input directory
- Configurable number of CPU threads
- Extracts FastQC results automatically
- Produces a TSV summary suitable for Excel, R or Python
- Saves FastQC HTML reports
- Saves extracted FastQC results
- Creates a run log
- Detects missing input files and dependencies
- Can be safely re-run

## Requirements

The following software must be available on your system:

- Bash
- FastQC
- awk
- grep
- sort
- column (optional, used only for prettier terminal output)

Check FastQC:

```bash
fastqc --version
