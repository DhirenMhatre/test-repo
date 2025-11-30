import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime

from src.request_validator import (
    ValidationError,
    validate_review_request,
    validate_statistics_request,
    sanitize_input,
    sanitize_request_data,
    contains_null_bytes,
    contains_path_traversal,
    log_validation_errors,
    keep_recent_errors,
    get_validation_errors,
    clear_validation_errors,
    ALLOWED_LANGUAGES,
    MAX_CONTENT_SIZE,
)


@pytest.fixture
def validation_error_instance():
    """Create a ValidationError instance for testing."""
    return ValidationError(field="test_field", reason="test_reason")


@pytest.fixture(autouse=True)
def reset_validation_errors():
    """Ensure validation error log is cleared before and after tests that use it."""
    clear_validation_errors()
    yield
    clear_validation_errors()


def test_ValidationError___init___sets_fields_and_iso_timestamp():
    """Test that ValidationError initialization sets fields and ISO timestamp."""
    fixed_dt = datetime(2024, 1, 1, 12, 34, 56, 789012)
    with patch("src.request_validator.datetime") as mock_datetime:
        mock_datetime.now.return_value = fixed_dt
        err = ValidationError(field="content", reason="is required")
        assert err.field == "content"
        assert err.reason == "is required"
        assert err.timestamp == fixed_dt.isoformat()


def test_ValidationError_to_dict_returns_expected_structure():
    """Test to_dict returns correct dict with field, reason, timestamp."""
    fixed_dt = datetime(2023, 5, 6, 7, 8, 9, 123456)
    with patch("src.request_validator.datetime") as mock_datetime:
        mock_datetime.now.return_value = fixed_dt
        err = ValidationError(field="language", reason="invalid")
        d = err.to_dict()
        assert d["field"] == "language"
        assert d["reason"] == "invalid"
        assert d["timestamp"] == fixed_dt.isoformat()


def test_ValidationError___init___supports_empty_strings():
    """Test that ValidationError accepts empty strings for field and reason."""
    err = ValidationError(field="", reason="")
    d = err.to_dict()
    assert d["field"] == ""
    assert d["reason"] == ""
    # Ensure timestamp is a valid ISO string
    datetime.fromisoformat(d["timestamp"])  # Will raise if invalid


def test_ValidationError___init___propagates_datetime_exception():
    """Test that initialization propagates exceptions from datetime.now()."""
    with patch("src.request_validator.datetime") as mock_datetime:
        mock_datetime.now.side_effect = RuntimeError("boom")
        with pytest.raises(RuntimeError):
            ValidationError(field="x", reason="y")


def test_validate_review_request_missing_content_adds_error_and_logs():
    """Test validate_review_request when content is missing logs a content error."""
    errors = validate_review_request({"language": "python"})
    assert len(errors) == 1
    assert errors[0].field == "content"
    assert "required" in errors[0].reason.lower()
    logged = get_validation_errors()
    assert len(logged) == 1
    assert logged[0]["field"] == "content"


def test_validate_review_request_content_too_large():
    """Test validate_review_request detects oversized content."""
    oversized = "a" * (MAX_CONTENT_SIZE + 1)
    errors = validate_review_request({"content": oversized, "language": "python"})
    assert len(errors) == 1
    assert errors[0].field == "content"
    assert str(MAX_CONTENT_SIZE) in errors[0].reason


def test_validate_review_request_content_with_null_bytes():
    """Test validate_review_request detects null bytes in content."""
    errors = validate_review_request({"content": "abc\x00def", "language": "python"})
    assert len(errors) == 1
    assert errors[0].field == "content"
    assert "null bytes" in errors[0].reason.lower()


def test_validate_review_request_invalid_language():
    """Test validate_review_request detects unsupported language."""
    errors = validate_review_request({"content": "ok", "language": "elixir"})
    assert len(errors) == 1
    assert errors[0].field == "language"
    for lang in ALLOWED_LANGUAGES:
        assert lang in errors[0].reason


def test_validate_review_request_valid_no_errors_no_logging():
    """Test validate_review_request returns no errors and does not log when valid."""
    with patch("src.request_validator.validation_lock", new=MagicMock()) as mock_lock:
        errs = validate_review_request({"content": "ok", "language": ALLOWED_LANGUAGES[0]})
        assert errs == []
        # no logging should happen; lock should not be entered
        assert not mock_lock.__enter__.called
        assert get_validation_errors() == []


