import time
from datetime import datetime, timedelta
from unittest.mock import Mock, patch

import pytest
from flask import Flask, g, jsonify

from src.correlation_middleware import (
    CORRELATION_ID_HEADER,
    CorrelationIDMiddleware,
    cleanup_old_traces,
    get_all_traces,
    get_traces,
    store_trace,
    trace_storage,
)


@pytest.fixture
def middleware_instance():
    """Create CorrelationIDMiddleware instance for testing"""
    return CorrelationIDMiddleware()


@pytest.fixture
def flask_app():
    """Create a Flask app for testing"""
    app = Flask(__name__)
    return app


@pytest.fixture(autouse=True)
def reset_trace_storage(monkeypatch):
    """Reset trace_storage for isolation between tests"""
    new_storage = {}
    monkeypatch.setattr("src.correlation_middleware.trace_storage", new_storage)
    yield
    new_storage.clear()


def test_CorrelationIDMiddleware___init___with_app_calls_init_app(flask_app):
    """Ensure __init__ calls init_app when app is provided"""
    with patch.object(CorrelationIDMiddleware, "init_app") as mock_init:
        middleware = CorrelationIDMiddleware(app=flask_app)
        assert middleware.app is flask_app
        mock_init.assert_called_once_with(flask_app)


def test_CorrelationIDMiddleware___init___without_app(middleware_instance):
    """Ensure __init__ without app sets app to None"""
    m = CorrelationIDMiddleware()
    assert m.app is None


def test_CorrelationIDMiddleware_init_app_registers_hooks(flask_app, middleware_instance):
    """Verify that init_app registers before and after request handlers and sets correlation_start_time"""
    middleware_instance.init_app(flask_app)

    # Flask stores before/after request functions keyed by blueprint name (None for app)
    assert middleware_instance.before_request in flask_app.before_request_funcs.get(None, [])
    assert middleware_instance.after_request in flask_app.after_request_funcs.get(None, [])
    assert hasattr(flask_app, "correlation_start_time")
    assert flask_app.correlation_start_time is None


def test_CorrelationIDMiddleware_before_request_sets_g_values(flask_app, middleware_instance, monkeypatch):
    """before_request should set g.correlation_id and g.request_start_time"""
    middleware_instance.init_app(flask_app)

    monkeypatch.setattr(
        middleware_instance,
        "extract_or_generate_correlation_id",
        lambda req: "test-correlation-12345",
    )

    with flask_app.test_request_context("/test-endpoint", method="GET"):
        middleware_instance.before_request()
        assert g.correlation_id == "test-correlation-12345"
        assert isinstance(g.request_start_time, float)
        assert g.request_start_time > 0.0


def test_CorrelationIDMiddleware_after_request_adds_header_and_stores_trace(flask_app, middleware_instance):
    """after_request should add correlation header and store trace with expected fields"""
    middleware_instance.init_app(flask_app)

    with flask_app.test_request_context("/foo", method="GET"):
        # Setup g context as if before_request has run
        g.correlation_id = "cid-1234567890"
        g.request_start_time = time.time() - 0.01  # ensure positive duration

        response = flask_app.make_response(("OK", 201))

        with patch("src.correlation_middleware.store_trace") as mock_store:
            result = middleware_instance.after_request(response)

            assert result is response
            assert response.headers[CORRELATION_ID_HEADER] == "cid-1234567890"
            mock_store.assert_called_once()

            args, kwargs = mock_store.call_args
            assert args[0] == "cid-1234567890"
            trace_data = args[1]

            # Validate required trace fields
            assert trace_data["service"] == "python-reviewer"
            assert trace_data["method"] == "GET"
            assert trace_data["path"] == "/foo"
            # timestamp should be an ISO formatted string
            assert isinstance(trace_data["timestamp"], str)
            assert trace_data["correlation_id"] == "cid-1234567890"
            assert isinstance(trace_data["duration_ms"], float) or isinstance(trace_data["duration_ms"], int)
            assert trace_data["duration_ms"] >= 0
            assert trace_data["status"] == 201


def test_CorrelationIDMiddleware_after_request_without_correlation_id(flask_app, middleware_instance):
    """after_request should not add header or store trace if no correlation_id in g"""
    middleware_instance.init_app(flask_app)

    with flask_app.test_request_context("/bar", method="POST"):
        response = flask_app.make_response(("OK", 200))

        with patch("src.correlation_middleware.store_trace") as mock_store:
            result = middleware_instance.after_request(response)
            assert result is response
            assert CORRELATION_ID_HEADER not in response.headers
            mock_store.assert_not_called()


def test_CorrelationIDMiddleware_extract_or_generate_correlation_id_uses_existing_valid(middleware_instance):
    """extract_or_generate_correlation_id should return existing valid header value"""
    class DummyRequest:
        def __init__(self, headers):
            self.headers = headers

    req = DummyRequest(headers={CORRELATION_ID_HEADER: "valid-abcdef12"})
    result = middleware_instance.extract_or_generate_correlation_id(req)
    assert result == "valid-abcdef12"


def test_CorrelationIDMiddleware_extract_or_generate_correlation_id_generates_when_invalid(middleware_instance, monkeypatch):
    """extract_or_generate_correlation_id should generate new ID when existing is invalid"""
    class DummyRequest:
        def __init__(self, headers):
            self.headers = headers

    req = DummyRequest(headers={CORRELATION_ID_HEADER: "short"})
    monkeypatch.setattr(middleware_instance, "generate_correlation_id", lambda: "generated-1234567890")
    result = middleware_instance.extract_or_generate_correlation_id(req)
    assert result == "generated-1234567890"


