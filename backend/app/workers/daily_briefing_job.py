"""CLI entry for scheduled executive briefing + Telegram (Windows Task / manual)."""

from __future__ import annotations

import argparse
import asyncio
import sys

from app.workers.daily_briefing_delivery import deliver_executive_briefing
from app.db.redis_client import close_redis


async def _main(args: argparse.Namespace) -> int:
    try:
        if args.force:
            result = await deliver_executive_briefing(force=True)
        elif args.ensure:
            result = await deliver_executive_briefing(ensure=True)
        else:
            result = await deliver_executive_briefing(force=False)
    finally:
        await close_redis()

    print(result.get("status", "unknown"))
    if result.get("error"):
        print(f"error: {result['error']}")
    if result.get("telegram_sent"):
        return 0
    if result.get("status") in ("already_sent", "sent"):
        return 0
    return 1


def main() -> None:
    parser = argparse.ArgumentParser(description="JCM daily executive briefing delivery")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Regenerate briefing and send Telegram even if already sent today",
    )
    parser.add_argument(
        "--ensure",
        action="store_true",
        help="Send only if today's Telegram delivery has not been recorded",
    )
    args = parser.parse_args()
    raise SystemExit(asyncio.run(_main(args)))


if __name__ == "__main__":
    main()
