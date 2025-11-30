import pytest
from unittest.mock import Mock, patch, MagicMock

from src.request_validator import (
    ValidationError,
    validate_review_request,
    validate_statistics_request,
    sanitize_input,
    sanitize_request_data,
    contains_null_bytes,
    contains_path_traversal,
    log_validation_errors,
    get_validation_errors,
    clear_validation_errors,
    keep_recent_errors,
    MAX_CONTENT_SIZE,
    ALLOWED_LANGUAGES,
)


@pytest.fixture(autouse=True)
def clear_errors_before_after():
    """Ensure the global validation errors store is clear before and after each test."""
    clear_validation_errors()
    yield
    clear_validation_errors()


@pytest.fixture
def fixed_datetime():
    """Patch datetime.now().isoformat() to a fixed value."""
    with patch('src.request_validator.datetime') as mock_dt:
        mock_now = Mock()
        mock_now.isoformat.return_value = "2020-01-01T00:00:00"
        mock_dt.now.return_value = mock_now
        yield mock_dt


@pytest.fixture
def validation_error_instance(fixed_datetime):
    """Create a ValidationError instance for testing."""
    return ValidationError(field="content", reason="Invalid content")


def test_validationerror_init_sets_fields_and_timestamp(fixed_datetime):
    """Test that ValidationError initializes fields and timestamp correctly."""
    err = ValidationError(field="language", reason="Unsupported language")
    assert err.field == "language"
    assert err.reason == "Unsupported language"
    assert isinstance(err.timestamp, str)
    assert err.timestamp == "2020-01-01T00:00:00"


def test_validationerror_to_dict_returns_dict(validation_error_instance):
    """Test to_dict returns expected dictionary representation."""
    d = validation_error_instance.to_dict()
    assert d["field"] == "content"
    assert d["reason"] == "Invalid content"
    assert d["timestamp"] == "2020-01-01T00:00:00"


def test_validate_review_request_content_required():
    """Test validate_review_request returns error when content is missing or empty."""
    errors = validate_review_request({})
    assert len(errors) == 1
    assert errors[0].field == "content"
    assert "required" in errors[0].reason.lower()

    errors = validate_review_request({"content": ""})
    assert len(errors) == 1
    assert errors[0].field == "content"


def test_validate_review_request_content_size_exceeded():
    """Test validate_review_request returns error when content exceeds max size."""
    oversized = "a" * (MAX_CONTENT_SIZE + 1)
    errors = validate_review_request({"content": oversized})
    assert len(errors) == 1
    assert errors[0].field == "content"
    assert "exceeds" in errors[0].reason.lower()


def test_validate_review_request_content_contains_null():
    """Test validate_review_request returns error when content contains null bytes."""
    content = "hello\x00world"
    errors = validate_review_request({"content": content})
    assert len(errors) == 1
    assert errors[0].field == "content"
    assert "null" in errors[0].reason.lower()


def test_validate_review_request_invalid_language():
    """Test validate_review_request returns error for invalid language."""
    data = {"content": "print('ok')", "language": "perl"}
    errors = validate_review_request(data)
    assert len(errors) == 1
    assert errors[0].field == "language"
    for lang in ALLOWED_LANGUAGES:
        assert lang in errors[0].reason


def test_validate_review_request_valid_input():
    """Test validate_review_request returns no errors for valid input."""
    data = {"content": "print('ok')", "language": "python"}
    errors = validate_review_request(data)
    assert errors == []


def test_validate_statistics_request_files_required():
    """Test validate_statistics_request requires 'files' key."""
    errors = validate_statistics_request({})
    assert len(errors) == 1
    assert errors[0].field == "files"
    assert "required" in errors[0].reason.lower()


def test_validate_statistics_request_files_must_be_array():
    """Test validate_statistics_request enforces files must be a list."""
    errors = validate_statistics_request({"files": "not-a-list"})
    assert len(errors) == 1
    assert errors[0].field == "files"
    assert "array" in errors[0].reason.lower()


def test_validate_statistics_request_files_not_empty():
    """Test validate_statistics_request rejects empty files list."""
    errors = validate_statistics_request({"files": []})
    assert len(errors) == 1
    assert errors[0].field == "files"
    assert "cannot be empty" in errors[0].reason.lower()


def test_validate_statistics_request_files_limit():
    """Test validate_statistics_request enforces files list limit."""
    errors = validate_statistics_request({"files": list(range(1001))})
    assert len(errors) == 1
    assert errors[0].field == "files"
    assert "cannot exceed 1000" in errors[0].reason.lower()


