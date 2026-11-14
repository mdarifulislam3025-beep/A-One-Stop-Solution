"""ERP: multi-entity chart of accounts, double-entry journal, wallets/credit, payments, pricing rules, invoicing.

Money invariants (enforced in DB, not only in code):
  * a journal is balanced: SUM(debit)=SUM(credit) -> deferred constraint trigger, created in the Alembic migration
  * ledger lines are append-only (UPDATE/DELETE revoked from the app role); corrections are reversing journals
  * a wallet can never be overdrawn beyond its credit limit: CHECK (balance + credit_limit - held >= 0)
"""
from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal

from sqlalchemy import (BigInteger, Boolean, CheckConstraint, Date, ForeignKey, Index, Integer, String, Text,
                        UniqueConstraint, func, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, PkMixin, Rate, TenantMixin, TimestampMixin, E
from app.db.enums import (DisputeStatus, ReconQueue, ReconStatus, RefundStatus, AccountKind, AccountType, AmountKind, ApprovalStatus, ChargeType, HoldStatus, InvoiceStatus,
                          JournalKind, JournalStatus, MarkupScope, PayMethod, PayProvider, PayStatus, RouteType)

NOW = func.now()


class Account(Base, PkMixin, TenantMixin, TimestampMixin):
    """Chart of accounts, one tree per legal entity (sister concern). Wallet accounts are LIABILITY (we owe the agent)."""
    __tablename__ = "accounts"
    code: Mapped[str] = mapped_column(String(32))
    name: Mapped[str] = mapped_column(String(160))
    account_type: Mapped[AccountType] = mapped_column(E(AccountType))
    kind: Mapped[AccountKind] = mapped_column(E(AccountKind), default=AccountKind.NORMAL)
    parent_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("accounts.id", ondelete="RESTRICT"))
    currency: Mapped[str] = mapped_column(String(3), default="BDT")
    is_postable: Mapped[bool] = mapped_column(Boolean, default=True)
    __table_args__ = (UniqueConstraint("organization_id", "code"),)


class JournalEntry(Base, PkMixin, TenantMixin):
    """Journal header. `txn_ref` is the user-visible Transaction ID. (organization_id, idempotency_key) makes retries safe."""
    __tablename__ = "journal_entries"
    txn_ref: Mapped[str] = mapped_column(String(32), unique=True)
    kind: Mapped[JournalKind] = mapped_column(E(JournalKind))
    status: Mapped[JournalStatus] = mapped_column(E(JournalStatus), default=JournalStatus.POSTED)
    booking_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("bookings.id", ondelete="RESTRICT"))
    payment_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("payments.id", ondelete="RESTRICT"))
    reversal_of_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("journal_entries.id", ondelete="RESTRICT"))
    idempotency_key: Mapped[str | None] = mapped_column(String(80))
    memo: Mapped[str | None] = mapped_column(String(255))
    created_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    posted_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    __table_args__ = (
        Index("uq_journal_entries_org_idem", "organization_id", "idempotency_key", unique=True,
              postgresql_where=text("idempotency_key IS NOT NULL")),
        Index("ix_journal_entries_org_posted", "organization_id", "posted_at"),
        Index("ix_journal_entries_booking_id", "booking_id"),
    )


class LedgerEntry(Base, TenantMixin):
    """One debit OR credit line. BIGINT identity gives a total order for statements and reconciliation."""
    __tablename__ = "ledger_entries"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    journal_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("journal_entries.id", ondelete="RESTRICT"))
    account_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("accounts.id", ondelete="RESTRICT"))
    wallet_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("wallets.id", ondelete="RESTRICT"))
    debit: Mapped[Decimal] = mapped_column(default=Decimal("0.00"))
    credit: Mapped[Decimal] = mapped_column(default=Decimal("0.00"))
    currency: Mapped[str] = mapped_column(String(3), default="BDT")
    balance_after: Mapped[Decimal | None]                       # wallet lines only: the 'Balance After' column of the statement
    counterparty_org_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("organizations.id", ondelete="RESTRICT"))  # inter-company
    agent_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    payment_method: Mapped[PayMethod | None] = mapped_column(E(PayMethod))
    created_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    __table_args__ = (
        CheckConstraint("debit >= 0 AND credit >= 0 AND (debit = 0 OR credit = 0) AND (debit + credit) > 0", name="one_sided_positive"),
        Index("ix_ledger_entries_journal_id", "journal_id"),
        Index("ix_ledger_entries_account_id_id", "account_id", "id"),
        Index("ix_ledger_entries_wallet_id_id", "wallet_id", "id"),
        Index("ix_ledger_entries_org_created", "organization_id", "created_at"),
    )


