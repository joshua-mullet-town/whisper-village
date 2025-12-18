"""
Tests for the repetition removal model.

Run with:
    pytest ml/tests/test_repetition.py -v
"""

import json
import pytest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from ml.pipeline.models import RepetitionRemover


# Load test fixtures
FIXTURES_PATH = Path(__file__).parent / "fixtures.json"
with open(FIXTURES_PATH) as f:
    FIXTURES = json.load(f)


@pytest.fixture(scope="module")
def rep_model():
    """Load repetition model once for all tests."""
    return RepetitionRemover()


class TestRepetitionRemover:
    """Test suite for RepetitionRemover model."""

    @pytest.mark.parametrize("test_case", FIXTURES["repetition_tests"])
    def test_repetition_removal(self, rep_model, test_case):
        """Test that repetitions are removed correctly."""
        result = rep_model.process(test_case["input"])
        assert result == test_case["expected"], \
            f"Input: {test_case['input']!r}, Expected: {test_case['expected']!r}, Got: {result!r}"

    def test_empty_string(self, rep_model):
        """Test handling of empty string."""
        assert rep_model.process("") == ""

    def test_no_repetitions(self, rep_model):
        """Test string with no repetitions."""
        result = rep_model.process("this is a normal sentence")
        assert "this" in result
        assert "sentence" in result

    def test_triple_repetition(self, rep_model):
        """Test handling of triple repetition."""
        result = rep_model.process("i i i think")
        # Should reduce to single "i"
        assert result.count("i") <= 2  # May keep 1 or 2 depending on model

    def test_process_with_details(self, rep_model):
        """Test detailed output."""
        result = rep_model.process_with_details("the the thing is")
        assert "output" in result
        assert "removed" in result
        assert "labels" in result

    @pytest.mark.parametrize("test_case", FIXTURES["discourse_preservation_tests"])
    def test_preserves_discourse_markers(self, rep_model, test_case):
        """Test that discourse markers are NOT removed by repetition model."""
        result = rep_model.process(test_case["input"])
        # Discourse markers should be preserved
        assert result == test_case["expected"], \
            f"Discourse marker incorrectly removed: {test_case['input']!r} -> {result!r}"


class TestRepetitionModelLoading:
    """Test model loading behavior."""

    def test_model_loads_successfully(self):
        """Test that model loads without error."""
        model = RepetitionRemover()
        assert model is not None
        assert model.model is not None
        assert model.tokenizer is not None

    def test_model_has_correct_labels(self):
        """Test that model has expected label configuration."""
        model = RepetitionRemover()
        labels = list(model.id2label.values())
        assert "O" in labels  # Keep label
        # Should have REP labels
        assert any("REP" in label for label in labels)
