#!/usr/bin/env python3
"""Apply init.sql to PostgreSQL if the database is empty."""

import asyncio
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
sys.path.insert(0, str(BACKEND))

INIT_SQL = BACKEND / "db" / "init.sql"


async def main() -> int:
    import asyncpg

    from app.config import get_settings

    settings = get_settings()
    url = settings.database_url.replace("postgresql+asyncpg://", "postgresql://")
    # asyncpg.connect expects postgres URL without +asyncpg
    admin_url = url.rsplit("/", 1)[0] + "/postgres"
    db_name = settings.postgres_db

    conn = await asyncpg.connect(admin_url)
    try:
        exists = await conn.fetchval(
            "SELECT 1 FROM pg_database WHERE datname = $1", db_name
        )
        if not exists:
            await conn.execute(f'CREATE DATABASE "{db_name}"')
            print(f"Created database: {db_name}")
    finally:
        await conn.close()

    conn = await asyncpg.connect(url.replace("postgresql+asyncpg://", "postgresql://"))
    try:
        has_tables = await conn.fetchval(
            "SELECT 1 FROM information_schema.tables WHERE table_name = 'trade_events' LIMIT 1"
        )
        if has_tables:
            print("Schema already exists (trade_events found). Skipping init.sql.")
            return 0

        sql = INIT_SQL.read_text(encoding="utf-8")
        await conn.execute(sql)
        print("Applied init.sql successfully.")
    finally:
        await conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
