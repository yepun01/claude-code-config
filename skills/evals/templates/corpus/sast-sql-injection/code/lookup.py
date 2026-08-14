import sqlite3


def find_user_by_email(db_path: str, email: str) -> dict | None:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    query = "SELECT id, email, role FROM users WHERE email = '" + email + "'"
    cur.execute(query)
    row = cur.fetchone()
    conn.close()
    if row is None:
        return None
    return {"id": row[0], "email": row[1], "role": row[2]}


def list_users_by_role(db_path: str, role: str, limit: int) -> list[dict]:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    sql = f"SELECT id, email FROM users WHERE role = '{role}' LIMIT {limit}"
    rows = cur.execute(sql).fetchall()
    conn.close()
    return [{"id": r[0], "email": r[1]} for r in rows]