class Wallet(Base, PkMixin, TenantMixin, TimestampMixin):
    """Cached balance for fast reads. The ledger is the truth; a nightly Celery job reconciles and pages on any drift."""
    __tablename__ = "wallets"
    owner_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))  # NULL = org wallet; set = B2C wallet
    account_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("accounts.id", ondelete="RESTRICT"))
    currency: Mapped[str] = mapped_column(String(3), default="BDT")
    balance: Mapped[Decimal] = mapped_column(default=Decimal("0.00"))
    credit_limit: Mapped[Decimal] = mapped_column(default=Decimal("0.00"))
    held_amount: Mapped[Decimal] = mapped_column(default=Decimal("0.00"))
    status: Mapped[str] = mapped_column(String(12), default="active")
    version_id: Mapped[int] = mapped_column(Integer, default=1)  # optimistic lock; hot path also uses SELECT ... FOR UPDATE
    __mapper_args__ = {"version_id_col": version_id}
    __table_args__ = (
        CheckConstraint("balance + credit_limit - held_amount >= 0", name="not_overdrawn"),
        CheckConstraint("held_amount >= 0 AND credit_limit >= 0", name="non_negative_parts"),
        Index("uq_wallets_org_ccy", "organization_id", "currency", unique=True, postgresql_where=text("owner_user_id IS NULL")),
        Index("uq_wallets_owner_ccy", "organization_id", "owner_user_id", "currency", unique=True,
              postgresql_where=text("owner_user_id IS NOT NULL")),
    )


class WalletHold(Base, PkMixin, TenantMixin):
    """Funds reserved while an issue is in process / partial payment is approved."""
    __tablename__ = "wallet_holds"
    wallet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("wallets.id", ondelete="RESTRICT"))
    booking_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("bookings.id", ondelete="RESTRICT"))
    amount: Mapped[Decimal]
    status: Mapped[HoldStatus] = mapped_column(E(HoldStatus), default=HoldStatus.ACTIVE)
    expires_at: Mapped[dt.datetime | None]
    idempotency_key: Mapped[str | None] = mapped_column(String(80))
    created_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    __table_args__ = (
        CheckConstraint("amount > 0", name="positive"),
        Index("uq_wallet_holds_org_idem", "organization_id", "idempotency_key", unique=True, postgresql_where=text("idempotency_key IS NOT NULL")),
        Index("ix_wallet_holds_active_expiry", "status", "expires_at"),
        Index("ix_wallet_holds_wallet_id", "wallet_id"),
    )


class DepositRequest(Base, PkMixin, TenantMixin, TimestampMixin):
    __tablename__ = "deposit_requests"
    wallet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("wallets.id", ondelete="RESTRICT"))
    requested_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    amount: Mapped[Decimal]
    method: Mapped[PayMethod] = mapped_column(E(PayMethod))
    reference_no: Mapped[str] = mapped_column(String(64))          # bank slip / bKash TrxID; unique per method to stop re-use
    proof_storage_key: Mapped[str | None] = mapped_column(String(255))
    status: Mapped[ApprovalStatus] = mapped_column(E(ApprovalStatus), default=ApprovalStatus.PENDING)
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    reviewed_at: Mapped[dt.datetime | None]
    journal_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("journal_entries.id", ondelete="RESTRICT"))
    note: Mapped[str | None] = mapped_column(String(255))
    __table_args__ = (
        CheckConstraint("amount > 0", name="positive"),
        UniqueConstraint("method", "reference_no"),
        Index("ix_deposit_requests_org_status", "organization_id", "status", "created_at"),
    )


