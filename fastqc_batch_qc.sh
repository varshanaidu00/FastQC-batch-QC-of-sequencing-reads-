#!/usr/bin/env bash

# ==============================================================================
# fastqc_batch_qc.sh
#
# Run FastQC on all .fastq.gz files in an input directory and generate a
# tab-delimited summary of key QC metrics.
#
# Usage:
#   ./fastqc_batch_qc.sh -i INPUT_DIR -o OUTPUT_DIR [-t THREADS]
#
# Example:
#   ./fastqc_batch_qc.sh \
#       -i /path/to/FastQ_files \
#       -o /path/to/fastqc_output \
#       -t 8
#
# Requirements:
#   - bash
#   - FastQC
#   - awk
#   - grep
#   - sed
#   - sort
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------------------

THREADS=8
SUMMARY_NAME="fastqc_summary.tsv"

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

usage() {
    cat << EOF

FastQC Batch QC
===============

Run FastQC on all .fastq.gz files in a directory and generate a summary TSV.

Usage:
    $(basename "$0") -i INPUT_DIR -o OUTPUT_DIR [-t THREADS]

Options:
    -i    Input directory containing .fastq.gz files
    -o    Output directory for FastQC results
    -t    Number of FastQC threads [default: ${THREADS}]
    -h    Show this help message

Example:
    $(basename "$0") \\
        -i /data/FastQ_files \\
        -o /data/fastqc_output \\
        -t 8

EOF
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || \
        error "Required command not found: $1"
}

# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------

INPUT_DIR=""
OUTPUT_DIR=""

while getopts ":i:o:t:h" opt; do
    case "$opt" in
        i)
            INPUT_DIR="$OPTARG"
            ;;
        o)
            OUTPUT_DIR="$OPTARG"
            ;;
        t)
            THREADS="$OPTARG"
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            error "Invalid option: -$OPTARG"
            ;;
        :)
            error "Option -$OPTARG requires an argument."
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Validate arguments
# ------------------------------------------------------------------------------

[[ -n "$INPUT_DIR" ]] || error "Input directory is required. Use -i."
[[ -n "$OUTPUT_DIR" ]] || error "Output directory is required. Use -o."

[[ -d "$INPUT_DIR" ]] || \
    error "Input directory does not exist: $INPUT_DIR"

