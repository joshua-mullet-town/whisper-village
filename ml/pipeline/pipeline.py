"""
Transcript cleanup pipeline that chains multiple models.

The pipeline runs models in sequence:
    Raw text -> Filler Remover -> Repetition Remover -> Repair Remover -> Clean text

Each model only removes what it's trained for, keeping discourse
markers like "well", "you know" intact.
"""

from typing import Optional
from .models import FillerRemover, RepetitionRemover, RepairRemover, BaseModel


class TranscriptPipeline:
    """
    Chains cleanup models to process transcripts.

    Default pipeline order:
    1. Filler removal (uh, um)
    2. Repetition removal (I I -> I)
    3. Repair removal (store -> mall self-corrections) [disabled by default]

    Example:
        pipeline = TranscriptPipeline()
        clean = pipeline.process("i uh think um we we should go")
        # Returns: "i think we should go"

    To customize which models run:
        pipeline = TranscriptPipeline(enable_fillers=True, enable_repetitions=False)

    To enable repair removal:
        pipeline = TranscriptPipeline(enable_repairs=True)
    """

    def __init__(
        self,
        enable_fillers: bool = True,
        enable_repetitions: bool = True,
        enable_repairs: bool = False,  # Disabled by default - experimental
        custom_models: Optional[list[BaseModel]] = None
    ):
        """
        Initialize the pipeline.

        Args:
            enable_fillers: Include filler removal in pipeline
            enable_repetitions: Include repetition removal in pipeline
            enable_repairs: Include repair/self-correction removal (experimental)
            custom_models: Optional list of custom model instances to use instead
        """
        self.models: list[BaseModel] = []

        if custom_models:
            self.models = custom_models
        else:
            if enable_fillers:
                self.models.append(FillerRemover())
            if enable_repetitions:
                self.models.append(RepetitionRemover())
            if enable_repairs:
                self.models.append(RepairRemover())

    def process(self, text: str) -> str:
        """
        Run text through all models in the pipeline.

        Args:
            text: Input text to clean

        Returns:
            Cleaned text
        """
        result = text
        for model in self.models:
            result = model.process(result)
        return result

    def process_with_details(self, text: str) -> dict:
        """
        Run text through pipeline with detailed step-by-step results.

        Args:
            text: Input text to clean

        Returns:
            Dict with 'input', 'output', and 'steps' (list of intermediate results)
        """
        steps = []
        current_text = text

        for model in self.models:
            model_name = model.__class__.__name__
            result = model.process_with_details(current_text)

            steps.append({
                'model': model_name,
                'input': current_text,
                'output': result['output'],
                'removed': result['removed'],
            })

            current_text = result['output']

        return {
            'input': text,
            'output': current_text,
            'steps': steps,
        }

    def add_model(self, model: BaseModel) -> None:
        """Add a model to the end of the pipeline."""
        self.models.append(model)

    def insert_model(self, index: int, model: BaseModel) -> None:
        """Insert a model at a specific position in the pipeline."""
        self.models.insert(index, model)

    @property
    def model_names(self) -> list[str]:
        """Get names of models in the pipeline."""
        return [m.__class__.__name__ for m in self.models]


# Convenience function for quick use
def cleanup_transcript(text: str) -> str:
    """
    Quick cleanup using default pipeline.

    Args:
        text: Input transcript

    Returns:
        Cleaned transcript
    """
    pipeline = TranscriptPipeline()
    return pipeline.process(text)