class Payment(Base, PkMixin, TenantMixin, TimestampMixin):
    """Gateway payment. We store provider tokens/ids only - NEVER card numbers (hosted pages keep PCI scope at SAQ-A)."""
    __tablename__ = "payments"
    payer_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    booking_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("bookings.id", ondelete="RESTRICT"))
    purpose: Mapped[str] = mapped_column(String(24))               # booking | wallet_topup | stage_fee
    provider: Mapped[PayProvider] = mapped_column(E(PayProvider))
    provider_txn_id: Mapped[str | None] = mapped_column(String(96))
    amount: Mapped[Decimal]
    fee_amount: Mapped[Decimal] = mapped_column(default=Decimal("0.00"))
    currency: Mapped[str] = mapped_column(String(3), default="BDT")
    status: Mapped[PayStatus] = mapped_column(E(PayStatus), default=PayStatus.INITIATED)
    idempotency_key: Mapped[str] = mapped_column(String(80))
    raw: Mapped[dict] = mapped_column(default=dict, server_default=text("'{}'::jsonb"))
    __table_args__ = (
        CheckConstraint("amount > 0", name="positive"),
        UniqueConstraint("organization_id", "idempotency_key"),
        Index("uq_payments_provider_txn", "provider", "provider_txn_id", unique=True, postgresql_where=text("provider_txn_id IS NOT NULL")),
        Index("ix_payments_booking_id", "booking_id"),
        Index("ix_payments_org_status_created", "organization_id", "status", "created_at"),
    )


class PaymentEvent(Base, PkMixin):
    """Webhook inbox. (provider, event_id) unique => replayed webhooks are no-ops."""
    __tablename__ = "payment_events"
    organization_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("organizations.id", ondelete="RESTRICT"), index=True)
    provider: Mapped[PayProvider] = mapped_column(E(PayProvider))
    event_id: Mapped[str] = mapped_column(String(96))
    payload: Mapped[dict]
    received_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    processed_at: Mapped[dt.datetime | None]
    __table_args__ = (UniqueConstraint("provider", "event_id"),)


class CommissionRule(Base, PkMixin, TenantMixin, TimestampMixin):
    """Per airline x route type x class x date window. Most specific + highest priority wins; ties are rejected at write time."""
    __tablename__ = "commission_rules"
    agency_org_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))  # NULL = all agencies
    airline_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("airlines.id", ondelete="RESTRICT"))
    route_type: Mapped[RouteType | None] = mapped_column(E(RouteType))
    cabin_class: Mapped[str | None] = mapped_column(String(2))     # RBD letters, e.g. "Y,B"
    commission_pct: Mapped[Decimal] = mapped_column(Rate)          # applied to base fare
    valid_from: Mapped[dt.date] = mapped_column(Date)
    valid_to: Mapped[dt.date | None] = mapped_column(Date)
    priority: Mapped[int] = mapped_column(Integer, default=100)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    __table_args__ = (
        CheckConstraint("commission_pct >= 0 AND commission_pct <= 100", name="pct_range"),
        Index("ix_commission_rules_lookup", "organization_id", "airline_id", "route_type", "valid_from"),
    )


class MarkupRule(Base, PkMixin, TenantMixin, TimestampMixin):
    """Global > agency > airline > route levels. `value` is a fixed amount or a percent according to `kind`."""
    __tablename__ = "markup_rules"
    scope: Mapped[MarkupScope] = mapped_column(E(MarkupScope))
    agency_org_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    airline_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("airlines.id", ondelete="RESTRICT"))
    origin: Mapped[str | None] = mapped_column(String(3))
    destination: Mapped[str | None] = mapped_column(String(3))
    kind: Mapped[AmountKind] = mapped_column(E(AmountKind))
    value: Mapped[Decimal] = mapped_column(Rate)                   # NUMERIC(9,6): BDT 250 or 1.5 (%)
    valid_from: Mapped[dt.date | None] = mapped_column(Date)
    valid_to: Mapped[dt.date | None] = mapped_column(Date)
    priority: Mapped[int] = mapped_column(Integer, default=100)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    __table_args__ = (Index("ix_markup_rules_lookup", "organization_id", "scope", "airline_id", "origin", "destination"),)


