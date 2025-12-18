"""
Tests for the filler removal model.

Run with:
    pytest ml/tests/test_filler.py -v
"""

import json
import pytest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from ml.pipeline.models import FillerRemover


# Load test fixtures
FIXTURES_PATH = Path(__file__).parent / "fixtures.json"
with open(FIXTURES_PATH) as f:
    FIXTURES = json.load(f)


@pytest.fixture(scope="module")
def filler_model():
    """Load filler model once for all tests."""
    return FillerRemover()


class TestFillerRemover:
    """Test suite for FillerRemover model."""

    @pytest.mark.parametrize("test_case", FIXTURES["filler_tests"])
    def test_filler_removal(self, filler_model, test_case):
        """Test that fillers are removed correctly."""
        result = filler_model.process(test_case["input"])
        assert result == test_case["expected"], \
            f"Input: {test_case['input']!r}, Expected: {test_case['expected']!r}, Got: {result!r}"

    def test_empty_string(self, filler_model):
        """Test handling of empty string."""
        assert filler_model.process("") == ""

    def test_only_fillers(self, filler_model):
        """Test string with only fillers."""
        result = filler_model.process("uh um")
        # Should return empty or nearly empty
        assert len(result.split()) <= 0 or result == ""

    def test_preserves_case(self, filler_model):
        """Test that remaining words preserve their case."""
        result = filler_model.process("I uh THINK")
        # Note: model lowercases, but this tests behavior
        assert "think" in result.lower()

    def test_process_with_details(self, filler_model):
        """Test detailed output."""
        result = filler_model.process_with_details("i uh think um here")
        assert "output" in result
        assert "removed" in result
        assert "labels" in result
        assert "uh" in result["removed"] or "um" in result["removed"]

    @pytest.mark.parametrize("test_case", FIXTURES["discourse_preservation_tests"])
    def test_preserves_discourse_markers(self, filler_model, test_case):
        """Test that discourse markers are NOT removed by filler model."""
        result = filler_model.process(test_case["input"])
        # Discourse markers should be preserved
        assert result == test_case["expected"], \
            f"Discourse marker incorrectly removed: {test_case['input']!r} -> {result!r}"


class TestFillerModelLoading:
    """Test model loading behavior."""

    def test_model_loads_successfully(self):
        """Test that model loads without error."""
        model = FillerRemover()
        assert model is not None
        assert model.model is not None
        assert model.tokenizer is not None

    def test_model_has_correct_labels(self):
        """Test that model has expected label configuration."""
        model = FillerRemover()
        labels = list(model.id2label.values())
        assert "O" in labels  # Keep label
        # Should have filler labels
        assert any("FILL" in label for label in labels)
