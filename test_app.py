import sqlite3
from flask import Flask, request

app = Flask(__name__)

# This has SQL injection vulnerability (should be flagged as critical)
@app.route('/search')
def search():
    query = request.args.get('q')
    conn = sqlite3.connect('database.db')
    cursor = conn.cursor()
    # SQL injection vulnerability
    cursor.execute(f"SELECT * FROM users WHERE name = '{query}'")
    results = cursor.fetchall()
    return str(results)

# This has missing error handling (should be flagged)
@app.route('/divide')
def divide():
    a = int(request.args.get('a'))
    b = int(request.args.get('b'))
    result = a / b  # No error handling for division by zero
    return str(result)

# This has style issues (should be skipped per instructions)
def badly_formatted_function(  ):
    x=1+2
    y = 3   +   4
    return x+y

if __name__ == '__main__':
    app.run(debug=True)
