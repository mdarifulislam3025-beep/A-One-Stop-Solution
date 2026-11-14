"""Structural guarantees that must hold for every future migration. Run in CI; failing any of these blocks the merge."""
import sqlalchemy as sa
from sqlalchemy import Numeric, Float

from app.db.base import GLOBAL_TABLES
from app.models import Base

T = Base.metadata.tables
GEO_FLOATS = {("airports", "latitude"), ("airports", "longitude")}


def test_no_float_money_and_money_is_decimal_12_2():
    for t in T.values():
        for c in t.columns:
            if isinstance(c.type, Float):
                assert (t.name, c.name) in GEO_FLOATS, f"FLOAT not allowed: {t.name}.{c.name}"
    money_cols = [c for t in T.values() for c in t.columns if isinstance(c.type, Numeric)]
    assert money_cols
    for c in money_cols:
        assert (c.type.precision, c.type.scale) in {(12, 2), (9, 6)}, f"{c.table.name}.{c.name} has {c.type}"


def test_every_tenant_table_has_organization_id_fk():
    for name, t in T.items():
        if name in GLOBAL_TABLES:
            continue
        assert "organization_id" in t.c, f"{name} missing organization_id (add TenantMixin or list it in GLOBAL_TABLES)"
        fks = {fk.target_fullname for fk in t.c.organization_id.foreign_keys}
        assert "organizations.id" in fks, f"{name}.organization_id is not an FK to organizations"


def test_organization_id_is_indexed_or_leads_a_unique_or_composite_index():
    for name, t in T.items():
        if name in GLOBAL_TABLES:
            continue
        col = t.c.organization_id
        led = any(list(i.columns)[0].name == "organization_id" for i in t.indexes) or \
              any(list(c.columns)[0].name == "organization_id" for c in t.constraints if isinstance(c, sa.UniqueConstraint)) or \
              col.primary_key or col.index
        assert led, f"{name}: organization_id is not index-led (tenant scans would be sequential)"


def test_enums_are_check_constrained_varchar_not_native():
    for t in T.values():
        for c in t.columns:
            if isinstance(c.type, sa.Enum):
                assert not c.type.native_enum, f"{t.name}.{c.name} uses a native enum"


def test_partitioned_logs_include_partition_key_in_pk():
    for name in ("audit_logs", "supplier_api_logs", "search_request_logs"):
        assert "created_at" in {c.name for c in T[name].primary_key.columns}
        assert T[name].dialect_options["postgresql"]["partition_by"].startswith("RANGE")


def test_ledger_and_wallet_safety_constraints_present():
    names = lambda t: {c.name for c in T[t].constraints if c.name}
    assert any("one_sided_positive" in n for n in names("ledger_entries"))
    assert any("not_overdrawn" in n for n in names("wallets"))


def test_every_table_has_a_primary_key():
    assert all(len(t.primary_key.columns) for t in T.values())
