#!/usr/bin/env python3
"""
BERT Repetition-Only Tagger Training Script

Trains on Switchboard examples where reparandum words OVERLAP with repair words.
This catches simple repetitions like "I I think" or "to to go".

Filter: If 50%+ of reparandum words appear in the following fluent text, it's a repetition.
"""

import re
import ast
import csv
import numpy as np
from pathlib import Path
from datasets import Dataset
from transformers import (
    AutoTokenizer,
    AutoModelForTokenClassification,
    TrainingArguments,
    Trainer,
    DataCollatorForTokenClassification
)
import evaluate

# ============================================================================
# Configuration
# ============================================================================

MODEL_NAME = "distilbert-base-uncased"
OUTPUT_DIR = str(Path(__file__).parent.parent / "models" / "repetition-remover")
SWITCHBOARD_PATH = "/tmp/switchboard_corrected_reannotated/switchboard_corrected_with_silver_reannotation.tsv"

NUM_EPOCHS = 3
BATCH_SIZE = 16
LEARNING_RATE = 2e-5
OVERLAP_THRESHOLD = 0.5  # 50% word overlap = repetition

# Labels for repetition removal
LABEL_LIST = ["O", "B-REP", "I-REP"]
LABEL2ID = {label: i for i, label in enumerate(LABEL_LIST)}
ID2LABEL = {i: label for i, label in enumerate(LABEL_LIST)}

# ============================================================================
# Data Loading with Repetition Filter
# ============================================================================

def is_repetition(words, tags):
    """
    Determine if this example is a repetition (vs repair).

    A repetition has high word overlap between reparandum and repair.
    Example: "I I think" - reparandum "I" appears in repair "I think"

    Returns: (is_repetition: bool, reparandum_words: list, repair_words: list)
    """
    reparandum_words = []
    repair_words = []
    seen_reparandum = False

    for w, t in zip(words, tags):
        w_lower = w.lower()
        if t in ['BE', 'IE', 'BE_IP']:
            reparandum_words.append(w_lower)
            seen_reparandum = True
        elif t in ['O', 'C'] and seen_reparandum:
            # Fluent words after reparandum
            repair_words.append(w_lower)

    if not reparandum_words:
        return False, [], []

    # Check overlap
    rep_set = set(reparandum_words)
    repair_set = set(repair_words[:len(reparandum_words) + 3])  # Check nearby words

    overlap = rep_set & repair_set
    overlap_ratio = len(overlap) / len(rep_set) if rep_set else 0

    return overlap_ratio >= OVERLAP_THRESHOLD, reparandum_words, repair_words


def convert_tag(tag):
    """Convert Switchboard tag to our label scheme."""
    if tag in ['BE', 'BE_IP']:
        return 'B-REP'
    elif tag in ['IE', 'IP', 'C_IE', 'C_IP']:
        return 'I-REP'
    else:
        return 'O'


