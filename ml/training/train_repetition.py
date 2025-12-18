#!/usr/bin/env python3
"""
BERT Disfluency Tagger Training Script - Combined Dataset Version

Trains a DistilBERT model on DisfluencySpeech + Switchboard datasets to tag words for removal.
Tags: O (keep), B-REP/I-REP (repair/reparandum - remove)
"""

import re
import ast
import csv
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
OUTPUT_DIR = "/tmp/disfluency-tagger-combined"
NUM_EPOCHS = 3
BATCH_SIZE = 16
LEARNING_RATE = 2e-5

# Simplified labels - just O (keep) and REP (remove)
LABEL_LIST = ["O", "B-REP", "I-REP"]
LABEL2ID = {label: i for i, label in enumerate(LABEL_LIST)}
ID2LABEL = {i: label for i, label in enumerate(LABEL_LIST)}

# ============================================================================
# DisfluencySpeech Parsing (existing logic)
# ============================================================================

def parse_disfluency_speech_transcript(annotated):
    """Parse DisfluencySpeech annotated transcript into tokens and BIO tags."""
    tokens = []
    tags = []

    # Remove non-speech markers like <laughter>
    text = re.sub(r'<[^>]+>', '', annotated)

    i = 0
    while i < len(text):
        # Check for filler {F ... } - REMOVE
        filler_match = re.match(r'\{F\s+([^}]+)\}', text[i:])
        if filler_match:
            content = filler_match.group(1).strip()
            words = content.replace(',', '').split()
            for j, word in enumerate(words):
                if word:
                    tokens.append(word.lower())
                    tags.append('B-REP' if j == 0 else 'I-REP')
            i += filler_match.end()
            continue

        # Check for discourse marker {D ... } - REMOVE
        disc_match = re.match(r'\{D\s+([^}]+)\}', text[i:])
        if disc_match:
            content = disc_match.group(1).strip()
            words = content.replace(',', '').split()
            for j, word in enumerate(words):
                if word:
                    tokens.append(word.lower())
                    tags.append('B-REP' if j == 0 else 'I-REP')
            i += disc_match.end()
            continue

        # Check for conjunction {C ... } - KEEP these
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

        # Check for repair [ ... + ... ] - before part REMOVED, after part KEPT
        repair_match = re.match(r'\[\s*([^+\]]*)\+\s*([^\]]*)\]', text[i:])
        if repair_match:
            before = repair_match.group(1).strip()
            after = repair_match.group(2).strip()

            before_words = before.replace(',', '').split()
            for j, word in enumerate(before_words):
                if word and not word.startswith('-'):
                    tokens.append(word.lower())
                    tags.append('B-REP' if j == 0 else 'I-REP')

            after_words = after.replace(',', '').split()
            for word in after_words:
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
# Switchboard Parsing
# ============================================================================

def convert_switchboard_tag(tag):
    """Convert Switchboard BIO tag to our simplified scheme.

    Switchboard tags:
    - BE, IE, IP, BE_IP, C_IE, C_IP = reparandum (REMOVE)
    - O, C = keep
    """
    if tag in ['BE', 'BE_IP']:
        return 'B-REP'
    elif tag in ['IE', 'IP', 'C_IE', 'C_IP']:
        return 'I-REP'
    else:  # 'O' or 'C'
        return 'O'

def load_switchboard_data(filepath):
    """Load and parse Switchboard TSV file."""
    tokens_list = []
    tags_list = []

    print(f"Loading Switchboard from {filepath}...")

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')

        count = 0
        skipped = 0

        for row in reader:
            try:
                # Parse the sentence (stored as Python list string)
                sentence = ast.literal_eval(row['sentence'])
                # Parse the disfluency tags
                ms_disfl = ast.literal_eval(row['ms_disfl'])

                if len(sentence) != len(ms_disfl):
                    skipped += 1
                    continue

                # Convert to lowercase and our tag scheme
                tokens = [w.lower() for w in sentence]
                tags = [convert_switchboard_tag(t) for t in ms_disfl]

                # Convert label strings to IDs
                tag_ids = [LABEL2ID[t] for t in tags]

                tokens_list.append(tokens)
                tags_list.append(tag_ids)
                count += 1

                if count % 50000 == 0:
                    print(f"  Processed {count} examples...")

            except (ValueError, SyntaxError) as e:
                skipped += 1
                continue

    print(f"Loaded {count} Switchboard examples (skipped {skipped})")
    return tokens_list, tags_list

