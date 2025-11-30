import sys
import types
import pytest
from unittest.mock import Mock

# Ensure stub external modules are available before importing src.app
# Create stub modules for src.code_reviewer, src.statistics, src.correlation_middleware, src.request_validator

# Stub for src.code_reviewer
code_reviewer_mod = types.ModuleType("src.code_reviewer")


class ReviewIssue:
    def __init__(self, severity="low", line=1, message="msg", suggestion="do this"):
        self.severity = severity
        self.line = line
        self.message = message
        self.suggestion = suggestion


class ReviewResult:
    def __init__(self, score=1.0, issues=None, suggestions=None, complexity_score=0.0):
        self.score = score
        self.issues = issues or []
        self.suggestions = suggestions or []
        self.complexity_score = complexity_score


class CodeReviewer:
    def review_code(self, content, language):
        return ReviewResult(
            score=0.8,
            issues=[ReviewIssue()],
            suggestions=["Use better naming"],
            complexity_score=2.5,
        )

    def review_function(self, function_code):
        return {"status": "ok", "length": len(function_code)}


code_reviewer_mod.CodeReviewer = CodeReviewer
sys.modules["src.code_reviewer"] = code_reviewer_mod

# Stub for src.statistics
statistics_mod = types.ModuleType("src.statistics")


class StatisticsAggregator:
    class Stats:
        def __init__(
            self,
            total_files=0,
            average_score=0.0,
            total_issues=0,
            issues_by_severity=None,
            average_complexity=0.0,
            files_with_high_complexity=None,
            total_suggestions=0,
        ):
            self.total_files = total_files
            self.average_score = average_score
            self.total_issues = total_issues
            self.issues_by_severity = issues_by_severity or {}
            self.average_complexity = average_complexity
            self.files_with_high_complexity = files_with_high_complexity or []
            self.total_suggestions = total_suggestions

    def aggregate_reviews(self, files):
        return self.Stats()

statistics_mod.StatisticsAggregator = StatisticsAggregator
sys.modules["src.statistics"] = statistics_mod

# Stub for src.request_validator
request_validator_mod = types.ModuleType("src.request_validator")


def validate_review_request(data):
    return []


def validate_statistics_request(data):
    return []


def sanitize_request_data(data):
    return data


_VALIDATION_ERRORS = []


def get_validation_errors():
    return list(_VALIDATION_ERRORS)


def clear_validation_errors():
    _VALIDATION_ERRORS.clear()


request_validator_mod.validate_review_request = validate_review_request
request_validator_mod.validate_statistics_request = validate_statistics_request
request_validator_mod.sanitize_request_data = sanitize_request_data
request_validator_mod.get_validation_errors = get_validation_errors
request_validator_mod.clear_validation_errors = clear_validation_errors
sys.modules["src.request_validator"] = request_validator_mod

# Stub for src.correlation_middleware
correlation_mw_mod = types.ModuleType("src.correlation_middleware")


class CorrelationIDMiddleware:
    def __init__(self, app):
        @app.before_request
        def _set_correlation():
            from flask import g, request
            g.correlation_id = request.headers.get("X-Correlation-ID", "corr-123")


def get_traces(correlation_id):
    return []


def get_all_traces():
    return []


correlation_mw_mod.CorrelationIDMiddleware = CorrelationIDMiddleware
correlation_mw_mod.get_traces = get_traces
correlation_mw_mod.get_all_traces = get_all_traces
sys.modules["src.correlation_middleware"] = correlation_mw_mod

# Now import the app after stubbing dependencies
from src.app import app  # noqa: E402


@pytest.fixture
def client():
    """Provide a Flask test client with testing enabled."""
    app.testing = True
    with app.test_client() as c:
        yield c


@pytest.fixture
def app_module():
    """Expose the src.app module for monkeypatching attributes."""
    return sys.modules["src.app"]


def test_health_check_ok(client):
    """Test /health endpoint returns healthy status."""
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "healthy"
    assert data["service"] == "python-reviewer"


def test_review_code_missing_body_error(client):
    """Test /review returns 400 when body is missing."""
    resp = client.post("/review")
    assert resp.status_code == 400
    assert resp.get_json()["error"] == "Missing request body"


def test_review_code_validation_error(client, monkeypatch, app_module):
    """Test /review returns 422 with validation errors when validation fails."""
    class Err:
        def __init__(self, field, msg):
            self.field = field
            self.msg = msg

        def to_dict(self):
            return {"field": self.field, "message": self.msg}

    monkeypatch.setattr(app_module, "validate_review_request", lambda data: [Err("content", "is required")])
    resp = client.post("/review", json={"content": ""})
    assert resp.status_code == 422
    payload = resp.get_json()
    assert payload["error"] == "Validation failed"
    assert payload["details"] == [{"field": "content", "message": "is required"}]


def test_review_code_success_with_correlation(client, monkeypatch, app_module):
    """Test /review returns analysis result and includes correlation_id from middleware."""
    monkeypatch.setattr(app_module, "validate_review_request", lambda data: [])
    monkeypatch.setattr(app_module, "sanitize_request_data", lambda data: {"content": "print('hi')", "language": "python"})

    class IssueObj:
        def __init__(self, severity, line, message, suggestion):
            self.severity = severity
            self.line = line
            self.message = message
            self.suggestion = suggestion

    class ResultObj:
        def __init__(self):
            self.score = 0.95
            self.issues = [IssueObj("low", 1, "nit", "use f-string")]
            self.suggestions = ["Add type hints"]
            self.complexity_score = 1.2

    monkeypatch.setattr(app_module.reviewer, "review_code", lambda content, language: ResultObj())

    resp = client.post("/review", json={"content": "print('hi')"}, headers={"X-Correlation-ID": "abc-123"})
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["score"] == 0.95
    assert body["issues"] == [
        {"severity": "low", "line": 1, "message": "nit", "suggestion": "use f-string"}
    ]
    assert body["suggestions"] == ["Add type hints"]
    assert body["complexity_score"] == 1.2
    assert body["correlation_id"] == "abc-123"


