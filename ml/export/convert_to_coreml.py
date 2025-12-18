"""
Convert PyTorch BERT token classifier to CoreML format.

Usage:
    python ml/export/convert_to_coreml.py filler
    python ml/export/convert_to_coreml.py repetition
"""

import sys
import os
from pathlib import Path

# Add parent to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

import torch
import coremltools as ct
from transformers import AutoTokenizer, AutoModelForTokenClassification
import numpy as np


def convert_bert_classifier(model_name: str):
    """Convert a BERT token classifier to CoreML."""

    model_path = Path(__file__).parent.parent / "models" / f"{model_name}-remover"
    output_path = Path(__file__).parent.parent / "coreml" / f"{model_name}_remover.mlpackage"

    print(f"Loading model from {model_path}...")

    if not model_path.exists():
        print(f"ERROR: Model not found at {model_path}")
        return False

    # Load the model and tokenizer
    tokenizer = AutoTokenizer.from_pretrained(str(model_path))
    model = AutoModelForTokenClassification.from_pretrained(str(model_path))
    model.eval()

    print(f"Model loaded. Labels: {model.config.id2label}")

    # Create example input for tracing
    # Use a fixed sequence length for CoreML (we'll pad/truncate in Swift)
    MAX_SEQ_LEN = 128

    example_text = "i uh think um we should go"
    inputs = tokenizer(
        example_text,
        return_tensors="pt",
        max_length=MAX_SEQ_LEN,
        padding="max_length",
        truncation=True
    )

    print(f"Example input shape: {inputs['input_ids'].shape}")

    # Trace the model
    print("Tracing model...")

    class TracingWrapper(torch.nn.Module):
        """Wrapper that only takes input_ids and attention_mask."""
        def __init__(self, model):
            super().__init__()
            self.model = model

        def forward(self, input_ids, attention_mask):
            outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
            return outputs.logits

    wrapped_model = TracingWrapper(model)
    wrapped_model.eval()

    traced_model = torch.jit.trace(
        wrapped_model,
        (inputs["input_ids"], inputs["attention_mask"])
    )

    print("Converting to CoreML...")

    # Convert to CoreML
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="logits"),
        ],
        minimum_deployment_target=ct.target.macOS13,
    )

    # Add metadata
    mlmodel.author = "Whisper Village"
    mlmodel.short_description = f"BERT-based {model_name} word remover for transcript cleanup"
    mlmodel.version = "1.0"

    # Add label mapping as user-defined metadata
    mlmodel.user_defined_metadata["id2label"] = str(model.config.id2label)
    mlmodel.user_defined_metadata["label2id"] = str(model.config.label2id)
    mlmodel.user_defined_metadata["max_seq_len"] = str(MAX_SEQ_LEN)

    # Save
    output_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output_path))

    print(f"\nSaved CoreML model to: {output_path}")
    print(f"Model size: {sum(f.stat().st_size for f in output_path.rglob('*') if f.is_file()) / 1024 / 1024:.1f} MB")

    # Also export the tokenizer vocab for Swift
    vocab_path = output_path.parent / f"{model_name}_vocab.json"
    tokenizer.save_pretrained(str(output_path.parent / f"{model_name}_tokenizer"))
    print(f"Saved tokenizer to: {output_path.parent / f'{model_name}_tokenizer'}")

    return True


def test_coreml_model(model_name: str):
    """Test the converted CoreML model."""

    model_path = Path(__file__).parent.parent / "models" / f"{model_name}-remover"
    coreml_path = Path(__file__).parent.parent / "coreml" / f"{model_name}_remover.mlpackage"

    if not coreml_path.exists():
        print(f"CoreML model not found at {coreml_path}")
        return

    print(f"\nTesting CoreML model...")

    # Load both models
    tokenizer = AutoTokenizer.from_pretrained(str(model_path))
    pytorch_model = AutoModelForTokenClassification.from_pretrained(str(model_path))
    pytorch_model.eval()

    coreml_model = ct.models.MLModel(str(coreml_path))

    # Test cases
    test_texts = [
        "i uh think um we should go",
        "so basically um you know like it was",
        "hello world",
    ]

    MAX_SEQ_LEN = 128

    for text in test_texts:
        print(f"\nInput: '{text}'")

        # PyTorch prediction
        inputs = tokenizer(
            text,
            return_tensors="pt",
            max_length=MAX_SEQ_LEN,
            padding="max_length",
            truncation=True
        )

        with torch.no_grad():
            pytorch_logits = pytorch_model(**inputs).logits
        pytorch_preds = torch.argmax(pytorch_logits, dim=2)[0].numpy()

        # CoreML prediction
        coreml_input = {
            "input_ids": inputs["input_ids"].numpy().astype(np.int32),
            "attention_mask": inputs["attention_mask"].numpy().astype(np.int32),
        }
        coreml_output = coreml_model.predict(coreml_input)
        coreml_logits = coreml_output["logits"]
        coreml_preds = np.argmax(coreml_logits, axis=2)[0]

        # Compare
        match = np.array_equal(pytorch_preds, coreml_preds)
        print(f"  PyTorch preds (first 20): {pytorch_preds[:20]}")
        print(f"  CoreML preds (first 20):  {coreml_preds[:20]}")
        print(f"  Match: {'✓' if match else '✗'}")

        if not match:
            diff_indices = np.where(pytorch_preds != coreml_preds)[0]
            print(f"  Differences at indices: {diff_indices[:10]}...")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python convert_to_coreml.py <model_name>")
        print("  model_name: 'filler' or 'repetition'")
        sys.exit(1)

    model_name = sys.argv[1]

    if convert_bert_classifier(model_name):
        test_coreml_model(model_name)
