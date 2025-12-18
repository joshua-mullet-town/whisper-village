"""
Local ML server for transcript cleanup.

Runs Flask server on localhost:8000 that Whisper Village can call.

Usage:
    python ml/server.py

Endpoints:
    POST /process - Clean up transcript text
        Body: {"text": "i uh think we should go", "models": ["filler", "list"]}
        Response: {"text": "i think we should go", "models_applied": ["filler"]}

    GET /health - Check server status
        Response: {"status": "ok", "models_loaded": ["filler", "repetition", "repair", "list"]}
"""

import os
import sys
from pathlib import Path

# Add parent to path so we can import from ml.pipeline
sys.path.insert(0, str(Path(__file__).parent.parent))

from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)  # Allow cross-origin requests from Swift app

# Global model instances (loaded once at startup)
MODELS = {}
LOAD_ERRORS = {}


def convert_list_style(text, style="bullets"):
    """Convert bullet list to numbered list if requested."""
    if style != "numbered":
        return text

    lines = text.split("\n")
    result = []
    num = 1
    for line in lines:
        if line.startswith("- "):
            result.append(f"{num}. {line[2:]}")
            num += 1
        else:
            result.append(line)
            num = 1  # reset for next list
    return "\n".join(result)


def load_models():
    """Load all available models at startup."""
    from ml.pipeline.models import AVAILABLE_MODELS

    print("Loading ML models...")
    for name, model_class in AVAILABLE_MODELS.items():
        try:
            print(f"  Loading {name}...", end=" ", flush=True)
            MODELS[name] = model_class()
            print("✓")
        except FileNotFoundError as e:
            print(f"✗ (not found)")
            LOAD_ERRORS[name] = str(e)
        except Exception as e:
            print(f"✗ ({e})")
            LOAD_ERRORS[name] = str(e)

    print(f"\nLoaded {len(MODELS)}/{len(AVAILABLE_MODELS)} models")
    if LOAD_ERRORS:
        print(f"Failed to load: {list(LOAD_ERRORS.keys())}")


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({
        'status': 'ok',
        'models_loaded': list(MODELS.keys()),
        'models_failed': LOAD_ERRORS
    })


@app.route('/process', methods=['POST'])
def process():
    """
    Process text through ML pipeline.

    Request body:
        {
            "text": "the transcript text to clean",
            "models": ["filler", "repetition", "repair", "list"]  # optional, defaults to all
        }

    Response:
        {
            "text": "cleaned text",
            "original": "original text",
            "models_applied": ["filler", "repetition"]
        }
    """
    data = request.get_json()

    # Debug: log what we received
    print(f"\n[REQUEST] models={data.get('models', 'NOT SPECIFIED')}, text={data.get('text', '')[:50]}...")

    if not data or 'text' not in data:
        return jsonify({'error': 'Missing "text" field'}), 400

    text = data['text']
    original = text

    # Which models to apply
    # Default: just 'filler' (safest, no false positives)
    # Repetition/repair can have false positives on list-style text
    # List formatter has issues with long context before list indicators
    DEFAULT_MODELS = ['filler']
    requested_models = data.get('models', DEFAULT_MODELS)

    # Define processing order (matters for quality)
    # 0. Truecasing FIRST (needs full context, proper nouns)
    # 1. Filler removal (uh, um)
    # 2. Repetition removal (i i -> i)
    # 3. Repair removal (we were i was -> i was)
    # 4. List formatting LAST (so disfluency models clean the raw text first)
    DISFLUENCY_ORDER = ['filler', 'repetition', 'repair']

    models_applied = []

    # Run truecasing FIRST (before removing any words, so it has full context)
    if 'truecase' in requested_models and 'truecase' in MODELS:
        try:
            text = MODELS['truecase'].process(text)
            models_applied.append('truecase')
        except Exception as e:
            print(f"Error in truecase: {e}")

    # Run disfluency models on the (now properly cased) transcript
    for model_name in DISFLUENCY_ORDER:
        if model_name in requested_models and model_name in MODELS:
            try:
                text = MODELS[model_name].process(text)
                models_applied.append(model_name)
            except Exception as e:
                print(f"Error in {model_name}: {e}")

    # Run list formatter last (it transforms structure, disfluency models would break it)
    if 'list' in requested_models and 'list' in MODELS:
        try:
            text = MODELS['list'].process(text)
            # Apply list style conversion (bullets or numbered)
            list_style = data.get('list_style', 'bullets')
            text = convert_list_style(text, list_style)
            models_applied.append('list')
        except Exception as e:
            print(f"Error in list: {e}")

    return jsonify({
        'text': text,
        'original': original,
        'models_applied': models_applied
    })


@app.route('/process/<model_name>', methods=['POST'])
def process_single(model_name):
    """
    Process text through a single model.

    Useful for testing individual models.
    """
    if model_name not in MODELS:
        return jsonify({
            'error': f'Model "{model_name}" not loaded',
            'available': list(MODELS.keys())
        }), 404

    data = request.get_json()
    if not data or 'text' not in data:
        return jsonify({'error': 'Missing "text" field'}), 400

    text = data['text']

    try:
        result = MODELS[model_name].process(text)
        return jsonify({
            'text': result,
            'original': text,
            'model': model_name
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    load_models()
    print("\n" + "="*50)
    print("ML Server starting on http://localhost:8000")
    print("="*50)
    print("\nEndpoints:")
    print("  GET  /health          - Check status")
    print("  POST /process         - Run full pipeline")
    print("  POST /process/<model> - Run single model")
    print("\nExample:")
    print('  curl -X POST http://localhost:8000/process \\')
    print('       -H "Content-Type: application/json" \\')
    print('       -d \'{"text": "i uh think we should go"}\'')
    print("\nPress Ctrl+C to stop\n")

    app.run(host='0.0.0.0', port=8000, debug=False)
