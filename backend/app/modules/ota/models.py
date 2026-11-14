"""OTA: supplier/airline/airport reference data, bookings + PNR state, pricing snapshot, after-sales (void/refund/reissue),
partial payment, group fares, work-permit visa pipeline.

Double-booking defence is layered: Redis lock (fast path, advisory) -> idempotency key -> DB unique indexes below (authoritative):
  * uq_bookings_supplier_pnr      one supplier PNR belongs to one booking
  * uq_bookings_active_dedupe     same pax + same flights cannot have two ACTIVE bookings
"""
from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal

from sqlalchemy import (BigInteger, Boolean, CheckConstraint, Date, Float, ForeignKey, Index, Integer, LargeBinary, SmallInteger,
                        String, Text, UniqueConstraint, func, text)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, PkMixin, TenantMixin, TimestampMixin, E
from app.db.enums import (AfterSalesStatus, AfterSalesType, BookingKind, BookingStatus, Direction, GroupStatus, MixEffect,
                          OnDefault, PaxType, PlanStatus, PriceComponent, QuoteComponent, SupplierKind, TicketStatus, VisaStage)

NOW = func.now()
ACTIVE = "('hold','partial_payment','issue_in_process','issued')"


# ---------------------------------------------------------------- reference data (global)
class Supplier(Base, PkMixin):
    """Internal-only identity of a GDS/NDC/consolidator. `code` and `name` must NEVER appear in any agent/customer API payload."""
    __tablename__ = "suppliers"
    code: Mapped[str] = mapped_column(String(24), unique=True)
    name: Mapped[str] = mapped_column(String(80))
    kind: Mapped[SupplierKind] = mapped_column(E(SupplierKind))


class Airline(Base, PkMixin):
    __tablename__ = "airlines"
    iata_code: Mapped[str] = mapped_column(String(3), unique=True)
    name: Mapped[str] = mapped_column(String(120))
    country: Mapped[str | None] = mapped_column(String(2))
    is_lcc: Mapped[bool] = mapped_column(Boolean, default=False)
    one_way_fare_combinable: Mapped[bool] = mapped_column(Boolean, default=True)  # 'owf' flag used by the mixed-airline rule


class Airport(Base, PkMixin):
    __tablename__ = "airports"
    iata_code: Mapped[str] = mapped_column(String(3), unique=True)
    name: Mapped[str] = mapped_column(String(160))
    city: Mapped[str] = mapped_column(String(80))
    country: Mapped[str] = mapped_column(String(2))
    latitude: Mapped[float] = mapped_column(Float)    # geographic coordinates, not money; PostGIS/earthdistance index added in migration
    longitude: Mapped[float] = mapped_column(Float)
    timezone: Mapped[str | None] = mapped_column(String(48))
    __table_args__ = (Index("ix_airports_city", "city"), Index("ix_airports_lat_lon", "latitude", "longitude"))


# ---------------------------------------------------------------- tenant-scoped configuration
class SupplierAccount(Base, PkMixin, TenantMixin, TimestampMixin):
    """A tenant's credentials/office id for a supplier. Secrets live in the secret manager; only the reference is stored."""
    __tablename__ = "supplier_accounts"
    supplier_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("suppliers.id", ondelete="RESTRICT"))
    label: Mapped[str] = mapped_column(String(80))
    office_id: Mapped[str | None] = mapped_column(String(32))   # PCC / OfficeID
    credentials_ref: Mapped[str] = mapped_column(String(200))
    currency: Mapped[str] = mapped_column(String(3), default="BDT")
    priority: Mapped[int] = mapped_column(Integer, default=100)
    rate_limit_rps: Mapped[int] = mapped_column(Integer, default=20)
    timeout_ms: Mapped[int] = mapped_column(Integer, default=8000)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    __table_args__ = (UniqueConstraint("organization_id", "supplier_id", "label"),)


