import pytest
from unittest.mock import Mock, patch, ANY
from types import SimpleNamespace
from flask import Flask, g, Response

from src.correlation_middleware import CorrelationIDMiddleware


@pytest.fixture
def flask_app():
    """Create a Flask app for testing."""
    app = Flask(__name__)
    return app


@pytest.fixture
def middleware_unbound():
    """Create a CorrelationIDMiddleware instance without binding to an app."""
    return CorrelationIDMiddleware()


@pytest.fixture
def middleware(flask_app):
    """Create a CorrelationIDMiddleware instance bound to a Flask app with a simple route."""
    mw = CorrelationIDMiddleware(flask_app)

    @flask_app.route("/ok", methods=["GET"])
    def ok():
        return "OK", 200

    return mw


@pytest.fixture
def client(flask_app, middleware):
    """Flask test client with middleware attached."""
    return flask_app.test_client()


def test_CorrelationIDMiddleware___init___with_app_calls_init_app():
    """Ensure __init__ calls init_app when app is provided."""
    app_mock = Mock()
    with patch("src.correlation_middleware.CorrelationIDMiddleware.init_app") as mock_init_app:
        mw = CorrelationIDMiddleware(app=app_mock)
        assert isinstance(mw, CorrelationIDMiddleware)
        mock_init_app.assert_called_once_with(app_mock)


def test_CorrelationIDMiddleware___init___without_app_does_not_call_init_app():
    """Ensure __init__ does not call init_app when app is None."""
    with patch("src.correlation_middleware.CorrelationIDMiddleware.init_app") as mock_init_app:
        mw = CorrelationIDMiddleware(app=None)
        assert isinstance(mw, CorrelationIDMiddleware)
        mock_init_app.assert_not_called()


def test_CorrelationIDMiddleware_init_app_registers_hooks_and_sets_attribute(middleware_unbound):
    """Verify init_app registers before/after hooks and sets correlation_start_time attribute."""
    app_mock = SimpleNamespace(
        before_request=Mock(),
        after_request=Mock(),
    )

    middleware_unbound.init_app(app_mock)  # type: ignore[arg-type]
    app_mock.before_request.assert_called_once()
    app_mock.after_request.assert_called_once()
    # The exact callable is less important; ensure callables are provided
    args_before = app_mock.before_request.call_args[0]
    args_after = app_mock.after_request.call_args[0]
    assert callable(args_before[0])
    assert callable(args_after[0])

    # Attribute added to the app
    assert hasattr(app_mock, "correlation_start_time")
    assert app_mock.correlation_start_time is None


def test_CorrelationIDMiddleware_extract_or_generate_correlation_id_returns_existing_when_valid(middleware_unbound):
    """If a valid correlation header exists, it should be returned as-is."""
    valid_id = "abcde-12345"
    request_mock = SimpleNamespace(headers={"X-Correlation-ID": valid_id})
    cid = middleware_unbound.extract_or_generate_correlation_id(request_mock)
    assert cid == valid_id


def test_CorrelationIDMiddleware_extract_or_generate_correlation_id_generates_when_missing(middleware_unbound):
    """If header is missing, a new correlation ID is generated."""
    request_mock = SimpleNamespace(headers={})
    with patch("src.correlation_middleware.CorrelationIDMiddleware.generate_correlation_id", return_value="generated-xyz"):
        cid = middleware_unbound.extract_or_generate_correlation_id(request_mock)
        assert cid == "generated-xyz"


def test_CorrelationIDMiddleware_extract_or_generate_correlation_id_generates_when_invalid(middleware_unbound):
    """If header is present but invalid, a new correlation ID is generated."""
    request_mock = SimpleNamespace(headers={"X-Correlation-ID": "bad id with spaces"})
    with patch("src.correlation_middleware.CorrelationIDMiddleware.generate_correlation_id", return_value="generated-abc"):
        cid = middleware_unbound.extract_or_generate_correlation_id(request_mock)
        assert cid == "generated-abc"


def test_CorrelationIDMiddleware_extract_or_generate_handles_non_string_header_gracefully(middleware_unbound):
    """Non-string header values should be treated as invalid and generate a new ID."""
    request_mock = SimpleNamespace(headers={"X-Correlation-ID": b"bytes-value"})
    with patch("src.correlation_middleware.CorrelationIDMiddleware.generate_correlation_id", return_value="gen-non-string"):
        cid = middleware_unbound.extract_or_generate_correlation_id(request_mock)
        assert cid == "gen-non-string"


def test_CorrelationIDMiddleware_is_valid_correlation_id_various(middleware_unbound):
    """Validate boundaries and invalid characters for correlation IDs."""
    # Non-string
    assert middleware_unbound.is_valid_correlation_id(123) is False  # type: ignore[arg-type]

    # Too short
    assert middleware_unbound.is_valid_correlation_id("short123") is False

    # Exactly 10 chars
    assert middleware_unbound.is_valid_correlation_id("abcdefghij") is True

    # Exactly 100 chars
    assert middleware_unbound.is_valid_correlation_id("a" * 100) is True

    # Too long (101)
    assert middleware_unbound.is_valid_correlation_id("a" * 101) is False

    # Invalid characters
    assert middleware_unbound.is_valid_correlation_id("bad id") is False
    assert middleware_unbound.is_valid_correlation_id("bad!id") is False

    # Valid with underscores and hyphens
    assert middleware_unbound.is_valid_correlation_id("abc_DEF-12345") is True


