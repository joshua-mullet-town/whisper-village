"""
Tests for the full transcript cleanup pipeline.

Run with:
    pytest ml/tests/test_pipeline.py -v
"""

import json
import pytest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from ml.pipeline import TranscriptPipeline, FillerRemover, RepetitionRemover
from ml.pipeline.pipeline import cleanup_transcript


# Load test fixtures
FIXTURES_PATH = Path(__file__).parent / "fixtures.json"
with open(FIXTURES_PATH) as f:
    FIXTURES = json.load(f)


@pytest.fixture(scope="module")
def pipeline():
    """Load full pipeline once for all tests."""
    return TranscriptPipeline()


class TestTranscriptPipeline:
    """Test suite for the full pipeline."""

    @pytest.mark.parametrize("test_case", FIXTURES["pipeline_tests"])
    def test_full_pipeline(self, pipeline, test_case):
        """Test full pipeline produces expected output."""
        result = pipeline.process(test_case["input"])
        assert result == test_case["expected"], \
            f"[{test_case.get('description', 'test')}] " \
            f"Input: {test_case['input']!r}, Expected: {test_case['expected']!r}, Got: {result!r}"

    def test_empty_string(self, pipeline):
        """Test handling of empty string."""
        assert pipeline.process("") == ""

    def test_clean_string_unchanged(self, pipeline):
        """Test that clean strings pass through unchanged."""
        clean = "this is a clean sentence"
        result = pipeline.process(clean)
        assert result == clean

    def test_process_with_details_structure(self, pipeline):
        """Test that detailed output has correct structure."""
        result = pipeline.process_with_details("i uh think um we should go")

        assert "input" in result
        assert "output" in result
        assert "steps" in result
        assert isinstance(result["steps"], list)
        assert len(result["steps"]) == 2  # Two models in pipeline

    def test_process_with_details_steps(self, pipeline):
        """Test that each step is recorded correctly."""
        result = pipeline.process_with_details("i uh i i think")

        # First step should be filler removal
        assert result["steps"][0]["model"] == "FillerRemover"

        # Second step should be repetition removal
        assert result["steps"][1]["model"] == "RepetitionRemover"

        # Each step should have input/output
        for step in result["steps"]:
            assert "input" in step
            assert "output" in step
            assert "removed" in step

    @pytest.mark.parametrize("test_case", FIXTURES["discourse_preservation_tests"])
    def test_preserves_discourse_markers(self, pipeline, test_case):
        """Test that discourse markers survive the full pipeline."""
        result = pipeline.process(test_case["input"])
        assert result == test_case["expected"], \
            f"Discourse marker lost in pipeline: {test_case['input']!r} -> {result!r}"


class TestPipelineConfiguration:
    """Test pipeline configuration options."""

    def test_filler_only_pipeline(self):
        """Test pipeline with only filler removal."""
        pipeline = TranscriptPipeline(enable_fillers=True, enable_repetitions=False)
        assert len(pipeline.models) == 1
        assert pipeline.model_names == ["FillerRemover"]

        result = pipeline.process("i uh i i think")
        assert "uh" not in result
        # Repetitions should still be there
        assert "i i" in result

    def test_repetition_only_pipeline(self):
        """Test pipeline with only repetition removal."""
        pipeline = TranscriptPipeline(enable_fillers=False, enable_repetitions=True)
        assert len(pipeline.models) == 1
        assert pipeline.model_names == ["RepetitionRemover"]

        result = pipeline.process("the the thing is good")
        # Repetitions should be removed
        assert "the the" not in result
        assert "thing" in result

    def test_empty_pipeline(self):
        """Test pipeline with no models."""
        pipeline = TranscriptPipeline(enable_fillers=False, enable_repetitions=False)
        assert len(pipeline.models) == 0

        # Should return input unchanged
        text = "i uh i i think"
        assert pipeline.process(text) == text

    def test_custom_models_pipeline(self):
        """Test pipeline with custom model list."""
        # Reverse order: repetition first, then filler
        models = [RepetitionRemover(), FillerRemover()]
        pipeline = TranscriptPipeline(custom_models=models)

        assert pipeline.model_names == ["RepetitionRemover", "FillerRemover"]

    def test_add_model(self):
        """Test adding model to pipeline."""
        pipeline = TranscriptPipeline(enable_fillers=True, enable_repetitions=False)
        assert len(pipeline.models) == 1

        pipeline.add_model(RepetitionRemover())
        assert len(pipeline.models) == 2

    def test_insert_model(self):
        """Test inserting model at specific position."""
        pipeline = TranscriptPipeline(enable_fillers=True, enable_repetitions=True)

        # Insert another filler model at the beginning
        pipeline.insert_model(0, FillerRemover())
        assert len(pipeline.models) == 3
        assert pipeline.model_names[0] == "FillerRemover"


class TestConvenienceFunction:
    """Test the cleanup_transcript convenience function."""

    def test_cleanup_transcript_works(self):
        """Test that convenience function works."""
        result = cleanup_transcript("i uh think um we should go")
        assert result == "i think we should go"

    def test_cleanup_transcript_handles_empty(self):
        """Test convenience function with empty string."""
        assert cleanup_transcript("") == ""
