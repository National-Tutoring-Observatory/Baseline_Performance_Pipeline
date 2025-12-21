# FloorBenchmark Pipeline

A standalone, configurable pipeline for running the Foundation Model FloorBenchmark on different data samples.

## Overview

This pipeline allows you to:
- **Run benchmarks on different samples** (whole sample, stratified sample, or custom samples)
- **Configure models and prompts** through a YAML configuration file
- **Parallelize execution** for faster processing
- **Automatically analyze results** and generate performance metrics
- **Track runs and compare** different configurations

## Directory Structure

```
FloorBenchmark_Pipeline/
├── config/
│   └── pipeline_config.yaml       # Main configuration file
├── scripts/
│   └── analyze_results.r          # Analysis script
├── prompts/                        # Prompt JSON files (copy from main project)
├── data/
│   ├── inputs/                     # Symlinks to data samples
│   └── outputs/                    # Pipeline results
├── results/                        # Analysis results and summaries
├── logs/                           # Execution logs
├── run_pipeline.r                  # Main pipeline runner
├── .env                            # API keys (copy from main project)
└── README.md                       # This file
```

## Setup

### 1. Copy Required Files

From the main project directory, copy or symlink:

```bash
# Copy prompts
cp -r ../prompts/FloorBenchmark_Prompts/* prompts/

# Copy or create symlink to .env file
cp ../.env .
# OR
ln -s ../.env .env

# Create symlinks to data directories
ln -s ../data/inputs/TalkMoves/all_transcripts data/inputs/whole_sample
ln -s ../data/inputs/stratified_samples/RepresentativeSample_Oversampled_Chunks data/inputs/stratified_sample
```

### 2. Install Required R Packages

```r
install.packages(c(
    "dplyr", "readr", "stringr", "purrr", "jsonlite",
    "fs", "httr", "furrr", "yaml", "irr", "tidyr"
))
```

### 3. Configure Your Run

Edit `config/pipeline_config.yaml`:

```yaml
# Choose your sample
sample_type: "stratified_sample"  # or "whole_sample" or "custom"

# Set run name
run_name: "FloorBenchmark_MyRun"

# Select models
models:
  - "anthropic.claude-4.5-opus"
  - "openai.gpt-5.1"
  # ... add more models

# Enable test mode for quick testing
test_mode: false
test_subset_size: 10
```

## Usage

### Basic Usage

Run the pipeline with default configuration:

```bash
Rscript run_pipeline.r
```

### Using Custom Configuration

```bash
Rscript run_pipeline.r config/my_custom_config.yaml
```

### Test Mode

For quick testing with a small subset:

1. Edit `config/pipeline_config.yaml`:
```yaml
test_mode: true
test_subset_size: 10
```

2. Run:
```bash
Rscript run_pipeline.r
```

### Analysis Only

To analyze existing results without running the pipeline:

```bash
Rscript scripts/analyze_results.r
```

### Analysis Only
 
To analyze existing results without running the pipeline:
 
```bash
Rscript scripts/analyze_results.r
```

## Configuration Options

### Sample Selection

```yaml
sample_type: "stratified_sample"  # Options: whole_sample, stratified_sample, custom

sample_paths:
  whole_sample: "../data/inputs/TalkMoves/all_transcripts"
  stratified_sample: "../data/inputs/stratified_samples/RepresentativeSample_Oversampled_Chunks"

# For custom samples
custom_sample_path: "/path/to/your/custom/sample"
```

### Model Configuration

```yaml
models:
  - "anthropic.claude-4.5-opus"
  - "anthropic.claude-4.5-sonnet"
  - "openai.gpt-5.1"
  - "openai.o3"
  - "google.gemini-2.5-pro"
  - "google.gemini-3-pro-preview"
```

### Prompt Configuration

Use all prompts:
```yaml
# Set prompt directory (e.g., for No Reasoning experiments)
prompt_directory: "prompts/TalkMoves_NoReasoningRequested"

specific_prompts:
  - "TalkMoves_Teacher_ZeroShot.json"
  - "TalkMoves_Teacher_OneShot.json"
  - "TalkMoves_Teacher_FewShot_3.json"
  - "TalkMoves_Teacher_FewShot_ALL.json"
```

### Execution Settings

