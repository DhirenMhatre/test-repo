import sys
import types
import pytest
from unittest.mock import Mock
from types import SimpleNamespace

# Attempt to import app and endpoints; if missing dependencies, stub them then retry
try:
    from src.app import app
    from src.app import (
        health_check,
        review_code,
        review_function,
        get_statistics,
        list_traces,
        get_trace,
        list_validation_errors,
        delete_validation_errors,
    )
except Exception:
    # Create stub modules for missing dependencies
    if 'src.code_reviewer' not in sys.modules:
        m = types.ModuleType('src.code_reviewer')

        class CodeReviewer:
            def review_code(self, content, language):
                return SimpleNamespace(score=0, issues=[], suggestions=[], complexity_score=0.0)

            def review_function(self, function_code):
                return {"ok": True}

        m.CodeReviewer = CodeReviewer
        sys.modules['src.code_reviewer'] = m

    if 'src.statistics' not in sys.modules:
        m = types.ModuleType('src.statistics')

        class StatisticsAggregator:
            def aggregate_reviews(self, files):
                return SimpleNamespace(
                    total_files=len(files),
                    average_score=0.0,
                    total_issues=0,
                    issues_by_severity={},
                    average_complexity=0.0,
                    files_with_high_complexity=[],
                    total_suggestions=0
                )

        m.StatisticsAggregator = StatisticsAggregator
        sys.modules['src.statistics'] = m

    if 'src.correlation_middleware' not in sys.modules:
        m = types.ModuleType('src.correlation_middleware')

        class CorrelationIDMiddleware:
            def __init__(self, app):
                self.app = app

        def get_traces(correlation_id):
            return []

        def get_all_traces():
            return []

        m.CorrelationIDMiddleware = CorrelationIDMiddleware
        m.get_traces = get_traces
        m.get_all_traces = get_all_traces
        sys.modules['src.correlation_middleware'] = m

    if 'src.request_validator' not in sys.modules:
        m = types.ModuleType('src.request_validator')

        def validate_review_request(data):
            return []

        def validate_statistics_request(data):
            return []

        def sanitize_request_data(data):
            return data

        def get_validation_errors():
            return []

        def clear_validation_errors():
            return None

        m.validate_review_request = validate_review_request
        m.validate_statistics_request = validate_statistics_request
        m.sanitize_request_data = sanitize_request_data
        m.get_validation_errors = get_validation_errors
        m.clear_validation_errors = clear_validation_errors
        sys.modules['src.request_validator'] = m

    from src.app import app
    from src.app import (
        health_check,
        review_code,
        review_function,
        get_statistics,
        list_traces,
        get_trace,
        list_validation_errors,
        delete_validation_errors,
    )

import importlib


@pytest.fixture
def app_module():
    """Provide the imported src.app module for monkeypatching."""
    return importlib.import_module('src.app')


@pytest.fixture
def client():
    """Create a Flask test client."""
    with app.test_client() as c:
        yield c


@pytest.fixture
def inject_correlation_id():
    """Register a before_request hook to inject a correlation_id into Flask's g."""
    def _inject(cid: str):
        from flask import g
        handler_called = {"called": False}

        def _handler():
            g.correlation_id = cid
            handler_called["called"] = True

        before_list = app.before_request_funcs.setdefault(None, [])
        before_list.append(_handler)

        def _teardown():
            before_list.remove(_handler)

        return _teardown, handler_called

    return _inject


def test_health_check_returns_status(client):
    """Test GET /health returns healthy status."""
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "healthy"
    assert data["service"] == "python-reviewer"


def test_review_code_missing_body_returns_400(client):
    """Test POST /review with missing body returns 400."""
    resp = client.post("/review")
    assert resp.status_code == 400
    assert resp.get_json()["error"] == "Missing request body"