[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || \
    error "Threads must be a positive integer: $THREADS"

# ------------------------------------------------------------------------------
# Check dependencies
# ------------------------------------------------------------------------------

check_command fastqc
check_command awk
check_command grep
check_command sort

# ------------------------------------------------------------------------------
# Prepare directories
# ------------------------------------------------------------------------------

mkdir -p "$OUTPUT_DIR"

SUMMARY_TXT="$OUTPUT_DIR/$SUMMARY_NAME"
LOG_FILE="$OUTPUT_DIR/fastqc_batch_qc.log"

# ------------------------------------------------------------------------------
# Find FASTQ files
# ------------------------------------------------------------------------------

shopt -s nullglob
FASTQ_FILES=("$INPUT_DIR"/*.fastq.gz)
shopt -u nullglob

if [[ ${#FASTQ_FILES[@]} -eq 0 ]]; then
    error "No .fastq.gz files found in: $INPUT_DIR"
fi

# ------------------------------------------------------------------------------
# Print run information
# ------------------------------------------------------------------------------

{
    echo "============================================"
    echo "FastQC Batch QC"
    echo "============================================"
    echo "Input directory : $INPUT_DIR"
    echo "Output directory: $OUTPUT_DIR"
    echo "Threads         : $THREADS"
    echo "FASTQ files     : ${#FASTQ_FILES[@]}"
    echo "Started         : $(date)"
    echo "============================================"
} | tee "$LOG_FILE"

# ------------------------------------------------------------------------------
# Create summary header
# ------------------------------------------------------------------------------

printf "Sample\tTotal_Reads\tUnique_Reads\tDuplicate_Reads\tPct_Duplicates\tAvg_Q_Score\tPct_Q30\tGC_Content\tSequence_Length\tFastQC_Status\n" \
    > "$SUMMARY_TXT"

# ------------------------------------------------------------------------------
# Run FastQC
# ------------------------------------------------------------------------------

log "Starting FastQC..." | tee -a "$LOG_FILE"

for FASTQ in "${FASTQ_FILES[@]}"; do

    SAMPLE=$(basename "$FASTQ" .fastq.gz)

    log "Processing: $SAMPLE" | tee -a "$LOG_FILE"

    fastqc \
        "$FASTQ" \
        --outdir "$OUTPUT_DIR" \
        --threads "$THREADS" \
        --extract \
        --quiet

    log "FastQC complete: $SAMPLE" | tee -a "$LOG_FILE"

done

# ------------------------------------------------------------------------------
# Extract FastQC metrics
# ------------------------------------------------------------------------------

log "Generating summary..." | tee -a "$LOG_FILE"

for FASTQ in "${FASTQ_FILES[@]}"; do

    SAMPLE=$(basename "$FASTQ" .fastq.gz)

    DATA_FILE="$OUTPUT_DIR/${SAMPLE}_fastqc/fastqc_data.txt"

    if [[ ! -f "$DATA_FILE" ]]; then
        log "WARNING: fastqc_data.txt not found for $SAMPLE — skipping." \
            | tee -a "$LOG_FILE"
        continue
    fi

    # --------------------------------------------------------------------------
    # Total reads
    # --------------------------------------------------------------------------

    TOTAL=$(awk -F'\t' '
        $1 == "Total Sequences" {
            print $2
            exit
        }
    ' "$DATA_FILE")

    # --------------------------------------------------------------------------
    # Sequence length
    # --------------------------------------------------------------------------

    SEQ_LEN=$(awk -F'\t' '
        $1 == "Sequence length" {
            print $2
            exit
        }
    ' "$DATA_FILE")

    # --------------------------------------------------------------------------
    # GC content
    # --------------------------------------------------------------------------

    GC=$(awk -F'\t' '
        $1 == "%GC" {
            print $2
            exit
        }
    ' "$DATA_FILE")

    # --------------------------------------------------------------------------
    # Deduplication metrics
    #
    # FastQC reports "Total Deduplicated Percentage".
    # This is used to estimate unique and duplicate reads.
    # --------------------------------------------------------------------------

    PCT_DEDUP=$(awk -F'\t' '
        $1 == "Total Deduplicated Percentage" {
            print $2
            exit
        }
    ' "$DATA_FILE")

    if [[ -n "$PCT_DEDUP" && -n "$TOTAL" ]]; then

        UNIQUE=$(awk -v total="$TOTAL" -v pct="$PCT_DEDUP" \
            'BEGIN { printf "%.0f", total * pct / 100 }')

        DUPLICATES=$(awk -v total="$TOTAL" -v unique="$UNIQUE" \
            'BEGIN { printf "%.0f", total - unique }')

        PCT_DUP=$(awk -v pct="$PCT_DEDUP" \
            'BEGIN { printf "%.2f", 100 - pct }')

    else
        UNIQUE="NA"
        DUPLICATES="NA"
        PCT_DUP="NA"
    fi

    # --------------------------------------------------------------------------
    # Average Q score
    #
    # Uses the Per sequence quality scores module.
    # --------------------------------------------------------------------------

    AVG_Q=$(awk '
        />>Per sequence quality scores/ {
            in_module=1
            next
        }

        />>END_MODULE/ {
            in_module=0
        }

        in_module && $1 ~ /^[0-9]/ {
            sum += $1 * $2
            count += $2
        }

        END {
            if (count > 0)
                printf "%.2f", sum / count
            else
                printf "NA"
        }
    ' "$DATA_FILE")

    # --------------------------------------------------------------------------
    # Percentage of base positions with mean quality >= Q30
    #
    # NOTE:
    # This is the percentage of positions whose mean quality score is >= Q30,
    # not the percentage of individual bases in the FASTQ file that are Q30+.
    # --------------------------------------------------------------------------

    PCT_Q30=$(awk '
        />>Per base sequence quality/ {
            in_module=1
            next
        }

        />>END_MODULE/ {
            in_module=0
        }

        in_module && $1 ~ /^[0-9]/ {
            total++
            if ($2 + 0 >= 30)
                good++
        }

        END {
            if (total > 0)
                printf "%.2f", (good / total) * 100
            else
                printf "NA"
        }
    ' "$DATA_FILE")

    # --------------------------------------------------------------------------
    # FastQC module status
    #
    # Produces values such as:
    #   PASS:8 WARN:2 FAIL:0
    # --------------------------------------------------------------------------

    STATUS=$(awk '
        /^(PASS|WARN|FAIL)/ {
            count[$1]++
        }

        END {
            printf "PASS:%d WARN:%d FAIL:%d", \
                count["PASS"] + 0, \
                count["WARN"] + 0, \
                count["FAIL"] + 0
        }
    ' "$DATA_FILE")

    # --------------------------------------------------------------------------
    # Write summary row
    # --------------------------------------------------------------------------

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$SAMPLE" \
        "${TOTAL:-NA}" \
        "$UNIQUE" \
        "$DUPLICATES" \
        "$PCT_DUP" \
        "$AVG_Q" \
        "$PCT_Q30" \
        "${GC:-NA}" \
        "${SEQ_LEN:-NA}" \
        "$STATUS" \
        >> "$SUMMARY_TXT"

done

# ------------------------------------------------------------------------------
# Finish
# ------------------------------------------------------------------------------

{
    echo ""
    echo "============================================"
    echo "FastQC Batch QC complete"
    echo "============================================"
    echo "Summary : $SUMMARY_TXT"
    echo "Log     : $LOG_FILE"
    echo "Finished: $(date)"
    echo "============================================"
} | tee -a "$LOG_FILE"

echo ""
echo "Summary:"
column -t -s $'\t' "$SUMMARY_TXT" 2>/dev/null || cat "$SUMMARY_TXT"
