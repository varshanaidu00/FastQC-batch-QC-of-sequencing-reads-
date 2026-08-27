# Batch QC of sequencing reads by FastQC

A lightweight Bash code for running [FastQC](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
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
````
Output is a txt summary file, which extracts the following information from FastQC analyses

| Parameter            | Description                                  |
| -------------------- | -------------------------------------------  |
| `samples`            | The name/identifier of the sequencing sample |
| `Total_Reads`        | The total number of sequencing reads/sequence records analysed by FastQC |
| `Unique_Reads`       | The estimated number of reads that are not duplicates based on FastQC's deduplication percentage                    |
| `Duplicate_Reads`    | The estimated number of reads identified as duplicates based on FastQC's deduplication percentage                |
| `Pct_Duplicates(%)`  | The estimated percentage of reads that are duplicates       |
| `Avg_Q_Score`        | The average Phred quality score across the sequencing reads |
| `Pct_Q30(%)`         | The percentage of base positions with a mean quality score of Q30 or higher |
| `GC_Content(%)`      | The percentage of guanine (G) and cytosine (C) bases in the sequences    |
| `Sequence_length`    | The length of the sequencing reads, or the range of read lengths when reads are variable in length                      |
