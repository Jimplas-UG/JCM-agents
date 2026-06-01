"""Marketing daily regeneration — unique cycle_key per calendar day."""

from datetime import date

from app.agents.marketing.content_engine import ContentEngine


def test_daily_batch_unique_cycle_keys_per_day() -> None:
    engine = ContentEngine()
    d1 = date(2026, 6, 1)
    d2 = date(2026, 6, 2)
    batch1 = engine.generate_daily_batch(d1)
    batch2 = engine.generate_daily_batch(d2)
    keys1 = {item["metadata"]["cycle_key"] for item in batch1}
    keys2 = {item["metadata"]["cycle_key"] for item in batch2}
    assert len(batch1) == 3
    assert len(batch2) == 3
    assert keys1.isdisjoint(keys2)


def test_daily_batch_same_day_idempotent_keys() -> None:
    engine = ContentEngine()
    d = date(2026, 6, 1)
    a = engine.generate_daily_batch(d)
    b = engine.generate_daily_batch(d)
    assert {x["metadata"]["cycle_key"] for x in a} == {x["metadata"]["cycle_key"] for x in b}
