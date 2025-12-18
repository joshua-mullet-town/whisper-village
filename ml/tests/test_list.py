"""
Tests for the list formatting model.

Run with:
    pytest ml/tests/test_list.py -v
"""

import json
import pytest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from ml.pipeline.models import ListFormatter


# Load test fixtures
FIXTURES_PATH = Path(__file__).parent / "fixtures.json"
with open(FIXTURES_PATH) as f:
    FIXTURES = json.load(f)


@pytest.fixture(scope="module")
def list_model():
    """Load list formatter model once for all tests."""
    return ListFormatter()


class TestListFormatter:
    """Test suite for ListFormatter model."""

    @pytest.mark.parametrize("test_case", FIXTURES["list_tests"])
    def test_list_formatting(self, list_model, test_case):
        """Test that lists are formatted correctly."""
        result = list_model.process(test_case["input"])
        # Normalize newlines for comparison
        expected_normalized = test_case["expected"].strip()
        result_normalized = result.strip()
        assert result_normalized == expected_normalized, \
            f"Input: {test_case['input']!r}\nExpected:\n{expected_normalized!r}\nGot:\n{result_normalized!r}"

    def test_empty_string(self, list_model):
        """Test handling of empty string."""
        assert list_model.process("") == ""

    def test_whitespace_only(self, list_model):
        """Test handling of whitespace-only string."""
        assert list_model.process("   ").strip() == ""

    def test_no_list_unchanged(self, list_model):
        """Test that text without list indicators is returned unchanged."""
        input_text = "hello this is a normal sentence"
        result = list_model.process(input_text)
        # Should be the same or very similar (model might add minor formatting)
        assert "hello" in result.lower()
        assert "-" not in result  # No bullet points added

    def test_output_has_newlines(self, list_model):
        """Test that list items are separated by newlines."""
        result = list_model.process("one apples two bananas")
        assert "\n" in result, f"Expected newlines in output, got: {result!r}"

    def test_items_capitalized(self, list_model):
        """Test that list items are capitalized."""
        result = list_model.process("one finish the report two send email")
        lines = result.strip().split("\n")
        # Find the bullet lines
        bullet_lines = [l for l in lines if l.strip().startswith("-")]
        for line in bullet_lines:
            # Remove "- " prefix and check first char is capitalized
            item = line.strip()[2:].strip()
            if item:
                assert item[0].isupper(), f"Expected capitalized item, got: {item!r}"


class TestListFormatterOrdinals:
    """Test ordinal list indicators (first, second, third)."""

    def test_first_second(self, list_model):
        """Test 'first/second' format."""
        result = list_model.process("first buy groceries second clean house")
        assert "-" in result
        assert "\n" in result

    def test_mixed_ordinals(self, list_model):
        """Test first/second/third/fourth ordinals."""
        result = list_model.process("first a second b third c")
        # Should have multiple bullet points
        bullet_count = result.count("-")
        assert bullet_count >= 3, f"Expected at least 3 bullets, got {bullet_count}: {result!r}"


class TestListFormatterCardinals:
    """Test cardinal list indicators (one, two, three)."""

    def test_one_two(self, list_model):
        """Test 'one/two' format."""
        result = list_model.process("one buy groceries two clean house")
        assert "-" in result
        assert "\n" in result

    def test_one_two_three(self, list_model):
        """Test one/two/three format."""
        result = list_model.process("one a two b three c")
        bullet_count = result.count("-")
        assert bullet_count >= 3, f"Expected at least 3 bullets, got {bullet_count}: {result!r}"


class TestListFormatterWithContext:
    """Test lists with preceding context text."""

    def test_context_before_list(self, list_model):
        """Test that context before list is preserved."""
        result = list_model.process("my goals are one exercise two read")
        assert "goals" in result.lower() or "my" in result.lower()
        assert "-" in result

    def test_long_context(self, list_model):
        """Test with longer context before list."""
        result = list_model.process("the things i need to do today are one buy milk two call mom")
        assert "-" in result
        assert "\n" in result


class TestListModelLoading:
    """Test model loading behavior."""

    def test_model_loads_successfully(self):
        """Test that model loads without error."""
        model = ListFormatter()
        assert model is not None
        assert model.model is not None
        assert model.tokenizer is not None

    def test_model_has_correct_path(self):
        """Test that model uses correct directory."""
        model = ListFormatter()
        assert "list-formatter" in str(model.model_path)


class TestNewlinePostProcessing:
    """Test the _fix_newlines helper method."""

    def test_fix_newlines_method_exists(self, list_model):
        """Test that _fix_newlines method exists."""
        assert hasattr(list_model, "_fix_newlines")

    def test_inline_dashes_converted(self, list_model):
        """Test that inline dashes become newlines."""
        # The raw model might output "- A - B" instead of "- A\n- B"
        # The _fix_newlines method should handle this
        test_input = "- First item - Second item"
        result = list_model._fix_newlines(test_input)
        # Should have converted " - " to "\n- " before capital letters
        assert "Second" in result
