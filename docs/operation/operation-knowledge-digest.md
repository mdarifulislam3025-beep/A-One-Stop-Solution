# Operation Knowledge Digest

Built from: GDS-first architecture document (14 Nov 2026), Claude OTA Airline Knowledge Vault v1, Claude API/NDC/OTA Production Manuals v1, and the previous prototype archive (byte-identical to the published Version 11 `public/index.html`; nothing new there).

## Evidence levels used here
- **Stated by you** (profile, vault "user-historical", chat): treat as fact about the operation.
- **Industry reference**: general practice written by an assistant; useful, but not your SOP.
- **To verify**: carrier, GDS, IATA/BSP, NBR, Bangladesh Bank or regulator rules; always check market, effective date and source.

## What the sources say about YOUR operation (stated)
1. Sales workflow (11 Apr 2026): show options lowest price first → client selects/negotiates and confirms → collect travel documents → complete booking and cross-check → send invoice to Accounts → get payment confirmation → pay vendor/airline → issue and send ticket. Control point: **payment confirmation precedes supplier payment and ticketing.**
2. A One Stop Solution, tagline "Everything. One Place."; first trip reported fully booked 26 June 2026.
3. Suppliers discussed (none confirmed live): Amadeus, Sabre, Travelport, Hotelbeds, Expedia, Agoda. The BRD also lists Flyhub, Mystifly, Verteil and airline NDC.
4. OTA website requirement (12 Jun 2026): Node.js and your own UI/UX. **Conflicts with your 14 Nov brief (Python/FastAPI).**
5. Your expertise areas: GDS/PNR monitoring, ticketing control, ADM prevention and disputes, ACM recovery, fare-rule compliance, API diagnostics, reconciliation, QA, visa and documents.

## Operating model implied (industry reference, consistent with the above)
`search → reprice → customer/agent accepts price → payment → PNR/order → retrieve & verify → ticket → verify ticket document → invoice/e-ticket → daily reconciliation → servicing (void/refund/exchange/schedule change) → ADM/ACM`

Non-negotiable controls (appear in all three sources and are now in the schema):
- A PNR is not a ticket; an authorization is not a capture; a cancellation is not a refund.
- A timeout is not a failure: mark UNKNOWN, query the supplier, never blind-retry booking, ticketing, cancel or refund.
- Keep the accepted price snapshot and fare rules; they are the defence in disputes and ADMs.
- Corrections are reversing entries, never overwrites.
- Reconcile daily: internal order vs supplier vs PSP vs settlement; every exception has an owner.

## Where the sources conflict (and my decision)
| Topic | GDS-first document | Your brief / prototype | Decision |
|---|---|---|---|
| Language/stack | Node 26 + NestJS + Prisma + RabbitMQ | Python 3.12 + FastAPI + SQLAlchemy + Celery/Redis | Python (your latest, explicit). Needs your confirmation. |
| Money | integer minor units | `DECIMAL(12,2)` | Keep DECIMAL(12,2) (your rule). Fails for 3-decimal currencies, so FX is explicit. |
| Scope | one GDS, one flight vertical slice first; no hotels/loyalty/mobile | B2B + B2C + ERP + visa + group fares + hotels | Schema covers breadth; **build order follows the vertical slice**. |
| Suppliers | one contracted GDS | BRD lists consolidator APIs too | Provider-neutral adapter; first adapter chosen by ticketing authority. |
| Payment vs booking order | "agree with GDS/consolidator" | your workflow: payment before supplier payment and ticketing | B2C: confirm payment, then book and ticket. B2B: wallet hold, then book and ticket. |

## What is NOT known yet (needs you)
- Ticketing authority (own IATA, consolidator, host agency) and the BSP market/agency identifiers.
- Which GDS/consolidator and whether sandbox credentials exist.
- Your real SOPs: void/refund/reissue rules, ADM handling steps, deadlines and sources, QA scorecards. The vault confirms none were recovered; it is explicitly not a full export.
- Payment gateway choices and settlement calendar; chart of accounts and finance policy.
- Whether B2C launches with or after the agent portal.

## Vault cautions I will follow
Never invent carrier fare rules, ADM deadlines, GDS syntax, API schemas, waiver policies or immigration requirements. Every ADM/ACM deadline must carry a source (enforced in the schema).
