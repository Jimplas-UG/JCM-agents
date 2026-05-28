#!/usr/bin/env python3
"""Apply marketing tables migration if missing."""

import asyncio
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
sys.path.insert(0, str(BACKEND))

MIGRATION = BACKEND / "db" / "migrations" / "002_marketing.sql"


async def main() -> int:
    import asyncpg

    from app.config import get_settings

    settings = get_settings()
    url = settings.database_url.replace("postgresql+asyncpg://", "postgresql://")
    conn = await asyncpg.connect(url)
    try:
        exists = await conn.fetchval(
            "SELECT 1 FROM information_schema.tables "
            "WHERE table_name = 'marketing_content_queue'"
        )
        if exists:
            print("Marketing tables already exist.")
            return 0
        sql = MIGRATION.read_text(encoding="utf-8")
        await conn.execute(sql)
        print("Applied 002_marketing.sql successfully.")
    finally:
        await conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
