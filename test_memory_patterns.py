# Test file for memory leak patterns
# Should trigger warnings when priority is set to "Memory leaks" or "Resource management"

class DatabaseConnection:
    def __init__(self, connection_string):
        self.conn = open_connection(connection_string)
        # Bad: No cleanup, file handle leak

    def query(self, sql):
        # Bad: Opening file without closing
        log_file = open('/var/log/queries.log', 'a')
        log_file.write(sql)
        return self.conn.execute(sql)

def process_large_file(filename):
    # Bad: File opened but never closed
    file = open(filename, 'r')
    data = file.read()
    return data.upper()

def fetch_user_data(user_id):
    # Bad: Connection not properly closed
    connection = create_db_connection()
    user = connection.fetch_user(user_id)
    return user

# Should be caught when priority is "unclosed resources" or "memory leaks"
