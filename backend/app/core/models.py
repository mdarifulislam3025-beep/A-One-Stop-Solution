"""Cross-cutting tables: idempotency, transactional outbox, notifications, and append-only logs.

Log tables (audit_logs, supplier_api_logs, search_request_logs) have no inbound foreign keys, so they are RANGE-partitioned by
month on created_at (PK includes the partition key). Retention = drop a partition, never DELETE. Partitions are created by a Celery beat job.
"""
from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import BigInteger, Boolean, ForeignKey, Index, Integer, SmallInteger, String, UniqueConstraint, func, text
from sqlalchemy.dialects.postgresql import INET
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, PkMixin, TenantMixin, E, uuid7
from app.db.enums import Channel, IdemStatus, OutboxStatus

NOW = func.now()


class IdempotencyKey(Base, PkMixin, TenantMixin):
    """Same (org, scope, key) + same request_hash => return the stored response. Same key + different hash => 422."""
    __tablename__ = "idempotency_keys"
    scope: Mapped[str] = mapped_column(String(48))               # booking.create, payment.init, deposit.approve ...
    key: Mapped[str] = mapped_column(String(80))
    request_hash: Mapped[str] = mapped_column(String(64))
    status: Mapped[IdemStatus] = mapped_column(E(IdemStatus), default=IdemStatus.IN_PROGRESS)
    response_code: Mapped[int | None] = mapped_column(SmallInteger)
    response_body: Mapped[dict | None]
    resource_type: Mapped[str | None] = mapped_column(String(32))
    resource_id: Mapped[uuid.UUID | None]
    locked_until: Mapped[dt.datetime | None]
    created_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    expires_at: Mapped[dt.datetime]
    __table_args__ = (UniqueConstraint("organization_id", "scope", "key"), Index("ix_idempotency_keys_expires", "expires_at"))


class OutboxEvent(Base, TenantMixin):
    """Written in the SAME transaction as the state change; a relay publishes to Celery. No lost or phantom side effects."""
    __tablename__ = "outbox_events"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    topic: Mapped[str] = mapped_column(String(64))               # ticketing.issue, voucher.pdf, notify.send, ledger.reconcile
    payload: Mapped[dict]
    dedupe_key: Mapped[str | None] = mapped_column(String(96))
    status: Mapped[OutboxStatus] = mapped_column(E(OutboxStatus), default=OutboxStatus.PENDING)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    next_attempt_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    created_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    sent_at: Mapped[dt.datetime | None]
    __table_args__ = (Index("ix_outbox_events_pending", "next_attempt_at", postgresql_where=text("status = 'pending'")),
                      Index("uq_outbox_events_dedupe", "dedupe_key", unique=True, postgresql_where=text("dedupe_key IS NOT NULL")))


class Notification(Base, PkMixin, TenantMixin):
    __tablename__ = "notifications"
    user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    channel: Mapped[Channel] = mapped_column(E(Channel))
    template: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict]
    status: Mapped[str] = mapped_column(String(12), default="queued")
    provider_msg_id: Mapped[str | None] = mapped_column(String(96))
    sent_at: Mapped[dt.datetime | None]
    read_at: Mapped[dt.datetime | None]
    created_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    __table_args__ = (Index("ix_notifications_user_created", "user_id", "created_at"),)


class AuditLog(Base, TenantMixin):
    __tablename__ = "audit_logs"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid7)
    created_at: Mapped[dt.datetime] = mapped_column(primary_key=True, server_default=NOW)
    actor_user_id: Mapped[uuid.UUID | None]
    action: Mapped[str] = mapped_column(String(64))
    entity_type: Mapped[str] = mapped_column(String(48))
    entity_id: Mapped[str | None] = mapped_column(String(64))
    ip: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(String(255))
    request_id: Mapped[str | None] = mapped_column(String(48))
    before: Mapped[dict | None]
    after: Mapped[dict | None]
    __table_args__ = (Index("ix_audit_logs_org_created", "organization_id", "created_at"),
                      Index("ix_audit_logs_entity", "entity_type", "entity_id"),
                      {"postgresql_partition_by": "RANGE (created_at)"})


class SupplierApiLog(Base, TenantMixin):
    __tablename__ = "supplier_api_logs"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid7)
    created_at: Mapped[dt.datetime] = mapped_column(primary_key=True, server_default=NOW)
    supplier_account_id: Mapped[uuid.UUID]
    operation: Mapped[str] = mapped_column(String(32))
    latency_ms: Mapped[int] = mapped_column(Integer)
    ok: Mapped[bool] = mapped_column(Boolean)
    error_code: Mapped[str | None] = mapped_column(String(48))
    request_id: Mapped[str | None] = mapped_column(String(48))
    payload_ref: Mapped[str | None] = mapped_column(String(255))     # raw XML/JSON goes to object storage, not Postgres
    __table_args__ = (Index("ix_supplier_api_logs_acct_created", "supplier_account_id", "created_at"),
                      {"postgresql_partition_by": "RANGE (created_at)"})


class SearchRequestLog(Base, TenantMixin):
    """Sampled/aggregated search telemetry: look-to-book ratio per supplier is a contractual and cost metric."""
    __tablename__ = "search_request_logs"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid7)
    created_at: Mapped[dt.datetime] = mapped_column(primary_key=True, server_default=NOW)
    user_id: Mapped[uuid.UUID | None]
    origin: Mapped[str] = mapped_column(String(3))
    destination: Mapped[str] = mapped_column(String(3))
    depart_on: Mapped[dt.date]
    pax_count: Mapped[int] = mapped_column(SmallInteger)
    cache_hit: Mapped[bool] = mapped_column(Boolean)
    offers_count: Mapped[int] = mapped_column(Integer, default=0)
    latency_ms: Mapped[int] = mapped_column(Integer)
    supplier_breakdown: Mapped[dict | None]
    __table_args__ = (Index("ix_search_request_logs_org_created", "organization_id", "created_at"),
                      {"postgresql_partition_by": "RANGE (created_at)"})
