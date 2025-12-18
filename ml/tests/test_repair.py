"""
Tests for the repair removal model.

Run with:
    pytest ml/tests/test_repair.py -v

NOTE: This is an experimental model. Tests may need adjustment based on actual
model performance since repairs are harder than simple repetitions.
"""

import json
import pytest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from ml.pipeline.models import RepairRemover


# Load test fixtures
FIXTURES_PATH = Path(__file__).parent / "fixtures.json"
with open(FIXTURES_PATH) as f:
    FIXTURES = json.load(f)


@pytest.fixture(scope="module")
def repair_model():
    """Load repair model once for all tests."""
    return RepairRemover()


class TestRepairRemover:
    """Test suite for RepairRemover model."""

    @pytest.mark.parametrize("test_case", FIXTURES["repair_tests"])
    def test_repair_removal(self, repair_model, test_case):
        """Test that repairs are removed correctly."""
        result = repair_model.process(test_case["input"])
        assert result == test_case["expected"], \
            f"[{test_case.get('description', 'test')}] " \
            f"Input: {test_case['input']!r}, Expected: {test_case['expected']!r}, Got: {result!r}"

    def test_empty_string(self, repair_model):
        """Test handling of empty string."""
        assert repair_model.process("") == ""

    def test_no_repairs(self, repair_model):
        """Test string with no repairs."""
        result = repair_model.process("this is a normal sentence")
        assert "this" in result
        assert "sentence" in result

    def test_process_with_details(self, repair_model):
        """Test detailed output."""
        result = repair_model.process_with_details("we were i was there")
        assert "output" in result
        assert "removed" in result
        assert "labels" in result


class TestRepairModelLoading:
    """Test model loading behavior."""

    def test_model_loads_successfully(self):
        """Test that model loads without error."""
        model = RepairRemover()
        assert model is not None
        assert model.model is not None
        assert model.tokenizer is not None

    def test_model_has_correct_labels(self):
        """Test that model has expected label configuration."""
        model = RepairRemover()
        labels = list(model.id2label.values())
        assert "O" in labels  # Keep label
        # Should have REPAIR labels
        assert any("REPAIR" in label for label in labels)
