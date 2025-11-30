import sys
import importlib
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock

import pytest


def _ensure_stub_modules():
    """Ensure stubbed external modules exist before importing src.app."""
    # Stub src.code_reviewer
    if "src.code_reviewer" not in sys.modules:
        code_reviewer_mod = ModuleType("src.code_reviewer")

        class CodeReviewer:
            def review_code(self, content: str, language: str):
                # Default stubbed result
                issue = SimpleNamespace(
                    severity="low", line=1, message="stub issue", suggestion="stub suggestion"
                )
                return SimpleNamespace(
                    score=100,
                    issues=[issue],
                    suggestions=["stub suggestion"],
                    complexity_score=1.0,
                )

            def review_function(self, function_code: str):
                return {"review": "ok", "length": len(function_code or "")}

        code_reviewer_mod.CodeReviewer = CodeReviewer
        sys.modules["src.code_reviewer"] = code_reviewer_mod

    # Stub src.statistics
    if "src.statistics" not in sys.modules:
        statistics_mod = ModuleType("src.statistics")

        class StatisticsAggregator:
            def aggregate_reviews(self, files):
                return SimpleNamespace(
                    total_files=len(files or []),
                    average_score=0.0,
                    total_issues=0,
                    issues_by_severity={},
                    average_complexity=0.0,
                    files_with_high_complexity=[],
                    total_suggestions=0,
                )

        statistics_mod.StatisticsAggregator = StatisticsAggregator
        sys.modules["src.statistics"] = statistics_mod

    # Stub src.correlation_middleware
    if "src.correlation_middleware" not in sys.modules:
        correlation_mod = ModuleType("src.correlation_middleware")

        from flask import request, g

        class CorrelationIDMiddleware:
            def __init__(self, app):
                @app.before_request
                def _set_correlation_id():
                    g.correlation_id = request.headers.get(
                        "X-Correlation-ID", "test-correlation-id"
                    )

        def get_traces(correlation_id):
            return []

        def get_all_traces():
            return []

        correlation_mod.CorrelationIDMiddleware = CorrelationIDMiddleware
        correlation_mod.get_traces = get_traces
        correlation_mod.get_all_traces = get_all_traces
        sys.modules["src.correlation_middleware"] = correlation_mod

    # Stub src.request_validator
    if "src.request_validator" not in sys.modules:
        request_validator_mod = ModuleType("src.request_validator")

        _validation_errors_store = []

        class _Error:
            def __init__(self, field="field", message="invalid"):
                self.field = field
                self.message = message

            def to_dict(self):
                return {"field": self.field, "message": self.message}

        def validate_review_request(data):
            return []

        def validate_statistics_request(data):
            return []

        def sanitize_request_data(data):
            return data or {}

        def get_validation_errors():
            return list(_validation_errors_store)

        def clear_validation_errors():
            _validation_errors_store.clear()

        request_validator_mod.validate_review_request = validate_review_request
        request_validator_mod.validate_statistics_request = validate_statistics_request
        request_validator_mod.sanitize_request_data = sanitize_request_data
        request_validator_mod.get_validation_errors = get_validation_errors
        request_validator_mod.clear_validation_errors = clear_validation_errors
        request_validator_mod._Error = _Error

        sys.modules["src.request_validator"] = request_validator_mod


@pytest.fixture
def app_module(monkeypatch):
    """Provide a fresh import of src.app with stubbed dependencies and return the module."""
    _ensure_stub_modules()
    if "src.app" in sys.modules:
        del sys.modules["src.app"]
    module = importlib.import_module("src.app")
    # Also import using the required statement
    from src.app import app as _imported_app  # noqa: F401

    return module


@pytest.fixture
def client(app_module):
    """Flask test client for the app."""
    return app_module.app.test_client()


def test_health_check_returns_status_healthy(client):
    """GET /health returns 200 and expected payload."""
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data == {"status": "healthy", "service": "python-reviewer"}


@pytest.mark.parametrize("endpoint", ["/review", "/statistics"])
def test_endpoints_missing_body_returns_400(client, endpoint):
    """POST endpoints with missing body should return 400."""
    resp = client.post(endpoint)
    assert resp.status_code == 400
    data = resp.get_json()
    assert data["error"] == "Missing request body"


def test_review_code_validation_failure_returns_422(app_module, client, monkeypatch):
    """POST /review returns 422 when validate_review_request returns errors."""
    class FakeError:
        def to_dict(self):
            return {"field": "content", "message": "required"}

    monkeypatch.setattr(app_module, "validate_review_request", lambda data: [FakeError()])

    resp = client.post("/review", json={"content": "", "language": "python"})
    assert resp.status_code == 422
    data = resp.get_json()
    assert data["error"] == "Validation failed"
    assert data["details"] == [{"field": "content", "message": "required"}]


def test_review_code_success_returns_result_and_correlation_id(app_module, client, monkeypatch):
    """POST /review returns 200 with review results and correlation_id."""
    # Ensure no validation errors
    monkeypatch.setattr(app_module, "validate_review_request", lambda data: [])
    # Ensure sanitization passes through
    monkeypatch.setattr(app_module, "sanitize_request_data", lambda data: data)

    # Mock reviewer result
    def fake_review_code(content, language):
        issues = [
            SimpleNamespace(severity="medium", line=10, message="Use of eval", suggestion="Avoid using eval"),
            SimpleNamespace(severity="low", line=2, message="Trailing whitespace", suggestion="Remove trailing whitespace"),
        ]
        return SimpleNamespace(
            score=85,
            issues=issues,
            suggestions=["Consider using f-strings"],
            complexity_score=3.2,
        )

    monkeypatch.setattr(app_module.reviewer, "review_code", fake_review_code)

    cid = "abc-123"
    payload = {"content": "print('hi')", "language": "python"}
    resp = client.post("/review", json=payload, headers={"X-Correlation-ID": cid})
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["score"] == 85
    assert isinstance(data["issues"], list) and len(data["issues"]) == 2
    assert data["suggestions"] == ["Consider using f-strings"]
    assert data["complexity_score"] == 3.2
    assert data["correlation_id"] == cid


