import sys
import types
from typing import List, Dict

# ----- Create stub modules for external dependencies before importing the app -----

# Stub for src.request_validator
request_validator = types.ModuleType("src.request_validator")


class FakeValidationError:
    def __init__(self, code: str, message: str, field: str = None):
        self.code = code
        self.message = message
        self.field = field

    def to_dict(self):
        d = {"code": self.code, "message": self.message}
        if self.field is not None:
            d["field"] = self.field
        return d


# State variables for the stub
request_validator.review_validation_errors: List[FakeValidationError] = []
request_validator.statistics_validation_errors: List[FakeValidationError] = []
request_validator.validation_errors_list: List[Dict] = []
request_validator.sanitized_data_override = None
request_validator.cleared_called_count = 0


def validate_review_request(data):
    return list(request_validator.review_validation_errors)


def validate_statistics_request(data):
    return list(request_validator.statistics_validation_errors)


def sanitize_request_data(data):
    return request_validator.sanitized_data_override if request_validator.sanitized_data_override is not None else data


def get_validation_errors():
    return list(request_validator.validation_errors_list)


def clear_validation_errors():
    request_validator.validation_errors_list = []
    request_validator.cleared_called_count += 1


request_validator.validate_review_request = validate_review_request
request_validator.validate_statistics_request = validate_statistics_request
request_validator.sanitize_request_data = sanitize_request_data
request_validator.get_validation_errors = get_validation_errors
request_validator.clear_validation_errors = clear_validation_errors

sys.modules["src.request_validator"] = request_validator

# Stub for src.code_reviewer
code_reviewer = types.ModuleType("src.code_reviewer")


class FakeIssue:
    def __init__(self, severity: str, line: int, message: str, suggestion: str):
        self.severity = severity
        self.line = line
        self.message = message
        self.suggestion = suggestion


class FakeReviewResult:
    def __init__(self, score: int, issues: List[FakeIssue], suggestions: List[str], complexity_score: float):
        self.score = score
        self.issues = issues
        self.suggestions = suggestions
        self.complexity_score = complexity_score


class CodeReviewer:
    def review_code(self, content: str, language: str):
        if "bad" in content:
            issues = [FakeIssue("HIGH", 1, "Detected bad code pattern", "Avoid using 'bad'")]
            score = 70
            suggestions = ["Consider refactoring", "Add tests"]
            complexity_score = 5.0
        else:
            issues = []
            score = 95
            suggestions = ["Looks good"]
            complexity_score = 1.0
        return FakeReviewResult(score=score, issues=issues, suggestions=suggestions, complexity_score=complexity_score)

    def review_function(self, function_code: str):
        return {"status": "ok", "length": len(function_code), "issues_found": ("bad" in function_code)}


code_reviewer.CodeReviewer = CodeReviewer
sys.modules["src.code_reviewer"] = code_reviewer

# Stub for src.statistics
statistics = types.ModuleType("src.statistics")


class FakeStats:
    def __init__(
        self,
        total_files: int,
        average_score: float,
        total_issues: int,
        issues_by_severity: Dict[str, int],
        average_complexity: float,
        files_with_high_complexity: int,
        total_suggestions: int,
    ):
        self.total_files = total_files
        self.average_score = average_score
        self.total_issues = total_issues
        self.issues_by_severity = issues_by_severity
        self.average_complexity = average_complexity
        self.files_with_high_complexity = files_with_high_complexity
        self.total_suggestions = total_suggestions


class StatisticsAggregator:
    def aggregate_reviews(self, files: List[Dict]):
        return FakeStats(
            total_files=len(files),
            average_score=82.5,
            total_issues=3,
            issues_by_severity={"LOW": 2, "HIGH": 1},
            average_complexity=2.1,
            files_with_high_complexity=1 if len(files) > 0 else 0,
            total_suggestions=4,
        )


statistics.StatisticsAggregator = StatisticsAggregator
sys.modules["src.statistics"] = statistics