def test_CorrelationIDMiddleware_generate_correlation_id_format(middleware_instance):
    """generate_correlation_id should produce a reasonably formatted ID"""
    cid = middleware_instance.generate_correlation_id()
    assert isinstance(cid, str)
    assert "py" in cid
    assert "-" in cid
    # Should be valid by the middleware validator
    assert middleware_instance.is_valid_correlation_id(cid) is True


def test_CorrelationIDMiddleware_is_valid_correlation_id_cases(middleware_instance):
    """is_valid_correlation_id should validate type, length, and allowed characters"""
    assert middleware_instance.is_valid_correlation_id(123) is False  # non-string
    assert middleware_instance.is_valid_correlation_id("shortid") is False  # too short (<10)
    assert middleware_instance.is_valid_correlation_id("a" * 101) is False  # too long (>100)
    assert middleware_instance.is_valid_correlation_id("invalid id") is False  # space not allowed
    assert middleware_instance.is_valid_correlation_id("invalid@id") is False  # @ not allowed
    assert middleware_instance.is_valid_correlation_id("abc-DEF_1234") is True  # valid, length >= 10


def test_store_trace_appends_and_get_traces_returns_copy():
    """store_trace should append traces and get_traces should return a copy"""
    now_iso = datetime.now().isoformat()
    trace1 = {
        "timestamp": now_iso,
        "path": "/a",
        "method": "GET",
        "service": "python-reviewer",
        "correlation_id": "cid1",
        "duration_ms": 1.23,
        "status": 200,
    }
    trace2 = {
        "timestamp": now_iso,
        "path": "/b",
        "method": "POST",
        "service": "python-reviewer",
        "correlation_id": "cid1",
        "duration_ms": 2.34,
        "status": 201,
    }

    store_trace("cid1", trace1)
    store_trace("cid1", trace2)

    assert "cid1" in trace_storage
    assert len(trace_storage["cid1"]) == 2

    returned = get_traces("cid1")
    assert returned == trace_storage["cid1"]
    assert returned is not trace_storage["cid1"]

    # Mutate returned list and ensure original is unaffected
    returned.append({"timestamp": now_iso})
    assert len(trace_storage["cid1"]) == 2


def test_cleanup_old_traces_removes_old_and_keeps_recent():
    """cleanup_old_traces should remove entries older than 1 hour and keep recent entries"""
    old_time = (datetime.now() - timedelta(hours=2)).isoformat()
    new_time = datetime.now().isoformat()

    trace_storage["old"] = [
        {
            "timestamp": old_time,
            "path": "/old",
            "method": "GET",
            "service": "python-reviewer",
            "correlation_id": "old",
            "duration_ms": 10.0,
            "status": 200,
        }
    ]
    trace_storage["new"] = [
        {
            "timestamp": new_time,
            "path": "/new",
            "method": "GET",
            "service": "python-reviewer",
            "correlation_id": "new",
            "duration_ms": 5.0,
            "status": 200,
        }
    ]

    cleanup_old_traces()

    assert "old" not in trace_storage
    assert "new" in trace_storage


def test_get_all_traces_returns_copies():
    """get_all_traces should return copies of trace lists to prevent external mutation"""
    now_iso = datetime.now().isoformat()
    trace_storage["cidA"] = [{"timestamp": now_iso, "service": "python-reviewer", "path": "/", "method": "GET", "correlation_id": "cidA", "duration_ms": 1.0, "status": 200}]
    trace_storage["cidB"] = [{"timestamp": now_iso, "service": "python-reviewer", "path": "/b", "method": "POST", "correlation_id": "cidB", "duration_ms": 2.0, "status": 201}]

    all_traces = get_all_traces()
    assert all_traces == trace_storage
    assert all_traces is not trace_storage
    assert all_traces["cidA"] is not trace_storage["cidA"]

    # Mutate returned lists; original should remain unchanged
    all_traces["cidA"].append({"timestamp": now_iso})
    assert len(trace_storage["cidA"]) == 1


def test_integration_request_flow_sets_header_and_traces(flask_app, monkeypatch):
    """End-to-end: Middleware sets header and stores trace after a real request"""
    app = flask_app
    middleware = CorrelationIDMiddleware()
    middleware.init_app(app)

    @app.route("/ping", methods=["GET"])
    def ping():
        return jsonify(ok=True), 202

    # Ensure generator is deterministic for test when no header provided
    monkeypatch.setattr(middleware, "generate_correlation_id", lambda: "generated-fixed-123456")

    with app.test_client() as client:
        # Case 1: Provide incoming correlation header (should be echoed)
        incoming_id = "incoming-valid-123456"
        resp = client.get("/ping", headers={CORRELATION_ID_HEADER: incoming_id})
        assert resp.status_code == 202
        assert resp.headers[CORRELATION_ID_HEADER] == incoming_id

        traces = get_traces(incoming_id)
        assert len(traces) == 1
        trace = traces[0]
        assert trace["path"] == "/ping"
        assert trace["method"] == "GET"
        assert trace["status"] == 202
        assert trace["service"] == "python-reviewer"

        # Case 2: No header; generated ID should be used and echoed
        resp2 = client.get("/ping")
        assert resp2.status_code == 202
        assert resp2.headers[CORRELATION_ID_HEADER] == "generated-fixed-123456"

        traces2 = get_traces("generated-fixed-123456")
        assert len(traces2) == 1
        assert traces2[0]["path"] == "/ping"


def test_CorrelationIDMiddleware_is_valid_handles_non_string(middleware_instance):
    """is_valid_correlation_id should gracefully handle non-string inputs without raising"""
    assert middleware_instance.is_valid_correlation_id(None) is False
    assert middleware_instance.is_valid_correlation_id(0) is False
    assert middleware_instance.is_valid_correlation_id(object()) is False