class SupplierIndicator(Base, PkMixin, TenantMixin):
    """Admin-set badge shown instead of the supplier name (e.g. 'Source D', tone 'blue')."""
    __tablename__ = "supplier_indicators"
    supplier_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("suppliers.id", ondelete="CASCADE"))
    label: Mapped[str] = mapped_column(String(24))
    tone: Mapped[str] = mapped_column(String(12), default="neutral")
    visible: Mapped[bool] = mapped_column(Boolean, default=True)
    __table_args__ = (UniqueConstraint("organization_id", "supplier_id"),)


class OtaSetting(Base, TenantMixin, TimestampMixin):
    __tablename__ = "ota_settings"
    organization_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("organizations.id", ondelete="CASCADE"), primary_key=True)
    show_branded_fares: Mapped[bool] = mapped_column(Boolean, default=True)
    best_buy_min_bag_kg: Mapped[int] = mapped_column(SmallInteger, default=20)
    mixed_airlines_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    mix_require_same_source: Mapped[bool] = mapped_column(Boolean, default=False)
    search_cache_ttl_s: Mapped[int] = mapped_column(Integer, default=120)


class AirlineMixRule(Base, PkMixin, TenantMixin):
    """Admin override for combining two airlines on one round trip. Stored with airline_a < airline_b (canonical pair)."""
    __tablename__ = "airline_mix_rules"
    airline_a_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("airlines.id", ondelete="CASCADE"))
    airline_b_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("airlines.id", ondelete="CASCADE"))
    effect: Mapped[MixEffect] = mapped_column(E(MixEffect))
    reason: Mapped[str | None] = mapped_column(String(255))
    created_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    __table_args__ = (CheckConstraint("airline_a_id < airline_b_id", name="canonical_pair"),
                      UniqueConstraint("organization_id", "airline_a_id", "airline_b_id"))


# ---------------------------------------------------------------- bookings
class Booking(Base, PkMixin, TenantMixin, TimestampMixin):
    """Core booking row for every vertical; flight detail lives in flight_segments/tickets, hotel/package get their own detail tables later."""
    __tablename__ = "bookings"
    booking_ref: Mapped[str] = mapped_column(String(20), unique=True)     # public Booking ID, unique for every booking in every status
    kind: Mapped[BookingKind] = mapped_column(E(BookingKind), default=BookingKind.FLIGHT)
    status: Mapped[BookingStatus] = mapped_column(E(BookingStatus), default=BookingStatus.HOLD)
    booked_by_user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    customer_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    supplier_account_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("supplier_accounts.id", ondelete="RESTRICT"))
    supplier_pnr: Mapped[str | None] = mapped_column(String(12))
    airline_pnr: Mapped[str | None] = mapped_column(String(12))
    mix_group_id: Mapped[uuid.UUID | None]                                 # links the two bookings of a mixed-airline round trip
    direction: Mapped[Direction] = mapped_column(E(Direction), default=Direction.NONE)
    parent_booking_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("bookings.id", ondelete="RESTRICT"))  # reissue child -> mother
    group_fare_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("group_fares.id", ondelete="RESTRICT"))
    currency: Mapped[str] = mapped_column(String(3), default="BDT")
    total_amount: Mapped[Decimal]                                          # what the buyer pays
    supplier_cost: Mapped[Decimal | None]
    ticket_time_limit_at: Mapped[dt.datetime | None]                       # T/L, real clock
    issued_at: Mapped[dt.datetime | None]
    cancelled_at: Mapped[dt.datetime | None]
    offer_snapshot: Mapped[dict] = mapped_column(default=dict, server_default=text("'{}'::jsonb"))  # fare, rules, baggage as sold
    dedupe_key: Mapped[str | None] = mapped_column(String(64))             # hash(pax identities + segments + dates)
    idempotency_key: Mapped[str] = mapped_column(String(80))
    version_id: Mapped[int] = mapped_column(Integer, default=1)
    __mapper_args__ = {"version_id_col": version_id}
    __table_args__ = (
        CheckConstraint("total_amount >= 0", name="non_negative"),
        UniqueConstraint("organization_id", "idempotency_key"),
        Index("uq_bookings_supplier_pnr", "supplier_account_id", "supplier_pnr", unique=True, postgresql_where=text("supplier_pnr IS NOT NULL")),
        Index("uq_bookings_active_dedupe", "organization_id", "dedupe_key", unique=True,
              postgresql_where=text(f"dedupe_key IS NOT NULL AND status IN {ACTIVE}")),
        Index("ix_bookings_org_created", "organization_id", "created_at"),
        Index("ix_bookings_org_status_created", "organization_id", "status", "created_at"),
        Index("ix_bookings_timelimit_open", "ticket_time_limit_at", postgresql_where=text("status IN ('hold','partial_payment')")),
        Index("ix_bookings_customer", "customer_user_id", "created_at"),
        Index("ix_bookings_supplier_pnr", "supplier_pnr"), Index("ix_bookings_airline_pnr", "airline_pnr"),
        Index("ix_bookings_mix_group", "mix_group_id"), Index("ix_bookings_parent", "parent_booking_id"),
    )


