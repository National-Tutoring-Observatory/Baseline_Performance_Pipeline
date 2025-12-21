# Quick Start Guide - FloorBenchmark Pipeline

## 1. Run Setup

```bash
cd FloorBenchmark_Pipeline
./setup.sh
```

This will:
- Copy the `.env` file
- Create symlinks to data directories
- Copy prompt files
- Update configuration

## 2. Test the Pipeline

Edit `config/pipeline_config.yaml` to enable test mode:

```yaml
sample_type: "stratified_sample"
test_mode: true
test_subset_size: 5
```

Run a quick test:

```bash
Rscript run_pipeline.r
```

## 3. Run Full Benchmark

### On Stratified Sample:

Edit `config/pipeline_config.yaml`:
```yaml
sample_type: "stratified_sample"
test_mode: false
run_name: "FloorBenchmark_Stratified"
```

Run:
```bash
Rscript run_pipeline.r
```

Rscript run_pipeline.r
```

## 4. Benchmark with "No Reasoning" Prompts (Current Experiment)

Edit `config/pipeline_config.yaml`:
```yaml
sample_type: "experiment_800"
run_name: "Experiment_800_NoReasoning"
prompt_directory: "prompts/TalkMoves_NoReasoningRequested"
# Ensure specific_prompts includes the 4 files
```

Run:
```bash
Rscript run_pipeline.r
```

## 5. View Results

Results are saved in:
- `results/` - CSV files with performance metrics
- `data/outputs/{run_name}/` - Raw model outputs
- `logs/` - Execution logs

View detailed results:
```bash
cat results/FloorBenchmark_Stratified_results.csv
```

View summary:
```bash
cat results/FloorBenchmark_Stratified_summary.csv
```



## 4. Compare Samples

After running on both samples, compare results using R:

```r
library(dplyr)
library(readr)

# Load both results
whole <- read_csv("results/FloorBenchmark_Whole_results.csv")
stratified <- read_csv("results/FloorBenchmark_Stratified_results.csv")

# Compare
merged <- full_join(whole, stratified, 
                    by = c("Prompt", "Model"),
                    suffix = c("_Whole", "_Stratified"))

# View differences
merged %>% 
    mutate(Kappa_Diff = Kappa_Stratified - Kappa_Whole) %>%
    select(Model, Prompt, Kappa_Whole, Kappa_Stratified, Kappa_Diff) %>%
    arrange(desc(abs(Kappa_Diff)))
```

## Troubleshooting

### "Permission Denied" when running scripts

```bash
chmod +x run_pipeline.r setup.sh scripts/analyze_results.r
```

### "Input directory does not exist"

Check symlinks:
```bash
ls -la data/inputs/
```

Re-run setup:
```bash
./setup.sh
```

### API Errors

Verify `.env` file has valid credentials:
```bash
cat .env
```

Should contain:
```
AI_GATEWAY_KEY=your_key_here
AI_GATEWAY_BASE_URL=https://your-gateway.com
```

## Configuration Tips

### Run Specific Models Only

```yaml
models:
  - "anthropic.claude-4.5-opus"
  - "openai.gpt-5.1"
```

### Run Specific Prompts Only

```yaml
specific_prompts:
  - "TalkMoves_Teacher_ZeroShot.json"
  - "TalkMoves_Teacher_OneShot.json"
```

### Adjust Parallelization

For faster execution (if API allows):
```yaml
parallel_workers: 30
```

For rate-limited APIs:
```yaml
parallel_workers: 5
```

## Next Steps

1. Review the full [README.md](README.md) for detailed documentation
2. Customize configurations for your specific needs
3. Set up version control for your configurations
4. Track and compare different experimental runs
