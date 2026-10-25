"""Invoices and what is owed on them."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date


@dataclass(frozen=True)
class Invoice:
    amount: int
    due: date
    paid: bool = False


def amount_due(invoices: list[Invoice], today: date) -> int:
    """The total of unpaid invoices that have fallen due by `today`."""
    return sum(i.amount for i in invoices if not i.paid and i.due < today)
