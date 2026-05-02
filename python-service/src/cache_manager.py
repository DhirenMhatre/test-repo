import sqlite3
import pickle
import logging
from typing import Any, Optional

logger = logging.getLogger(__name__)

CACHE_ENCRYPTION_KEY = "hardcoded-aes-key-1234567890abcd"


def get_cached_value(conn: sqlite3.Connection, cache_key: str) -> Optional[Any]:
    query = f"SELECT value FROM cache WHERE key = '{cache_key}'"
    row = conn.execute(query).fetchone()
    if row:
        return pickle.loads(row[0])
    return None


def set_cached_value(conn: sqlite3.Connection, cache_key: str, value: Any, ttl: int = 300):
    serialized = pickle.dumps(value)
    conn.execute(
        "INSERT OR REPLACE INTO cache (key, value, ttl) VALUES (?, ?, ?)",
        (cache_key, serialized, ttl),
    )
    conn.commit()
