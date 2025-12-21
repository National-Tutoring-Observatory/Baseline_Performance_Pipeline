#!/bin/bash
# Setup script for FloorBenchmark Pipeline

echo "=== FloorBenchmark Pipeline Setup ==="
echo ""

# Check if we're in the right directory
if [ ! -f "run_pipeline.r" ]; then
    echo "Error: This script must be run from the FloorBenchmark_Pipeline directory"
    exit 1
fi

# Copy .env file
if [ ! -f ".env" ]; then
    if [ -f "../.env" ]; then
        echo "Copying .env file from parent directory..."
        cp ../.env .
        echo "✓ .env file copied"
    else
        echo "⚠ .env file not found. Please create one with:"
        echo "  AI_GATEWAY_KEY=your_key"
        echo "  AI_GATEWAY_BASE_URL=your_url"
    fi
else
    echo "✓ .env file already exists"
fi

# Create data input symlinks
echo ""
echo "Creating data symlinks..."

mkdir -p data/inputs

# Whole sample
if [ ! -e "data/inputs/whole_sample" ]; then
    if [ -d "../data/inputs/TalkMoves/all_transcripts" ]; then
        ln -s "$(cd ../data/inputs/TalkMoves/all_transcripts && pwd)" data/inputs/whole_sample
        echo "✓ Created symlink: data/inputs/whole_sample"
    else
        echo "⚠ Whole sample directory not found"
    fi
else
    echo "✓ whole_sample symlink already exists"
fi

# Stratified sample
if [ ! -e "data/inputs/stratified_sample" ]; then
    if [ -d "../data/inputs/stratified_samples/RepresentativeSample_Oversampled_Chunks" ]; then
        ln -s "$(cd ../data/inputs/stratified_samples/RepresentativeSample_Oversampled_Chunks && pwd)" data/inputs/stratified_sample
        echo "✓ Created symlink: data/inputs/stratified_sample"
    else
        echo "⚠ Stratified sample directory not found"
    fi
else
    echo "✓ stratified_sample symlink already exists"
fi

# Copy prompts
echo ""
echo "Copying prompt files..."

if [ -d "../prompts/FloorBenchmark_Prompts" ]; then
    cp ../prompts/FloorBenchmark_Prompts/*.json prompts/ 2>/dev/null
    prompt_count=$(ls -1 prompts/*.json 2>/dev/null | wc -l)
    if [ $prompt_count -gt 0 ]; then
        echo "✓ Copied $prompt_count prompt files"
    else
        echo "⚠ No prompt files found to copy"
    fi
else
    echo "⚠ Prompt directory not found: ../prompts/FloorBenchmark_Prompts"
fi

# Update config paths
echo ""
echo "Checking configuration..."

# Update the config file to use absolute paths for the symlinks
if [ -f "config/pipeline_config.yaml" ]; then
    # Create backup
    cp config/pipeline_config.yaml config/pipeline_config.yaml.bak
    
    # Update paths to use the new symlinks
    sed -i '' 's|whole_sample:.*|whole_sample: "data/inputs/whole_sample"|g' config/pipeline_config.yaml
    sed -i '' 's|stratified_sample:.*|stratified_sample: "data/inputs/stratified_sample"|g' config/pipeline_config.yaml
    
    echo "✓ Configuration updated"
else
    echo "⚠ Configuration file not found"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Ensure your .env file has valid API credentials"
echo "2. Review config/pipeline_config.yaml"
echo "3. Run a test: Rscript run_pipeline.r (with test_mode: true in config)"
echo ""
