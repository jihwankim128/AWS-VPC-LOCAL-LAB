import os
from html import escape

import pymysql
from flask import Flask


app = Flask(__name__)


def fetch_content():
    connection = pymysql.connect(
        host=os.environ.get("DB_HOST", "10.10.2.10"),
        port=int(os.environ.get("DB_PORT", "3306")),
        user=os.environ.get("DB_USER", "root"),
        password=os.environ.get("DB_PASSWORD", "localpass"),
        database=os.environ.get("DB_NAME", "appdb"),
        connect_timeout=3,
        read_timeout=3,
        cursorclass=pymysql.cursors.DictCursor,
    )
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT title, body FROM page_contents ORDER BY id LIMIT 1"
            )
            return cursor.fetchone()
    finally:
        connection.close()


@app.route("/")
def index():
    try:
        content = fetch_content()
        if not content:
            title = "AWS VPC Local Lab"
            body = "DB row was not found."
            status = "DB 연결 성공, 표시할 데이터 없음"
        else:
            title = content["title"]
            body = content["body"]
            status = "DB 연결 성공"
    except Exception as exc:
        title = "AWS VPC Local Lab"
        body = f"Database query failed: {exc}"
        status = "DB 연결 실패"

    return f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <title>{escape(title)}</title>
  <style>
    body {{
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      margin: 40px;
      line-height: 1.6;
    }}
    code {{
      background: #f4f4f4;
      padding: 2px 6px;
      border-radius: 4px;
    }}
  </style>
</head>
<body>
  <h1>{escape(title)}</h1>
  <p><strong>{escape(status)}</strong></p>
  <p>{escape(body)}</p>
  <hr>
  <p><code>Host -> DNS -> IGW -> EC2 AppServer -> RDS Database</code></p>
</body>
</html>
"""


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
