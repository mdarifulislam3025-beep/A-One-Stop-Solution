# TravelHub B2B: A One Stop Solution

Clickable prototype of the B2B OTA platform for A One Stop Solution (Bangladesh). It is a single self-contained HTML file in `public/index.html`, with no build step.

**Status: demo.** All fares, itineraries, agents, ledger entries and rules are sample data. There is no live GDS, airline, payment or SMS integration and no real authentication.

## Covered in the prototype
Agent portal: flight search and results (view fare, branded fares and Best Buy, mixed-airline round trips), booking and ticketing, wallet, group fares, work permit visa, partial payment, reissue with quotation, profile and 2FA choice.
Admin console: bookings workflow, deposits, ledger, commission, markup, supplier indicators, branded fare and mixed-trip rules, agent desk ("Others"), security, reports and top clients.

## Run locally
Open `public/index.html` in a browser, or run `npx serve public`.

## Deploy
Static site. `vercel.json` sets `public/` as the output directory. Vercel: import this repo with framework "Other". GitHub Pages: serve `public/`.

## Before production
- Replace sample data and in-browser logic with a backend: auth (real MFA), wallet and ledger as the server-side source of truth, supplier APIs.
- Keep GDS/API names server-side only. Agents see admin-set indicators.
- Verify tax and AIT rules against current NBR requirements.
- PCI DSS scope: use hosted gateway pages (SSLCommerz, Stripe) so card data never touches the platform.
