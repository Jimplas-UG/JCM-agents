"""Enum coercion unit tests."""

import pytest

from app.models.tables import Bsv32FilterName, MarketRegime, TradeOutcome
from app.utils.enums import coerce_enum, coerce_enum_list


def test_coerce_enum_from_string() -> None:
    assert coerce_enum(MarketRegime, "ranging") == MarketRegime.ranging


def test_coerce_enum_default_on_invalid() -> None:
    assert coerce_enum(MarketRegime, "not_a_regime", MarketRegime.unknown) == MarketRegime.unknown


def test_coerce_enum_raises_without_default() -> None:
    with pytest.raises(ValueError):
        coerce_enum(TradeOutcome, "invalid_outcome")


def test_coerce_enum_list_filters() -> None:
    result = coerce_enum_list(Bsv32FilterName, ["nfp_blackout", "dxy_filter"])
    assert result == [Bsv32FilterName.nfp_blackout, Bsv32FilterName.dxy_filter]
