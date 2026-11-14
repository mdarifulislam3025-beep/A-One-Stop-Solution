"""Shared SQLAlchemy base, mixins and column conventions.

Rules enforced here (and by tests/test_schema_invariants.py):
  * every money column is NUMERIC(12,2); rates/percentages are NUMERIC(9,6) via Rate; never FLOAT
  * every tenant-owned table carries organization_id (TenantMixin); only listed GLOBAL tables are exempt
  * primary keys are time-ordered UUIDv7 (index-locality at millions of rows), generated in the app
  * enums are VARCHAR + CHECK (native_enum=False) so values can change via Alembic without ALTER TYPE
"""
from __future__ import annotations

import datetime as dt
import enum
import os
import time
import uuid
from decimal import Decimal

from sqlalchemy import DateTime, ForeignKey, MetaData, Numeric, func
from sqlalchemy import Enum as SAEnum
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

NAMING = {
    "ix": "ix_%(table_name)s_%(column_0_N_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_N_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}

Money = Numeric(12, 2)   # all currency amounts
Rate = Numeric(9, 6)     # percentages / tax rates / FX (0.003000 = 0.3%)


def uuid7() -> uuid.UUID:
    """RFC 9562 UUIDv7: 48-bit ms timestamp + random. Sorts by creation time."""
    ms = int(time.time() * 1000)
    b = bytearray(ms.to_bytes(6, "big") + os.urandom(10))
    b[6] = (b[6] & 0x0F) | 0x70
    b[8] = (b[8] & 0x3F) | 0x80
    return uuid.UUID(bytes=bytes(b))


def E(py_enum: type[enum.Enum], length: int = 32) -> SAEnum:
    return SAEnum(py_enum, native_enum=False, length=length, create_constraint=True, validate_strings=True,
                  values_callable=lambda e: [m.value for m in e])


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING)
    type_annotation_map = {
        uuid.UUID: UUID(as_uuid=True),
        dt.datetime: DateTime(timezone=True),
        dict: JSONB,
        Decimal: Money,  # any bare `Decimal` annotation becomes DECIMAL(12,2) - float is impossible by default
    }


class PkMixin:
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid7)


class TimestampMixin:
    created_at: Mapped[dt.datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[dt.datetime] = mapped_column(server_default=func.now(), onupdate=func.now())


class TenantMixin:
    """Owning tenant. Every query is filtered by the caller's visible org set; Postgres RLS enforces it again (Phase 2)."""
    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id", ondelete="RESTRICT"), index=True)


# Tables that are intentionally NOT tenant-scoped (platform reference data or the tenant table itself).
GLOBAL_TABLES = {"organizations", "roles", "permissions", "role_permissions", "airlines", "airports", "suppliers"}
