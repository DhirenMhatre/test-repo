from typing import Any, Dict, List, Optional
import re
import time
from flask import g, request, Response


# Simple in-memory storage for traces; useful for tests and simple apps
TRACES: Dict[str, List[Dict[str, Any]]] = {}

SERVICE_NAME = "python-reviewer"


def store_trace(correlation_id: str, trace_data: Dict[str, Any]) -> None:
    """Store trace data keyed by correlation ID."""
    TRACES.setdefault(correlation_id, []).append(trace_data)


class CorrelationIDMiddleware:
    """
    Flask middleware to manage correlation IDs, timing, and trace storage.

    - Extracts or generates a correlation ID for each request.
    - Adds X-Correlation-ID header to responses.
    - Stores basic trace information for each request.
    """

    CORRELATION_HEADER = "X-Correlation-ID"
    VALID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{10,100}$")

    def __init__(self, app: Optional[Any] = None) -> None:
        if app is not None:
            self.init_app(app)

    def init_app(self, app: Any) -> None:
        # Register hooks
        app.before_request(self.before_request)
        app.after_request(self.after_request)
        # Optional attribute used by tests
        setattr(app, "correlation_start_time", None)

    def is_valid_correlation_id(self, value: Any) -> bool:
        if not isinstance(value, str):
            return False
        return bool(self.VALID_PATTERN.fullmatch(value))

    def generate_correlation_id(self) -> str:
        now = time.time()
        seconds = int(now)
        micros_part = int((now - seconds) * 1_000_000) % 100000  # 5 digits
        return f"{seconds}-py-{micros_part:05d}"

    def extract_or_generate_correlation_id(self, req: Any) -> str:
        header_value = None
        try:
            header_value = req.headers.get(self.CORRELATION_HEADER)
        except Exception:
            header_value = None

        if isinstance(header_value, str) and self.is_valid_correlation_id(header_value):
            return header_value

        return self.generate_correlation_id()

    def before_request(self) -> None:
        cid = self.extract_or_generate_correlation_id(request)
        g.correlation_id = cid
        g.request_start_time = time.time()

    def after_request(self, response: Response) -> Response:
        cid = getattr(g, "correlation_id", None)
        if not cid:
            return response

        # Ensure header is set
        response.headers[self.CORRELATION_HEADER] = cid

        # Calculate duration
        start = getattr(g, "request_start_time", time.time())
        end = time.time()
        duration_ms = round((end - start) * 1000.0, 2)

        # Build trace data
        trace_data = {
            "service": SERVICE_NAME,
            "method": getattr(request, "method", None),
            "path": getattr(request, "path", None),
            "status": getattr(response, "status_code", None),
            "duration_ms": duration_ms,
            "timestamp": end,
        }

        store_trace(cid, trace_data)
        return response