class ServiceChargeRule(Base, PkMixin, TenantMixin, TimestampMixin):
    __tablename__ = "service_charge_rules"
    charge_type: Mapped[ChargeType] = mapped_column(E(ChargeType))
    agency_org_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"))
    fixed_amount: Mapped[Decimal] = mapped_column(default=Decimal("0.00"))
    pct: Mapped[Decimal] = mapped_column(Rate, default=Decimal("0"))
    min_amount: Mapped[Decimal | None]
    max_amount: Mapped[Decimal | None]
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    __table_args__ = (Index("ix_service_charge_rules_lookup", "organization_id", "charge_type"),)


class TaxRule(Base, PkMixin, TenantMixin, TimestampMixin):
    """AIT etc. Rates live in data, not code, with effective dates. Values must be verified against current NBR rules before go-live."""
    __tablename__ = "tax_rules"
    code: Mapped[str] = mapped_column(String(16))                  # AIT
    rate: Mapped[Decimal] = mapped_column(Rate)                    # 0.003000 = 0.3%
    base_description: Mapped[str] = mapped_column(String(255))     # human-readable formula; the engine owns the implementation
    refundable: Mapped[bool] = mapped_column(Boolean, default=False)  # AIT is never refundable (void/refund)
    valid_from: Mapped[dt.date] = mapped_column(Date)
    valid_to: Mapped[dt.date | None] = mapped_column(Date)
    __table_args__ = (UniqueConstraint("organization_id", "code", "valid_from"),)


class Invoice(Base, PkMixin, TenantMixin, TimestampMixin):
    __tablename__ = "invoices"
    invoice_no: Mapped[str] = mapped_column(String(32))
    customer_org_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("organizations.id", ondelete="RESTRICT"))
    customer_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    booking_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("bookings.id", ondelete="RESTRICT"))
    journal_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("journal_entries.id", ondelete="RESTRICT"))
    status: Mapped[InvoiceStatus] = mapped_column(E(InvoiceStatus), default=InvoiceStatus.DRAFT)
    currency: Mapped[str] = mapped_column(String(3), default="BDT")
    subtotal: Mapped[Decimal]
    tax_total: Mapped[Decimal] = mapped_column(default=Decimal("0.00"))
    total: Mapped[Decimal]
    issue_date: Mapped[dt.date] = mapped_column(Date)
    due_date: Mapped[dt.date | None] = mapped_column(Date)
    pdf_storage_key: Mapped[str | None] = mapped_column(String(255))
    __table_args__ = (UniqueConstraint("organization_id", "invoice_no"), Index("ix_invoices_booking_id", "booking_id"),
                      Index("ix_invoices_org_issue", "organization_id", "issue_date"))


class InvoiceLine(Base, PkMixin, TenantMixin):
    __tablename__ = "invoice_lines"
    invoice_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("invoices.id", ondelete="CASCADE"), index=True)
    description: Mapped[str] = mapped_column(String(255))
    component: Mapped[str | None] = mapped_column(String(24))
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    unit_price: Mapped[Decimal]
    amount: Mapped[Decimal]


# ---------------------------------------------------------------- v1.1: reconciliation, refunds, disputes, FX
class ReconciliationRun(Base, PkMixin, TenantMixin):
    """Daily four-way match: internal order vs supplier vs PSP vs supplier settlement. Sign-off is a recorded act."""
    __tablename__ = "reconciliation_runs"
    run_date: Mapped[dt.date] = mapped_column(Date)
    started_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    finished_at: Mapped[dt.datetime | None]
    items_checked: Mapped[int] = mapped_column(Integer, default=0)
    exceptions_found: Mapped[int] = mapped_column(Integer, default=0)
    control_total: Mapped[Decimal | None]
    signed_off_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    signed_off_at: Mapped[dt.datetime | None]
    __table_args__ = (UniqueConstraint("organization_id", "run_date"),)


