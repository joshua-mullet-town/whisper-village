"""
Generate synthetic training data for list formatting model.

The task: detect when user says "one X two Y" or "first X second Y" and format as bullet points.

Example:
  Input:  "My top goals this week are one finish the report two send the presentation"
  Output: "My top goals this week are\n- Finish the report\n- Send the presentation"
"""

import json
import random
from pathlib import Path

# Number words for lists
NUMBERS = ["one", "two", "three", "four", "five"]
ORDINALS = ["first", "second", "third", "fourth", "fifth"]

# Intro phrases that come before the list
INTRO_PHRASES = [
    "I need to",
    "my goals are",
    "things to do",
    "my tasks are",
    "I want to",
    "I have to",
    "the plan is",
    "for today",
    "this week I need to",
    "on my list",
    "I should",
    "reminder to",
    "don't forget to",
    "make sure to",
    "priorities are",
    "the agenda is",
    "items to cover",
    "topics to discuss",
    "questions to ask",
    "steps to take",
    "things to buy",
    "things to pack",
    "groceries",
    "shopping list",
    "packing list",
    "to do list",
    "action items",
    "next steps",
    "follow ups",
    "notes",
]

# List item templates - things people commonly list
TASK_TEMPLATES = [
    "finish the {noun}",
    "send the {noun}",
    "review the {noun}",
    "update the {noun}",
    "check the {noun}",
    "complete the {noun}",
    "submit the {noun}",
    "prepare the {noun}",
    "schedule the {noun}",
    "cancel the {noun}",
    "confirm the {noun}",
    "organize the {noun}",
    "clean the {noun}",
    "fix the {noun}",
    "buy {noun}",
    "get {noun}",
    "pick up {noun}",
    "return {noun}",
    "call {person}",
    "email {person}",
    "text {person}",
    "meet with {person}",
    "talk to {person}",
    "ask {person} about the {noun}",
    "follow up with {person}",
    "schedule a call with {person}",
    "{verb} the {noun}",
    "{verb} {noun}",
]

NOUNS = [
    "report", "presentation", "document", "email", "meeting", "project",
    "proposal", "budget", "schedule", "plan", "review", "analysis",
    "spreadsheet", "slides", "draft", "invoice", "contract", "agreement",
    "groceries", "milk", "bread", "eggs", "coffee", "batteries",
    "charger", "passport", "headphones", "laptop", "keys", "wallet",
    "tickets", "reservation", "appointment", "deadline", "paperwork",
    "laundry", "dishes", "garbage", "car", "house", "yard",
    "prescription", "package", "mail", "dry cleaning", "lunch",
]

PERSONS = [
    "mom", "dad", "john", "sarah", "mike", "the team", "the client",
    "my boss", "hr", "accounting", "the doctor", "the dentist",
    "the landlord", "customer service", "tech support", "the bank",
]

VERBS = [
    "finish", "start", "review", "update", "check", "verify",
    "write", "read", "edit", "proofread", "approve", "reject",
    "schedule", "cancel", "reschedule", "confirm", "book",
]

# Optional filler words to inject for realism
FILLERS = ["um", "uh", "like", "you know"]


def generate_list_item():
    """Generate a random list item."""
    template = random.choice(TASK_TEMPLATES)
    item = template.format(
        noun=random.choice(NOUNS),
        person=random.choice(PERSONS),
        verb=random.choice(VERBS),
    )
    return item


