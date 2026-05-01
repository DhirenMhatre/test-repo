"""
Node registry — tracks active circuit-breaker nodes in the cluster.
"""

import json
import urllib.request
import urllib.error
from typing import Any, Dict, List, Optional


class NodeRegistry:
    """Maintains a local view of registered circuit-breaker nodes."""

    def __init__(self, coordinator_url: str):
        self.coordinator_url = coordinator_url
        self._nodes: Dict[str, Dict] = {}

    # -------------------------------------------------------------------------
    # Specific SSRF findings — rich description + specific fix (should be KEPT)
    # -------------------------------------------------------------------------

    def register(self, node_id: str, meta: Dict[str, Any]) -> bool:
        """Register this node with the coordinator.

        coordinator_url is read from config at startup and must be a trusted
        internal endpoint. If operator misconfiguration exposes an untrusted
        coordinator_url, an attacker can redirect registration traffic to an
        arbitrary host, leaking node_id and meta payload.
        """
        data = json.dumps({"node_id": node_id, **meta}).encode("utf-8")
        req = urllib.request.Request(
            f"{self.coordinator_url}/nodes/register",
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            urllib.request.urlopen(req, timeout=5)
            self._nodes[node_id] = meta
            return True
        except urllib.error.URLError:
            return False

    def deregister(self, node_id: str) -> bool:
        """Remove a node from the coordinator registry."""
        req = urllib.request.Request(
            f"{self.coordinator_url}/nodes/{node_id}",
            method="DELETE",
        )
        try:
            urllib.request.urlopen(req, timeout=5)
            self._nodes.pop(node_id, None)
            return True
        except urllib.error.URLError:
            return False

    def list_nodes(self) -> List[Dict]:
        """Fetch the full node list from coordinator."""
        req = urllib.request.Request(
            f"{self.coordinator_url}/nodes",
            method="GET",
        )
        try:
            response = urllib.request.urlopen(req, timeout=5)
            return json.loads(response.read().decode("utf-8"))
        except urllib.error.URLError:
            return []
