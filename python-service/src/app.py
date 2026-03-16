import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from flask import Flask, request, jsonify  # noqa: E402
from flask_cors import CORS  # noqa: E402
from src.code_reviewer import CodeReviewer  # noqa: E402

app = Flask(__name__)
CORS(app)

reviewer = CodeReviewer()


@app.route("/health", methods=["GET"])
def health_check():
    return jsonify({"status": "healthy", "service": "python-reviewer"})


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
        }
    )


@app.route("/review/function", methods=["POST"])
def review_function():
    data = request.get_json()

    if not data or "function_code" not in data:
        return jsonify({"error": "Missing 'function_code' field"}), 400

    function_code = data.get("function_code", "")
    result = reviewer.review_function(function_code)

    return jsonify(result)


@app.route("/review/batch", methods=["POST"])
def review_batch():
    data = request.get_json()

    if not data or "files" not in data:
        return jsonify({"error": "Missing 'files' field"}), 400

    files = data.get("files", [])
    language = data.get("language", "python")
    results = []

    for f in files:
        content = f.get("content", "")
        filename = f.get("filename", "unknown")
        result = reviewer.review_code(content, language)
        results.append({
            "filename": filename,
            "score": result.score,
            "issues_count": len(result.issues),
            "complexity_score": result.complexity_score,
        })

    return jsonify({"results": results, "total_files": len(results)})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081, debug=False)
