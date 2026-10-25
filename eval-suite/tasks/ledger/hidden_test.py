from datetime import date

from probe.ledger import Invoice, amount_due


def test_hidden_due_today_counts() -> None:
    assert amount_due([Invoice(100, date(2026, 3, 10))], date(2026, 3, 10)) == 100


def test_hidden_tomorrow_does_not() -> None:
    assert amount_due([Invoice(100, date(2026, 3, 11))], date(2026, 3, 10)) == 0


def test_hidden_paid_today_does_not() -> None:
    assert amount_due([Invoice(100, date(2026, 3, 10), paid=True)], date(2026, 3, 10)) == 0
