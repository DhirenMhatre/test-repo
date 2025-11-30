from dataclasses import dataclass, field as dataclass_field
from datetime import datetime
from threading import Lock
from typing import Any, Dict, Iterable, List, Optional

# Constants
ALLOWED_LANGUAGES: List[str] = [
    "python",
    "javascript",
    "ruby",
    "go",
    "java",
    "c",
    "cpp",
    "csharp",
    "php",
    "bash",
    "typescript",
]
MAX_CONTENT_SIZE: int = 100000

# Global store and lock for validation errors
VALIDATION_ERRORS: List[Dict[str, Any]] = []
validation_lock: Lock = Lock()


@dataclass
class ValidationError:
    field: str
    reason: str
    timestamp: str = dataclass_field(default_factory=lambda: datetime.now().isoformat())

    def to_dict(self) -> Dict[str, str]:
        return {"field": self.field, "reason": self.reason, "timestamp": self.timestamp}


def contains_null_bytes(value: Optional[str]) -> bool:
    if value is None:
        return False
    if not isinstance(value, str):
        value = str(value)
    return "\x00" in value


def contains_path_traversal(path: Optional[str]) -> bool:
    if path is None or not isinstance(path, str):
        return False
    # Normalize separators to handle both POSIX and Windows-like paths
    p = path.replace("\\", "/")
    if p.startswith("~"):
        return True
    parts = p.split("/")
    if any(part == ".." for part in parts):
        return True
    if "../" in p or "..\\" in path:
        return True
    return False


def sanitize_input(value: Any) -> Optional[str]:
    if value is None:
        return None
    if not isinstance(value, str):
        value = str(value)
    allowed_controls = {9, 10, 13}  # tab, newline, carriage return
    # Keep characters with codepoint >= 32, and allowed control characters
    return "".join(ch for ch in value if (ord(ch) >= 32 or ord(ch) in allowed_controls))


def sanitize_request_data(data: Dict[str, Any]) -> Dict[str, Any]:
    sanitized: Dict[str, Any] = {}
    for key, val in data.items():
        if key in {"content", "language", "path"}:
            sanitized[key] = sanitize_input(val)
        else:
            sanitized[key] = val
    return sanitized


def validate_review_request(data: Dict[str, Any]) -> List[ValidationError]:
    errors: List[ValidationError] = []

    content = data.get("content") if isinstance(data, dict) else None
    if not content:
        errors.append(ValidationError(field="content", reason="Content is required"))
        return errors

    if not isinstance(content, str):
        content = str(content)

    if len(content) > MAX_CONTENT_SIZE:
        errors.append(
            ValidationError(
                field="content",
                reason=f"Content size exceeds maximum allowed of {MAX_CONTENT_SIZE} characters",
            )
        )
        return errors

    if contains_null_bytes(content):
        errors.append(ValidationError(field="content", reason="Content contains null bytes"))
        return errors

    language = data.get("language")
    if language is not None:
        # Compare case-insensitively
        lang_norm = language.lower() if isinstance(language, str) else str(language).lower()
        if lang_norm not in ALLOWED_LANGUAGES:
            allowed = ", ".join(ALLOWED_LANGUAGES)
            errors.append(
                ValidationError(
                    field="language",
                    reason=f"Unsupported language. Allowed languages: {allowed}",
                )
            )

    return errors


def validate_statistics_request(data: Dict[str, Any]) -> List[ValidationError]:
    errors: List[ValidationError] = []

    if "files" not in data:
        errors.append(ValidationError(field="files", reason="'files' is required"))
        return errors

    files = data.get("files")

    if not isinstance(files, list):
        errors.append(ValidationError(field="files", reason="'files' must be an array"))
        return errors

    if len(files) == 0:
        errors.append(ValidationError(field="files", reason="'files' cannot be empty"))
        return errors

    if len(files) > 1000:
        errors.append(
            ValidationError(field="files", reason="'files' count cannot exceed 1000")
        )
        return errors

    return errors


def keep_recent_errors(limit: int = 100) -> None:
    with validation_lock:
        if len(VALIDATION_ERRORS) > limit:
            # Keep only the most recent 'limit' entries
            del VALIDATION_ERRORS[: len(VALIDATION_ERRORS) - limit]


def log_validation_errors(errors: Iterable[ValidationError]) -> None:
    with validation_lock:
        for err in errors:
            # Let exceptions from to_dict propagate as per test expectation
            VALIDATION_ERRORS.append(err.to_dict())
        keep_recent_errors(100)


def get_validation_errors() -> List[Dict[str, Any]]:
    # Return a shallow copy to avoid external mutation
    return [e.copy() for e in VALIDATION_ERRORS]


def clear_validation_errors() -> None:
    with validation_lock:
        VALIDATION_ERRORS.clear()