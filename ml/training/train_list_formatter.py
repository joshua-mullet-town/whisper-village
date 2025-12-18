"""
Train T5-small model for list formatting.

Task: Convert spoken list indicators to formatted bullet points.
  Input:  "my goals are one finish report two send email"
  Output: "my goals are\n- Finish report\n- Send email"

Run:
    python ml/training/train_list_formatter.py
"""

import json
from pathlib import Path

import torch
from datasets import Dataset
from transformers import (
    T5Tokenizer,
    T5ForConditionalGeneration,
    Seq2SeqTrainer,
    Seq2SeqTrainingArguments,
    DataCollatorForSeq2Seq,
)

# Paths
DATA_DIR = Path(__file__).parent.parent / "data" / "list-formatting"
OUTPUT_DIR = Path(__file__).parent.parent / "models" / "list-formatter"

# Model
MODEL_NAME = "t5-small"  # ~60MB, good for simple tasks
MAX_INPUT_LENGTH = 256
MAX_TARGET_LENGTH = 512


def load_data(split: str) -> Dataset:
    """Load data from JSON file."""
    path = DATA_DIR / f"{split}.json"
    with open(path) as f:
        data = json.load(f)

    # Convert to HuggingFace dataset
    return Dataset.from_dict({
        "input": [ex["input"] for ex in data],
        "output": [ex["output"] for ex in data],
    })


def preprocess_function(examples, tokenizer):
    """Tokenize inputs and outputs for T5."""
    # Add task prefix (T5 convention)
    inputs = ["format list: " + text for text in examples["input"]]

    model_inputs = tokenizer(
        inputs,
        max_length=MAX_INPUT_LENGTH,
        truncation=True,
        padding=False,
    )

    # Tokenize targets
    labels = tokenizer(
        examples["output"],
        max_length=MAX_TARGET_LENGTH,
        truncation=True,
        padding=False,
    )

    model_inputs["labels"] = labels["input_ids"]
    return model_inputs


def compute_metrics(eval_pred, tokenizer):
    """Compute exact match accuracy."""
    predictions, labels = eval_pred

    # Replace invalid prediction IDs (negative or out of range) with pad token id
    vocab_size = tokenizer.vocab_size
    predictions = [
        [p if 0 <= p < vocab_size else tokenizer.pad_token_id for p in pred]
        for pred in predictions
    ]
    decoded_preds = tokenizer.batch_decode(predictions, skip_special_tokens=True)

    # Replace -100 in labels (padding) with pad token id
    labels = [[l if l != -100 else tokenizer.pad_token_id for l in label] for label in labels]
    decoded_labels = tokenizer.batch_decode(labels, skip_special_tokens=True)

    # Compute exact match
    exact_matches = sum(p.strip() == l.strip() for p, l in zip(decoded_preds, decoded_labels))
    accuracy = exact_matches / len(decoded_preds)

    return {"exact_match": accuracy}


def main():
    print(f"Loading model: {MODEL_NAME}")
    tokenizer = T5Tokenizer.from_pretrained(MODEL_NAME)
    model = T5ForConditionalGeneration.from_pretrained(MODEL_NAME)

    print(f"Model size: {sum(p.numel() for p in model.parameters()) / 1e6:.1f}M parameters")

    # Load datasets
    print("Loading datasets...")
    train_dataset = load_data("train")
    val_dataset = load_data("validation")
    test_dataset = load_data("test")

    print(f"  Train: {len(train_dataset)}")
    print(f"  Validation: {len(val_dataset)}")
    print(f"  Test: {len(test_dataset)}")

    # Preprocess
    print("Tokenizing...")
    train_dataset = train_dataset.map(
        lambda x: preprocess_function(x, tokenizer),
        batched=True,
        remove_columns=train_dataset.column_names,
    )
    val_dataset = val_dataset.map(
        lambda x: preprocess_function(x, tokenizer),
        batched=True,
        remove_columns=val_dataset.column_names,
    )

    # Data collator
    data_collator = DataCollatorForSeq2Seq(
        tokenizer=tokenizer,
        model=model,
        padding=True,
    )

    # Training arguments
    training_args = Seq2SeqTrainingArguments(
        output_dir=str(OUTPUT_DIR),
        eval_strategy="epoch",
        save_strategy="epoch",
        learning_rate=3e-4,
        per_device_train_batch_size=8,
        per_device_eval_batch_size=8,
        num_train_epochs=5,
        weight_decay=0.01,
        predict_with_generate=True,
        generation_max_length=MAX_TARGET_LENGTH,
        logging_steps=50,
        load_best_model_at_end=True,
        metric_for_best_model="exact_match",
        greater_is_better=True,
        save_total_limit=2,
        report_to="none",
    )

    # Trainer
    trainer = Seq2SeqTrainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=val_dataset,
        tokenizer=tokenizer,
        data_collator=data_collator,
        compute_metrics=lambda x: compute_metrics(x, tokenizer),
    )

    # Train
    print("\nStarting training...")
    trainer.train()

    # Save best model
    print(f"\nSaving model to {OUTPUT_DIR}")
    trainer.save_model(OUTPUT_DIR)
    tokenizer.save_pretrained(OUTPUT_DIR)

    # Final evaluation
    print("\nFinal evaluation on test set...")
    test_dataset_tokenized = test_dataset.map(
        lambda x: preprocess_function(x, tokenizer),
        batched=True,
        remove_columns=test_dataset.column_names,
    )
    results = trainer.evaluate(test_dataset_tokenized)
    print(f"Test exact match: {results['eval_exact_match']:.2%}")

    # Show some predictions
    print("\n=== Sample Predictions ===\n")
    test_data = load_data("test")
    for i in range(5):
        input_text = "format list: " + test_data[i]["input"]
        expected = test_data[i]["output"]

        inputs = tokenizer(input_text, return_tensors="pt", max_length=MAX_INPUT_LENGTH, truncation=True)
        outputs = model.generate(**inputs, max_length=MAX_TARGET_LENGTH)
        predicted = tokenizer.decode(outputs[0], skip_special_tokens=True)

        print(f"Input: {test_data[i]['input']}")
        print(f"Expected:\n{expected}")
        print(f"Predicted:\n{predicted}")
        print(f"Match: {'✓' if predicted.strip() == expected.strip() else '✗'}")
        print()


if __name__ == "__main__":
    main()