def load_repetition_data():
    """Load Switchboard and filter for repetitions only."""
    tokens_list = []
    tags_list = []

    print(f"Loading Switchboard from {SWITCHBOARD_PATH}...")
    print(f"Filtering for repetitions (overlap >= {OVERLAP_THRESHOLD*100:.0f}%)...")

    total = 0
    kept = 0
    skipped_repair = 0
    skipped_no_disfl = 0

    with open(SWITCHBOARD_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')

        for row in reader:
            total += 1

            try:
                words = ast.literal_eval(row['sentence'])
                tags = ast.literal_eval(row['ms_disfl'])

                if len(words) != len(tags):
                    continue

                # Check if this is a repetition
                is_rep, rep_words, repair_words = is_repetition(words, tags)

                if not rep_words:
                    skipped_no_disfl += 1
                    continue

                if not is_rep:
                    skipped_repair += 1
                    continue

                # Convert to our format
                tokens = [w.lower() for w in words]
                converted_tags = [convert_tag(t) for t in tags]
                tag_ids = [LABEL2ID[t] for t in converted_tags]

                tokens_list.append(tokens)
                tags_list.append(tag_ids)
                kept += 1

                if kept % 25000 == 0:
                    print(f"  Kept {kept} repetitions...")

            except (ValueError, SyntaxError):
                continue

    print(f"\nSwitchboard filtering complete:")
    print(f"  Total examples:      {total}")
    print(f"  No disfluency:       {skipped_no_disfl}")
    print(f"  Skipped (repairs):   {skipped_repair}")
    print(f"  Kept (repetitions):  {kept}")
    print(f"  Repetition ratio:    {kept/(kept+skipped_repair)*100:.1f}%")

    return tokens_list, tags_list


def prepare_dataset():
    """Prepare the filtered dataset."""
    tokens, tags = load_repetition_data()

    dataset = Dataset.from_dict({
        "tokens": tokens,
        "ner_tags": tags
    })

    # 95/5 split
    split = dataset.train_test_split(test_size=0.05, seed=42)
    print(f"\nTrain: {len(split['train'])}, Test: {len(split['test'])}")

    return split

# ============================================================================
# Tokenization
# ============================================================================

def tokenize_and_align_labels(examples, tokenizer):
    """Tokenize and align labels for subword tokens."""
    tokenized = tokenizer(
        examples["tokens"],
        truncation=True,
        is_split_into_words=True,
        max_length=256
    )

    labels = []
    for i, label in enumerate(examples["ner_tags"]):
        word_ids = tokenized.word_ids(batch_index=i)
        previous_word_idx = None
        label_ids = []

        for word_idx in word_ids:
            if word_idx is None:
                label_ids.append(-100)
            elif word_idx != previous_word_idx:
                label_ids.append(label[word_idx])
            else:
                # Subword: use I- tag if original was B-
                orig_label = label[word_idx]
                if LABEL_LIST[orig_label] == "B-REP":
                    label_ids.append(LABEL2ID["I-REP"])
                else:
                    label_ids.append(orig_label)
            previous_word_idx = word_idx

        labels.append(label_ids)

    tokenized["labels"] = labels
    return tokenized

# ============================================================================
# Metrics
# ============================================================================

def compute_metrics(eval_pred, seqeval):
    """Compute precision, recall, F1."""
    predictions, labels = eval_pred
    predictions = np.argmax(predictions, axis=2)

    true_predictions = []
    true_labels = []

    for prediction, label in zip(predictions, labels):
        true_pred = []
        true_lab = []
        for p, l in zip(prediction, label):
            if l != -100:
                true_pred.append(LABEL_LIST[p])
                true_lab.append(LABEL_LIST[l])
        true_predictions.append(true_pred)
        true_labels.append(true_lab)

    results = seqeval.compute(predictions=true_predictions, references=true_labels)

    return {
        "precision": results["overall_precision"],
        "recall": results["overall_recall"],
        "f1": results["overall_f1"],
        "accuracy": results["overall_accuracy"],
    }

# ============================================================================
# Main Training
# ============================================================================

def main():
    print("=" * 60)
    print("REPETITION-ONLY MODEL TRAINING")
    print("=" * 60)

    # Prepare data
    dataset = prepare_dataset()

    # Load tokenizer and model
    print(f"\nLoading {MODEL_NAME}...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    model = AutoModelForTokenClassification.from_pretrained(
        MODEL_NAME,
        num_labels=len(LABEL_LIST),
        id2label=ID2LABEL,
        label2id=LABEL2ID
    )

    # Tokenize
    print("Tokenizing...")
    tokenized_train = dataset["train"].map(
        lambda x: tokenize_and_align_labels(x, tokenizer),
        batched=True,
        remove_columns=dataset["train"].column_names
    )
    tokenized_test = dataset["test"].map(
        lambda x: tokenize_and_align_labels(x, tokenizer),
        batched=True,
        remove_columns=dataset["test"].column_names
    )

    # Training setup
    data_collator = DataCollatorForTokenClassification(tokenizer)
    seqeval = evaluate.load("seqeval")

    training_args = TrainingArguments(
        output_dir=OUTPUT_DIR,
        learning_rate=LEARNING_RATE,
        per_device_train_batch_size=BATCH_SIZE,
        per_device_eval_batch_size=BATCH_SIZE,
        num_train_epochs=NUM_EPOCHS,
        weight_decay=0.01,
        eval_strategy="epoch",
        save_strategy="epoch",
        load_best_model_at_end=True,
        metric_for_best_model="f1",
        logging_steps=500,
        report_to="none",
    )

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=tokenized_train,
        eval_dataset=tokenized_test,
        tokenizer=tokenizer,
        data_collator=data_collator,
        compute_metrics=lambda p: compute_metrics(p, seqeval),
    )

    # Train
    print("\n" + "=" * 60)
    print("STARTING TRAINING")
    print(f"Epochs: {NUM_EPOCHS}, Batch Size: {BATCH_SIZE}, LR: {LEARNING_RATE}")
    print("=" * 60 + "\n")

    trainer.train()

    # Evaluate
    print("\n" + "=" * 60)
    print("FINAL EVALUATION")
    print("=" * 60)

    results = trainer.evaluate()
    for key, value in results.items():
        print(f"  {key}: {value:.4f}" if isinstance(value, float) else f"  {key}: {value}")

    # Save
    trainer.save_model(OUTPUT_DIR)
    tokenizer.save_pretrained(OUTPUT_DIR)
    print(f"\nModel saved to {OUTPUT_DIR}")

    return results


if __name__ == "__main__":
    main()