class BookingPassenger(Base, PkMixin, TenantMixin):
    __tablename__ = "booking_passengers"
    booking_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("bookings.id", ondelete="CASCADE"), index=True)
    traveller_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("travellers.id", ondelete="SET NULL"))
    pax_type: Mapped[PaxType] = mapped_column(E(PaxType))    # INF <2, CNN 2-<12, ADT 12+ (computed vs travel date); max 9 per booking
    title: Mapped[str | None] = mapped_column(String(8))
    first_name: Mapped[str] = mapped_column(String(80))
    last_name: Mapped[str] = mapped_column(String(80))
    date_of_birth: Mapped[dt.date] = mapped_column(Date)
    gender: Mapped[str | None] = mapped_column(String(1))
    nationality: Mapped[str | None] = mapped_column(String(2))
    passport_no_enc: Mapped[bytes | None] = mapped_column(LargeBinary)
    passport_no_hash: Mapped[bytes | None] = mapped_column(LargeBinary(32))
    passport_expiry: Mapped[dt.date | None] = mapped_column(Date)


class FlightSegment(Base, PkMixin, TenantMixin):
    __tablename__ = "flight_segments"
    booking_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("bookings.id", ondelete="CASCADE"), index=True)
    direction: Mapped[Direction] = mapped_column(E(Direction))
    seq: Mapped[int] = mapped_column(SmallInteger)
    marketing_airline_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("airlines.id", ondelete="RESTRICT"))
    operating_airline_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("airlines.id", ondelete="RESTRICT"))  # codeshare when different
    flight_no: Mapped[str] = mapped_column(String(8))
    origin: Mapped[str] = mapped_column(String(3))
    destination: Mapped[str] = mapped_column(String(3))
    departs_at: Mapped[dt.datetime]
    arrives_at: Mapped[dt.datetime]
    dep_terminal: Mapped[str | None] = mapped_column(String(8))
    arr_terminal: Mapped[str | None] = mapped_column(String(8))
    cabin: Mapped[str | None] = mapped_column(String(16))
    booking_class: Mapped[str | None] = mapped_column(String(2))
    baggage_kg: Mapped[int | None] = mapped_column(SmallInteger)
    __table_args__ = (UniqueConstraint("booking_id", "direction", "seq"), Index("ix_flight_segments_dep", "origin", "destination", "departs_at"))


class Ticket(Base, PkMixin, TenantMixin):
    __tablename__ = "tickets"
    booking_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("bookings.id", ondelete="CASCADE"), index=True)
    passenger_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("booking_passengers.id", ondelete="CASCADE"))
    airline_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("airlines.id", ondelete="RESTRICT"))
    ticket_number: Mapped[str] = mapped_column(String(16), unique=True)
    status: Mapped[TicketStatus] = mapped_column(E(TicketStatus), default=TicketStatus.OPEN)
    issued_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)


