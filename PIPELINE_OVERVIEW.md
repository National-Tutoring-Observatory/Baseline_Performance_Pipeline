# FloorBenchmark Pipeline - Setup Complete! 🎉

## What Was Created

A standalone, configurable repository for running the FloorBenchmark pipeline on different data samples.

### Directory Structure

```
FloorBenchmark_Pipeline/
├── 📁 config/
│   └── pipeline_config.yaml          # YAML configuration (select sample, models, etc.)
│
├── 📁 scripts/
│   └── analyze_results.r              # Automated analysis script
│
├── 📁 prompts/                         # Prompt JSON files (to be copied from main project)
│
├── 📁 data/
│   ├── inputs/                         # Symlinks to data samples
│   │   ├── .gitkeep
│   │   ├── whole_sample → (symlink to full dataset)
│   │   └── stratified_sample → (symlink to stratified sample)
│   └── outputs/                        # Pipeline results
│       └── .gitkeep
│
├── 📁 results/                         # Analysis CSV files
│   └── .gitkeep
│
├── 📁 logs/                            # Execution logs
│   └── .gitkeep
│
├── 🚀 run_pipeline.r                   # Main pipeline runner script
├── 🔧 setup.sh                         # Automated setup script
├── 📖 README.md                        # Complete documentation
├── ⚡ QUICKSTART.md                    # Quick start guide
├── 🙈 .gitignore                       # Git ignore rules
└── 📄 .env                             # API credentials (to be copied)
```

## Key Features

### ✅ Configurable Sample Selection
Switch between samples by editing one line in the config:
```yaml
sample_type: "stratified_sample"  # or "whole_sample" or "custom"
```

### ✅ Model & Prompt Selection
Choose which models and prompts to test:
```yaml
models:
  - "anthropic.claude-4.5-opus"
  - "anthropic.claude-4.5-sonnet"
  - "openai.gpt-5.1"
  - "openai.o3"
  - "google.gemini-2.5-pro"
  - "google.gemini-3-pro-preview"

prompt_directory: "prompts/TalkMoves_NoReasoningRequested"
specific_prompts:
  - "TalkMoves_Teacher_ZeroShot.json"
  - "TalkMoves_Teacher_OneShot.json"
  - "TalkMoves_Teacher_FewShot_3.json"
  - "TalkMoves_Teacher_FewShot_ALL.json"
```

### ✅ Test Mode
Quick testing with small subsets:
```yaml
test_mode: true
test_subset_size: 10
```

### ✅ Automatic Analysis
Results are automatically analyzed and saved:
- `results/{run_name}_results.csv` - Detailed metrics
- `results/{run_name}_summary.csv` - Summary statistics

### ✅ Logging & Tracking
All runs are logged with timestamps and metadata

### ✅ Resume Capability
Pipeline skips already-completed files, so you can resume after failures

## Next Steps

### 1. Run Setup
```bash
cd FloorBenchmark_Pipeline
./setup.sh
```

### 2. Test Run
```bash
# Edit config/pipeline_config.yaml (set test_mode: true)
Rscript run_pipeline.r
```

### 3. Full Run(s)

**Stratified Sample:**
```yaml
# config/pipeline_config.yaml
sample_type: "stratified_sample"
run_name: "FloorBenchmark_Stratified"
test_mode: false
```
```bash
Rscript run_pipeline.r
```

**Whole Sample:**
```yaml
# config/pipeline_config.yaml
sample_type: "whole_sample"
run_name: "FloorBenchmark_Whole"
test_mode: false
```
```bash
Rscript run_pipeline.r
```

### 4. Compare Results

Results will be in:
- `results/FloorBenchmark_Stratified_results.csv`
- `results/FloorBenchmark_Whole_results.csv`

Use existing analysis scripts from the main project, or create custom comparisons!

## Configuration Examples

### Example 1: Quick Test on Stratified Sample
```yaml
sample_type: "stratified_sample"
run_name: "Test_Run"
test_mode: true
test_subset_size: 5
models:
  - "openai.gpt-5.1"
specific_prompts:
  - "TalkMoves_Teacher_ZeroShot.json"
parallel_workers: 5
```

### Example 2: Full Benchmark on Whole Sample
```yaml
sample_type: "whole_sample"
run_name: "FloorBenchmark_Whole_Production"
test_mode: false
models:
  - "anthropic.claude-4.5-opus"
  - "anthropic.claude-4.5-sonnet"
  - "openai.gpt-5.1"
  - "openai.o3"
  - "google.gemini-2.5-pro"
specific_prompts: []  # Use all prompts
parallel_workers: 20
auto_analyze: true
```

### Example 3: Custom Sample
```yaml
sample_type: "custom"
custom_sample_path: "/Users/you/my_custom_sample"
run_name: "Custom_Experiment"
# ... rest of config
```

## Files to Track in Git

If you want to version control the pipeline:

```bash
cd FloorBenchmark_Pipeline
git init
git add .
git commit -m "Initial pipeline setup"
```

The `.gitignore` is already configured to exclude:
- API credentials (`.env`)
- Output data (`data/outputs/*`)
- Results (`results/*`)
- Logs (`logs/*`)

## Benefits of This Approach

1. **🔄 Reproducible**: Same pipeline, different samples
2. **📊 Comparable**: Easy to compare results across samples
3. **🎛️ Configurable**: Change settings without editing code
4. **📝 Documented**: Everything runs are logged and tracked
5. **🚀 Portable**: Can be used as a separate repository
6. **🔁 Reusable**: Run multiple experiments with different configs

## Support

- See `README.md` for comprehensive documentation
- See `QUICKSTART.md` for step-by-step guide
- Configuration help: Check comments in `config/pipeline_config.yaml`

---

**Happy Benchmarking!** 🎯