# Stub for src.correlation_middleware
correlation_middleware = types.ModuleType("src.correlation_middleware")
from flask import g, request  # noqa: E402


class CorrelationIDMiddleware:
    def __init__(self, app):
        @app.before_request
        def _attach_correlation_id():
            cid = request.headers.get("X-Correlation-ID")
            if cid:
                g.correlation_id = cid


correlation_middleware.traces_store: Dict[str, List[Dict]] = {}


def get_traces(correlation_id: str):
    return list(correlation_middleware.traces_store.get(correlation_id, []))


def get_all_traces():
    all_items = []
    for v in correlation_middleware.traces_store.values():
        all_items.extend(v)
    return all_items


correlation_middleware.CorrelationIDMiddleware = CorrelationIDMiddleware
correlation_middleware.get_traces = get_traces
correlation_middleware.get_all_traces = get_all_traces

sys.modules["src.correlation_middleware"] = correlation_middleware

# ----- Now import the app under test -----
import pytest
from src.app import app  # noqa: E402


@pytest.fixture(autouse=True)
def reset_stubs():
    """Reset stub modules' state before each test."""
    # request_validator
    rv = sys.modules["src.request_validator"]
    rv.review_validation_errors = []
    rv.statistics_validation_errors = []
    rv.validation_errors_list = []
    rv.sanitized_data_override = None
    rv.cleared_called_count = 0
    # correlation_middleware
    cm = sys.modules["src.correlation_middleware"]
    cm.traces_store = {}
    yield


@pytest.fixture
def client():
    """Provide Flask test client with testing mode."""
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_health_check_ok(client):
    """GET /health should return healthy status."""
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "healthy"
    assert data["service"] == "python-reviewer"


def test_review_code_missing_body(client):
    """POST /review with no body should return 400."""
    resp = client.post("/review")  # No JSON body
    assert resp.status_code == 400
    data = resp.get_json()
    assert data["error"] == "Missing request body"


def test_review_code_validation_errors(client):
    """POST /review should return 422 when validation errors exist."""
    rv = sys.modules["src.request_validator"]
    rv.review_validation_errors = [
        FakeValidationError(code="MISSING_FIELD", message="content is required", field="content")
    ]
    payload = {"content": "", "language": "python"}
    resp = client.post("/review", json=payload)
    assert resp.status_code == 422
    data = resp.get_json()
    assert data["error"] == "Validation failed"
    assert isinstance(data["details"], list)
    assert data["details"][0] == {"code": "MISSING_FIELD", "message": "content is required", "field": "content"}


def test_review_code_success_default_correlation(client):
    """POST /review should return review result with correlation_id None when no header is set."""
    payload = {"content": "print('hello world')", "language": "python"}
    resp = client.post("/review", json=payload)
    assert resp.status_code == 200
    data = resp.get_json()
    assert "score" in data and isinstance(data["score"], int)
    assert "issues" in data and isinstance(data["issues"], list)
    assert data["suggestions"] == ["Looks good"]
    assert data["complexity_score"] == 1.0
    assert data["correlation_id"] is None


def test_review_code_propagates_correlation_id(client):
    """POST /review should propagate X-Correlation-ID header to response."""
    payload = {"content": "bad pattern here", "language": "python"}
    headers = {"X-Correlation-ID": "abc-123"}
    resp = client.post("/review", json=payload, headers=headers)
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["correlation_id"] == "abc-123"
    # From stub logic, 'bad' in content triggers one HIGH issue
    assert data["score"] == 70
    assert len(data["issues"]) == 1
    assert data["issues"][0]["severity"] == "HIGH"


@pytest.mark.parametrize(
    "body",
    [
        None,
        {},
        {"other": "field"},
    ],
)
def test_review_function_missing_field(client, body):
    """POST /review/function should return 400 when function_code is missing."""
    if body is None:
        resp = client.post("/review/function")
    else:
        resp = client.post("/review/function", json=body)
    assert resp.status_code == 400
    data = resp.get_json()
    assert data["error"] == "Missing 'function_code' field"