class BookingPriceLine(Base, PkMixin, TenantMixin):
    """Fare formula as rows: Base - Commission + Tax + AIT + Markup (+ service fee). Signed amounts; sum = total_amount.
    `refundable=false` on AIT is what makes AIT non-refundable in every void/refund quote."""
    __tablename__ = "booking_price_lines"
    booking_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("bookings.id", ondelete="CASCADE"), index=True)
    passenger_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("booking_passengers.id", ondelete="CASCADE"))
    component: Mapped[PriceComponent] = mapped_column(E(PriceComponent))
    label: Mapped[str | None] = mapped_column(String(40))                  # e.g. YQ, BD, UT
    amount: Mapped[Decimal]
    refundable: Mapped[bool] = mapped_column(Boolean, default=True)
    rule_type: Mapped[str | None] = mapped_column(String(24))              # which rule produced it (audit of pricing decisions)
    rule_id: Mapped[uuid.UUID | None]


class BookingStatusHistory(Base, TenantMixin):
    __tablename__ = "booking_status_history"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    booking_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("bookings.id", ondelete="CASCADE"))
    from_status: Mapped[str | None] = mapped_column(String(32))
    to_status: Mapped[str] = mapped_column(String(32))
    actor_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    reason: Mapped[str | None] = mapped_column(String(255))
    created_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    __table_args__ = (Index("ix_booking_status_history_booking", "booking_id", "id"),)


class PartialPaymentPlan(Base, PkMixin, TenantMixin, TimestampMixin):
    __tablename__ = "partial_payment_plans"
    booking_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("bookings.id", ondelete="RESTRICT"), unique=True)
    status: Mapped[PlanStatus] = mapped_column(E(PlanStatus), default=PlanStatus.REQUESTED)
    approved_amount: Mapped[Decimal | None]
    settlement_due_at: Mapped[dt.datetime | None]
    on_default: Mapped[OnDefault] = mapped_column(E(OnDefault), default=OnDefault.FLAG_ADMIN)
    approved_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    journal_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("journal_entries.id", ondelete="RESTRICT"))
    __table_args__ = (Index("ix_partial_payment_plans_due", "status", "settlement_due_at"),)


class AfterSalesRequest(Base, PkMixin, TenantMixin, TimestampMixin):
    """Void / refund / reissue. Quotation time limits run on the real clock (quote_expires_at). Every operation carries a unique serial."""
    __tablename__ = "after_sales_requests"
    booking_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("bookings.id", ondelete="RESTRICT"))
    request_type: Mapped[AfterSalesType] = mapped_column(E(AfterSalesType))
    status: Mapped[AfterSalesStatus] = mapped_column(E(AfterSalesStatus), default=AfterSalesStatus.REQUESTED)
    serial_no: Mapped[str] = mapped_column(String(32), unique=True)
    rejection_serial: Mapped[str | None] = mapped_column(String(32), unique=True)
    requested_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    reason: Mapped[str | None] = mapped_column(Text)
    new_departs_at: Mapped[dt.datetime | None]                             # reissue: window = today .. issue date + 1 year (validated in service)
    new_schedule_note: Mapped[str | None] = mapped_column(Text)
    quote_total: Mapped[Decimal | None]
    quote_expires_at: Mapped[dt.datetime | None]
    quoted_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    decided_at: Mapped[dt.datetime | None]
    resulting_booking_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("bookings.id", ondelete="RESTRICT"))
    journal_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("journal_entries.id", ondelete="RESTRICT"))
    idempotency_key: Mapped[str] = mapped_column(String(80))
    __table_args__ = (UniqueConstraint("organization_id", "idempotency_key"),
                      Index("ix_after_sales_booking", "booking_id"),
                      Index("ix_after_sales_quote_expiry", "quote_expires_at", postgresql_where=text("status = 'quotation_sent'")),
                      Index("ix_after_sales_org_type_status", "organization_id", "request_type", "status"))


