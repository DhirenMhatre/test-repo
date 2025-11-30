import pytest
from unittest.mock import patch
from flask import Flask, g, request, Response

from src.correlation_middleware import (
    CorrelationIDMiddleware,
    CORRELATION_ID_HEADER,
    store_trace,
    cleanup_old_traces,
    get_traces,
    get_all_traces,
    trace_storage,
    trace_lock,
)


@pytest.fixture
def flask_app():
    """Create a Flask app for testing."""
    app = Flask(__name__)
    app.testing = True
    return app


@pytest.fixture
def middleware_instance():
    """Create a CorrelationIDMiddleware instance without initializing app."""
    return CorrelationIDMiddleware()


@pytest.fixture
def initialized_app(flask_app, middleware_instance):
    """Initialize the middleware with the Flask app."""
    middleware_instance.init_app(flask_app)
    return flask_app, middleware_instance


@pytest.fixture(autouse=True)
def clear_trace_store():
    """Clear trace storage before and after each test to ensure isolation."""
    with trace_lock:
        trace_storage.clear()
    yield
    with trace_lock:
        trace_storage.clear()


def test_CorrelationIDMiddleware___init___with_app_registers_hooks(flask_app):
    """Test __init__ with app registers before and after request hooks and sets app attribute."""
    middleware = CorrelationIDMiddleware(flask_app)
    assert middleware.app is flask_app
    funcs_before = flask_app.before_request_funcs.get(None, [])
    funcs_after = flask_app.after_request_funcs.get(None, [])
    assert middleware.before_request in funcs_before
    assert middleware.after_request in funcs_after
    assert hasattr(flask_app, "correlation_start_time")
    assert flask_app.correlation_start_time is None


def test_CorrelationIDMiddleware___init___without_app(middleware_instance):
    """Test __init__ without app does not register hooks."""
    # No app is provided; just ensure instance is created properly
    assert isinstance(middleware_instance, CorrelationIDMiddleware)
    assert middleware_instance.app is None


def test_CorrelationIDMiddleware_init_app_registers_hooks(flask_app, middleware_instance):
    """Test init_app registers hooks on the Flask app."""
    middleware_instance.init_app(flask_app)
    funcs_before = flask_app.before_request_funcs.get(None, [])
    funcs_after = flask_app.after_request_funcs.get(None, [])
    assert middleware_instance.before_request in funcs_before
    assert middleware_instance.after_request in funcs_after
    assert hasattr(flask_app, "correlation_start_time")
    assert flask_app.correlation_start_time is None


def test_CorrelationIDMiddleware_before_request_sets_values(initialized_app):
    """Test before_request sets correlation_id and request_start_time on flask.g."""
    app, middleware = initialized_app
    with app.test_request_context("/test"):
        middleware.before_request()
        assert hasattr(g, "correlation_id")
        assert isinstance(g.correlation_id, str)
        assert hasattr(g, "request_start_time")
        assert isinstance(g.request_start_time, float)


def test_CorrelationIDMiddleware_extract_or_generate_correlation_id_uses_header(flask_app, middleware_instance):
    """Test extract_or_generate_correlation_id uses a valid incoming header."""
    valid_id = "valid_ID-12345"
    with flask_app.test_request_context("/test", headers={CORRELATION_ID_HEADER: valid_id}):
        cid = middleware_instance.extract_or_generate_correlation_id(request)
        assert cid == valid_id


def test_CorrelationIDMiddleware_extract_or_generate_correlation_id_invalid_generates_new(flask_app, middleware_instance):
    """Test extract_or_generate_correlation_id generates a new ID when header is invalid."""
    bad_id = "short"
    with patch("src.correlation_middleware.time.time", side_effect=[1700000000.123456, 1700000000.123456]):
        with flask_app.test_request_context("/test", headers={CORRELATION_ID_HEADER: bad_id}):
            cid = middleware_instance.extract_or_generate_correlation_id(request)
            # Expected generated format based on mocked time
            # int(1700000000.123456) = 1700000000
            # int(1700000000.123456 * 1_000_000) % 100000 = 1_700_000_000_123_456 % 100000 = 23456
            assert cid == "1700000000-py-23456"
            assert cid != bad_id


def test_CorrelationIDMiddleware_generate_correlation_id_format(middleware_instance):
    """Test generate_correlation_id returns expected format given mocked time."""
    with patch("src.correlation_middleware.time.time", side_effect=[1700000000.123456, 1700000000.123456]):
        cid = middleware_instance.generate_correlation_id()
        assert cid == "1700000000-py-23456"


def test_CorrelationIDMiddleware_is_valid_correlation_id_various(middleware_instance):
    """Test is_valid_correlation_id with various edge cases."""
    assert middleware_instance.is_valid_correlation_id(123) is False  # non-string
    assert middleware_instance.is_valid_correlation_id("short") is False  # too short (<10)
    assert middleware_instance.is_valid_correlation_id("a" * 101) is False  # too long (>100)
    assert middleware_instance.is_valid_correlation_id("abc!defghij") is False  # invalid char '!'
    assert middleware_instance.is_valid_correlation_id("abcdefghij") is True  # exactly 10, valid chars
    assert middleware_instance.is_valid_correlation_id("abc_123-DEFghi") is True  # valid mixed chars


