"""
Individual model classes for transcript cleanup.

Each model class handles:
- Loading the trained model from disk
- Running inference on text
- Returning cleaned text

To add a new model:
1. Create a new class inheriting from BaseModel
2. Set MODEL_DIR to the model's directory name in ml/models/
3. Implement any custom label handling if needed
"""

import os
from pathlib import Path
from typing import Optional
import torch
from transformers import AutoTokenizer, AutoModelForTokenClassification, T5Tokenizer, T5ForConditionalGeneration


# Base path for all models
MODELS_BASE_PATH = Path(__file__).parent.parent / "models"


class BaseModel:
    """Base class for all cleanup models."""

    MODEL_DIR: str = ""  # Override in subclass

    def __init__(self, model_path: Optional[str] = None):
        """
        Initialize the model.

        Args:
            model_path: Optional custom path. If None, uses default in ml/models/
        """
        if model_path:
            self.model_path = Path(model_path)
        else:
            self.model_path = MODELS_BASE_PATH / self.MODEL_DIR

        if not self.model_path.exists():
            raise FileNotFoundError(
                f"Model not found at {self.model_path}. "
                f"Run training script or download the model first."
            )

        self.tokenizer = AutoTokenizer.from_pretrained(str(self.model_path))
        self.model = AutoModelForTokenClassification.from_pretrained(str(self.model_path))
        self.model.eval()

        self.id2label = self.model.config.id2label

    def _get_word_labels(self, words: list[str]) -> dict[int, str]:
        """Run inference and get label for each word."""
        inputs = self.tokenizer(words, is_split_into_words=True, return_tensors="pt")

        with torch.no_grad():
            outputs = self.model(**inputs)

        predictions = torch.argmax(outputs.logits, dim=2)[0]
        word_ids = inputs.word_ids()

        word_labels = {}
        for idx, word_idx in enumerate(word_ids):
            if word_idx is not None and word_idx not in word_labels:
                word_labels[word_idx] = self.id2label[predictions[idx].item()]

        return word_labels

    def process(self, text: str) -> str:
        """
        Process text and return cleaned version.

        Args:
            text: Input text to clean

        Returns:
            Cleaned text with marked words removed
        """
        if not text.strip():
            return text

        words = text.split()
        word_labels = self._get_word_labels(words)

        # Keep words labeled as "O" (not marked for removal)
        kept_words = [
            word for i, word in enumerate(words)
            if word_labels.get(i, "O") == "O"
        ]

        return ' '.join(kept_words)

    def process_with_details(self, text: str) -> dict:
        """
        Process text and return detailed results.

        Args:
            text: Input text to clean

        Returns:
            Dict with 'output', 'removed', and 'labels' keys
        """
        if not text.strip():
            return {'output': text, 'removed': [], 'labels': {}}

        words = text.split()
        word_labels = self._get_word_labels(words)

        kept = []
        removed = []

        for i, word in enumerate(words):
            label = word_labels.get(i, "O")
            if label == "O":
                kept.append(word)
            else:
                removed.append(word)

        return {
            'output': ' '.join(kept),
            'removed': removed,
            'labels': {words[i]: word_labels.get(i, "O") for i in range(len(words))}
        }


class FillerRemover(BaseModel):
    """
    Removes filler words: "uh", "um", "er", etc.

    Trained on DisfluencySpeech dataset {F} tags.
    F1 Score: 99.7%

    Example:
        remover = FillerRemover()
        clean = remover.process("i uh think um we should go")
        # Returns: "i think we should go"
    """

    MODEL_DIR = "filler-remover"


class RepetitionRemover(BaseModel):
    """
    Removes simple word repetitions: "I I" -> "I", "the the" -> "the"

    Trained on Switchboard repetition subset (reparandum overlaps with repair).

    Example:
        remover = RepetitionRemover()
        clean = remover.process("i i really want to to go")
        # Returns: "i really want to go"
    """

    MODEL_DIR = "repetition-remover"


