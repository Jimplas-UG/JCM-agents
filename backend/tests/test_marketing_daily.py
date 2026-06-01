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
    assert len(batch1) == 12
    assert len(batch2) == 12
    assert keys1.isdisjoint(keys2)
    platforms = {item["platform"] for item in batch1}
    assert platforms == {"article", "linkedin", "x", "instagram"}
    assert sum(1 for i in batch1 if i["platform"] == "article") == 3
    assert sum(1 for i in batch1 if i["platform"] == "linkedin") == 3
    assert sum(1 for i in batch1 if i["platform"] == "x") == 3
    assert sum(1 for i in batch1 if i["platform"] == "instagram") == 3


def test_daily_batch_same_day_idempotent_keys() -> None:
    engine = ContentEngine()
    d = date(2026, 6, 1)
    a = engine.generate_daily_batch(d)
    b = engine.generate_daily_batch(d)
    assert {x["metadata"]["cycle_key"] for x in a} == {x["metadata"]["cycle_key"] for x in b}