class AfterSalesQuoteLine(Base, PkMixin, TenantMixin):
    """Compare-sheet rows: old vs new base/tax/commission, plus airline and service charges."""
    __tablename__ = "after_sales_quote_lines"
    request_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("after_sales_requests.id", ondelete="CASCADE"), index=True)
    component: Mapped[QuoteComponent] = mapped_column(E(QuoteComponent))
    old_amount: Mapped[Decimal | None]
    new_amount: Mapped[Decimal | None]
    amount: Mapped[Decimal]
    refundable: Mapped[bool] = mapped_column(Boolean, default=True)


# ---------------------------------------------------------------- group fares, visa
class GroupFare(Base, PkMixin, TenantMixin, TimestampMixin):
    __tablename__ = "group_fares"
    code: Mapped[str] = mapped_column(String(32))
    airline_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("airlines.id", ondelete="RESTRICT"))
    origin: Mapped[str] = mapped_column(String(3))
    destination: Mapped[str] = mapped_column(String(3))
    departs_on: Mapped[dt.date] = mapped_column(Date)
    seats_total: Mapped[int] = mapped_column(Integer)
    seats_sold: Mapped[int] = mapped_column(Integer, default=0)
    fixed_fare: Mapped[Decimal]
    deposit_due_at: Mapped[dt.datetime | None]
    ticketing_deadline_at: Mapped[dt.datetime | None]
    terms: Mapped[str | None] = mapped_column(Text)
    status: Mapped[GroupStatus] = mapped_column(E(GroupStatus), default=GroupStatus.OPEN)
    __table_args__ = (UniqueConstraint("organization_id", "code"),
                      CheckConstraint("seats_sold >= 0 AND seats_sold <= seats_total", name="quota"))


class VisaApplication(Base, PkMixin, TenantMixin, TimestampMixin):
    __tablename__ = "visa_applications"
    application_ref: Mapped[str] = mapped_column(String(20), unique=True)
    applicant_name: Mapped[str] = mapped_column(String(160))
    passport_no_hash: Mapped[bytes | None] = mapped_column(LargeBinary(32))
    destination_country: Mapped[str] = mapped_column(String(2))
    visa_type: Mapped[str] = mapped_column(String(24), default="work_permit")
    stage: Mapped[VisaStage] = mapped_column(E(VisaStage), default=VisaStage.RECEIVED)
    total_fee: Mapped[Decimal]
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    __table_args__ = (Index("ix_visa_applications_org_stage", "organization_id", "stage"),)


class VisaStagePayment(Base, PkMixin, TenantMixin):
    """One payment per stage; the service layer refuses to advance until the current stage's payment is settled."""
    __tablename__ = "visa_stage_payments"
    application_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("visa_applications.id", ondelete="CASCADE"))
    stage: Mapped[VisaStage] = mapped_column(E(VisaStage))
    amount: Mapped[Decimal]
    settled_at: Mapped[dt.datetime | None]
    journal_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("journal_entries.id", ondelete="RESTRICT"))
    __table_args__ = (UniqueConstraint("application_id", "stage"),)


class VisaEvent(Base, TenantMixin):
    """Timestamped tracking log shown on the agent's progress bar."""
    __tablename__ = "visa_events"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    application_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("visa_applications.id", ondelete="CASCADE"))
    stage: Mapped[VisaStage] = mapped_column(E(VisaStage))
    note: Mapped[str | None] = mapped_column(String(255))
    actor_user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    created_at: Mapped[dt.datetime] = mapped_column(server_default=NOW)
    __table_args__ = (Index("ix_visa_events_application", "application_id", "id"),)
