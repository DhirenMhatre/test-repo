from flask import Flask, jsonify, request, g

# External components
from src.code_reviewer import CodeReviewer
from src.statistics import StatisticsAggregator
from src.correlation_middleware import (
    CorrelationIDMiddleware,
    get_traces,
    get_all_traces,
)

# Request validation utilities exposed for tests to monkeypatch
from src.request_validator import (
    validate_review_request,
    validate_statistics_request,
    sanitize_request_data,
    get_validation_errors,
    clear_validation_errors,
)

app = Flask(__name__)

# Instantiate core services
reviewer = CodeReviewer()
statistics_aggregator = StatisticsAggregator()

# Register correlation middleware
CorrelationIDMiddleware(app)


def _get_correlation_id() -> str:
    # Prefer value set by middleware; fallback to header; finally default
    cid = getattr(g, "correlation_id", None) or request.headers.get("X-Correlation-ID")
    return cid or "test-correlation-id"


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
        details = [e.to_dict() if hasattr(e, "to_dict") else e for e in errors]
        return jsonify({"error": "Validation failed", "details": details}), 422

    clean = sanitize_request_data(data) or {}
    content = clean.get("content")
    language = clean.get("language")

    result = reviewer.review_code(content, language)

    # Normalize issues to list of dicts if they are objects with attributes
    issues = []
    if hasattr(result, "issues") and isinstance(result.issues, list):
        for it in result.issues:
            if isinstance(it, dict):
                issues.append(it)
            else:
                # Convert simple objects/namespaces to dict
                issues.append(
                    {k: getattr(it, k) for k in dir(it) if not k.startswith("_") and not callable(getattr(it, k))}
                )

    response = {
        "score": getattr(result, "score", None),
        "issues": issues,
        "suggestions": getattr(result, "suggestions", []),
        "complexity_score": getattr(result, "complexity_score", None),
        "correlation_id": _get_correlation_id(),
    }
    return jsonify(response), 200


@app.route("/review/function", methods=["POST"])
def review_function():
    payload = request.get_json(silent=True) or {}
    function_code = payload.get("function_code")
    if not function_code:
        return jsonify({"error": "Missing 'function_code' field"}), 400

    result = reviewer.review_function(function_code)
    # Ensure JSON serializable dict
    return jsonify(result), 200


@app.route("/statistics", methods=["POST"])
def statistics():
    data = request.get_json(silent=True)
    if data is None:
        return jsonify({"error": "Missing request body"}), 400

    errors = validate_statistics_request(data)
    if errors:
        details = [e.to_dict() if hasattr(e, "to_dict") else e for e in errors]
        return jsonify({"error": "Validation failed", "details": details}), 422

    clean = sanitize_request_data(data) or {}
    agg = statistics_aggregator.aggregate_reviews(clean.get("files"))

    response = {
        "total_files": getattr(agg, "total_files", 0),
        "average_score": getattr(agg, "average_score", 0.0),
        "total_issues": getattr(agg, "total_issues", 0),
        "issues_by_severity": getattr(agg, "issues_by_severity", {}),
        "average_complexity": getattr(agg, "average_complexity", 0.0),
        "files_with_high_complexity": getattr(agg, "files_with_high_complexity", []),
        "total_suggestions": getattr(agg, "total_suggestions", 0),
        "correlation_id": _get_correlation_id(),
    }
    return jsonify(response), 200


@app.route("/traces", methods=["GET"])
def list_traces():
    traces = get_all_traces()
    return jsonify({"total_traces": len(traces or []), "traces": traces or []}), 200


@app.route("/traces/<correlation_id>", methods=["GET"])
def get_trace(correlation_id: str):
    traces = get_traces(correlation_id)
    if not traces:
        return jsonify({"error": "No traces found for correlation ID"}), 404
    return (
        jsonify(
            {"correlation_id": correlation_id, "trace_count": len(traces), "traces": traces}
        ),
        200,
    )


@app.route("/validation/errors", methods=["GET"])
def list_validation_errors():
    errors = get_validation_errors() or []
    return jsonify({"total_errors": len(errors), "errors": errors}), 200


@app.route("/validation/errors", methods=["DELETE"])
def delete_validation_errors():
    clear_validation_errors()
    return jsonify({"message": "Validation errors cleared"}), 200


if __name__ == "__main__":
    app.run(debug=True)