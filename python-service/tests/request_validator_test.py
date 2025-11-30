from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional

# Public constants
MAX_CONTENT_SIZE = 10000
ALLOWED_LANGUAGES = [
    "python",
    "javascript",
    "typescript",
    "go",
    "ruby",
    "java",
    "csharp",
    "cpp",
]


@dataclass
class ValidationError:
    field: str
    reason: str
    timestamp: str = ""

    def __post_init__(self) -> None:
        # Use datetime.now().isoformat(), letting exceptions propagate as per tests
        self.timestamp = datetime.now().isoformat()

    def to_dict(self) -> Dict[str, str]:
        return {"field": self.field, "reason": self.reason, "timestamp": self.timestamp}


# In-memory log of validation errors (list of dicts)
validation_errors: List[Dict[str, str]] = []


def contains_null_bytes(s: Optional[str]) -> bool:
    if s is None:
        return False
    return "\x00" in s


def contains_path_traversal(path: Optional[str]) -> bool:
    if not path:
        return False
    # Detect tilde home traversal and directory going up
    if "~/" in path:
        return True
    segments = path.split("/")
    if any(seg == ".." for seg in segments):
        return True
    return False


def sanitize_input(value: Any) -> Optional[str]:
    if value is None:
        return None
    if not isinstance(value, str):
        # Let exceptions from str(value) propagate
        value = str(value)

    # Remove control characters (Cc) except for newline, tab, carriage return.
    # Also remove format characters (Cf) like zero-width space.
    # Keep: \n, \t, \r
    allowed_controls = {"\n", "\t", "\r"}

    def _keep_char(ch: str) -> bool:
        # Keep printable non-control chars or allowed whitespace controls
        if ch in allowed_controls:
            return True
        code = ord(ch)
        # DEL
        if code == 0x7F:
            return False
        # Null byte and other ASCII control 0x00-0x1F
        if 0x00 <= code <= 0x1F:
            return False
        # Remove general category Cf (format) like zero-width space U+200B
        # Using a small explicit check for U+200B to avoid importing unicodedata
        if ch == "\u200b":
            return False
        return True

    return "".join(ch for ch in value if _keep_char(ch))


def sanitize_request_data(data: Dict[str, Any]) -> Dict[str, Any]:
    # Return a shallow copy with certain string fields sanitized
    result = dict(data)
    for key in ("content", "language", "path"):
        if key in result and isinstance(result[key], str):
            result[key] = sanitize_input(result[key])
    return result


def log_validation_errors(errors: List[ValidationError]) -> None:
    if not errors:
        return
    global validation_errors
    for err in errors:
        if isinstance(err, ValidationError):
            validation_errors.append(err.to_dict())
        elif isinstance(err, dict):
            # Fallback if dict passed directly
            validation_errors.append(dict(err))
    keep_recent_errors()


def keep_recent_errors() -> None:
    global validation_errors
    if len(validation_errors) > 100:
        validation_errors = validation_errors[-100:]


def get_validation_errors() -> List[Dict[str, str]]:
    return list(validation_errors)


def clear_validation_errors() -> None:
    global validation_errors
    validation_errors = []


def validate_review_request(data: Dict[str, Any]) -> List[ValidationError]:
    errors: List[ValidationError] = []

    content = data.get("content")
    language = data.get("language")

    if not content:
        errors.append(ValidationError(field="content", reason="content is required"))
    else:
        if contains_null_bytes(content):
            errors.append(
                ValidationError(field="content", reason="content contains null bytes")
            )
        if isinstance(content, str) and len(content) > MAX_CONTENT_SIZE:
            errors.append(
                ValidationError(
                    field="content",
                    reason=f"content is too large; must not exceed {MAX_CONTENT_SIZE} characters",
                )
            )

    if language is not None and language not in ALLOWED_LANGUAGES:
        errors.append(
            ValidationError(
                field="language",
                reason=f"language must be one of {', '.join(ALLOWED_LANGUAGES)}",
            )
        )

    if errors:
        log_validation_errors(errors)
    return errors


def validate_statistics_request(data: Dict[str, Any]) -> List[ValidationError]:
    errors: List[ValidationError] = []

    if "files" not in data or data.get("files") is None:
        errors.append(ValidationError(field="files", reason="files is required"))
    else:
        files = data.get("files")
        if not isinstance(files, list):
            errors.append(
                ValidationError(field="files", reason="files must be an array")
            )
        else:
            if len(files) == 0:
                errors.append(
                    ValidationError(field="files", reason="files cannot be empty")
                )
            elif len(files) > 1000:
                errors.append(
                    ValidationError(
                        field="files", reason="files cannot exceed 1000 items"
                    )
                )

    if errors:
        log_validation_errors(errors)
    return errors