def generate_example(use_ordinals=False, num_items=None, add_fillers=False, include_intro=True):
    """Generate a single training example."""
    if num_items is None:
        num_items = random.randint(2, 5)

    numbers = ORDINALS if use_ordinals else NUMBERS

    # Generate list items
    items = [generate_list_item() for _ in range(num_items)]

    # Build input text
    input_parts = []

    # Optional intro
    if include_intro and random.random() > 0.2:
        intro = random.choice(INTRO_PHRASES)
        input_parts.append(intro)

    # Add numbered items
    for i, item in enumerate(items):
        # Maybe add filler before number
        if add_fillers and random.random() > 0.7:
            input_parts.append(random.choice(FILLERS))

        input_parts.append(numbers[i])
        input_parts.append(item)

    input_text = " ".join(input_parts)

    # Build output text
    output_parts = []

    # Keep intro if present
    if include_intro and input_parts and input_parts[0] in INTRO_PHRASES:
        output_parts.append(input_parts[0])

    # Add bullet points
    for item in items:
        # Capitalize first letter
        formatted_item = item[0].upper() + item[1:] if item else item
        output_parts.append(f"- {formatted_item}")

    if output_parts and output_parts[0] not in [f"- {item[0].upper() + item[1:]}" for item in items]:
        # Has intro
        output_text = output_parts[0] + "\n" + "\n".join(output_parts[1:])
    else:
        output_text = "\n".join(output_parts)

    return {
        "input": input_text,
        "output": output_text,
        "num_items": num_items,
        "style": "ordinal" if use_ordinals else "number",
    }


def generate_negative_example():
    """Generate an example WITHOUT list indicators (should pass through unchanged)."""
    # Regular sentence without numbers
    templates = [
        "I think we should {verb} the {noun} tomorrow",
        "the {noun} looks good to me",
        "can you {verb} the {noun} when you get a chance",
        "I spoke with {person} about the {noun}",
        "the meeting with {person} went well",
        "I'm working on the {noun} right now",
        "let me know when the {noun} is ready",
    ]

    template = random.choice(templates)
    text = template.format(
        noun=random.choice(NOUNS),
        person=random.choice(PERSONS),
        verb=random.choice(VERBS),
    )

    return {
        "input": text,
        "output": text,  # No change
        "num_items": 0,
        "style": "none",
    }


def generate_dataset(n_examples=1500, negative_ratio=0.15):
    """Generate full dataset with positive and negative examples."""
    examples = []

    n_negative = int(n_examples * negative_ratio)
    n_positive = n_examples - n_negative

    # Generate positive examples with variety
    for i in range(n_positive):
        use_ordinals = random.random() > 0.5
        add_fillers = random.random() > 0.7  # 30% have fillers
        include_intro = random.random() > 0.2  # 80% have intro

        example = generate_example(
            use_ordinals=use_ordinals,
            add_fillers=add_fillers,
            include_intro=include_intro,
        )
        examples.append(example)

    # Generate negative examples (no list formatting needed)
    for i in range(n_negative):
        examples.append(generate_negative_example())

    # Shuffle
    random.shuffle(examples)

    return examples


def split_dataset(examples, train_ratio=0.8, val_ratio=0.1):
    """Split into train/val/test sets."""
    n = len(examples)
    n_train = int(n * train_ratio)
    n_val = int(n * val_ratio)

    return {
        "train": examples[:n_train],
        "validation": examples[n_train:n_train + n_val],
        "test": examples[n_train + n_val:],
    }


def main():
    random.seed(42)

    print("Generating synthetic list formatting dataset...")

    # Generate examples
    examples = generate_dataset(n_examples=1500)

    print(f"Generated {len(examples)} total examples")

    # Split
    splits = split_dataset(examples)

    print(f"  Train: {len(splits['train'])}")
    print(f"  Validation: {len(splits['validation'])}")
    print(f"  Test: {len(splits['test'])}")

    # Save
    output_dir = Path(__file__).parent.parent / "data" / "list-formatting"
    output_dir.mkdir(parents=True, exist_ok=True)

    for split_name, split_data in splits.items():
        output_path = output_dir / f"{split_name}.json"
        with open(output_path, "w") as f:
            json.dump(split_data, f, indent=2)
        print(f"Saved {output_path}")

    # Show some examples
    print("\n=== Sample Examples ===\n")
    for i, ex in enumerate(examples[:5]):
        print(f"Example {i+1} ({ex['style']}, {ex['num_items']} items):")
        print(f"  Input:  {ex['input']}")
        print(f"  Output: {ex['output']}")
        print()


if __name__ == "__main__":
    main()
