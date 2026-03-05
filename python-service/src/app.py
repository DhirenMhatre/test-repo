import sys
import os
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from flask import Flask, request, jsonify, g  # noqa: E402
from flask_cors import CORS  # noqa: E402
from src.code_reviewer import CodeReviewer  # noqa: E402

app = Flask(__name__)
CORS(app)

reviewer = CodeReviewer()
SUPPORTED_LANGUAGES = ["python", "javascript", "typescript", "go", "ruby", "java"]
MODEL_VERSION = "v1"


@app.before_request
def set_correlation_id():
    incoming_id = request.headers.get("X-Correlation-ID")
    g.correlation_id = incoming_id or str(uuid.uuid4())


@app.after_request
def add_correlation_id_header(response):
    correlation_id = getattr(g, "correlation_id", None)
    if correlation_id:
        response.headers["X-Correlation-ID"] = correlation_id
    return response


@app.route("/health", methods=["GET"])
def health_check():
    return jsonify(
        {
            "status": "healthy",
            "service": "python-reviewer",
            "correlation_id": getattr(g, "correlation_id", None),
        }
    )


@app.route("/review/metadata", methods=["GET"])
def review_metadata():
    return jsonify(
        {
            "service": "python-reviewer",
            "model_version": MODEL_VERSION,
            "supported_languages": SUPPORTED_LANGUAGES,
            "correlation_id": getattr(g, "correlation_id", None),
        }
    )


@app.route("/review", methods=["POST"])
def review_code():
    data = request.get_json()

    if not data or "content" not in data:
        return jsonify({"error": "Missing 'content' field"}), 400

    content = data.get("content", "")
    language = data.get("language", "python")

    result = reviewer.review_code(content, language)

    return jsonify(
        {
            "score": result.score,
            "issues": [
                {
                    "severity": issue.severity,
                    "line": issue.line,
                    "message": issue.message,
                    "suggestion": issue.suggestion,
                }
                for issue in result.issues
            ],
            "suggestions": result.suggestions,
            "complexity_score": result.complexity_score,
            "correlation_id": getattr(g, "correlation_id", None),
        }
    )


@app.route("/review/function", methods=["POST"])
def review_function():
    data = request.get_json()

    if not data or "function_code" not in data:
        return jsonify({"error": "Missing 'function_code' field"}), 400

    function_code = data.get("function_code", "")
    result = reviewer.review_function(function_code)

    return jsonify(
        {
            **result,
            "correlation_id": getattr(g, "correlation_id", None),
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081, debug=False)
