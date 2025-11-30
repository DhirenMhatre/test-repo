from flask import Flask, jsonify, request, g

from src.code_reviewer import CodeReviewer
from src.statistics import StatisticsAggregator
from src.request_validator import (
    validate_review_request,
    validate_statistics_request,
    sanitize_request_data,
    get_validation_errors,
    clear_validation_errors,
)
from src.correlation_middleware import (
    CorrelationIDMiddleware,
    get_traces,
    get_all_traces,
)

app = Flask(__name__)

# Initialize services used by handlers (kept as module attributes for monkeypatching in tests)
reviewer = CodeReviewer()
statistics_aggregator = StatisticsAggregator()

# Attach correlation ID middleware
CorrelationIDMiddleware(app)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy", "service": "python-reviewer"}), 200


@app.route("/review", methods=["POST"])
def review_code():
    data = request.get_json(silent=True)
    if data is None:
        return jsonify({"error": "Missing request body"}), 400

    errors = validate_review_request(data)
    if errors:
        return (
            jsonify(
                {
                    "error": "Validation failed",
                    "details": [e.to_dict() for e in errors],
                }
            ),
            422,
        )

    clean = sanitize_request_data(data)
    content = clean.get("content")
    language = clean.get("language")

    result = reviewer.review_code(content, language)

    issues = [
        {
            "severity": getattr(issue, "severity", None),
            "line": getattr(issue, "line", None),
            "message": getattr(issue, "message", None),
            "suggestion": getattr(issue, "suggestion", None),
        }
        for issue in getattr(result, "issues", []) or []
    ]

    return (
        jsonify(
            {
                "score": getattr(result, "score", 0.0),
                "issues": issues,
                "suggestions": getattr(result, "suggestions", []) or [],
                "complexity_score": getattr(result, "complexity_score", 0.0),
                "correlation_id": getattr(g, "correlation_id", None),
            }
        ),
        200,
    )


@app.route("/review/function", methods=["POST"])
def review_function():
    data = request.get_json(silent=True) or {}
    if "function_code" not in data:
        return jsonify({"error": "Missing 'function_code' field"}), 400
    result = reviewer.review_function(data["function_code"])
    return jsonify(result), 200


@app.route("/statistics", methods=["POST"])
def statistics():
    data = request.get_json(silent=True)
    if data is None:
        return jsonify({"error": "Missing request body"}), 400

    errors = validate_statistics_request(data)
    if errors:
        return (
            jsonify(
                {
                    "error": "Validation failed",
                    "details": [e.to_dict() for e in errors],
                }
            ),
            422,
        )

    clean = sanitize_request_data(data)
    files = clean.get("files") or []
    stats = statistics_aggregator.aggregate_reviews(files)

    return (
        jsonify(
            {
                "total_files": getattr(stats, "total_files", 0),
                "average_score": getattr(stats, "average_score", 0.0),
                "total_issues": getattr(stats, "total_issues", 0),
                "issues_by_severity": getattr(stats, "issues_by_severity", {}) or {},
                "average_complexity": getattr(stats, "average_complexity", 0.0),
                "files_with_high_complexity": getattr(stats, "files_with_high_complexity", []) or [],
                "total_suggestions": getattr(stats, "total_suggestions", 0),
                "correlation_id": getattr(g, "correlation_id", None),
            }
        ),
        200,
    )


@app.route("/traces", methods=["GET"])
def list_traces():
    traces = get_all_traces()
    return jsonify({"total_traces": len(traces), "traces": traces}), 200


@app.route("/traces/<correlation_id>", methods=["GET"])
def get_trace(correlation_id):
    traces = get_traces(correlation_id)
    if not traces:
        return jsonify({"error": "No traces found for correlation ID"}), 404
    return (
        jsonify(
            {
                "correlation_id": correlation_id,
                "trace_count": len(traces),
                "traces": traces,
            }
        ),
        200,
    )


@app.route("/validation/errors", methods=["GET", "DELETE"])
def validation_errors_handler():
    if request.method == "GET":
        errors = get_validation_errors()
        return jsonify({"total_errors": len(errors), "errors": errors}), 200
    # DELETE
    clear_validation_errors()
    return jsonify({"message": "Validation errors cleared"}), 200


# Optional simple endpoints for broader compatibility with external tests

@app.route("/diff", methods=["POST"])
def diff():
    data = request.get_json(silent=True) or {}
    old_content = data.get("old_content")
    new_content = data.get("new_content")
    if not old_content or not new_content:
        return (
            jsonify({"error": "Missing 'old_content' or 'new_content' field"}),
            400,
        )
    old_lines = old_content.splitlines()
    new_lines = new_content.splitlines()
    changes = sum(1 for i in range(max(len(old_lines), len(new_lines))) if (old_lines[i] if i < len(old_lines) else None) != (new_lines[i] if i < len(new_lines) else None))
    return jsonify({"changes": changes}), 200