```yaml
parallel_workers: 20      # Number of parallel workers
temperature: 0.0          # LLM temperature (0.0 = deterministic)
max_tokens: 4000          # Max tokens per request
request_timeout: 300      # Timeout in seconds
```

### Test Mode

```yaml
test_mode: true           # Enable test mode
test_subset_size: 10      # Number of files to process
```

## Output Structure

```
data/outputs/FloorBenchmark_MyRun/
├── run_metadata.json                    # Run information
├── analysis_results.csv                 # Performance metrics
├── TalkMoves_Teacher_ZeroShot/
│   ├── anthropic.claude-4.5-opus/
│   │   ├── file1.json_raw.txt
│   │   └── file2.json_raw.txt
│   └── openai.gpt-5.1/
│       └── ...
└── TalkMoves_Teacher_OneShot/
    └── ...
```

## Results

Results are saved in the `results/` directory:

- `{run_name}_results.csv`: Detailed results for each model/prompt combination
- `{run_name}_summary.csv`: Summary statistics per model

### Results Format

**Detailed Results** (`_results.csv`):
```csv
Prompt,Model,N,Accuracy,Kappa
TalkMoves_Teacher_ZeroShot,anthropic.claude-4.5-opus,8350,0.686,0.513
```

**Summary** (`_summary.csv`):
```csv
Model,Prompts_Tested,Avg_Accuracy,Avg_Kappa,Best_Kappa,Total_Utterances
anthropic.claude-4.5-opus,4,0.685,0.511,0.513,27000
```

## Comparing Different Samples

### Run 1: Whole Sample
```yaml
sample_type: "whole_sample"
run_name: "FloorBenchmark_Whole"
```

```bash
Rscript run_pipeline.r
```

### Run 2: Stratified Sample
```yaml
sample_type: "stratified_sample"
run_name: "FloorBenchmark_Stratified"
```

```bash
Rscript run_pipeline.r
```

### Compare Results

```r
# Load results
whole <- read_csv("results/FloorBenchmark_Whole_results.csv")
stratified <- read_csv("results/FloorBenchmark_Stratified_results.csv")

# Compare
comparison <- full_join(
    whole %>% rename(Kappa_Whole = Kappa),
    stratified %>% rename(Kappa_Stratified = Kappa),
    by = c("Prompt", "Model")
) %>%
    mutate(Kappa_Diff = Kappa_Stratified - Kappa_Whole)
```

## Logging

Logs are saved to `logs/pipeline_{timestamp}.log` when `verbose_logging: true`.

Example log entries:
```
[2025-12-18 09:00:00] === FloorBenchmark Pipeline Started ===
[2025-12-18 09:00:00] Sample Type: stratified_sample
[2025-12-18 09:00:00] Found 405 input files
[2025-12-18 09:00:00] Total tasks: 8100
[2025-12-18 09:45:00] === Pipeline Complete ===
[2025-12-18 09:45:00] Elapsed time: 45.2 minutes
```

## Tips and Best Practices

### 1. Start with Test Mode
Always test with a small subset first:
```yaml
test_mode: true
test_subset_size: 5
```

### 2. Monitor Progress
Watch the logs in real-time:
```bash
tail -f logs/pipeline_*.log
```

### 3. Resume Failed Runs
The pipeline automatically skips completed files, so you can safely re-run after failures.

### 4. Parallel Workers
Adjust based on your system and API rate limits:
- For API rate limits: Use fewer workers (5-10)
- For fast execution: Use more workers (20-30)

### 5. Save Configurations
Save different configurations for different experiments:
```bash
cp config/pipeline_config.yaml config/experiment_1.yaml
# Edit experiment_1.yaml
Rscript run_pipeline.r config/experiment_1.yaml
```

## Troubleshooting

### API Authentication Errors
- Ensure `.env` file exists with valid credentials:
```
AI_GATEWAY_KEY=your_key_here
AI_GATEWAY_BASE_URL=https://your-gateway.com
```

### No Input Files Found
- Check that symlinks are created correctly
- Verify `sample_paths` in configuration
- Ensure input directory contains `.json` files

### Analysis Fails
- Check that `ground_truth_file` path is correct
- Ensure ground truth CSV has required columns: `ID`, `Transcript`, `Turn`, `TalkMove_truth`

### Out of Memory
- Reduce `parallel_workers`
- Enable `test_mode` to process smaller batches

## License

Same as parent project.

## Support

For issues or questions, please refer to the main project repository.
