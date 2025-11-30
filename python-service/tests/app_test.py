from flask import Flask, jsonify, request, g
from src.request_validator import (
    validate_review_request,
    validate_statistics_request,
    sanitize_request_data,
    get_validation_errors as rv_get_validation_errors,
    clear_validation_errors as rv_clear_validation_errors,
)
from src.code_reviewer import CodeReviewer
from src.statistics import StatisticsAggregator
from src.correlation_middleware import CorrelationIDMiddleware, get_all_traces, get_traces

app = Flask(__name__)
CorrelationIDMiddleware(app)


def _get_json_body():
    # Use silent=True to avoid 415 when content-type is missing or invalid
    return request.get_json(silent=True)


def _correlation_id():
    return getattr(g, "correlation_id", None)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy", "service": "python-reviewer"}), 200


@app.route("/review", methods=["POST"])
def review_code():
    data = _get_json_body()
    if not data:
        return jsonify({"error": "Missing request body"}), 400

    # Validate
    errors = validate_review_request(data)
    if errors:
        details = [e.to_dict() if hasattr(e, "to_dict") else e for e in errors]
        return jsonify({"error": "Validation failed", "details": details}), 422

    # Sanitize
    data = sanitize_request_data(data) or data

    content = data.get("content")
    language = data.get("language", "python")

    reviewer = CodeReviewer()
    result = reviewer.review_code(content, language)

    # Convert issues to serializable dicts if needed
    issues_out = []
    for issue in getattr(result, "issues", []):
        if isinstance(issue, dict):
            issues_out.append(issue)
        else:
            issues_out.append(
                {
                    "severity": getattr(issue, "severity", None),
                    "line": getattr(issue, "line", None),
                    "message": getattr(issue, "message", None),
                    "suggestion": getattr(issue, "suggestion", None),
                }
            )

    response = {
        "score": getattr(result, "score", None),
        "issues": issues_out,
        "suggestions": getattr(result, "suggestions", []),
        "complexity_score": getattr(result, "complexity_score", None),
        "correlation_id": _correlation_id(),
    }
    return jsonify(response), 200


@app.route("/review/function", methods=["POST"])
def review_function():
    data = _get_json_body()
    if not data or "function_code" not in data:
        return jsonify({"error": "Missing 'function_code' field"}), 400

    reviewer = CodeReviewer()
    analysis = reviewer.review_function(data["function_code"])

    # Ensure the result is JSON serializable and not missing keys
    if not isinstance(analysis, dict):
        analysis = {"status": "ok", "result": analysis}

    return jsonify(analysis), 200


@app.route("/statistics", methods=["POST"])
def statistics():
    data = _get_json_body()
    if not data:
        return jsonify({"error": "Missing request body"}), 400

    errors = validate_statistics_request(data)
    if errors:
        details = [e.to_dict() if hasattr(e, "to_dict") else e for e in errors]
        return jsonify({"error": "Validation failed", "details": details}), 422

    files = data.get("files", [])
    aggregator = StatisticsAggregator()
    stats = aggregator.aggregate_reviews(files)

    response = {
        "total_files": getattr(stats, "total_files", len(files)),
        "average_score": getattr(stats, "average_score", None),
        "total_issues": getattr(stats, "total_issues", None),
        "issues_by_severity": getattr(stats, "issues_by_severity", {}),
        "average_complexity": getattr(stats, "average_complexity", None),
        "files_with_high_complexity": getattr(stats, "files_with_high_complexity", 0),
        "total_suggestions": getattr(stats, "total_suggestions", 0),
        "correlation_id": _correlation_id(),
    }
    return jsonify(response), 200


@app.route("/traces", methods=["GET"])
def list_traces():
    traces = get_all_traces()
    return jsonify({"total_traces": len(traces), "traces": traces}), 200


@app.route("/traces/<correlation_id>", methods=["GET"])
def get_trace(correlation_id):
    traces = get_traces(correlation_id)
    if not traces:
        return jsonify({"error": "No traces found for correlation ID"}), 404
    return jsonify({"correlation_id": correlation_id, "trace_count": len(traces), "traces": traces}), 200


@app.route("/validation/errors", methods=["GET"])
def list_validation_errors():
    errors = rv_get_validation_errors()
    return jsonify({"total_errors": len(errors), "errors": errors}), 200


@app.route("/validation/errors", methods=["DELETE"])
def delete_validation_errors():
    rv_clear_validation_errors()
    return jsonify({"message": "Validation errors cleared"}), 200


# If this module is executed directly, run the Flask app (useful for manual testing)
if __name__ == "__main__":
    app.run(debug=True)