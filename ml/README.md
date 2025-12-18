# ML Pipeline - Transcript Cleanup

This module provides ML-powered transcript cleanup using fine-tuned DistilBERT models.

## Architecture

```
ml/
├── models/                    # Trained models (gitignored)
│   ├── filler-remover/        # Filler word removal model
│   └── repetition-remover/    # Repetition removal model
├── pipeline/                  # Pipeline module
│   ├── __init__.py           # Public API
│   ├── models.py             # Model classes
│   ├── pipeline.py           # Pipeline orchestration
│   └── server.py             # HTTP server
├── training/                  # Training scripts
│   ├── train_filler.py
│   └── train_repetition.py
├── tests/                     # Test suite
│   ├── fixtures.json         # Test cases
│   ├── test_filler.py
│   ├── test_repetition.py
│   └── test_pipeline.py
└── README.md
```

## Quick Start

```python
from ml.pipeline import TranscriptPipeline

pipeline = TranscriptPipeline()
clean = pipeline.process("i uh think um we we should go")
# Returns: "i think we should go"
```

## Models

### FillerRemover
- Removes filler words (uh, um, etc.)
- Preserves discourse markers (well, you know, so)
- 99.7% F1 score
- Trained on DisfluencySpeech dataset

### RepetitionRemover
- Removes stutters and repetitions
- Handles word and phrase repetitions
- 79.4% F1 score
- Trained on Switchboard + DisfluencySpeech (157K examples)

## How It Works

Both models use **BIO token classification**:
- **B-FILL / B-REP**: Beginning of filler/repetition
- **I-FILL / I-REP**: Inside filler/repetition
- **O**: Keep this word

The pipeline runs: Input → FillerRemover → RepetitionRemover → Clean output

## Testing

```bash
# Run all tests
pytest ml/tests/ -v

# Run specific test file
pytest ml/tests/test_pipeline.py -v

# Run with details
pytest ml/tests/ -v --tb=long
```

## HTTP Server

For Whisper Village integration:

```bash
# Start server
python -m ml.pipeline.server

# Endpoints:
# POST /cleanup          - Full pipeline cleanup
# POST /cleanup/fillers  - Filler removal only
# POST /cleanup/reps     - Repetition removal only
# GET  /health           - Health check
# GET  /models           - List available models
```

Example request:
```bash
curl -X POST http://localhost:8765/cleanup \
  -H "Content-Type: application/json" \
  -d '{"text": "i uh think we we should go"}'
```

## Adding a New Model

1. **Train the model** using `ml/training/` as a template

2. **Save model** to `ml/models/your-model-name/`

3. **Create model class** in `ml/pipeline/models.py`:
```python
class YourModel(BaseModel):
    MODEL_DIR = "your-model-name"

    def _should_remove(self, label: str) -> bool:
        return "YOUR_LABEL" in label
```

4. **Register in AVAILABLE_MODELS**:
```python
AVAILABLE_MODELS = {
    'filler': FillerRemover,
    'repetition': RepetitionRemover,
    'your_model': YourModel,  # Add here
}
```

5. **Add to pipeline** (optional - for default pipeline):
```python
# In pipeline.py __init__
if enable_your_feature:
    self.models.append(YourModel())
```

6. **Add tests** in `ml/tests/`:
   - Create `test_your_model.py`
   - Add test cases to `fixtures.json`

## Configuration

### Custom Pipeline
```python
# Only filler removal
pipeline = TranscriptPipeline(enable_fillers=True, enable_repetitions=False)

# Only repetition removal
pipeline = TranscriptPipeline(enable_fillers=False, enable_repetitions=True)

# Custom model order
from ml.pipeline import FillerRemover, RepetitionRemover
models = [RepetitionRemover(), FillerRemover()]  # Reversed order
pipeline = TranscriptPipeline(custom_models=models)
```

### Detailed Output
```python
result = pipeline.process_with_details("i uh i think")
# Returns:
# {
#   "input": "i uh i think",
#   "output": "i think",
#   "steps": [
#     {"model": "FillerRemover", "input": "...", "output": "...", "removed": [...]},
#     {"model": "RepetitionRemover", "input": "...", "output": "...", "removed": [...]}
#   ]
# }
```

## Dependencies

```
torch
transformers
datasets  # For training only
```

## Model Storage

Models are stored locally and gitignored (~265MB each). To set up:

1. Ensure models exist in `ml/models/`
2. Or retrain using scripts in `ml/training/`

## Datasets Used

- **DisfluencySpeech**: Filler annotations
- **Switchboard**: Repetition/restart annotations
- Combined: 157K training examples for repetition model
