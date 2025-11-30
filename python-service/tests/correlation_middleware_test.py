import sys
import types
import re
from datetime import datetime, timedelta
from unittest.mock import Mock

import pytest

import src.correlation_middleware as cm
from src.correlation_middleware import (
    CorrelationIDMiddleware,
    CORRELATION_ID_HEADER,
    store_trace,
    cleanup_old_traces,
    get_traces,
    get_all_traces,
)


class FakeApp:
    def __init__(self):
        self.before = None
        self.after = None
        self.correlation_start_time = "init"

    def before_request(self, func):
        self.before = func

    def after_request(self, func):
        self.after = func


class FakeRequest:
    def __init__(self, headers=None, method="GET", path="/"):
        self.headers = headers or {}
        self.method = method
        self.path = path


class FakeResponse:
    def __init__(self, status_code=200, headers=None):
        self.status_code = status_code
        self.headers = headers or {}


@pytest.fixture
def middleware():
    """Provide a fresh CorrelationIDMiddleware instance"""
    return CorrelationIDMiddleware()


@pytest.fixture(autouse=True)
def fresh_trace_storage(monkeypatch):
    """Ensure trace_storage is fresh per test"""
    monkeypatch.setattr(cm, "trace_storage", {})
    yield


def install_fake_flask(monkeypatch, request_obj, g_obj):
    """Install a fake 'flask' module with request and g attributes"""
    fake_flask = types.ModuleType("flask")
    fake_flask.request = request_obj
    fake_flask.g = g_obj
    monkeypatch.setitem(sys.modules, "flask", fake_flask)


def test_correlationidmiddleware___init___with_app_registers_handlers():
    """__init__ should call init_app and register before/after handlers when app is provided"""
    app = FakeApp()
    mw = CorrelationIDMiddleware(app=app)

    assert app.before is mw.before_request
    assert app.after is mw.after_request
    assert hasattr(app, "correlation_start_time")
    assert app.correlation_start_time is None
    assert mw.app is app


def test_correlationidmiddleware_init_app_registers_handlers(middleware):
    """init_app should register hooks on provided app"""
    app = FakeApp()
    middleware.init_app(app)

    assert app.before is middleware.before_request
    assert app.after is middleware.after_request
    assert app.correlation_start_time is None


def test_correlationidmiddleware_is_valid_correlation_id_various(middleware):
    """is_valid_correlation_id should validate length, type, and allowed characters"""
    assert middleware.is_valid_correlation_id(12345) is False  # non-string
    assert middleware.is_valid_correlation_id("short") is False  # too short
    assert middleware.is_valid_correlation_id("a" * 101) is False  # too long
    assert middleware.is_valid_correlation_id("invalid!char") is False  # invalid char
    assert middleware.is_valid_correlation_id("valid_123-ABC") is True  # valid


def test_correlationidmiddleware_generate_correlation_id_format(middleware):
    """generate_correlation_id should produce a sane token that matches expected pattern and passes validation"""
    cid = middleware.generate_correlation_id()
    assert isinstance(cid, str)
    assert 10 <= len(cid) <= 100
    assert re.match(r"^\d+-py-\d+$", cid) is not None
    assert middleware.is_valid_correlation_id(cid) is True


def test_correlationidmiddleware_extract_or_generate_correlation_id_uses_existing_when_valid(middleware):
    """extract_or_generate_correlation_id should return header value when present and valid"""
    request = FakeRequest(headers={CORRELATION_ID_HEADER: "valid-123456"})
    result = middleware.extract_or_generate_correlation_id(request)
    assert result == "valid-123456"


def test_correlationidmiddleware_extract_or_generate_correlation_id_generates_when_invalid(middleware, monkeypatch):
    """extract_or_generate_correlation_id should generate a new ID if existing is invalid"""
    request = FakeRequest(headers={CORRELATION_ID_HEADER: "bad id!"})
    monkeypatch.setattr(middleware, "generate_correlation_id", Mock(return_value="gen-1234567890"))
    result = middleware.extract_or_generate_correlation_id(request)
    assert result == "gen-1234567890"


def test_correlationidmiddleware_extract_or_generate_correlation_id_generates_when_missing(middleware, monkeypatch):
    """extract_or_generate_correlation_id should generate a new ID if header is missing"""
    request = FakeRequest(headers={})
    monkeypatch.setattr(middleware, "generate_correlation_id", Mock(return_value="gen-abcdef1234"))
    result = middleware.extract_or_generate_correlation_id(request)
    assert result == "gen-abcdef1234"


