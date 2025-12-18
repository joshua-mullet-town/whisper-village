"""
HTTP server for Whisper Village integration.

Run with:
    python -m ml.pipeline.server

Or from the ml directory:
    python -m pipeline.server

Endpoints:
    POST /cleanup          - Full pipeline cleanup
    POST /cleanup/fillers  - Only filler removal
    POST /cleanup/reps     - Only repetition removal
    GET  /health           - Health check
    GET  /models           - List available models

Request body:
    {"text": "your transcript here"}

Response:
    {"output": "cleaned transcript", "input": "original"}
"""

import json
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional

# Add parent directory to path for imports when run as script
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from ml.pipeline import TranscriptPipeline, FillerRemover, RepetitionRemover


# Global pipeline instances (lazy loaded)
_full_pipeline: Optional[TranscriptPipeline] = None
_filler_only: Optional[FillerRemover] = None
_rep_only: Optional[RepetitionRemover] = None


def get_full_pipeline() -> TranscriptPipeline:
    """Get or create full pipeline (cached)."""
    global _full_pipeline
    if _full_pipeline is None:
        print("Loading full pipeline...")
        _full_pipeline = TranscriptPipeline()
        print("Full pipeline ready")
    return _full_pipeline


def get_filler_model() -> FillerRemover:
    """Get or create filler model (cached)."""
    global _filler_only
    if _filler_only is None:
        print("Loading filler model...")
        _filler_only = FillerRemover()
        print("Filler model ready")
    return _filler_only


def get_rep_model() -> RepetitionRemover:
    """Get or create repetition model (cached)."""
    global _rep_only
    if _rep_only is None:
        print("Loading repetition model...")
        _rep_only = RepetitionRemover()
        print("Repetition model ready")
    return _rep_only


class CleanupHandler(BaseHTTPRequestHandler):
    """HTTP request handler for cleanup endpoints."""

    def _send_json(self, data: dict, status: int = 200):
        """Send JSON response."""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def _get_json_body(self) -> dict:
        """Parse JSON from request body."""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        return json.loads(body.decode())

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/health':
            self._send_json({'status': 'ok'})

        elif self.path == '/models':
            self._send_json({
                'available': ['filler', 'repetition'],
                'pipeline': get_full_pipeline().model_names
            })

        else:
            self._send_json({'error': 'Not found'}, 404)

    def do_POST(self):
        """Handle POST requests."""
        try:
            body = self._get_json_body()
            text = body.get('text', '')

            if not text:
                self._send_json({'error': 'Missing "text" field'}, 400)
                return

            if self.path == '/cleanup':
                pipeline = get_full_pipeline()
                result = pipeline.process_with_details(text)
                self._send_json({
                    'input': result['input'],
                    'output': result['output'],
                    'steps': result['steps']
                })

            elif self.path == '/cleanup/fillers':
                model = get_filler_model()
                result = model.process_with_details(text)
                self._send_json({
                    'input': text,
                    'output': result['output'],
                    'removed': result['removed']
                })

            elif self.path == '/cleanup/reps':
                model = get_rep_model()
                result = model.process_with_details(text)
                self._send_json({
                    'input': text,
                    'output': result['output'],
                    'removed': result['removed']
                })

            else:
                self._send_json({'error': 'Not found'}, 404)

        except json.JSONDecodeError:
            self._send_json({'error': 'Invalid JSON'}, 400)
        except Exception as e:
            self._send_json({'error': str(e)}, 500)

    def log_message(self, format, *args):
        """Custom log format."""
        print(f"[{self.log_date_time_string()}] {args[0]}")


def run_server(host: str = '127.0.0.1', port: int = 8765):
    """
    Start the HTTP server.

    Args:
        host: Host to bind to (default: localhost only)
        port: Port to listen on (default: 8765)
    """
    server = HTTPServer((host, port), CleanupHandler)
    print(f"ML Cleanup Server starting on http://{host}:{port}")
    print("Endpoints:")
    print("  POST /cleanup          - Full pipeline")
    print("  POST /cleanup/fillers  - Filler removal only")
    print("  POST /cleanup/reps     - Repetition removal only")
    print("  GET  /health           - Health check")
    print("  GET  /models           - List models")
    print()
    print("Models will be loaded on first request...")
    print("Press Ctrl+C to stop")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='ML Cleanup Server')
    parser.add_argument('--host', default='127.0.0.1', help='Host to bind to')
    parser.add_argument('--port', type=int, default=8765, help='Port to listen on')
    args = parser.parse_args()

    run_server(args.host, args.port)
