"""Enum coercion helpers for ORM / ingest boundaries."""

import enum
from typing import TypeVar

E = TypeVar("E", bound=enum.Enum)


def coerce_enum(enum_cls: type[E], value: str | E | None, default: E | None = None) -> E | None:
    if value is None:
        return default
    if isinstance(value, enum_cls):
        return value
    try:
        return enum_cls(value)
    except ValueError:
        if default is not None:
            return default
        raise


def coerce_enum_list(enum_cls: type[E], values: list[str] | list[E]) -> list[E]:
    return [coerce_enum(enum_cls, v) for v in values]  # type: ignore[misc]