def test_correlationidmiddleware_before_request_sets_context_and_time(middleware, monkeypatch):
    """before_request should set g.correlation_id and g.request_start_time"""
    # Prepare fake flask module
    fake_request = FakeRequest(headers={})
    fake_g = types.SimpleNamespace()
    install_fake_flask(monkeypatch, fake_request, fake_g)

    # Control time and extracted ID
    monkeypatch.setattr(cm.time, "time", Mock(return_value=1000.0))
    monkeypatch.setattr(middleware, "extract_or_generate_correlation_id", Mock(return_value="cid-0000000000"))

    middleware.before_request()

    assert getattr(fake_g, "correlation_id") == "cid-0000000000"
    assert getattr(fake_g, "request_start_time") == 1000.0
    middleware.extract_or_generate_correlation_id.assert_called_once()


def test_correlationidmiddleware_after_request_sets_header_and_stores_trace(middleware, monkeypatch):
    """after_request should set correlation header and store trace with duration"""
    # Install fake flask with request and g
    fake_request = FakeRequest(headers={}, method="POST", path="/items")
    fake_g = types.SimpleNamespace(correlation_id="corr-1234567890", request_start_time=100.0)
    install_fake_flask(monkeypatch, fake_request, fake_g)

    # Mock time and store_trace
    monkeypatch.setattr(cm.time, "time", Mock(return_value=200.0))
    mock_store = Mock()
    monkeypatch.setattr(cm, "store_trace", mock_store)

    response = FakeResponse(status_code=201)
    result = middleware.after_request(response)

    assert result is response
    assert response.headers.get(CORRELATION_ID_HEADER) == "corr-1234567890"

    # Verify store_trace was called with correct correlation id and trace data
    mock_store.assert_called_once()
    call_args = mock_store.call_args[0]
    assert call_args[0] == "corr-1234567890"
    trace = call_args[1]
    assert trace["service"] == "python-reviewer"
    assert trace["method"] == "POST"
    assert trace["path"] == "/items"
    assert trace["status"] == 201
    # duration should be (200 - 100) * 1000 = 100000.0
    assert trace["duration_ms"] == 100000.0
    # timestamp should be ISO format
    datetime.fromisoformat(trace["timestamp"])


def test_correlationidmiddleware_after_request_no_correlation_id_does_nothing(middleware, monkeypatch):
    """after_request should not set header or store trace if correlation id is absent"""
    fake_request = FakeRequest(headers={}, method="GET", path="/nothing")
    fake_g = types.SimpleNamespace()  # no correlation_id
    install_fake_flask(monkeypatch, fake_request, fake_g)

    mock_store = Mock()
    monkeypatch.setattr(cm, "store_trace", mock_store)

    response = FakeResponse(status_code=200)
    result = middleware.after_request(response)

    assert result is response
    assert CORRELATION_ID_HEADER not in response.headers
    mock_store.assert_not_called()


def test_store_trace_and_get_traces_and_get_all_traces(monkeypatch):
    """store_trace should persist traces; getters should return copies"""
    # Fresh storage already ensured by fixture
    now_iso = datetime.now().isoformat()
    cid1 = "cid-1"
    cid2 = "cid-2"

    store_trace(cid1, {"timestamp": now_iso, "k": 1})
    store_trace(cid1, {"timestamp": now_iso, "k": 2})
    store_trace(cid2, {"timestamp": now_iso, "k": 3})

    traces1 = get_traces(cid1)
    assert len(traces1) == 2
    assert traces1[0]["k"] == 1 and traces1[1]["k"] == 2

    all_traces = get_all_traces()
    assert set(all_traces.keys()) == {cid1, cid2}
    assert len(all_traces[cid2]) == 1

    # Ensure returned lists are copies (mutating does not affect storage)
    traces1.append({"timestamp": now_iso, "k": 999})
    assert len(get_traces(cid1)) == 2


def test_cleanup_old_traces_removes_outdated(monkeypatch):
    """cleanup_old_traces should remove correlation IDs whose oldest trace is older than cutoff"""
    # Arrange: create one old and one recent trace list
    old_time = (datetime.now() - timedelta(hours=2)).isoformat()
    recent_time = datetime.now().isoformat()

    cm.trace_storage["old"] = [{"timestamp": old_time, "k": "old"}]
    cm.trace_storage["recent"] = [{"timestamp": recent_time, "k": "new"}]

    cleanup_old_traces()

    assert "old" not in cm.trace_storage
    assert "recent" in cm.trace_storage


def test_correlationidmiddleware_extract_or_generate_correlation_id_handles_missing_headers_gracefully(middleware, monkeypatch):
    """extract_or_generate_correlation_id should not raise when request.headers is missing or None"""
    class WeirdRequest:
        def __init__(self):
            self.headers = None

    req = WeirdRequest()
    monkeypatch.setattr(middleware, "generate_correlation_id", Mock(return_value="gen-special-99999"))
    result = middleware.extract_or_generate_correlation_id(req)
    assert result == "gen-special-99999"