def test_CorrelationIDMiddleware_after_request_sets_header_and_stores_trace_integration(initialized_app):
    """Test full request cycle sets response header and stores trace data."""
    app, _ = initialized_app

    @app.route("/ping")
    def ping():
        return "pong", 200

    client = app.test_client()
    resp = client.get("/ping")
    assert resp.status_code == 200
    # Response should contain correlation ID header
    assert CORRELATION_ID_HEADER in resp.headers
    correlation_id = resp.headers[CORRELATION_ID_HEADER]
    assert isinstance(correlation_id, str) and correlation_id

    traces = get_traces(correlation_id)
    assert len(traces) == 1
    trace = traces[0]
    # Basic keys existence assertions
    for key in ["service", "method", "path", "timestamp", "correlation_id", "duration_ms", "status"]:
        assert key in trace
    assert trace["service"] == "python-reviewer"
    assert trace["method"] == "GET"
    assert trace["path"] == "/ping"
    assert trace["status"] == 200
    assert trace["correlation_id"] == correlation_id
    assert isinstance(trace["duration_ms"], float)


def test_CorrelationIDMiddleware_after_request_respects_existing_valid_header(initialized_app):
    """Test that a valid incoming correlation ID is echoed back in response and used for trace storage."""
    app, _ = initialized_app

    @app.route("/echo")
    def echo():
        return "ok", 201

    client = app.test_client()
    valid_id = "existing_valid-12345"
    resp = client.get("/echo", headers={CORRELATION_ID_HEADER: valid_id})
    assert resp.status_code == 201
    assert resp.headers.get(CORRELATION_ID_HEADER) == valid_id

    traces = get_traces(valid_id)
    assert len(traces) == 1
    assert traces[0]["correlation_id"] == valid_id
    assert traces[0]["status"] == 201


def test_CorrelationIDMiddleware_after_request_ignores_invalid_header_and_generates_new(initialized_app):
    """Test that an invalid incoming correlation ID is not used and a new one is generated."""
    app, _ = initialized_app

    @app.route("/new")
    def new_route():
        return "ok", 200

    client = app.test_client()
    resp = client.get("/new", headers={CORRELATION_ID_HEADER: "bad"})
    assert resp.status_code == 200
    assert resp.headers.get(CORRELATION_ID_HEADER) != "bad"


def test_CorrelationIDMiddleware_after_request_no_correlation_id_does_not_set_header_or_store(flask_app, middleware_instance):
    """Test after_request when no correlation ID is present in flask.g."""
    middleware_instance.init_app(flask_app)
    with flask_app.test_request_context("/no-cid"):
        # Create a response and invoke after_request without calling before_request
        response = Response("ok", status=200)
        updated = middleware_instance.after_request(response)
        assert CORRELATION_ID_HEADER not in updated.headers
        # No traces should be stored
        assert get_all_traces() == {}


def test_CorrelationIDMiddleware_after_request_propagates_store_exception(flask_app, middleware_instance):
    """Test that after_request propagates exceptions raised by store_trace."""
    middleware_instance.init_app(flask_app)
    with flask_app.test_request_context("/error"):
        # Manually set correlation_id and request_start_time to trigger store_trace
        g.correlation_id = "valid_cid-12345"
        g.request_start_time = 1000.0
        response = Response("err", status=500)
        with patch("src.correlation_middleware.store_trace", side_effect=RuntimeError("boom")):
            with pytest.raises(RuntimeError):
                middleware_instance.after_request(response)


def test_CorrelationIDMiddleware_request_duration_computation_with_mock_time(initialized_app):
    """Test duration_ms calculation using mocked time across the request lifecycle."""
    app, _ = initialized_app

    @app.route("/timed")
    def timed():
        return "timed", 200

    client = app.test_client()

    # Mock the sequence of time.time() calls:
    # generate_correlation_id: call1, call2
    # before_request request_start_time: call3
    # after_request duration measurement: call4
    with patch("src.correlation_middleware.time.time", side_effect=[1000.0, 1000.0, 1000.0, 1002.5]):
        resp = client.get("/timed")
    assert resp.status_code == 200
    cid = resp.headers.get(CORRELATION_ID_HEADER)
    assert cid == "1000-py-0"
    traces = get_traces(cid)
    assert len(traces) == 1
    # Duration should be approximately 2500.0 ms
    assert traces[0]["duration_ms"] == 2500.0


def test_cleanup_old_traces_removes_old_data():
    """Test that cleanup_old_traces removes entries older than one hour."""
    from datetime import datetime, timedelta

    old_cid = "old_cid-12345"
    recent_cid = "recent_cid-12345"

    old_timestamp = (datetime.now() - timedelta(hours=2)).isoformat()
    recent_timestamp = (datetime.now() - timedelta(minutes=30)).isoformat()

    with trace_lock:
        trace_storage[old_cid] = [{"timestamp": old_timestamp}]
        trace_storage[recent_cid] = [{"timestamp": recent_timestamp}]

    cleanup_old_traces()

    with trace_lock:
        assert old_cid not in trace_storage
        assert recent_cid in trace_storage


def test_store_trace_and_get_traces_and_get_all_traces_return_copies():
    """Test storing a trace and that retrieval functions return copies, not references."""
    cid = "copy_test-12345"
    data = {"timestamp": "now", "status": 200}

    store_trace(cid, data)
    assert len(get_traces(cid)) == 1

    # get_traces returns a copy; mutating it should not affect storage
    traces_copy = get_traces(cid)
    traces_copy.append({"timestamp": "later", "status": 201})
    assert len(traces_copy) == 2
    # Original remains unchanged
    assert len(get_traces(cid)) == 1

    # get_all_traces returns dict with list copies
    all_copy = get_all_traces()
    assert cid in all_copy
    all_copy[cid].append({"timestamp": "new", "status": 202})
    # Original remains unchanged
    assert len(get_traces(cid)) == 1