def test_review_function_missing_field(client):
    """Test /review/function returns 400 when 'function_code' is missing."""
    resp = client.post("/review/function", json={"code": "def f(): pass"})
    assert resp.status_code == 400
    assert resp.get_json()["error"] == "Missing 'function_code' field"


def test_review_function_success(client, monkeypatch, app_module):
    """Test /review/function returns reviewer output on success."""
    monkeypatch.setattr(app_module.reviewer, "review_function", lambda code: {"ok": True, "len": len(code)})
    resp = client.post("/review/function", json={"function_code": "def f(): pass"})
    assert resp.status_code == 200
    assert resp.get_json() == {"ok": True, "len": len("def f(): pass")}


def test_get_statistics_missing_body_error(client):
    """Test /statistics returns 400 when body is missing."""
    resp = client.post("/statistics")
    assert resp.status_code == 400
    assert resp.get_json()["error"] == "Missing request body"


def test_get_statistics_validation_error(client, monkeypatch, app_module):
    """Test /statistics returns 422 when validation fails."""
    class Err:
        def __init__(self, field, msg):
            self.field = field
            self.msg = msg

        def to_dict(self):
            return {"field": self.field, "message": self.msg}

    monkeypatch.setattr(app_module, "validate_statistics_request", lambda data: [Err("files", "must be a list")])
    resp = client.post("/statistics", json={"files": "not_a_list"})
    assert resp.status_code == 422
    payload = resp.get_json()
    assert payload["error"] == "Validation failed"
    assert payload["details"] == [{"field": "files", "message": "must be a list"}]


def test_get_statistics_success_with_correlation(client, monkeypatch, app_module):
    """Test /statistics returns aggregated stats and includes correlation_id."""
    monkeypatch.setattr(app_module, "validate_statistics_request", lambda data: [])
    monkeypatch.setattr(app_module, "sanitize_request_data", lambda data: {"files": [{"content": "x"}, {"content": "y"}]})

    class StatsObj:
        def __init__(self):
            self.total_files = 2
            self.average_score = 0.88
            self.total_issues = 3
            self.issues_by_severity = {"low": 2, "high": 1}
            self.average_complexity = 1.5
            self.files_with_high_complexity = ["a.py"]
            self.total_suggestions = 4

    monkeypatch.setattr(app_module.statistics_aggregator, "aggregate_reviews", lambda files: StatsObj())

    resp = client.post("/statistics", json={"files": []}, headers={"X-Correlation-ID": "stats-456"})
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["total_files"] == 2
    assert body["average_score"] == 0.88
    assert body["total_issues"] == 3
    assert body["issues_by_severity"] == {"low": 2, "high": 1}
    assert body["average_complexity"] == 1.5
    assert body["files_with_high_complexity"] == ["a.py"]
    assert body["total_suggestions"] == 4
    assert body["correlation_id"] == "stats-456"


def test_list_traces_returns_values(client, monkeypatch, app_module):
    """Test /traces returns all traces and count."""
    sample = [{"id": "t1"}, {"id": "t2"}]
    monkeypatch.setattr(app_module, "get_all_traces", lambda: sample)
    resp = client.get("/traces")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_traces"] == 2
    assert data["traces"] == sample


@pytest.mark.parametrize(
    "corr_id, traces, expected_status, expected_count",
    [
        ("nope", [], 404, None),
        ("ok-1", [{"evt": "a"}, {"evt": "b"}], 200, 2),
    ],
)
def test_get_trace_various_cases(client, monkeypatch, app_module, corr_id, traces, expected_status, expected_count):
    """Test /traces/<correlation_id> for not found and success cases."""
    monkeypatch.setattr(app_module, "get_traces", lambda cid: traces if cid == corr_id else [])
    resp = client.get(f"/traces/{corr_id}")
    assert resp.status_code == expected_status
    if expected_status == 404:
        assert resp.get_json()["error"] == "No traces found for correlation ID"
    else:
        data = resp.get_json()
        assert data["correlation_id"] == corr_id
        assert data["trace_count"] == expected_count
        assert data["traces"] == traces


def test_list_validation_errors_returns(client, monkeypatch, app_module):
    """Test /validation/errors returns current validation errors."""
    sample_errors = [{"id": "e1", "message": "bad"}, {"id": "e2", "message": "worse"}]
    monkeypatch.setattr(app_module, "get_validation_errors", lambda: sample_errors)
    resp = client.get("/validation/errors")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_errors"] == len(sample_errors)
    assert data["errors"] == sample_errors


def test_delete_validation_errors_calls_clear(client, monkeypatch, app_module):
    """Test /validation/errors DELETE clears validation errors and returns confirmation."""
    mock_clear = Mock()
    monkeypatch.setattr(app_module, "clear_validation_errors", mock_clear)
    resp = client.delete("/validation/errors")
    assert resp.status_code == 200
    assert resp.get_json()["message"] == "Validation errors cleared"
    assert mock_clear.call_count == 1