# ============================================================================
# Data Loading and Preparation
# ============================================================================

def load_disfluency_speech():
    """Load DisfluencySpeech and convert to token classification format."""
    print("Loading DisfluencySpeech dataset...")
    ds = load_dataset("amaai-lab/DisfluencySpeech", split="train")
    ds_text = ds.remove_columns(['audio'])

    print(f"Processing {len(ds_text)} DisfluencySpeech examples...")

    all_tokens = []
    all_tags = []

    for i, example in enumerate(ds_text):
        tokens, tags = parse_disfluency_speech_transcript(example['transcript_annotated'])
        if tokens:
            # Convert to IDs
            tag_ids = [LABEL2ID[t] for t in tags]
            all_tokens.append(tokens)
            all_tags.append(tag_ids)

        if (i + 1) % 1000 == 0:
            print(f"  Processed {i + 1}/{len(ds_text)}...")

    print(f"Loaded {len(all_tokens)} DisfluencySpeech examples")
    return all_tokens, all_tags

def prepare_combined_dataset():
    """Load both datasets and combine them."""
    # Load DisfluencySpeech
    ds_tokens, ds_tags = load_disfluency_speech()

    # Load Switchboard
    swbd_tokens, swbd_tags = load_switchboard_data(
        "/tmp/switchboard_corrected_reannotated/switchboard_corrected_with_silver_reannotation.tsv"
    )

    # Combine
    all_tokens = ds_tokens + swbd_tokens
    all_tags = ds_tags + swbd_tags

    print(f"\nCombined dataset: {len(all_tokens)} total examples")
    print(f"  - DisfluencySpeech: {len(ds_tokens)}")
    print(f"  - Switchboard: {len(swbd_tokens)}")

    # Create dataset
    dataset = Dataset.from_dict({
        "tokens": all_tokens,
        "ner_tags": all_tags
    })

    # Split into train/test (95/5 - we have lots of data now)
    split = dataset.train_test_split(test_size=0.05, seed=42)

    print(f"Train: {len(split['train'])}, Test: {len(split['test'])}")

    return split

# ============================================================================
# Tokenization with Label Alignment
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
                label_ids.append(-100)  # Special tokens
            elif word_idx != previous_word_idx:
                label_ids.append(label[word_idx])
            else:
                # For subword tokens, use I- tag if original was B-
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
    print("="*60)
    print("BERT DISFLUENCY TAGGER TRAINING - COMBINED DATASET")
    print("="*60)

    # Prepare data
    dataset = prepare_combined_dataset()

    # Load tokenizer and model
    print(f"\nLoading {MODEL_NAME}...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    model = AutoModelForTokenClassification.from_pretrained(
        MODEL_NAME,
        num_labels=len(LABEL_LIST),
        id2label=ID2LABEL,
        label2id=LABEL2ID
    )

    # Tokenize datasets
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
        logging_steps=500,
        report_to="none",  # Disable wandb
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

    # Train!
    print("\n" + "="*60)
    print("STARTING TRAINING")
    print(f"Epochs: {NUM_EPOCHS}, Batch Size: {BATCH_SIZE}, LR: {LEARNING_RATE}")
    print("="*60 + "\n")

    trainer.train()

    # Final evaluation
    print("\n" + "="*60)
    print("FINAL EVALUATION")
    print("="*60)

    results = trainer.evaluate()
    for key, value in results.items():
        print(f"  {key}: {value:.4f}" if isinstance(value, float) else f"  {key}: {value}")

    # Save model
    trainer.save_model(OUTPUT_DIR)
    tokenizer.save_pretrained(OUTPUT_DIR)
    print(f"\nModel saved to {OUTPUT_DIR}")

    return results

if __name__ == "__main__":
    main()
