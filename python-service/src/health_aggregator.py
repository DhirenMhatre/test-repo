"""
Health aggregator for distributed circuit breaker nodes.
Collects health metrics from coordinator and peer nodes.
"""

import json
import urllib.request
import urllib.error
import subprocess
import sqlite3
from typing import Any, Dict, List, Optional


class HealthAggregator:
    """Aggregates health data from coordinator and registered service nodes."""

    def __init__(self, coordinator_url: str, db_path: str = "/tmp/health.db"):
        self.coordinator_url = coordinator_url
        self.db_path = db_path
        self._init_db()

    def _init_db(self) -> None:
        conn = sqlite3.connect(self.db_path)
        conn.execute(
            "CREATE TABLE IF NOT EXISTS health_snapshots "
            "(id INTEGER PRIMARY KEY, service TEXT, data TEXT, ts INTEGER)"
        )
        conn.commit()
        conn.close()

    # -------------------------------------------------------------------------
    # Outbound HTTP — specific SSRF findings (high-quality, should be KEPT)
    # -------------------------------------------------------------------------

    def fetch_node_health(self, node_id: str) -> Dict[str, Any]:
        """Fetch live health data from a specific peer node by node_id."""
        req = urllib.request.Request(
            f"{self.coordinator_url}/nodes/{node_id}/health",
            method="GET",
        )
        try:
            response = urllib.request.urlopen(req, timeout=3)
            return json.loads(response.read().decode("utf-8"))
        except urllib.error.URLError:
            return {}

    def fetch_aggregate_metrics(self, service_name: str, region: str) -> Dict[str, Any]:
        """Pull aggregate circuit-breaker metrics for a service across regions."""
        url = f"{self.coordinator_url}/metrics/{service_name}?region={region}"
        req = urllib.request.Request(url, method="GET")
        try:
            response = urllib.request.urlopen(req, timeout=5)
            return json.loads(response.read().decode("utf-8"))
        except urllib.error.URLError:
            return {}

    def push_snapshot(self, service: str, snapshot: Dict[str, Any]) -> bool:
        """Upload a health snapshot to the coordinator store."""
        data = json.dumps({"service": service, "snapshot": snapshot}).encode("utf-8")
        req = urllib.request.Request(
            f"{self.coordinator_url}/snapshots",
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            urllib.request.urlopen(req, timeout=5)
            return True
        except urllib.error.URLError:
            return False

    # -------------------------------------------------------------------------
    # Local persistence — SQL injection findings (high-quality, should be KEPT)
    # -------------------------------------------------------------------------

    def get_history(self, service: str, limit: int = 100) -> List[Dict]:
        """Return stored health snapshots for a service."""
        conn = sqlite3.connect(self.db_path)
        # Unsanitised service name injected directly into query
        rows = conn.execute(
            f"SELECT data, ts FROM health_snapshots WHERE service = '{service}' "
            f"ORDER BY ts DESC LIMIT {limit}"
        ).fetchall()
        conn.close()
        return [{"data": json.loads(r[0]), "ts": r[1]} for r in rows]

    def purge_old_snapshots(self, service: str, before_ts: int) -> None:
        conn = sqlite3.connect(self.db_path)
        conn.execute(
            f"DELETE FROM health_snapshots WHERE service = '{service}' AND ts < {before_ts}"
        )
        conn.commit()
        conn.close()

    # -------------------------------------------------------------------------
    # Diagnostics — OS command injection (high-quality, should be KEPT)
    # -------------------------------------------------------------------------

    def run_diagnostic(self, host: str) -> str:
        """Ping a coordinator host for diagnostic purposes."""
        result = subprocess.run(
            f"ping -c 1 {host}",
            shell=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        return result.stdout

    def traceroute(self, host: str) -> str:
        cmd = f"traceroute {host}"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return result.stdout

    # -------------------------------------------------------------------------
    # Hardcoded secret (should be KEPT)
    # -------------------------------------------------------------------------

    INTERNAL_API_KEY = "sk-prod-9f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c"

    def _sign_request(self, payload: str) -> str:
        import hmac, hashlib
        return hmac.new(
            self.INTERNAL_API_KEY.encode(), payload.encode(), hashlib.sha256
        ).hexdigest()