def test_CorrelationIDMiddleware_generate_correlation_id_format_and_uniqueness(middleware_unbound):
    """Generated correlation IDs should follow the expected format and be valid."""
    # Fixed time to make format deterministic
    with patch("src.correlation_middleware.time.time", return_value=1700000000.123456):
        cid = middleware_unbound.generate_correlation_id()
        assert isinstance(cid, str)
        # "1700000000-py-23456" given our fixed time
        assert cid.startswith("1700000000-py-")
        # Ensure validity
        assert middleware_unbound.is_valid_correlation_id(cid) is True

    # Subsequent calls should produce different values (use differing times)
    with patch("src.correlation_middleware.time.time", side_effect=[1700000000.1, 1700000001.2]):
        cid1 = middleware_unbound.generate_correlation_id()
        cid2 = middleware_unbound.generate_correlation_id()
        assert cid1 != cid2


def test_CorrelationIDMiddleware_before_request_sets_g_values(flask_app, middleware):
    """before_request should set g.correlation_id and g.request_start_time."""
    valid_id = "valid-id-12345"
    with flask_app.test_request_context("/path", headers={"X-Correlation-ID": valid_id}):
        with patch("src.correlation_middleware.time.time", return_value=1234.5):
            middleware.before_request()
            assert getattr(g, "correlation_id", None) == valid_id
            assert getattr(g, "request_start_time", None) == 1234.5


def test_CorrelationIDMiddleware_after_request_sets_header_and_stores_trace(flask_app, middleware, client):
    """after_request should set the response header and store trace data with accurate duration."""
    # Patch time to control duration: before = 1000.0, after = 1000.123456 -> 123.456ms -> 123.46
    with patch("src.correlation_middleware.time.time", side_effect=[1000.0, 1000.123456]):
        with patch("src.correlation_middleware.store_trace") as mock_store_trace:
            rv = client.get("/ok", headers={"X-Correlation-ID": "abcde-12345"})
            assert rv.status_code == 200
            assert rv.headers.get("X-Correlation-ID") == "abcde-12345"
            mock_store_trace.assert_called_once()
            called_cid, trace_data = mock_store_trace.call_args[0]
            assert called_cid == "abcde-12345"
            assert isinstance(trace_data, dict)
            assert trace_data["service"] == "python-reviewer"
            assert trace_data["method"] == "GET"
            assert trace_data["path"] == "/ok"
            assert trace_data["status"] == 200
            assert trace_data["duration_ms"] == 123.46
            assert "timestamp" in trace_data


def test_CorrelationIDMiddleware_after_request_without_correlation_id_does_not_set_header_or_store(flask_app, middleware):
    """after_request should not set header or store trace when no correlation_id is present."""
    with flask_app.test_request_context("/no-cid"):
        # Ensure g has no correlation_id
        if hasattr(g, "correlation_id"):
            delattr(g, "correlation_id")
        response = Response("NOP", status=204)
        with patch("src.correlation_middleware.store_trace") as mock_store_trace:
            result = middleware.after_request(response)
            assert result.status_code == 204
            assert result.headers.get("X-Correlation-ID") is None
            mock_store_trace.assert_not_called()


def test_CorrelationIDMiddleware_after_request_when_request_start_missing_uses_current_time(flask_app, middleware):
    """If request_start_time is missing, duration should be computed from current time resulting in ~0 ms when times are equal."""
    with flask_app.test_request_context("/no-start"):
        g.correlation_id = "valid-cid-00123"
        response = Response("OK", status=200)
        with patch("src.correlation_middleware.time.time", return_value=9999.0):
            with patch("src.correlation_middleware.store_trace") as mock_store_trace:
                result = middleware.after_request(response)
                assert result.headers.get("X-Correlation-ID") == "valid-cid-00123"
                mock_store_trace.assert_called_once()
                _, trace_data = mock_store_trace.call_args[0]
                assert trace_data["duration_ms"] == 0.0


def test_CorrelationIDMiddleware_integration_generates_when_invalid_header(flask_app, middleware, client):
    """End-to-end: invalid header should be replaced with a generated one and stored."""
    with patch("src.correlation_middleware.CorrelationIDMiddleware.generate_correlation_id", return_value="gen-id-12345"):
        with patch("src.correlation_middleware.store_trace") as mock_store_trace:
            rv = client.get("/ok", headers={"X-Correlation-ID": "invalid header value"})
            assert rv.status_code == 200
            assert rv.headers.get("X-Correlation-ID") == "gen-id-12345"
            mock_store_trace.assert_called_once()
            called_cid, _ = mock_store_trace.call_args[0]
            assert called_cid == "gen-id-12345"