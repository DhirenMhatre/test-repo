from datetime import datetime
from threading import RLock
from typing import Any, Dict, List, Optional, Sequence, Union

# Public constants
ALLOWED_LANGUAGES: List[str] = [
    "python",
    "javascript",
    "java",
    "go",
    "ruby",
    "c",
    "cpp",
    "rust",
    "typescript",
]
MAX_CONTENT_SIZE: int = 100_000

# Internal storage for validation errors
_validation_errors: List[Dict[str, str]] = []
validation_lock = RLock()


class ValidationError:
    def __init__(self, field: str, reason: str):
        # Allow empty strings as test expects
        self.field = field
        self.reason = reason
        # Let exceptions from datetime.now() propagate as tests expect
        self.timestamp = datetime.now().isoformat()

    def to_dict(self) -> Dict[str, str]:
        return {
            "field": self.field,
            "reason": self.reason,
            "timestamp": self.timestamp,
        }


def contains_null_bytes(value: Optional[str]) -> bool:
    if value is None:
        return False
    try:
        return "\x00" in value
    except Exception:
        return False


def contains_path_traversal(path: Optional[str]) -> bool:
    if not isinstance(path, str):
        return False
    lowered = path.replace("\\", "/")
    if "../" in lowered or "/.." in lowered:
        return True
    if lowered.startswith("~/") or lowered == "~":
        return True
    return False


def sanitize_input(value: Any) -> Optional[str]:
    if value is None:
        return None
    if not isinstance(value, str):
        return str(value)

    # Allow only standard whitespace: space, \n, \r, \t
    allowed = {"\n", "\r", "\t"}
    out_chars: List[str] = []
    for ch in value:
        code = ord(ch)
        if code < 32 or code == 127:
            # control char
            if ch in allowed:
                out_chars.append(ch)
            else:
                # drop disallowed control chars
                continue
        else:
            out_chars.append(ch)

    result = "".join(out_chars)
    return result


def sanitize_request_data(data: Dict[str, Any]) -> Dict[str, Any]:
    # Only sanitize specific keys: content, language, path
    keys_to_sanitize = {"content", "language", "path"}
    sanitized = dict(data)  # shallow copy to avoid mutating input
    for k in keys_to_sanitize:
        if k in data:
            sanitized[k] = sanitize_input(data[k])
    return sanitized


def keep_recent_errors() -> None:
    # Keep only the most recent 100 entries
    global _validation_errors
    if len(_validation_errors) > 100:
        _validation_errors = _validation_errors[-100:]


def log_validation_errors(errors: Sequence[ValidationError]) -> None:
    if not errors:
        return
    with validation_lock:
        for err in errors:
            if isinstance(err, ValidationError):
                _validation_errors.append(err.to_dict())
            elif isinstance(err, dict):
                _validation_errors.append(err)
            else:
                # Fallback conversion
                _validation_errors.append(
                    {"field": "unknown", "reason": str(err), "timestamp": datetime.now().isoformat()}
                )
        keep_recent_errors()


def get_validation_errors() -> List[Dict[str, str]]:
    # return a copy to avoid external mutation
    return list(_validation_errors)


def clear_validation_errors() -> None:
    with validation_lock:
        _validation_errors.clear()


def validate_review_request(payload: Dict[str, Any]) -> List[ValidationError]:
    errors: List[ValidationError] = []

    content = payload.get("content")
    language = payload.get("language")

    # content validations
    if content is None or content == "":
        errors.append(ValidationError("content", "content is required"))
    elif not isinstance(content, str):
        errors.append(ValidationError("content", "content must be a string"))
    else:
        if len(content) > MAX_CONTENT_SIZE:
            errors.append(
                ValidationError("content", f"content exceeds maximum size of {MAX_CONTENT_SIZE} characters")
            )
        elif contains_null_bytes(content):
            errors.append(ValidationError("content", "content contains null bytes which are not allowed"))

    # language validations
    if language is None or language == "":
        errors.append(ValidationError("language", "language is required"))
    elif not isinstance(language, str):
        errors.append(ValidationError("language", "language must be a string"))
    elif language not in ALLOWED_LANGUAGES:
        allowed_str = ", ".join(ALLOWED_LANGUAGES)
        errors.append(
            ValidationError("language", f"unsupported language. Allowed languages: {allowed_str}")
        )

    if errors:
        log_validation_errors(errors)
    return errors


def validate_statistics_request(payload: Dict[str, Any]) -> List[ValidationError]:
    errors: List[ValidationError] = []

    if "files" not in payload:
        errors.append(ValidationError("files", "files is required"))
    else:
        files = payload.get("files")
        if not isinstance(files, list):
            errors.append(ValidationError("files", "files must be an array"))
        elif len(files) == 0:
            errors.append(ValidationError("files", "files cannot be empty"))
        elif len(files) > 1000:
            errors.append(ValidationError("files", "files count cannot exceed 1000"))

    if errors:
        log_validation_errors(errors)
    return errors