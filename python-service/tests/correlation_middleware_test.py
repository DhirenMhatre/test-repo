import os
import re
import time
from datetime import datetime, timedelta
from typing import Dict, List, Any

CORRELATION_ID_HEADER = "X-Correlation-ID"

# In-memory trace storage: {correlation_id: [trace_dict, ...]}
trace_storage: Dict[str, List[Dict[str, Any]]] = {}


class CorrelationIDMiddleware:
    def __init__(self, app=None):
        self.app = None
        if app is not None:
            self.init_app(app)

    def init_app(self, app):
        # Register hooks
        app.before_request(self.before_request)
        app.after_request(self.after_request)
        # Initialize any app-level state if needed
        setattr(app, "correlation_start_time", None)
        self.app = app

    def is_valid_correlation_id(self, correlation_id) -> bool:
        if not isinstance(correlation_id, str):
            return False
        # Accept IDs between 6 and 100 characters, consisting of alphanum, -, _
        if not (6 <= len(correlation_id) <= 100):
            return False
        if re.match(r"^[A-Za-z0-9_-]+$", correlation_id) is None:
            return False
        return True

    def generate_correlation_id(self) -> str:
        # Example format: <epoch>-py-<pid>
        return f"{int(time.time())}-py-{os.getpid()}"

    def extract_or_generate_correlation_id(self, request) -> str:
        # Headers may be None or missing .get()
        headers = getattr(request, "headers", None)
        header_val = None
        if headers is not None:
            try:
                header_val = headers.get(CORRELATION_ID_HEADER)
            except AttributeError:
                # headers may be a plain dict-like without .get or None
                try:
                    header_val = headers[CORRELATION_ID_HEADER]
                except Exception:
                    header_val = None

        if header_val and self.is_valid_correlation_id(header_val):
            return header_val

        return self.generate_correlation_id()

    def before_request(self):
        # Use flask globals
        from flask import request, g

        cid = self.extract_or_generate_correlation_id(request)
        g.correlation_id = cid
        g.request_start_time = time.time()

    def after_request(self, response):
        from flask import request, g

        cid = getattr(g, "correlation_id", None)
        if not cid:
            return response

        # Propagate correlation id to response header
        try:
            response.headers[CORRELATION_ID_HEADER] = cid
        except Exception:
            # If response headers not settable, just ignore
            pass

        # Compute trace data
        start = getattr(g, "request_start_time", None)
        now = time.time()
        duration_ms = None
        if isinstance(start, (int, float)):
            duration_ms = (now - start) * 1000.0

        trace = {
            "service": "python-reviewer",
            "method": getattr(request, "method", None),
            "path": getattr(request, "path", None),
            "status": getattr(response, "status_code", None),
            "duration_ms": duration_ms,
            "timestamp": datetime.now().isoformat(),
        }

        try:
            store_trace(cid, trace)
        except Exception:
            # Swallow storage errors to not break response flow
            pass

        return response


def store_trace(correlation_id: str, trace: Dict[str, Any]) -> None:
    # Store a shallow copy to avoid external mutation
    entry = dict(trace)
    if correlation_id not in trace_storage:
        trace_storage[correlation_id] = []
    trace_storage[correlation_id].append(entry)


def get_traces(correlation_id: str) -> List[Dict[str, Any]]:
    traces = trace_storage.get(correlation_id, [])
    # Return a shallow copy of the list
    return list(traces)


def get_all_traces() -> Dict[str, List[Dict[str, Any]]]:
    # Return shallow copies of lists
    return {cid: list(traces) for cid, traces in trace_storage.items()}


def cleanup_old_traces(hours: int = 1) -> None:
    """Remove correlation IDs whose oldest trace timestamp is older than cutoff."""
    cutoff = datetime.now() - timedelta(hours=hours)
    to_delete = []

    for cid, traces in trace_storage.items():
        # Determine the oldest timestamp within this cid traces
        oldest_dt = None
        for t in traces:
            ts = t.get("timestamp")
            try:
                dt = datetime.fromisoformat(ts) if isinstance(ts, str) else None
            except Exception:
                dt = None
            if dt is None:
                continue
            if oldest_dt is None or dt < oldest_dt:
                oldest_dt = dt

        if oldest_dt is not None and oldest_dt < cutoff:
            to_delete.append(cid)

    for cid in to_delete:
        try:
            del trace_storage[cid]
        except KeyError:
            pass