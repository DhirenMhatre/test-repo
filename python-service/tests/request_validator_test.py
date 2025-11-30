import pytest
from unittest.mock import Mock, patch

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
    MAX_CONTENT_SIZE,
    ALLOWED_LANGUAGES,
)


@pytest.fixture(autouse=True)
def clean_validation_errors():
    """Ensure validation_errors global state is clean before and after each test."""
    clear_validation_errors()
    yield
    clear_validation_errors()


@pytest.fixture
def validation_error_instance():
    """Provide a basic ValidationError instance for tests."""
    return ValidationError(field="test_field", reason="test_reason")


def test_ValidationError___init___sets_fields_and_timestamp():
    """ValidationError should set field, reason, and timestamp using datetime.now().isoformat()."""
    with patch("src.request_validator.datetime") as mock_datetime:
        mock_now = Mock()
        mock_now.isoformat.return_value = "2025-01-01T00:00:00"
        mock_datetime.now.return_value = mock_now

        err = ValidationError(field="content", reason="missing")

    assert err.field == "content"
    assert err.reason == "missing"
    assert err.timestamp == "2025-01-01T00:00:00"


def test_ValidationError_to_dict_returns_expected_dict(validation_error_instance):
    """to_dict should return a dictionary with field, reason, and timestamp keys."""
    data = validation_error_instance.to_dict()
    assert set(data.keys()) == {"field", "reason", "timestamp"}
    assert data["field"] == "test_field"
    assert data["reason"] == "test_reason"
    assert isinstance(data["timestamp"], str)


def test_ValidationError___init___handles_empty_strings():
    """ValidationError should accept empty strings for field and reason."""
    err = ValidationError(field="", reason="")
    data = err.to_dict()
    assert data["field"] == ""
    assert data["reason"] == ""
    assert isinstance(data["timestamp"], str)


def test_validate_review_request_missing_content_logs_error():
    """validate_review_request should add an error when content is missing."""
    errors = validate_review_request({"language": ALLOWED_LANGUAGES[0]})
    assert len(errors) == 1
    assert errors[0].field == "content"
    logged = get_validation_errors()
    assert len(logged) == 1
    assert logged[0]["field"] == "content"


def test_validate_review_request_content_with_null_bytes():
    """validate_review_request should flag content containing null bytes."""
    errors = validate_review_request({"content": "abc\x00def"})
    assert len(errors) == 1
    assert errors[0].field == "content"
    assert "null bytes" in errors[0].reason


def test_validate_review_request_content_too_large():
    """validate_review_request should flag content exceeding MAX_CONTENT_SIZE."""
    big_content = "a" * (MAX_CONTENT_SIZE + 1)
    errors = validate_review_request({"content": big_content})
    assert len(errors) == 1
    assert errors[0].field == "content"
    assert str(MAX_CONTENT_SIZE) in errors[0].reason


def test_validate_review_request_invalid_language():
    """validate_review_request should flag invalid language values."""
    errors = validate_review_request({"content": "ok", "language": "php"})
    assert len(errors) == 1
    assert errors[0].field == "language"
    assert "must be one of" in errors[0].reason


def test_validate_review_request_valid_no_errors():
    """validate_review_request should return no errors for valid content and language."""
    errors = validate_review_request({"content": "ok", "language": ALLOWED_LANGUAGES[0]})
    assert errors == []
    assert get_validation_errors() == []


def test_validate_statistics_request_files_missing():
    """validate_statistics_request should error when files key is missing or None."""
    errors = validate_statistics_request({})
    assert len(errors) == 1
    assert errors[0].field == "files"
    assert "required" in errors[0].reason


def test_validate_statistics_request_files_not_list():
    """validate_statistics_request should error when files is not a list."""
    errors = validate_statistics_request({"files": "not-a-list"})
    assert len(errors) == 1
    assert errors[0].field == "files"
    assert "must be an array" in errors[0].reason


def test_validate_statistics_request_files_empty():
    """validate_statistics_request should error when files list is empty."""
    errors = validate_statistics_request({"files": []})
    assert len(errors) == 1
    assert errors[0].field == "files"
    assert "cannot be empty" in errors[0].reason


def test_validate_statistics_request_files_too_many():
    """validate_statistics_request should error when files list exceeds 1000 entries."""
    errors = validate_statistics_request({"files": [f"f{i}" for i in range(1001)]})
    assert len(errors) == 1
    assert errors[0].field == "files"
    assert "cannot exceed 1000" in errors[0].reason


