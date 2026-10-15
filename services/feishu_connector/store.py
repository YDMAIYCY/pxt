"""Local development vault. Provider tokens are encrypted; session keys are hashed."""
import hashlib
import json
import sqlite3
import time
from pathlib import Path

from cryptography.fernet import Fernet


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


class Store:
    def __init__(self, path: Path, encryption_key: str):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.cipher = Fernet(encryption_key.encode())
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("""CREATE TABLE IF NOT EXISTS connections (
            session_hash TEXT PRIMARY KEY, expires REAL NOT NULL,
            state_hash TEXT UNIQUE, state_expires REAL,
            verifier BLOB, status TEXT NOT NULL, tokens BLOB,
            account TEXT, error TEXT)""")
        self.db.commit()

    def create(self, session: str, state: str, verifier: str):
        now = time.time()
        with self.db:
            self.db.execute("DELETE FROM connections WHERE expires < ?", (now,))
            self.db.execute("INSERT INTO connections VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, NULL)",
                            (digest(session), now + 8 * 3600, digest(state), now + 300,
                             self.cipher.encrypt(verifier.encode()), "pending"))

    def get(self, session_hash: str):
        row = self.db.execute("SELECT * FROM connections WHERE session_hash=? AND expires>?",
                              (session_hash, time.time())).fetchone()
        return dict(row) if row else None

    def consume_state(self, state: str):
        with self.db:
            row = self.db.execute("SELECT * FROM connections WHERE state_hash=? AND state_expires>? AND expires>? AND status='pending'",
                                  (digest(state), time.time(), time.time())).fetchone()
            if not row:
                return None
            self.db.execute("UPDATE connections SET state_hash=NULL, verifier=NULL, status='exchanging' WHERE session_hash=?",
                            (row["session_hash"],))
        return row["session_hash"], self.cipher.decrypt(row["verifier"]).decode()

    def save_tokens(self, key: str, token: dict, account: str | None = None):
        token = dict(token)
        now = time.time()
        token["expires_at"] = now + int(token["expires_in"])
        token["refresh_expires_at"] = now + int(token.get("refresh_token_expires_in", 0))
        encrypted = self.cipher.encrypt(json.dumps(token).encode())
        with self.db:
            self.db.execute("UPDATE connections SET tokens=?, account=COALESCE(?, account), status='connected', error=NULL WHERE session_hash=?",
                            (encrypted, account, key))

    def tokens(self, row: dict) -> dict:
        return json.loads(self.cipher.decrypt(row["tokens"]))

    def fail(self, key: str, message: str):
        with self.db:
            self.db.execute("UPDATE connections SET status='failed', error=?, tokens=NULL WHERE session_hash=?", (message, key))

    def delete(self, key: str):
        with self.db:
            self.db.execute("DELETE FROM connections WHERE session_hash=?", (key,))
