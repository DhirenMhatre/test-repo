"""
Test file with security vulnerabilities for Azure DevOps review
"""
import sqlite3
from flask import Flask, request

app = Flask(__name__)

# Security Issue: Hardcoded credentials
DATABASE_PASSWORD = "admin123"
API_SECRET_KEY = "sk_live_abc123xyz789"

@app.route('/search')
def search_users():
    query = request.args.get('q')
    conn = sqlite3.connect('users.db')
    cursor = conn.cursor()
    # Security Issue: SQL injection vulnerability
    cursor.execute(f"SELECT * FROM users WHERE name = '{query}'")
    results = cursor.fetchall()
    return str(results)

@app.route('/admin/<user_id>')
def delete_user(user_id):
    # Security Issue: No authorization check
    conn = sqlite3.connect('users.db')
    cursor = conn.cursor()
    cursor.execute(f"DELETE FROM users WHERE id = {user_id}")
    conn.commit()
    return "User deleted"

@app.route('/profile')
def get_profile():
    # Security Issue: Authentication bypass
    username = request.args.get('username')
    if len(username) > 0:
        return f"Welcome {username}"
    return "Access denied"

if __name__ == '__main__':
    # Security Issue: Debug mode enabled
    app.run(debug=True, host='0.0.0.0')