@pytest.mark.parametrize(
    "payload",
    [
        None,
        {},
        {"not_function_code": "def foo(): pass"},
    ],
)
def test_review_function_missing_field_returns_400(client, payload):
    """POST /review/function returns 400 when 'function_code' is missing."""
    if payload is None:
        resp = client.post("/review/function")
    else:
        resp = client.post("/review/function", json=payload)
    assert resp.status_code == 400
    data = resp.get_json()
    assert data["error"] == "Missing 'function_code' field"


def test_review_function_success_returns_result(app_module, client, monkeypatch):
    """POST /review/function returns 200 with review result."""
    def fake_review_function(function_code):
        return {"result": "ok", "length": len(function_code)}

    monkeypatch.setattr(app_module.reviewer, "review_function", fake_review_function)

    code = "def f():\n    return 1"
    resp = client.post("/review/function", json={"function_code": code})
    assert resp.status_code == 200
    data = resp.get_json()
    assert data == {"result": "ok", "length": len(code)}


def test_statistics_validation_failure_returns_422(app_module, client, monkeypatch):
    """POST /statistics returns 422 when validate_statistics_request returns errors."""
    class FakeError:
        def to_dict(self):
            return {"field": "files", "message": "must be a non-empty list"}

    monkeypatch.setattr(app_module, "validate_statistics_request", lambda data: [FakeError()])

    resp = client.post("/statistics", json={"files": []})
    assert resp.status_code == 422
    data = resp.get_json()
    assert data["error"] == "Validation failed"
    assert data["details"] == [{"field": "files", "message": "must be a non-empty list"}]


def test_statistics_success_returns_aggregated_stats_with_correlation_id(app_module, client, monkeypatch):
    """POST /statistics returns 200 with aggregated statistics and correlation_id."""
    monkeypatch.setattr(app_module, "validate_statistics_request", lambda data: [])
    monkeypatch.setattr(app_module, "sanitize_request_data", lambda data: data)

    def fake_aggregate_reviews(files):
        return SimpleNamespace(
            total_files=3,
            average_score=92.5,
            total_issues=4,
            issues_by_severity={"high": 1, "medium": 2, "low": 1},
            average_complexity=2.1,
            files_with_high_complexity=["a.py"],
            total_suggestions=5,
        )

    monkeypatch.setattr(app_module.statistics_aggregator, "aggregate_reviews", fake_aggregate_reviews)

    cid = "xyz-789"
    resp = client.post(
        "/statistics",
        json={"files": [{"name": "a.py"}, {"name": "b.py"}, {"name": "c.py"}]},
        headers={"X-Correlation-ID": cid},
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_files"] == 3
    assert data["average_score"] == 92.5
    assert data["total_issues"] == 4
    assert data["issues_by_severity"] == {"high": 1, "medium": 2, "low": 1}
    assert data["average_complexity"] == 2.1
    assert data["files_with_high_complexity"] == ["a.py"]
    assert data["total_suggestions"] == 5
    assert data["correlation_id"] == cid


def test_list_traces_returns_all_traces(app_module, client, monkeypatch):
    """GET /traces returns list of all traces."""
    traces = [{"id": "t1"}, {"id": "t2"}]
    monkeypatch.setattr(app_module, "get_all_traces", lambda: traces)

    resp = client.get("/traces")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_traces"] == 2
    assert data["traces"] == traces


def test_get_trace_not_found_returns_404(app_module, client, monkeypatch):
    """GET /traces/<id> returns 404 when no traces found for the correlation ID."""
    monkeypatch.setattr(app_module, "get_traces", lambda cid: [])

    resp = client.get("/traces/does-not-exist")
    assert resp.status_code == 404
    data = resp.get_json()
    assert data["error"] == "No traces found for correlation ID"


def test_get_trace_success_returns_trace_data(app_module, client, monkeypatch):
    """GET /traces/<id> returns 200 with traces for the given correlation ID."""
    trace_items = [{"step": "recv"}, {"step": "process"}]
    monkeypatch.setattr(app_module, "get_traces", lambda cid: trace_items)

    correlation_id = "cid-123"
    resp = client.get(f"/traces/{correlation_id}")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["correlation_id"] == correlation_id
    assert data["trace_count"] == len(trace_items)
    assert data["traces"] == trace_items


def test_list_validation_errors_returns_errors(app_module, client, monkeypatch):
    """GET /validation/errors returns list of validation errors with total count."""
    errors = [{"field": "content", "message": "required"}, {"field": "files", "message": "must be list"}]
    monkeypatch.setattr(app_module, "get_validation_errors", lambda: errors)

    resp = client.get("/validation/errors")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_errors"] == len(errors)
    assert data["errors"] == errors


def test_delete_validation_errors_clears_store(app_module, client, monkeypatch):
    """DELETE /validation/errors calls clear_validation_errors and returns confirmation."""
    clear_mock = Mock()
    monkeypatch.setattr(app_module, "clear_validation_errors", clear_mock)

    resp = client.delete("/validation/errors")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data == {"message": "Validation errors cleared"}
    assert clear_mock.called is True