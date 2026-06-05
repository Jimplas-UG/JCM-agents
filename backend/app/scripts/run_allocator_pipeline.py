"""Allocator pipeline: backfill closes, reconcile, tear sheet, readiness gates."""

from __future__ import annotations

import asyncio
import sys

from app.db.session import AsyncSessionLocal
from app.scripts.backfill_trade_closed_from_mt5 import run_backfill
from app.scripts.close_stale_jcm_opens import run_close_stale
from app.scripts.reconcile_trades import run_reconcile
from app.services.allocator_tear_sheet import build_allocator_tear_sheet, write_tear_sheet_json


async def main() -> dict:
    backfill = await run_backfill(dry_run=False)
    stale = await run_close_stale(dry_run=False)
    reconcile = await run_reconcile()
    async with AsyncSessionLocal() as db:
        sheet = await build_allocator_tear_sheet(db)
    path = write_tear_sheet_json(sheet)
    state_path = path.parent / "allocator-pipeline-state.json"
    import json

    state_path.write_text(
        json.dumps(
            {
                "stale_jcm_opens": reconcile.get("jcm_open", 0),
                "reconcile_ok": reconcile.get("ok", False),
                "updated_at": sheet.get("generated_at"),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    return {
        "backfill": backfill,
        "stale_closed": stale,
        "reconcile": reconcile,
        "tear_sheet": str(path),
        "check_ready": sheet.get("allocator_check_ready"),
        "progress": sheet.get("allocator_progress"),
    }


if __name__ == "__main__":
    result = asyncio.run(main())
    print(result)
    if result.get("reconcile", {}).get("stale_open_records") and not result.get("check_ready"):
        sys.exit(0)
    sys.exit(0)
