#!/bin/bash

# Check if a model name was provided
if [ -z "$1" ]; then
    echo "Please provide a model name (e.g. ./check_model_usage.sh Question)"
    exit 1
fi

MODEL_NAME=$1
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Checking usage of $MODEL_NAME model..."
echo "----------------------------------------"

# Check model definition
echo "Model Definition:"
find "$PROJECT_ROOT" -name "*.swift" -exec grep -l "struct $MODEL_NAME:" {} \;
echo ""

# Check view model usage
echo "ViewModel Usage:"
find "$PROJECT_ROOT/TTB/ViewModels" -name "*.swift" -exec grep -l "$MODEL_NAME" {} \;
echo ""

# Check view usage
echo "View Usage:"
find "$PROJECT_ROOT/TTB/Views" -name "*.swift" -exec grep -l "$MODEL_NAME" {} \;
echo ""

# Check preview providers
echo "Preview Providers:"
find "$PROJECT_ROOT" -name "*.swift" -exec grep -l "$MODEL_NAME.*_Previews" {} \;
echo ""

# Check Firestore references
echo "Firestore References:"
find "$PROJECT_ROOT" -name "*.swift" -exec grep -l "Firestore.*$MODEL_NAME" {} \;
echo ""

# Check computed properties
echo "Computed Properties:"
find "$PROJECT_ROOT" -name "*.swift" -exec grep -l "var.*$MODEL_NAME" {} \;
echo ""

echo "----------------------------------------"
echo "Please review each file listed above for potential impacts of model changes."
echo "Follow the Model Change Impact Analysis Protocol in the project documentation."
