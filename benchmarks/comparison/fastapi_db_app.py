import sqlite3
import os
from fastapi import FastAPI, HTTPException

app = FastAPI()

DB_PATH = os.path.join(os.path.dirname(__file__), "bench.sqlite3")

def get_user(user_id):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.execute("SELECT id, name, email, age, role FROM users WHERE id = ?", (user_id,))
    row = cursor.fetchone()
    conn.close()
    if row:
        return dict(row)
    return None

@app.get("/users/{user_id}")
def read_user(user_id: int):
    user = get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="not_found")
    return user