class RepairRemover(BaseModel):
    """
    Removes self-corrections/repairs: "the store no the mall" -> "the mall"

    Trained on Switchboard repair subset (reparandum replaced by different words).
    This is the harder task - requires understanding which part was "wrong".

    Note: Uses B-REPAIR/I-REPAIR labels (different from repetition's B-REP/I-REP)

    Example:
        remover = RepairRemover()
        clean = remover.process("we were i was fortunate")
        # Returns: "i was fortunate"
    """

    MODEL_DIR = "repair-remover"

    def process(self, text: str) -> str:
        """
        Process text and return cleaned version.

        Overrides base to handle REPAIR labels (not just O).
        """
        if not text.strip():
            return text

        words = text.split()
        word_labels = self._get_word_labels(words)

        # Keep words labeled as "O" (not REPAIR)
        kept_words = [
            word for i, word in enumerate(words)
            if not self._should_remove(word_labels.get(i, "O"))
        ]

        return ' '.join(kept_words)

    def _should_remove(self, label: str) -> bool:
        """Check if label indicates word should be removed."""
        return "REPAIR" in label


class ListFormatter:
    """
    Formats spoken list indicators into bullet points.

    Detects patterns like "one X two Y" or "first X second Y" and
    converts them to formatted bullet lists.

    Uses T5-small (seq2seq) rather than BERT (token classification).

    Example:
        formatter = ListFormatter()
        formatted = formatter.process("my goals are one finish report two send email")
        # Returns: "my goals are\n- Finish report\n- Send email"
    """

    MODEL_DIR = "list-formatter"

    def __init__(self, model_path: Optional[str] = None):
        """
        Initialize the model.

        Args:
            model_path: Optional custom path. If None, uses default in ml/models/
        """
        if model_path:
            self.model_path = Path(model_path)
        else:
            self.model_path = MODELS_BASE_PATH / self.MODEL_DIR

        if not self.model_path.exists():
            raise FileNotFoundError(
                f"Model not found at {self.model_path}. "
                f"Run ml/training/train_list_formatter.py first."
            )

        self.tokenizer = T5Tokenizer.from_pretrained(str(self.model_path), legacy=True)
        self.model = T5ForConditionalGeneration.from_pretrained(str(self.model_path))
        self.model.eval()

    def process(self, text: str) -> str:
        """
        Process text and format any detected lists.

        Args:
            text: Input text that may contain list indicators

        Returns:
            Text with lists formatted as bullet points
        """
        if not text.strip():
            return text

        # Add T5 task prefix
        input_text = "format list: " + text

        inputs = self.tokenizer(
            input_text,
            return_tensors="pt",
            max_length=256,
            truncation=True
        )

        with torch.no_grad():
            outputs = self.model.generate(**inputs, max_length=512)

        result = self.tokenizer.decode(outputs[0], skip_special_tokens=True)

        # Post-process: fix newlines (model outputs "- X - Y" instead of "- X\n- Y")
        result = self._fix_newlines(result)

        return result

    def _fix_newlines(self, text: str) -> str:
        """Add newlines before bullet points."""
        # Pattern: space-dash-space between items should be newline-dash-space
        import re
        # Match " - " that's followed by a capital letter (list item) but not at start
        result = re.sub(r'(?<!^)(\s-\s)(?=[A-Z])', r'\n- ', text)
        return result


class Truecaser:
    """
    Restores proper capitalization using statistical model.

    Uses the 'truecase' library which is trained on NLTK English corpus.
    Handles:
    - Sentence-initial capitals
    - Proper nouns (John, New York, McDonald's)
    - "I" capitalization

    Note: Runs FIRST in pipeline (before disfluency removal) because
    the statistical model needs proper context to make decisions.

    Example:
        tc = Truecaser()
        fixed = tc.process("hey how are you i went to new york")
        # Returns: "Hey how are you I went to New York"
    """

    def __init__(self):
        """Initialize the truecaser (no model path needed - uses library)."""
        import truecase
        self._truecase = truecase

    def process(self, text: str) -> str:
        """Apply truecasing to text."""
        if not text.strip():
            return text

        try:
            return self._truecase.get_true_case(text)
        except Exception as e:
            # If truecasing fails, return original
            print(f"[Truecaser] Error: {e}")
            return text


# Registry of available models (for easy iteration)
AVAILABLE_MODELS = {
    'filler': FillerRemover,
    'repetition': RepetitionRemover,
    'repair': RepairRemover,
    'list': ListFormatter,
    'truecase': Truecaser,
}


def get_model(name: str) -> BaseModel:
    """
    Get a model instance by name.

    Args:
        name: Model name ('filler', 'repetition')

    Returns:
        Instantiated model

    Raises:
        ValueError: If model name not found
    """
    if name not in AVAILABLE_MODELS:
        raise ValueError(
            f"Unknown model: {name}. "
            f"Available: {list(AVAILABLE_MODELS.keys())}"
        )
    return AVAILABLE_MODELS[name]()
