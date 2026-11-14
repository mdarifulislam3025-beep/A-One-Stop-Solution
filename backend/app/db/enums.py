"""All domain enums in one place. Values are stored as lowercase strings."""
import enum


class OrgType(str, enum.Enum):
    PARENT = "parent"                  # A One Stop Solution (root)
    SISTER_CONCERN = "sister_concern"  # separate legal entity / brand / ledger
    B2B_AGENCY = "b2b_agency"
    SUB_AGENT = "sub_agent"
    CORPORATE_CLIENT = "corporate_client"
    B2C_STOREFRONT = "b2c_storefront"  # the tenant that owns individual customers of a brand


class OrgStatus(str, enum.Enum):
    PENDING = "pending"; ACTIVE = "active"; SUSPENDED = "suspended"; CLOSED = "closed"


class UserType(str, enum.Enum):
    STAFF = "staff"; B2B = "b2b"; B2C = "b2c"


class RoleCode(str, enum.Enum):
    SUPER_ADMIN = "super_admin"; SISTER_ADMIN = "sister_admin"; ACCOUNTANT = "accountant"
    AGENCY_OWNER = "agency_owner"  # added vs brief: prototype has owner vs staff agent
    B2B_AGENT = "b2b_agent"; B2C_CUSTOMER = "b2c_customer"


class MfaMethod(str, enum.Enum):
    OFF = "off"; EMAIL = "email"; TOTP = "totp"


class UserStatus(str, enum.Enum):
    ACTIVE = "active"; LOCKED = "locked"; DISABLED = "disabled"


class KycStatus(str, enum.Enum):
    SUBMITTED = "submitted"; VERIFIED = "verified"; REJECTED = "rejected"


class AgentOpType(str, enum.Enum):
    WARN = "warn"; SUSPEND = "suspend"; REACTIVATE = "reactivate"; WATCH_ADD = "watch_add"
    WATCH_REMOVE = "watch_remove"; NOTE = "note"; RESET_2FA = "reset_2fa"


class AccountType(str, enum.Enum):
    ASSET = "asset"; LIABILITY = "liability"; EQUITY = "equity"; INCOME = "income"; EXPENSE = "expense"


class AccountKind(str, enum.Enum):
    NORMAL = "normal"; WALLET = "wallet"; RECEIVABLE = "receivable"; PAYABLE = "payable"; TAX = "tax"; CLEARING = "clearing"


class JournalKind(str, enum.Enum):
    DEPOSIT = "deposit"; SALE = "sale"; PARTIAL_PAYMENT = "partial_payment"; REFUND = "refund"; VOID = "void"
    REISSUE = "reissue"; MARKUP_ADJ = "markup_adj"; STAGE_FEE = "stage_fee"; COMMISSION = "commission"
    MANUAL = "manual"; REVERSAL = "reversal"; SUPPLIER_SETTLEMENT = "supplier_settlement"


class JournalStatus(str, enum.Enum):
    POSTED = "posted"; REVERSED = "reversed"


class HoldStatus(str, enum.Enum):
    ACTIVE = "active"; CAPTURED = "captured"; RELEASED = "released"; EXPIRED = "expired"


class PayMethod(str, enum.Enum):
    BANK = "bank"; BKASH = "bkash"; NAGAD = "nagad"; ROCKET = "rocket"; CARD = "card"; INTL_GATEWAY = "intl_gateway"; WALLET = "wallet"


class ApprovalStatus(str, enum.Enum):
    PENDING = "pending"; APPROVED = "approved"; REJECTED = "rejected"


class PayProvider(str, enum.Enum):
    SSLCOMMERZ = "sslcommerz"; BKASH = "bkash"; NAGAD = "nagad"; STRIPE = "stripe"; PAYPAL = "paypal"


class PayStatus(str, enum.Enum):
    INITIATED = "initiated"; AUTHORIZED = "authorized"; CAPTURED = "captured"; FAILED = "failed"; REFUNDED = "refunded"; EXPIRED = "expired"


class RouteType(str, enum.Enum):
    SITI = "siti"; SOTI = "soti"; SOTO = "soto"; DOMESTIC = "domestic"


class MarkupScope(str, enum.Enum):
    GLOBAL = "global"; AGENCY = "agency"; AIRLINE = "airline"; ROUTE = "route"