def test_validate_statistics_request_valid():
    """validate_statistics_request should return no errors for a non-empty list of files."""
    errors = validate_statistics_request({"files": ["file1", "file2"]})
    assert errors == []
    assert get_validation_errors() == []


def test_sanitize_input_controls_removed_and_whitespace_preserved():
    """sanitize_input should remove control chars but preserve newline, tab, carriage return."""
    raw = "A\x00B\x01C\nD\tE\rF\x7fG\u200bH"
    result = sanitize_input(raw)
    assert result == "ABC\nD\tE\rFGH"


def test_sanitize_input_none_returns_none():
    """sanitize_input should return None when input is None."""
    assert sanitize_input(None) is None


def test_sanitize_input_non_string_is_str_casted():
    """sanitize_input should cast non-string inputs to string using str()."""
    assert sanitize_input(123) == "123"
    assert sanitize_input(True) == "True"


def test_sanitize_input_non_string_str_raises_exception():
    """sanitize_input should propagate exceptions thrown by str() on non-string inputs."""

    class BadStr:
        def __str__(self):
            raise ValueError("cannot stringify")

    with pytest.raises(ValueError):
        sanitize_input(BadStr())


def test_sanitize_request_data_calls_sanitize_input_for_string_fields():
    """sanitize_request_data should call sanitize_input for content, language, and path string fields."""
    data = {"content": "c", "language": "l", "path": "p", "other": 10}
    with patch("src.request_validator.sanitize_input") as mock_sanitize:
        mock_sanitize.side_effect = lambda x: f"sanitized:{x}"
        result = sanitize_request_data(data)

    assert result["content"] == "sanitized:c"
    assert result["language"] == "sanitized:l"
    assert result["path"] == "sanitized:p"
    assert result["other"] == 10
    # Ensure sanitize_input called exactly for the string fields
    assert mock_sanitize.call_count == 3


def test_contains_null_bytes_true_false():
    """contains_null_bytes should accurately detect presence of null bytes."""
    assert contains_null_bytes("abc\x00def") is True
    assert contains_null_bytes("abcdef") is False


def test_contains_path_traversal_detection():
    """contains_path_traversal should detect '..' or '~/' sequences."""
    assert contains_path_traversal("../etc/passwd") is True
    assert contains_path_traversal("~/secrets") is True
    assert contains_path_traversal("dir/..") is True
    assert contains_path_traversal("dir/file.txt") is False


def test_log_validation_errors_calls_keep_recent_errors_and_stores_errors():
    """log_validation_errors should store error dicts and call keep_recent_errors."""
    with patch("src.request_validator.keep_recent_errors") as mock_keep:
        errs = [ValidationError("f1", "r1"), ValidationError("f2", "r2")]
        log_validation_errors(errs)

    stored = get_validation_errors()
    assert len(stored) == 2
    assert {e["field"] for e in stored} == {"f1", "f2"}
    assert mock_keep.called


def test_log_validation_errors_no_errors_does_not_call_keep_recent_errors():
    """log_validation_errors should do nothing when provided an empty list."""
    with patch("src.request_validator.keep_recent_errors") as mock_keep:
        log_validation_errors([])

    assert get_validation_errors() == []
    mock_keep.assert_not_called()


def test_keep_recent_errors_trims_to_last_100():
    """keep_recent_errors should retain only the last 100 entries in validation_errors."""
    errs = [ValidationError("f", f"r-{i}") for i in range(120)]
    log_validation_errors(errs)
    stored = get_validation_errors()
    assert len(stored) == 100
    reasons = [e["reason"] for e in stored]
    assert reasons[0] == "r-20"
    assert reasons[-1] == "r-119"


def test_get_validation_errors_returns_copy():
    """get_validation_errors should return a copy so external mutation does not affect internal state."""
    errs = [ValidationError("f", "r")]
    log_validation_errors(errs)
    stored = get_validation_errors()
    stored.append({"field": "x", "reason": "y", "timestamp": "z"})
    stored2 = get_validation_errors()
    assert len(stored2) == 1
    assert stored2[0]["reason"] == "r"


def test_clear_validation_errors_empties_storage():
    """clear_validation_errors should remove all stored error records."""
    log_validation_errors([ValidationError("f", "r")])
    assert len(get_validation_errors()) == 1
    clear_validation_errors()
    assert get_validation_errors() == []


def test_ValidationError___init___datetime_now_raises_exception():
    """ValidationError initialization should propagate exceptions from datetime.now()."""
    with patch("src.request_validator.datetime") as mock_datetime:
        mock_datetime.now.side_effect = RuntimeError("time failed")
        with pytest.raises(RuntimeError):
            ValidationError(field="x", reason="y")