@app.route("/metrics", methods=["POST"])
def metrics():
    data = request.get_json(silent=True) or {}
    content = data.get("content")
    if not content:
        return jsonify({"error": "Missing 'content' field"}), 400
    lines = content.splitlines()
    loc = len(lines)
    chars = len(content)
    complexity = sum(line.strip().startswith(("if", "for", "while", "try", "def")) for line in lines)
    return jsonify({"loc": loc, "chars": chars, "complexity": complexity}), 200


@app.route("/dashboard", methods=["POST"])
def dashboard():
    data = request.get_json(silent=True) or {}
    files = data.get("files")
    if not isinstance(files, list) or len(files) == 0:
        return jsonify({"error": "Missing or empty 'files' array"}), 400
    count = len(files)
    total_chars = sum(len((f or {}).get("content", "")) for f in files)
    return jsonify({"files": count, "total_chars": total_chars}), 200


# src/code_reviewer.py
import re
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class ReviewIssue:
    severity: str = "low"
    line: int = 1
    message: str = "issue"
    suggestion: Optional[str] = None


@dataclass
class ReviewResult:
    score: float = 1.0
    issues: List[ReviewIssue] = None
    suggestions: List[str] = None
    complexity_score: float = 0.0

    def __post_init__(self):
        if self.issues is None:
            self.issues = []
        if self.suggestions is None:
            self.suggestions = []


class CodeReviewer:
    LONG_LINE_LIMIT = 79

    def review_code(self, content: str, language: Optional[str] = None) -> ReviewResult:
        if content is None:
            content = ""

        issues: List[ReviewIssue] = []
        suggestions: List[str] = []

        lines = content.splitlines() or [content]
        # Detect long lines
        for idx, line in enumerate(lines, start=1):
            if len(line) > self.LONG_LINE_LIMIT:
                issues.append(
                    ReviewIssue(
                        severity="low",
                        line=idx,
                        message="Line too long",
                        suggestion="Consider wrapping the line to within 79 characters",
                    )
                )

        # Detect TODO/FIXME
        for idx, line in enumerate(lines, start=1):
            if "TODO" in line or "FIXME" in line:
                issues.append(
                    ReviewIssue(
                        severity="medium",
                        line=idx,
                        message="TODO or FIXME comment detected",
                        suggestion="Address the TODO/FIXME or remove it",
                    )
                )

        # Detect hardcoded password patterns
        pwd_pattern = re.compile(r"\bpassword\s*=\s*(['\"]).*?\1", re.IGNORECASE)
        for idx, line in enumerate(lines, start=1):
            if pwd_pattern.search(line):
                issues.append(
                    ReviewIssue(
                        severity="high",
                        line=idx,
                        message="Hardcoded password detected",
                        suggestion="Use environment variables or a secret manager",
                    )
                )

        # Simple cyclomatic complexity heuristic
        complexity_tokens = ("if", "elif", "for", "while", "case", "try", "except", "and", "or")
        complexity = 0
        token_pattern = re.compile(r"\b(" + "|".join(complexity_tokens) + r")\b")
        for line in lines:
            complexity += len(token_pattern.findall(line))

        # Score heuristic: start at 1.0 and subtract penalties
        penalty = 0.0
        penalty += len([i for i in issues if i.severity == "low"]) * 0.02
        penalty += len([i for i in issues if i.severity == "medium"]) * 0.05
        penalty += len([i for i in issues if i.severity == "high"]) * 0.1
        penalty += min(complexity, 10) * 0.01  # cap complexity effect

        score = max(0.0, round(1.0 - penalty, 2))

        # General suggestion
        if "def " in content and "->" not in content:
            suggestions.append("Consider adding type hints to functions")

        return ReviewResult(
            score=score,
            issues=issues,
            suggestions=suggestions,
            complexity_score=float(complexity),
        )

    def review_function(self, function_code: str):
        info = {"status": "ok", "length": len(function_code or "")}

        # Try to detect the function signature and count parameters
        sig_match = re.search(r"def\s+\w+\s*\((.*?)\)\s*:", function_code or "")
        if sig_match:
            params_str = sig_match.group(1).strip()
            if params_str:
                params = [p.strip() for p in params_str.split(",") if p.strip()]
                # Exclude typical self/cls for methods
                filtered = [p for p in params if not re.match(r"^(self|cls)\b", p)]
                if len(filtered) > 5:
                    info["warning"] = "Function has too many parameters"
        return info


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)