def test_sanitize_input_removes_control_chars_and_keeps_whitespace():
    """Test sanitize_input removes control characters but keeps newline, tab, carriage return."""
    raw = "A\x00B\x07C\nD\tE\rF\x0bG\x1fH"
    sanitized = sanitize_input(raw)
    assert "A" in sanitized and "B" in sanitized and "C" in sanitized
    assert "\n" in sanitized and "\t" in sanitized and "\r" in sanitized
    assert "\x00" not in sanitized
    assert "\x07" not in sanitized
    assert "\x0b" not in sanitized
    assert "\x1f" not in sanitized


def test_sanitize_input_non_string():
    """Test sanitize_input converts non-string input to string."""
    sanitized = sanitize_input(12345)
    assert sanitized == "12345"


def test_sanitize_input_none():
    """Test sanitize_input returns None when input is None."""
    assert sanitize_input(None) is None


def test_sanitize_request_data_sanitizes_fields():
    """Test sanitize_request_data sanitizes content, language, and path fields."""
    data = {
        "content": "ok\x00ay",
        "language": "py\x07thon",
        "path": "../bad/\x00path"
    }
    sanitized = sanitize_request_data(data)
    assert "\x00" not in sanitized["content"]
    assert "\x07" not in sanitized["language"]
    assert "\x00" not in sanitized["path"]
    # Ensure keys not removed
    assert "content" in sanitized and "language" in sanitized and "path" in sanitized


def test_contains_null_bytes():
    """Test contains_null_bytes detects null bytes."""
    assert contains_null_bytes("a\x00b") is True
    assert contains_null_bytes("abc") is False


def test_contains_path_traversal():
    """Test contains_path_traversal detects basic traversal patterns."""
    assert contains_path_traversal("../etc/passwd") is True
    assert contains_path_traversal("~/secret") is True
    assert contains_path_traversal("/safe/path/file.txt") is False


def test_log_validation_errors_appends_and_limits(fixed_datetime):
    """Test log_validation_errors appends errors and keeps only the most recent 100."""
    # Add 120 errors
    errs = [ValidationError(field=f"f{i}", reason="r") for i in range(120)]
    log_validation_errors(errs)
    stored = get_validation_errors()
    assert len(stored) == 100
    # Ensure they are the last 100 errors (f20..f119)
    fields = [e["field"] for e in stored]
    assert "f0" not in fields and "f19" not in fields
    assert "f20" in fields and "f119" in fields


def test_get_validation_errors_returns_copy(fixed_datetime):
    """Test get_validation_errors returns a copy, not a direct reference."""
    log_validation_errors([ValidationError("a", "b")])
    errs = get_validation_errors()
    errs.append({"field": "tamper", "reason": "x", "timestamp": "y"})
    # Original should remain unchanged
    original = get_validation_errors()
    assert len(original) == 1
    assert original[0]["field"] == "a"


def test_clear_validation_errors_empties_store(fixed_datetime):
    """Test clear_validation_errors removes all stored errors."""
    log_validation_errors([ValidationError("a", "b"), ValidationError("c", "d")])
    assert len(get_validation_errors()) == 2
    clear_validation_errors()
    assert get_validation_errors() == []


def test_keep_recent_errors_trims_to_100():
    """Test keep_recent_errors trims the global list to 100 entries."""
    # Prepare by logging more than 100 errors in two batches
    errs1 = [ValidationError(field=f"x{i}", reason="r") for i in range(60)]
    errs2 = [ValidationError(field=f"y{i}", reason="r") for i in range(60)]
    log_validation_errors(errs1)
    log_validation_errors(errs2)
    # keep_recent_errors is already called inside log_validation_errors,
    # but we call explicitly to satisfy test coverage.
    keep_recent_errors()
    stored = get_validation_errors()
    assert len(stored) == 100
    fields = [e["field"] for e in stored]
    # First 20 of x-series should be trimmed
    assert any(f.startswith("y") for f in fields)
    assert "x0" not in fields and "x19" not in fields


def test_log_validation_errors_uses_lock(fixed_datetime):
    """Test log_validation_errors acquires the validation lock when logging."""
    with patch('src.request_validator.validation_lock', new=MagicMock()) as mock_lock:
        log_validation_errors([ValidationError("field", "reason")])
        assert mock_lock.__enter__.called
        assert mock_lock.__exit__.called


def test_log_validation_errors_raises_when_to_dict_fails():
    """Test log_validation_errors propagates exceptions from to_dict."""
    bad = Mock()
    bad.to_dict.side_effect = ValueError("boom")
    with pytest.raises(ValueError):
        log_validation_errors([bad])