class AmountKind(str, enum.Enum):
    FIXED = "fixed"; PERCENT = "percent"


class ChargeType(str, enum.Enum):
    FLIGHT_DOMESTIC = "flight_domestic"; FLIGHT_INTL = "flight_intl"; REISSUE = "reissue"; REFUND = "refund"; VOID = "void"


class InvoiceStatus(str, enum.Enum):
    DRAFT = "draft"; ISSUED = "issued"; PAID = "paid"; VOID = "void"


class SupplierKind(str, enum.Enum):
    GDS = "gds"; NDC = "ndc"; CONSOLIDATOR = "consolidator"; AGGREGATOR = "aggregator"; HOTEL = "hotel"


class MixEffect(str, enum.Enum):
    ALLOW = "allow"; BLOCK = "block"


class BookingKind(str, enum.Enum):
    FLIGHT = "flight"; HOTEL = "hotel"; VISA = "visa"; PACKAGE = "package"; INSURANCE = "insurance"; GROUP = "group"


class BookingStatus(str, enum.Enum):
    """Lifecycle only. Void/refund/reissue progress lives on after_sales_requests. Full list still to be confirmed with ops."""
    HOLD = "hold"; PARTIAL_PAYMENT = "partial_payment"; ISSUE_IN_PROCESS = "issue_in_process"; ISSUED = "issued"
    ISSUE_REJECTED = "issue_rejected"; CANCELLED = "cancelled"; EXPIRED = "expired"
    VOIDED = "voided"; REFUNDED = "refunded"; REISSUED = "reissued"


class Direction(str, enum.Enum):
    OUT = "out"; RET = "ret"; NONE = "none"


class PaxType(str, enum.Enum):
    ADT = "adt"; CNN = "cnn"; INF = "inf"


class TicketStatus(str, enum.Enum):
    OPEN = "open"; USED = "used"; VOID = "void"; REFUNDED = "refunded"; EXCHANGED = "exchanged"


class PriceComponent(str, enum.Enum):
    BASE = "base"; COMMISSION = "commission"; TAX = "tax"; AIT = "ait"; MARKUP = "markup"
    SERVICE_FEE = "service_fee"; DISCOUNT = "discount"; SUPPLIER_COST = "supplier_cost"


class PlanStatus(str, enum.Enum):
    REQUESTED = "requested"; APPROVED = "approved"; SETTLED = "settled"; DEFAULTED = "defaulted"; CANCELLED = "cancelled"


class OnDefault(str, enum.Enum):
    AUTO_CANCEL = "auto_cancel"; FLAG_ADMIN = "flag_admin"


class AfterSalesType(str, enum.Enum):
    VOID = "void"; REFUND = "refund"; REISSUE = "reissue"


class AfterSalesStatus(str, enum.Enum):
    REQUESTED = "requested"; QUOTATION_SENT = "quotation_sent"; QUOTATION_EXPIRED = "quotation_expired"
    QUOTATION_REJECTED = "quotation_rejected"; QUOTATION_APPROVED = "quotation_approved"
    IN_PROCESS = "in_process"; REQUEST_APPROVED = "request_approved"; REJECTED = "rejected"; COMPLETED = "completed"


class QuoteComponent(str, enum.Enum):
    FARE_DIFF = "fare_diff"; TAX_DIFF = "tax_diff"; AIRLINE_CHARGE = "airline_charge"; SERVICE_CHARGE = "service_charge"
    AIT_NON_REFUNDABLE = "ait_non_refundable"; REFUND_AMOUNT = "refund_amount"


class GroupStatus(str, enum.Enum):
    OPEN = "open"; CLOSED = "closed"; CANCELLED = "cancelled"


class VisaStage(str, enum.Enum):
    RECEIVED = "received"; DOCUMENT_CHECK = "document_check"; SUBMITTED_TO_EMBASSY = "submitted_to_embassy"
    APPROVED = "approved"; DELIVERED_TO_AGENT = "delivered_to_agent"


class IdemStatus(str, enum.Enum):
    IN_PROGRESS = "in_progress"; COMPLETED = "completed"; FAILED = "failed"


class OutboxStatus(str, enum.Enum):
    PENDING = "pending"; SENT = "sent"; FAILED = "failed"


class Channel(str, enum.Enum):
    EMAIL = "email"; SMS = "sms"; WHATSAPP = "whatsapp"; IN_APP = "in_app"
