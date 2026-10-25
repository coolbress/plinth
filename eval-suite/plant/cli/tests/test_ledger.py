from datetime import date

from probe.ledger import Invoice, amount_due


def test_overdue_counts() -> None:
    assert amount_due([Invoice(100, date(2026, 3, 1))], date(2026, 3, 10)) == 100


def test_future_does_not_count() -> None:
    assert amount_due([Invoice(100, date(2026, 4, 1))], date(2026, 3, 10)) == 0


def test_paid_does_not_count() -> None:
    assert amount_due([Invoice(100, date(2026, 3, 1), paid=True)], date(2026, 3, 10)) == 0