def test_review_function_success(client):
    """POST /review/function should return stubbed analysis result."""
    payload = {"function_code": "def foo():\n    return 1"}
    resp = client.post("/review/function", json=payload)
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "ok"
    assert data["length"] == len(payload["function_code"])
    assert data["issues_found"] is False


def test_statistics_missing_body(client):
    """POST /statistics with no body should return 400."""
    resp = client.post("/statistics")
    assert resp.status_code == 400
    data = resp.get_json()
    assert data["error"] == "Missing request body"


def test_statistics_validation_errors(client):
    """POST /statistics should return 422 when validation fails."""
    rv = sys.modules["src.request_validator"]
    rv.statistics_validation_errors = [FakeValidationError(code="INVALID", message="files is required", field="files")]
    payload = {}
    resp = client.post("/statistics", json=payload)
    assert resp.status_code == 422
    data = resp.get_json()
    assert data["error"] == "Validation failed"
    assert data["details"][0]["code"] == "INVALID"
    assert data["details"][0]["field"] == "files"


def test_statistics_success_with_correlation_id(client):
    """POST /statistics should return aggregated data and propagate correlation id."""
    payload = {"files": [{"name": "a.py", "score": 90}, {"name": "b.py", "score": 75}]}
    headers = {"X-Correlation-ID": "stat-999"}
    resp = client.post("/statistics", json=payload, headers=headers)
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_files"] == 2
    assert data["average_score"] == 82.5
    assert data["total_issues"] == 3
    assert data["issues_by_severity"] == {"LOW": 2, "HIGH": 1}
    assert data["average_complexity"] == 2.1
    assert data["files_with_high_complexity"] == 1
    assert data["total_suggestions"] == 4
    assert data["correlation_id"] == "stat-999"


def test_list_traces_returns_all(client):
    """GET /traces should list all traces from middleware store."""
    cm = sys.modules["src.correlation_middleware"]
    cm.traces_store = {
        "id1": [{"event": "start"}, {"event": "end"}],
        "id2": [{"event": "only"}],
    }
    resp = client.get("/traces")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_traces"] == 3
    assert isinstance(data["traces"], list)
    assert len(data["traces"]) == 3


def test_get_trace_not_found(client):
    """GET /traces/<id> should return 404 when no traces exist for id."""
    resp = client.get("/traces/missing-id")
    assert resp.status_code == 404
    data = resp.get_json()
    assert data["error"] == "No traces found for correlation ID"


def test_get_trace_found(client):
    """GET /traces/<id> should return traces when present."""
    cm = sys.modules["src.correlation_middleware"]
    cm.traces_store = {"cid-123": [{"event": "start"}, {"event": "process"}, {"event": "end"}]}
    resp = client.get("/traces/cid-123")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["correlation_id"] == "cid-123"
    assert data["trace_count"] == 3
    assert isinstance(data["traces"], list)
    assert len(data["traces"]) == 3


def test_list_validation_errors(client):
    """GET /validation/errors should return stored validation errors."""
    rv = sys.modules["src.request_validator"]
    rv.validation_errors_list = [
        {"code": "E1", "message": "error one"},
        {"code": "E2", "message": "error two"},
    ]
    resp = client.get("/validation/errors")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["total_errors"] == 2
    assert data["errors"] == rv.validation_errors_list


def test_delete_validation_errors(client):
    """DELETE /validation/errors should clear stored errors and return confirmation."""
    rv = sys.modules["src.request_validator"]
    rv.validation_errors_list = [{"code": "E1"}, {"code": "E2"}]
    assert len(rv.get_validation_errors()) == 2
    resp = client.delete("/validation/errors")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["message"] == "Validation errors cleared"
    assert rv.get_validation_errors() == []
    assert rv.cleared_called_count == 1