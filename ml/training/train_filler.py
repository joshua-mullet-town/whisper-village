#!/usr/bin/env python3
"""
FILLER REMOVER MODEL - Google Colab Version
Copy this entire script into a Colab notebook cell and run it.

Trains a DistilBERT model to remove fillers ("uh", "um", "er", etc.)
Uses only {F ...} tags from DisfluencySpeech dataset.
"""

# ============================================================================
# STEP 1: Install dependencies (run this cell first in Colab)
# ============================================================================
# !pip install transformers datasets evaluate seqeval accelerate -q

import re
import numpy as np
from datasets import load_dataset, Dataset
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
OUTPUT_DIR = "./filler-remover-model"
NUM_EPOCHS = 3
BATCH_SIZE = 16
LEARNING_RATE = 2e-5

# Simple labels: O (keep) or FILL (remove)
LABEL_LIST = ["O", "B-FILL", "I-FILL"]
LABEL2ID = {label: i for i, label in enumerate(LABEL_LIST)}
ID2LABEL = {i: label for i, label in enumerate(LABEL_LIST)}

# ============================================================================
# Parse DisfluencySpeech - FILLERS ONLY
# ============================================================================

def parse_fillers_only(annotated):
    """Parse annotated transcript - only extract fillers, ignore everything else."""
    tokens = []
    tags = []

    # Remove non-speech markers like <laughter>
    text = re.sub(r'<[^>]+>', '', annotated)

    i = 0
    while i < len(text):
        # Check for filler {F ... } - REMOVE THESE
        filler_match = re.match(r'\{F\s+([^}]+)\}', text[i:])
        if filler_match:
            content = filler_match.group(1).strip()
            words = content.replace(',', '').split()
            for j, word in enumerate(words):
                if word:
                    tokens.append(word.lower())
                    tags.append('B-FILL' if j == 0 else 'I-FILL')
            i += filler_match.end()
            continue

        # Check for discourse marker {D ... } - KEEP (not removing discourse)
        disc_match = re.match(r'\{D\s+([^}]+)\}', text[i:])
        if disc_match:
            content = disc_match.group(1).strip()
            words = content.replace(',', '').split()
            for word in words:
                if word:
                    tokens.append(word.lower())
                    tags.append('O')  # Keep discourse markers
            i += disc_match.end()
            continue

        # Check for conjunction {C ... } - KEEP
        conj_match = re.match(r'\{C\s+([^}]+)\}', text[i:])
        if conj_match:
            content = conj_match.group(1).strip()
            words = content.replace(',', '').split()
            for word in words:
                if word:
                    tokens.append(word.lower())
                    tags.append('O')
            i += conj_match.end()
            continue

        # Check for repair [ ... + ... ] - KEEP ALL (not handling repairs here)
        repair_match = re.match(r'\[\s*([^+\]]*)\+\s*([^\]]*)\]', text[i:])
        if repair_match:
            before = repair_match.group(1).strip()
            after = repair_match.group(2).strip()

            # Keep both parts for this model (repairs handled separately)
            for part in [before, after]:
                words = part.replace(',', '').split()
                for word in words:
                    if word and not word.startswith('-'):
                        tokens.append(word.lower())
                        tags.append('O')

            i += repair_match.end()
            continue

        # Regular word - KEEP
        word_match = re.match(r"[\w']+", text[i:])
        if word_match:
            word = word_match.group(0)
            tokens.append(word.lower())
            tags.append('O')
            i += word_match.end()
            continue

        i += 1

    return tokens, tags

# ============================================================================
# Data Loading
# ============================================================================

def prepare_dataset():
    """Load DisfluencySpeech and convert to filler-only classification."""
    print("Loading DisfluencySpeech dataset...")
    ds = load_dataset("amaai-lab/DisfluencySpeech", split="train")
    ds_text = ds.remove_columns(['audio'])

    print(f"Processing {len(ds_text)} examples...")

    all_tokens = []
    all_tags = []
    filler_count = 0

    for i, example in enumerate(ds_text):
        tokens, tags = parse_fillers_only(example['transcript_annotated'])
        if tokens:
            tag_ids = [LABEL2ID[t] for t in tags]
            all_tokens.append(tokens)
            all_tags.append(tag_ids)

            # Count fillers
            filler_count += sum(1 for t in tags if t != 'O')

        if (i + 1) % 1000 == 0:
            print(f"  Processed {i + 1}/{len(ds_text)}...")

    print(f"\nDataset stats:")
    print(f"  Total examples: {len(all_tokens)}")
    print(f"  Total filler words: {filler_count}")

    # Create dataset
    dataset = Dataset.from_dict({
        "tokens": all_tokens,
        "ner_tags": all_tags
    })

    # Split into train/test
    split = dataset.train_test_split(test_size=0.1, seed=42)
    print(f"  Train: {len(split['train'])}, Test: {len(split['test'])}")

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
                orig_label = label[word_idx]
                if LABEL_LIST[orig_label] == "B-FILL":
                    label_ids.append(LABEL2ID["I-FILL"])
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
    print("FILLER REMOVER MODEL TRAINING")
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

    # Data collator
    data_collator = DataCollatorForTokenClassification(tokenizer)

    # Evaluation metric
    seqeval = evaluate.load("seqeval")

    # Training arguments
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
        logging_steps=50,
        report_to="none",
    )

    # Trainer
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
    print("=" * 60 + "\n")

    trainer.train()

    # Final evaluation
    print("\n" + "=" * 60)
    print("FINAL EVALUATION")
    print("=" * 60)

    results = trainer.evaluate()
    for key, value in results.items():
        print(f"  {key}: {value:.4f}" if isinstance(value, float) else f"  {key}: {value}")

    # Save model
    trainer.save_model(OUTPUT_DIR)
    tokenizer.save_pretrained(OUTPUT_DIR)
    print(f"\nModel saved to {OUTPUT_DIR}")

    # Test it
    print("\n" + "=" * 60)
    print("TESTING THE MODEL")
    print("=" * 60)

    test_sentences = [
        "i uh think um we should go",
        "so uh you know it's like really good",
        "um i was wondering uh if you could help",
    ]

    import torch
    model.eval()

    for sentence in test_sentences:
        words = sentence.split()
        inputs = tokenizer(words, is_split_into_words=True, return_tensors="pt")

        with torch.no_grad():
            outputs = model(**inputs)

        predictions = torch.argmax(outputs.logits, dim=2)[0]
        word_ids = inputs.word_ids()

        word_labels = {}
        for idx, word_idx in enumerate(word_ids):
            if word_idx is not None and word_idx not in word_labels:
                word_labels[word_idx] = ID2LABEL[predictions[idx].item()]

        keep = [w for i, w in enumerate(words) if word_labels.get(i, "O") == "O"]
        remove = [w for i, w in enumerate(words) if word_labels.get(i, "O") != "O"]

        print(f"\nInput:  {sentence}")
        print(f"Remove: {' '.join(remove) if remove else '(none)'}")
        print(f"Output: {' '.join(keep)}")

    return results

if __name__ == "__main__":
    main()