def test_review_code_validation_error_returns_422(client, monkeypatch, app_module):
    """Test POST /review with validation errors returns 422 and details."""
    class ValErr:
        def __init__(self, code):
            self.code = code

        def to_dict(self):
            return {"code": self.code, "message": f"Invalid {self.code}"}

    monkeypatch.setattr(app_module, "validate_review_request", lambda data: [ValErr("A"), ValErr("B")])
    # sanitize shouldn't be called, but ensure it's present
    monkeypatch.setattr(app_module, "sanitize_request_data", lambda data: data)

    payload = {"content": "print('x')", "language": "python"}
    resp = client.post("/review", json=payload)
    assert resp.status_code == 422
    data = resp.get_json()
    assert data["error"] == "Validation failed"
    assert data["details"] == [
        {"code": "A", "message": "Invalid A"},
        {"code": "B", "message": "Invalid B"},
    ]


def test_review_code_happy_path_returns_review_result(client, monkeypatch, app_module, inject_correlation_id):
    """Test POST /review happy path returns proper review JSON with correlation_id."""
    # Arrange mocks
    monkeypatch.setattr(app_module, "validate_review_request", lambda data: [])
    monkeypatch.setattr(app_module, "sanitize_request_data", lambda data: {"content": "print('hi')", "language": "python"})

    mock_reviewer = Mock()
    issues = [
        SimpleNamespace(severity="HIGH", line=10, message="Issue 1", suggestion="Fix it"),
        SimpleNamespace(severity="LOW", line=20, message="Issue 2", suggestion="Consider change"),
    ]
    result = SimpleNamespace(
        score=85,
        issues=issues,
        suggestions=["Use f-strings"],
        complexity_score=2.3,
    )
    mock_reviewer.review_code.return_value = result
    monkeypatch.setattr(app_module, "reviewer", mock_reviewer)

    # Inject correlation id
    teardown, _ = inject_correlation_id()("cid-123")
    try:
        resp = client.post("/review", json={"content": "ignored", "language": "ignored"})
    finally:
        teardown()

    # Assert
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["score"] == 85
    assert data["suggestions"] == ["Use f-strings"]
    assert data["complexity_score"] == 2.3
    assert data["correlation_id"] == "cid-123"
    assert isinstance(data["issues"], list)
    assert len(data["issues"]) == 2
    assert data["issues"][0] == {
        "severity": "HIGH",
        "line": 10,
        "message": "Issue 1",
        "suggestion": "Fix it",
    }


@pytest.mark.parametrize("payload", [None, {}])
def test_review_function_missing_function_code_returns_400(client, payload):
    """Test POST /review/function returns 400 when 'function_code' is missing."""
    if payload is None:
        resp = client.post("/review/function")
    else:
        resp = client.post("/review/function", json=payload)
    assert resp.status_code == 400
    assert resp.get_json()["error"] == "Missing 'function_code' field"


def test_review_function_happy_path_returns_result(client, monkeypatch, app_module):
    """Test POST /review/function returns result from reviewer."""
    mock_reviewer = Mock()
    mock_reviewer.review_function.return_value = {"ok": True, "issues": [], "score": 100}
    monkeypatch.setattr(app_module, "reviewer", mock_reviewer)

    resp = client.post("/review/function", json={"function_code": "def f(): pass"})
    assert resp.status_code == 200
    data = resp.get_json()
    assert data == {"ok": True, "issues": [], "score": 100}
    mock_reviewer.review_function.assert_called_once()


def test_statistics_missing_body_returns_400(client):
    """Test POST /statistics with missing body returns 400."""
    resp = client.post("/statistics")
    assert resp.status_code == 400
    assert resp.get_json()["error"] == "Missing request body"


def test_statistics_validation_error_returns_422(client, monkeypatch, app_module):
    """Test POST /statistics with validation errors returns 422."""
    class ValErr:
        def __init__(self, field):
            self.field = field

        def to_dict(self):
            return {"field": self.field, "message": f"Invalid {self.field}"}

    monkeypatch.setattr(app_module, "validate_statistics_request", lambda data: [ValErr("files")])
    monkeypatch.setattr(app_module, "sanitize_request_data", lambda data: data)

    resp = client.post("/statistics", json={"files": []})
    assert resp.status_code == 422
    data = resp.get_json()
    assert data["error"] == "Validation failed"
    assert data["details"] == [{"field": "files", "message": "Invalid files"}]