@pytest.mark.parametrize(
    "payload,expected_field,expected_substr",
    [
        ({}, "files", "required"),
        ({"files": "not-a-list"}, "files", "array"),
        ({"files": []}, "files", "cannot be empty"),
        ({"files": [0] * 1001}, "files", "cannot exceed"),
    ],
)
def test_validate_statistics_request_invalid_cases(payload, expected_field, expected_substr):
    """Test validate_statistics_request for various invalid inputs."""
    errors = validate_statistics_request(payload)
    assert len(errors) == 1
    assert errors[0].field == expected_field
    assert expected_substr.lower() in errors[0].reason.lower()
    # confirm they were logged
    logged = get_validation_errors()
    assert len(logged) == 1
    assert logged[0]["field"] == expected_field


def test_validate_statistics_request_valid():
    """Test validate_statistics_request returns no errors with valid data."""
    errs = validate_statistics_request({"files": ["a", "b"]})
    assert errs == []
    assert get_validation_errors() == []


def test_sanitize_input_various_control_chars():
    """Test sanitize_input removes disallowed control chars and keeps allowed whitespace."""
    raw = "A\x00B\x07C\nD\rE\tF\x1fG\x7fH\x0bI\x0cJ"
    sanitized = sanitize_input(raw)
    assert sanitized == "ABC\nD\rE\tFGHJI".replace("J", "J").replace("I", "I")
    # Explicitly check that vertical/horizontal tabs (0x0B, 0x0C) are removed
    assert "\x0b" not in sanitized
    assert "\x0c" not in sanitized
    assert "\x00" not in sanitized
    assert "\x1f" not in sanitized
    assert "\x7f" not in sanitized


def test_sanitize_input_non_string_and_none():
    """Test sanitize_input handles non-string inputs and None."""
    assert sanitize_input(None) is None
    assert sanitize_input(123) == "123"
    assert sanitize_input("clean text") == "clean text"


def test_sanitize_request_data_sanitizes_specific_fields_only():
    """Test sanitize_request_data sanitizes content, language, and path keys only."""
    raw = {
        "content": "ok\x00",
        "language": "py\x07thon",
        "path": "../\x00secret",
        "other": "\x00ok",  # should remain as-is if not a string field handled
    }
    sanitized = sanitize_request_data(raw)
    assert sanitized["content"] == "ok"
    assert sanitized["language"] == "python"
    assert sanitized["path"] == "../secret"
    # 'other' is a string but not processed by sanitize_request_data; remains unchanged
    assert sanitized["other"] == "\x00ok"
    # ensure original dict is not mutated
    assert raw["content"] == "ok\x00"


def test_contains_null_bytes_behaviour():
    """Test contains_null_bytes correctly identifies presence of null byte."""
    assert contains_null_bytes("abc\x00def") is True
    assert contains_null_bytes("abcdef") is False


def test_contains_path_traversal_behaviour():
    """Test contains_path_traversal detects traversal patterns."""
    assert contains_path_traversal("../etc/passwd") is True
    assert contains_path_traversal("~/.ssh/id_rsa") is True
    assert contains_path_traversal("safe/path/file.txt") is False


def test_log_validation_errors_uses_lock_and_calls_keep_recent_errors():
    """Test log_validation_errors acquires lock and calls keep_recent_errors when errors exist."""
    with patch("src.request_validator.validation_lock", new=MagicMock()) as mock_lock, \
         patch("src.request_validator.keep_recent_errors") as mock_keep:
        errs = [ValidationError("f", "r")]
        log_validation_errors(errs)
        assert mock_lock.__enter__.called
        mock_keep.assert_called_once()


def test_log_validation_errors_noop_without_errors():
    """Test log_validation_errors does nothing when errors list is empty."""
    with patch("src.request_validator.validation_lock", new=MagicMock()) as mock_lock, \
         patch("src.request_validator.keep_recent_errors") as mock_keep:
        log_validation_errors([])
        assert not mock_lock.__enter__.called
        mock_keep.assert_not_called()


def test_keep_recent_errors_trims_to_100():
    """Test that keep_recent_errors trims stored errors to the last 100 entries."""
    # log 105 errors at once
    errs = [ValidationError("field", f"reason-{i}") for i in range(105)]
    log_validation_errors(errs)
    stored = get_validation_errors()
    assert len(stored) == 100
    # first five should be trimmed out
    reasons = [e["reason"] for e in stored]
    assert "reason-0" not in reasons
    assert "reason-4" not in reasons
    assert "reason-5" in reasons
    assert "reason-104" in reasons


def test_get_validation_errors_returns_copy():
    """Test get_validation_errors returns a copy and not a reference to internal list."""
    log_validation_errors([ValidationError("field", "reason")])
    out = get_validation_errors()
    out.append({"field": "x", "reason": "y", "timestamp": "z"})
    # internal storage should remain unchanged
    out2 = get_validation_errors()
    assert len(out2) == 1
    assert out2[0]["field"] == "field"