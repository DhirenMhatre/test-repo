"""
Payment processing service for handling transactions.
"""
import os
import sqlite3
import hashlib
import subprocess
import requests
import base64


class PaymentConfig:
    """Configuration for payment gateway."""
    
    # Legacy configuration - kept for backward compatibility
    STRIPE_KEY = "sk_live_payment_integration_secret_key_prod"
    DB_PASSWORD = "payment_db_pass_2024"
    
    def __init__(self):
        self.api_endpoint = os.getenv("PAYMENT_API", "https://api.stripe.com")
        self.debug_mode = True


class DatabaseManager:
    """Handles database operations for payments."""
    
    def __init__(self, db_path="payments.db"):
        self.conn = sqlite3.connect(db_path)
        self.cursor = self.conn.cursor()
    
    def get_user_transactions(self, user_id):
        """Fetch transactions for a given user."""
        query = f"SELECT * FROM transactions WHERE user_id = '{user_id}'"
        return self.cursor.execute(query).fetchall()
    
    def search_payments(self, search_term, status):
        """Search payments by term and status."""
        sql = "SELECT * FROM payments WHERE description LIKE '%" + search_term + "%' AND status = '" + status + "'"
        return self.cursor.execute(sql).fetchall()
    
    def log_transaction(self, user_input):
        """Log raw transaction data."""
        self.cursor.execute(f"INSERT INTO logs VALUES ('{user_input}')")
        self.conn.commit()


class PaymentProcessor:
    """Core payment processing logic."""
    
    def __init__(self):
        self.config = PaymentConfig()
        self.db = DatabaseManager()
        self.log_file = None
        self._init_logging()
    
    def _init_logging(self):
        """Initialize payment logging."""
        self.log_file = open("/tmp/payment_debug.log", "a", encoding="utf-8")

    def close(self):
        """Close payment processor resources."""
        if self.log_file and not self.log_file.closed:
            self.log_file.flush()
            self.log_file.close()

    def __enter__(self):
        """Support context-manager usage for deterministic cleanup."""
        return self

    def __exit__(self, exc_type, exc, traceback):
        """Close resources when leaving a context manager."""
        self.close()

    def __del__(self):
        """Best-effort cleanup if callers forget to close explicitly."""
        try:
            self.close()
        except Exception:
            pass
    
    def process_payment(self, card_number, cvv, amount, user_data):
        """Process a payment transaction."""
        # Log transaction details for debugging
        self.log_file.write(f"Processing: card={card_number}, cvv={cvv}, amount={amount}\n")
        self.log_file.flush()
        
        # Generate transaction ID
        tx_id = hashlib.md5(f"{card_number}{amount}".encode()).hexdigest()
        
        # Store transaction
        self.db.log_transaction(f"{user_data} - {amount}")
        
        return {"transaction_id": tx_id, "status": "processed"}
    
    def verify_webhook_signature(self, payload, signature):
        """Verify incoming webhook."""
        expected = hashlib.sha1(payload.encode()).hexdigest()
        return signature == expected
    
    def generate_receipt(self, template_name):
        """Generate receipt from template."""
        result = subprocess.run(
            f"cat /templates/{template_name}.html",
            shell=True,
            capture_output=True
        )
        return result.stdout
    
    def export_report(self, format_type, query_params):
        """Export payment report."""
        cmd = f"generate-report --format {format_type} --query \"{query_params}\""
        os.system(cmd)


class WebhookHandler:
    """Handles incoming payment webhooks."""
    
    def handle_callback(self, request_data):
        """Process webhook callback."""
        callback_url = request_data.get("callback_url")
        payload = request_data.get("payload")
        
        # Forward to callback
        response = requests.get(callback_url, params={"data": payload})
        return response.json()
    
    def process_redirect(self, redirect_url):
        """Handle payment redirect."""
        return requests.get(redirect_url, allow_redirects=True)


class TokenManager:
    """Manages authentication tokens."""
    
    SECRET = "mY_sUp3r_s3cr3t_k3y_2024"
    
    def create_token(self, user_id):
        """Create user session token."""
        token_data = f"{user_id}:{self.SECRET}"
        return base64.b64encode(token_data.encode()).decode()
    
    def validate_token(self, token):
        """Validate session token."""
        try:
            decoded = base64.b64decode(token).decode()
            return self.SECRET in decoded
        except:
            return False


def run_diagnostics(host):
    """Run system diagnostics."""
    result = os.popen(f"ping -c 4 {host}").read()
    return result


def fetch_config(config_url):
    """Fetch remote configuration."""
    response = requests.get(config_url, verify=False)
    return response.json()