def test_statistics_happy_path_returns_aggregated_stats(client, monkeypatch, app_module, inject_correlation_id):
    """Test POST /statistics returns aggregated statistics with correlation_id."""
    monkeypatch.setattr(app_module, "validate_statistics_request", lambda data: [])
    files = [{"path": "a.py"}, {"path": "b.py"}]
    monkeypatch.setattr(app_module, "sanitize_request_data", lambda data: {"files": files})

    stats_obj = SimpleNamespace(
        total_files=2,
        average_score=77.5,
        total_issues=5,
        issues_by_severity={"HIGH": 2, "LOW": 3},
        average_complexity=3.14,
        files_with_high_complexity=["a.py"],
        total_suggestions=4,
    )
    mock_stats = Mock()
    mock_stats.aggregate_reviews.return_value = stats_obj
    monkeypatch.setattr(app_module, "statistics_aggregator", mock_stats)

    teardown, _ = inject_correlation_id()("cid-456")
    try:
        resp = client.post("/statistics", json={"files": ["ignored"]})
    finally:
        teardown()

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_files"] == 2
    assert data["average_score"] == 77.5
    assert data["total_issues"] == 5
    assert data["issues_by_severity"] == {"HIGH": 2, "LOW": 3}
    assert data["average_complexity"] == 3.14
    assert data["files_with_high_complexity"] == ["a.py"]
    assert data["total_suggestions"] == 4
    assert data["correlation_id"] == "cid-456"
    mock_stats.aggregate_reviews.assert_called_once_with(files)


def test_list_traces_returns_all_traces(client, monkeypatch, app_module):
    """Test GET /traces returns list of all traces with total count."""
    traces = [{"id": 1}, {"id": 2}, {"id": 3}]
    monkeypatch.setattr(app_module, "get_all_traces", lambda: traces)

    resp = client.get("/traces")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_traces"] == 3
    assert data["traces"] == traces


def test_get_trace_returns_trace_details_when_found(client, monkeypatch, app_module):
    """Test GET /traces/<correlation_id> returns traces when found."""
    monkeypatch.setattr(app_module, "get_traces", lambda cid: [{"step": 1}, {"step": 2}] if cid == "abc" else [])
    resp = client.get("/traces/abc")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["correlation_id"] == "abc"
    assert data["trace_count"] == 2
    assert data["traces"] == [{"step": 1}, {"step": 2}]


def test_get_trace_returns_404_when_not_found(client, monkeypatch, app_module):
    """Test GET /traces/<correlation_id> returns 404 when no traces found."""
    monkeypatch.setattr(app_module, "get_traces", lambda cid: [])
    resp = client.get("/traces/none")
    assert resp.status_code == 404
    assert resp.get_json()["error"] == "No traces found for correlation ID"


def test_list_validation_errors_returns_errors(client, monkeypatch, app_module):
    """Test GET /validation/errors returns errors list and total count."""
    errs = [{"field": "content", "message": "required"}, {"field": "language", "message": "invalid"}]
    monkeypatch.setattr(app_module, "get_validation_errors", lambda: errs)

    resp = client.get("/validation/errors")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_errors"] == 2
    assert data["errors"] == errs


def test_delete_validation_errors_clears_errors(client, monkeypatch, app_module):
    """Test DELETE /validation/errors triggers clearing of validation errors."""
    mock_clear = Mock()
    monkeypatch.setattr(app_module, "clear_validation_errors", mock_clear)

    resp = client.delete("/validation/errors")
    assert resp.status_code == 200
    assert resp.get_json()["message"] == "Validation errors cleared"
    mock_clear.assert_called_once()