class ReconciliationItem(Base, PkMixin, TenantMixin, TimestampMixin):
    """An exception. Every one has a queue, severity, amount at risk, owner and resolution evidence; none is silently corrected."""
    __tablename__ = "reconciliation_items"
    run_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("reconciliation_runs.id", ondelete="SET NULL"))
    queue: Mapped[ReconQueue] = mapped_column(E(ReconQueue))
    status: Mapped[ReconStatus] = mapped_column(E(ReconStatus), default=ReconStatus.OPEN)
    severity: Mapped[str] = mapped_column(String(8), default="medium")
    booking_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("bookings.id", ondelete="RESTRICT"))
    payment_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("payments.id", ondelete="RESTRICT"))
    external_ref: Mapped[str | None] = mapped_column(String(96))
    amount_at_risk: Mapped[Decimal] = mapped_column(default=Decimal("0.00"))
    owner_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    resolution: Mapped[str | None] = mapped_column(Text)
    evidence_ref: Mapped[str | None] = mapped_column(String(255))
    resolved_at: Mapped[dt.datetime | None]
    __table_args__ = (Index("ix_reconciliation_items_open", "organization_id", "queue", "created_at",
                            postgresql_where=text("status IN ('open','assigned')")),
                      Index("ix_reconciliation_items_booking", "booking_id"))


class PaymentRefund(Base, PkMixin, TenantMixin, TimestampMixin):
    """PSP refund. Cancellation confirmed != refund completed; this row is completed only on the PSP's confirmation."""
    __tablename__ = "payment_refunds"
    payment_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("payments.id", ondelete="RESTRICT"))
    booking_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("bookings.id", ondelete="RESTRICT"))
    amount: Mapped[Decimal]
    currency: Mapped[str] = mapped_column(String(3), default="BDT")
    status: Mapped[RefundStatus] = mapped_column(E(RefundStatus), default=RefundStatus.PENDING)
    provider_refund_id: Mapped[str | None] = mapped_column(String(96))
    reason: Mapped[str | None] = mapped_column(String(255))
    due_at: Mapped[dt.datetime | None]
    journal_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("journal_entries.id", ondelete="RESTRICT"))
    idempotency_key: Mapped[str] = mapped_column(String(80))
    __table_args__ = (CheckConstraint("amount > 0", name="positive"), UniqueConstraint("organization_id", "idempotency_key"),
                      Index("ix_payment_refunds_pending_due", "due_at", postgresql_where=text("status = 'pending'")),
                      Index("uq_payment_refunds_provider", "payment_id", "provider_refund_id", unique=True, postgresql_where=text("provider_refund_id IS NOT NULL")))


class PaymentDispute(Base, PkMixin, TenantMixin, TimestampMixin):
    """Chargeback / gateway dispute."""
    __tablename__ = "payment_disputes"
    payment_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("payments.id", ondelete="RESTRICT"))
    provider_case_id: Mapped[str] = mapped_column(String(96))
    amount: Mapped[Decimal]
    status: Mapped[DisputeStatus] = mapped_column(E(DisputeStatus), default=DisputeStatus.OPEN)
    evidence_due_at: Mapped[dt.datetime | None]
    evidence_ref: Mapped[str | None] = mapped_column(String(255))
    __table_args__ = (UniqueConstraint("payment_id", "provider_case_id"),)


class FxRate(Base, PkMixin, TenantMixin):
    """Rate used for a conversion, kept so a supplier-currency cost can always be re-derived. Rounding policy lives in the pricing service."""
    __tablename__ = "fx_rates"
    base_ccy: Mapped[str] = mapped_column(String(3))
    quote_ccy: Mapped[str] = mapped_column(String(3))
    rate: Mapped[Decimal] = mapped_column(Rate)
    source: Mapped[str] = mapped_column(String(40))
    as_of: Mapped[dt.datetime]
    __table_args__ = (CheckConstraint("rate > 0", name="positive"), Index("ix_fx_rates_pair", "organization_id", "base_ccy", "quote_ccy", "as_of"))
