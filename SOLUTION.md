# Super Pixel — Solution

# Design Questions

## Domain modeling

### 1. What are your core models and how do leads, layer-results, verdicts, and certificates relate? Where does a "verification run" live?

The core models are:

Account
User
Pixel
PixelSession
Lead
VerificationRun
LayerResult
Verdict
CreditTransaction
ConsentCertificate
ActivityEvent

The main relationship is:

Account
-> Pixel
-> PixelSession
-> Lead
-> VerificationRun
-> LayerResult(s)
-> Verdict
-> ConsentCertificate
-> CreditTransaction(s)

A `VerificationRun` is a first-class persisted model rather than temporary service state.

That gives each verification attempt its own lifecycle, timestamps, policy version, layer results, verdict, credit usage, and certificate.

This also means the system could support re-verification later without overwriting the history of a previous run.

---

### 2. A layer can be not-enabled, not-applicable, or returned-a-verdict. How does your schema keep these distinct?

`LayerResult` has a separate `execution_status` from its verdict.

Execution states include:

pending
completed
failed
not_enabled
not_applicable
insufficient_credits

The layer verdict itself is separate:

pass
warn
fail

So these cases remain semantically different:

not_enabled

means the account/pixel did not run the layer.

not_applicable

means the layer was enabled but did not apply to this lead.

completed + pass/warn/fail

means the provider actually returned usable verification evidence.

I kept execution state separate from business verdict so the consensus engine does not treat missing evidence as a clean result.

---

# Consensus engine

### 3. Which layers are hard stops vs weighted signals, and why?

Hard stops represent conditions where the business should reject regardless of the aggregate soft-risk score.

Examples include:

- known litigator / blacklist hit
- DNC-listed or internal DNC
- TrustedForm mismatch
- TrustedForm expired
- recent exact duplicate

Weighted signals include:

- suspicious Anura result
- VPN / proxy evidence
- phone disagreement
- invalid phone
- VoIP indicators
- undeliverable email
- disposable email
- fraud-related email signals
- suspected blacklist result
- enrichment risk
- softer duplicate signals
- voice-related risk signals

I separated hard stops from weighted signals because some compliance or business rules are categorical.

For example, a known DNC violation should not become acceptable simply because all other checks look good.

---

### 4. How do you turn N layer results into ACCEPT / REVIEW / REJECT + a reason? Weights? Thresholds? Rules? Show the shape.

The engine evaluates completed layer results, accumulates weighted risk, and separately tracks hard stops.

The current thresholds are:

risk < 25 -> ACCEPT
risk 25..59 -> REVIEW
risk >= 60 -> REJECT

A hard stop overrides the numeric score and produces:

REJECT

The shape is conceptually:

```ruby
risk_score = 0
reasons = []
hard_stop = false

layer_results.each do |result|
  next unless result.execution_status == "completed"

  if hard_stop_condition?(result)
    hard_stop = true
    reasons << result.reason
  else
    risk_score += weight_for(result)
    reasons << result.reason if result.verdict != "pass"
  end
end

decision =
  if hard_stop
    "REJECT"
  elsif incomplete_required_evidence?
    "REVIEW"
  elsif risk_score >= 60
    "REJECT"
  elsif risk_score >= 25
    "REVIEW"
  else
    "ACCEPT"
  end
```

The final `Verdict` persists:

- decision
- risk score
- hard-stop flag
- reasons
- policy snapshot
- decision timestamp

---

### 5. What happens when a required layer is unavailable or errors mid-run — does the lead fail open or fail closed?

It does not silently fail open.

A failed or unavailable required layer is recorded explicitly as incomplete evidence.

The lead is not automatically rejected merely because a provider failed, because provider outage is not the same as a fraudulent lead.

Instead, incomplete required evidence forces the final result to at least:

REVIEW

This is a middle-ground policy:

provider failure != PASS
provider failure != automatic REJECT
provider failure => REVIEW

That avoids falsely accepting a lead when evidence is missing while also avoiding rejecting good leads purely because an external provider was unavailable.

---

### 6. How would a buyer tune the engine, for example treating "suspected litigator" as a hard stop? Is your policy data or code?

In the current take-home implementation, the policy is primarily code-driven.

I chose that because the assignment benefits more from transparent, testable business rules than from building a full policy-management product.

The verdict also stores a `policy_snapshot`, which gives the decision an auditable record of which policy produced it.

For production, I would move tunable parts into versioned policy data, for example:

```json
{
  "hard_stops": {
    "blacklist.litigator": true,
    "blacklist.suspected": false,
    "dnc.dnc_listed": true
  },
  "weights": {
    "anura.suspicious": 30,
    "vpn.detected": 10,
    "email.disposable": 20
  },
  "thresholds": {
    "review": 25,
    "reject": 60
  }
}
```

A buyer could then promote `suspected litigator` from a weighted signal to a hard stop without changing application code.

I would version every policy change so old certificates remain explainable under the policy that was active when the lead was evaluated.

---

# Multi-tenancy & authorization

### 7. How do you guarantee an account never sees another account's leads, certificates, or CRM — at the query layer, not just the UI?

Tenant ownership is enforced through backend queries.

For CRM access, normal users do not start from:

```ruby
Lead.all
```

and filter afterward in the UI.

Instead, the lead query is scoped through the owning pixel/account:

```ruby
Lead
  .joins(pixel_session: :pixel)
  .where(pixels: { account_id: current_user.account_id })
```

The detail endpoint also resolves the requested lead from that scoped relation.

So changing a lead ID in the browser does not allow cross-tenant access.

Pixels are similarly scoped to the current account.

Certificate access is separated into a public verification endpoint with a redacted response. The full internal evidence remains stored server-side and is not exposed through account UI queries.

Tests cover cross-account access attempts.

---

### 8. How is super_admin different, and how do you keep that power from leaking?

`super_admin` is intentionally cross-tenant.

For example, the CRM scope becomes:

```ruby
Lead.all
```

for a Super Admin, while normal users receive an account-scoped relation.

Super Admin also has access to the cross-account account/credit dashboard.

I keep that privilege explicit by checking the role on the server rather than giving every user a broad query and relying on the frontend to hide records.

The browser routes are role-aware as well:

super_admin -> admin dashboard
account_admin -> account CRM / pixel management
member -> CRM only

Super Admin is not allowed into account-specific Pixel Management because there is no single tenant context attached to that user.

In a larger system, I would also add audit logging for privileged cross-tenant actions and potentially an explicit "impersonate/select account" workflow rather than allowing ambient super-admin access everywhere.

---

# Credits & subscriptions

### 9. When exactly is a credit consumed — per lead, per layer, per run? What's your reasoning?

Credits are consumed per verification layer when that check is initiated.

Each module has its own cost.

This is preferable to a flat per-lead charge because:

- different accounts enable different modules
- different verification stacks have different costs
- some checks may be not applicable
- some leads may consume only a subset of configured layers

The credit transaction is associated with both the verification run and layer.

Account balance updates use a database lock so concurrent verification jobs cannot both observe the same available balance and overspend it.

---

### 10. What happens when an account hits zero credits mid-verification? What does the super-admin dashboard show, and how early does it warn?

The system does not overspend the account.

For each layer, it attempts an atomic credit charge.

If the account cannot afford that layer:

execution_status = insufficient_credits

No credit transaction is created for that layer.

The run continues with later layers that are still affordable.

This preserves as much evidence as possible instead of abandoning the whole run immediately.

Because the evidence is incomplete, the consensus cannot silently return `ACCEPT`; it requires at least `REVIEW`.

The Super Admin dashboard shows:

- monthly allowance
- used credits
- remaining credits
- average daily burn
- estimated days remaining
- nearly-out state

The nearly-out warning considers both balance and burn rate.

The current rule marks an account as nearly out when remaining credits are within approximately three days of average burn, with a minimum fixed threshold of 100 credits.

That gives the operator some warning before the account actually reaches zero.

---

# Consent certificates

### 11. What goes in a certificate so a buyer could defend the lead later? How do you make it tamper-evident / verifiable?

The internal certificate stores a snapshot of the evidence at decision time.

It includes:

- certificate version
- lead context
- account
- pixel
- verification run
- policy version
- start/completion timestamps
- final verdict
- risk score
- hard-stop flag
- decision reasons
- policy snapshot
- all layer results
- execution statuses
- provider responses
- TrustedForm reference

The evidence is canonicalized and signed using:

HMAC-SHA256

When the certificate is retrieved, the server recomputes the signature from the stored evidence and compares it using a constant-time secure comparison.

If the evidence is changed, verification returns:

valid: false

The certificate model also prevents normal application-level update and destroy operations.

The public verification endpoint does not expose the full evidence because it contains lead PII and raw provider responses. It exposes a redacted verification summary while still validating the signature against the complete internal evidence snapshot.

For stronger production guarantees, I would use dedicated signing keys, key versioning, and database/storage-level append-only controls.

---

# Real-time & jobs

### 12. Sync or background jobs for the layer calls? Why?

Verification runs in a background job.

The `/leads` endpoint accepts the lead and queues verification instead of making the browser wait for every provider layer to finish.

That keeps ingestion responsive and separates user-facing request latency from external-provider latency.

It also creates a better architecture for retries, provider timeouts, and independent failure handling.

Conceptually:

POST /leads
|
| 202 Accepted
v
VerificationJob
|
v
VerificationRunner

For production, I would use a durable job backend with retry policies, dead-letter handling, and idempotency around provider calls.

---

### 13. Which real-time transport did you pick for the live landing page, and what did you trade away?

I used short polling at approximately 750ms.

The browser requests:

GET /leads/:lead_id/activity?session_id=...&after_id=...

and only receives events newer than the last event it has seen.

The important point is that the UI displays actual backend activity rather than fake timed progress.

I chose polling because it is simple, reliable, easy to demonstrate, and explicitly acceptable for the assignment.

The tradeoff is that polling produces more repeated HTTP requests and is less efficient than a push transport at larger scale.

For production, I would consider:

- Server-Sent Events for one-way verification updates
- Action Cable / WebSockets if bidirectional real-time communication became useful

I would also replace the current client-generated session identifier with a short-lived server-issued polling token.

---

# If you had another week

### 14. What's the first thing you'd build next, and what's the biggest risk in your current design?

The first thing I would build next is a production-grade provider execution layer.

That would include:

- explicit provider timeouts
- retry/backoff policies
- circuit breakers
- idempotency
- structured provider error classification
- observability
- latency metrics
- dead-letter handling
- provider health monitoring

The biggest current risk is that the take-home uses simplified provider execution and application-level guarantees around things that would be more sensitive in production.

In particular, I would harden:

- provider reliability
- server-issued activity authorization tokens
- certificate signing key management
- append-only certificate storage
- policy versioning/configuration
- rate limiting
- privileged-action auditing

The current design is intentionally optimized for a clear, testable assignment implementation rather than pretending those production concerns are already solved.

## Overview of the submission

This submission implements a multi-tenant lead verification platform built with Ruby on Rails.

The system provides a single embeddable **Super Pixel** that can be installed on a landing page. When a visitor submits a lead, the platform processes that lead through the verification modules enabled for the account and pixel, combines the results using a consensus policy, records a final `ACCEPT`, `REVIEW`, or `REJECT` decision, and issues a signed verification certificate.

The implementation focuses on the core areas requested in the assignment:

- Authentication and role-based authorization
- Multi-tenant account isolation
- Pixel management
- Lead ingestion
- Modular verification layers
- Credit accounting
- Consensus decisions
- Consent / verification certificates
- Real-time verification activity
- CRM lead visibility
- Super-admin account monitoring
- Automated tests

The goal was to keep the implementation small enough to understand and defend while still modeling the important production concerns explicitly.

---

# Architecture

At a high level, the application follows this flow:

Landing Page
|
| loads
v
super-pixel.js
|
| POST /visit
v
PixelSession
|
| form submitted
v
POST /leads
|
v
Lead
|
v
VerificationJob
|
v
VerificationRunner
|
+----------------------------+
| |
v v
Verification Layers CreditManager
| |
+-------------+--------------+
|
v
ConsensusEngine
|
v
Verdict
ACCEPT / REVIEW / REJECT
|
v
CertificateIssuer
|
v
ConsentCertificate

The browser polls the activity endpoint while verification is running so the supplied landing page displays actual backend verification events rather than simulated progress.

---

# Domain Model

The main domain objects are:

## Account

Represents a tenant of the platform.

An account contains:

- plan
- monthly credit allowance
- credits consumed during the current cycle
- enabled verification modules
- billing cycle information
- average daily burn rate
- status

Tenant-owned resources ultimately derive their ownership from an account.

---

## User

Users authenticate using Rails sessions and `has_secure_password`.

Supported roles are:

- `super_admin`
- `account_admin`
- `member`

An `account_admin` and `member` belong to an account.

A `super_admin` operates across accounts and therefore does not require a tenant account.

Authorization is enforced on the server rather than relying on hidden navigation or frontend controls.

---

## Pixel

A Pixel belongs to an account and contains:

- public pixel ID
- name
- allowed landing pages
- enabled verification modules
- active/inactive state

A pixel cannot enable a verification module that the owning account is not entitled to use.

Account admins can create and manage pixels for their own account.

---

## PixelSession

A PixelSession represents a browser visit observed by the Super Pixel.

It records information including:

- pixel
- session ID
- page URL
- referrer
- user agent
- visit IP
- start time

The session is later connected to a submitted Lead.

---

## Lead

A Lead represents a form submission.

It contains the submitted identity/contact information and contextual information such as:

- name
- email
- phone
- campaign
- landing page
- IP
- user agent
- TrustedForm certificate reference
- form dwell time
- submission timestamp

Tenant ownership is derived through:

Lead
-> PixelSession
-> Pixel
-> Account

This relationship is used for account-scoped CRM queries.

---

## VerificationRun

Each verification attempt creates a VerificationRun.

A run tracks:

- status
- policy version
- start/completion timestamps
- layer results
- final verdict
- credit transactions
- consent certificate

---

## LayerResult

Every verification layer produces an explicit result.

Layer execution states distinguish between:

- completed
- failed
- not enabled
- not applicable
- insufficient credits

This distinction is intentional.

For example, a module that was not purchased is different from a provider that was called but failed, and both are different from a check that does not apply to the lead.

Layer results also contain the provider result, risk information, reason, and credit cost.

---

## Verdict

The Verdict contains the final consensus decision:

ACCEPT
REVIEW
REJECT

It also stores:

- risk score
- whether a hard stop occurred
- decision reasons
- policy snapshot
- decision timestamp

The policy snapshot provides evidence of which policy produced the decision.

---

## ConsentCertificate

A certificate is issued after verification finishes.

It contains an immutable snapshot of the evidence used to make the decision.

The snapshot includes:

- lead context
- account
- pixel
- verification run
- verdict
- layer results
- provider responses
- TrustedForm reference

The evidence is signed using HMAC-SHA256.

The public certificate endpoint exposes a privacy-conscious verification summary rather than returning the full internal evidence snapshot containing lead PII and raw provider responses.

Signature verification still runs against the complete stored evidence.

---

# Authentication and Multi-Tenancy

Authentication uses Rails sessions.

The primary roles are:

### Super Admin

Can access cross-account administrative information.

### Account Admin

Can manage pixels and view resources belonging to their account.

### Member

Can view permitted account CRM resources but cannot manage pixels.

Multi-tenancy is enforced at the query/controller layer.

For example, CRM access uses an account-aware scope rather than loading a Lead globally and checking ownership only in the UI.

Conceptually:

```ruby
if current_user.super_admin?
  Lead.all
else
  Lead
    .joins(pixel_session: :pixel)
    .where(pixels: { account_id: current_user.account_id })
end
```

This prevents users from retrieving another tenant's lead simply by changing an identifier in the URL.

Tests cover cross-account access attempts.

---

# Pixel Management

Account administrators can:

- view their pixels
- create a pixel
- edit a pixel
- configure allowed landing pages
- select verification modules
- activate/deactivate the pixel
- obtain the installation snippet

The generated snippet resembles:

```html
<script
  src="http://localhost:3000/super-pixel.js"
  data-pixel-id="PIXEL_PUBLIC_ID"
  data-endpoint="http://localhost:3000"
></script>
```

For production, the script URL and API endpoint would use the deployed Super Pixel domain or CDN rather than localhost.

The Rails application serves the embeddable script from:

```text
/public/super-pixel.js
```

---

# Landing Page Restrictions

Pixels may optionally define allowed landing pages.

Incoming `/visit` requests validate the page against the pixel configuration.

The `/leads` endpoint validates the page again before accepting the lead.

Rechecking during lead submission is important because pixel configuration could change after the initial visit.

Allowed-page matching parses URLs rather than relying on string-prefix comparison.

The comparison considers:

- scheme
- hostname
- normalized port
- normalized path

Query strings do not prevent a configured page from matching.

A configured origin such as:

```text
https://example.com
```

allows pages on that origin.

A configured path such as:

```text
https://example.com/form
```

matches that normalized path rather than unsafe prefix variants.

---

# Lead Ingestion

The Super Pixel uses two main ingestion endpoints.

## Visit

```text
POST /visit
```

The endpoint:

1. identifies the pixel
2. verifies that it exists
3. verifies that it is active
4. validates the landing page
5. creates or updates the PixelSession

## Lead Submission

```text
POST /leads
```

The endpoint:

1. identifies the pixel
2. verifies that the pixel is active
3. identifies the PixelSession
4. revalidates landing-page permission
5. creates the Lead
6. schedules verification
7. returns without requiring the browser to wait for every provider

Verification runs through a Rails background job.

---

# Verification Layers

The platform models external verification providers as independent layers.

The supplied mock provider data is used to produce deterministic provider responses.

Implemented verification concepts include:

- VPN / proxy detection
- Anura fraud detection
- TrustedForm verification
- blacklist / litigator checks
- DNC checks
- phone verification
- email verification
- enrichment
- duplicate detection
- optional voice verification

Provider responses are normalized before consensus processing.

This prevents the consensus engine from needing to understand every provider's raw response format.

---

# Duplicate Detection

Duplicate detection is account scoped.

A lead from one customer therefore cannot cause a duplicate result for another customer.

The duplicate window is limited to recent leads rather than treating the existence of any historical matching lead as a permanent duplicate.

Exact recent duplicates can act as a hard stop.

Older duplicates are not treated as current duplicates.

Tests cover both the time window and tenant isolation.

---

# Credit Accounting

Verification modules consume account credits.

Module costs are applied when a verification check is initiated.

Credit consumption uses database locking around the account balance calculation.

This prevents two concurrent verification processes from independently observing the same balance and overspending the account.

Credit transactions are also associated with the verification run and layer.

---

# Insufficient Credit Policy

The implementation deliberately does not fail the entire verification process immediately when an account cannot afford one layer.

Instead:

1. the system attempts each enabled verification layer
2. affordable checks continue
3. an unaffordable check is recorded as `insufficient_credits`
4. no credit transaction is created for that check
5. the final consensus knows that verification evidence is incomplete

Incomplete verification cannot silently produce an `ACCEPT`.

The consensus policy therefore requires at least `REVIEW` when required evidence could not be collected.

This preserves useful verification evidence without overspending the customer's balance.

---

# Not Applicable vs Not Enabled

The system distinguishes:

```text
not_enabled
```

from:

```text
not_applicable
```

For example, optional voice verification may be enabled for an account but not applicable to a particular fixture/lead.

In that situation:

- no provider charge is made
- no credit transaction is created
- the layer is explicitly recorded as not applicable

This is different from the account never enabling the module.

---

# Consensus Engine

The consensus engine converts normalized layer results into a final decision.

The policy supports both:

- hard-stop rules
- weighted soft-risk signals

The weighted risk thresholds are:

```text
Risk < 25       -> ACCEPT
Risk 25 - 59    -> REVIEW
Risk >= 60      -> REJECT
```

A hard stop produces `REJECT` independently of the weighted risk score.

Examples of hard-stop conditions include:

- known litigator / blacklist result
- DNC violations
- TrustedForm mismatch or expiration
- recent exact duplicate

Soft signals contribute weighted risk instead.

Examples include:

- suspicious fraud results
- VPN/proxy indicators
- phone disagreement or invalidity
- VoIP signals
- undeliverable/disposable email
- enrichment signals
- softer duplicate signals
- voice-related signals

Only completed checks contribute normal weighted risk.

Failed or unavailable verification evidence is treated separately so the system does not confuse provider failure with a clean result.

---

# Why a REJECT Can Have Risk Score 0

The numeric risk score represents weighted soft-risk signals.

Hard stops are modeled separately.

Therefore a lead can legitimately have:

```text
risk_score: 0
hard_stop: true
decision: REJECT
```

For example, an exact recent duplicate may immediately reject the lead even if no soft-risk points were accumulated.

This separation makes hard business rules explicit instead of artificially encoding every rule into the numeric score.

---

# Fixture Verification

The consensus implementation is validated against the provided fixture scenarios.

The expected fixture outcomes are produced by the verification rules rather than hardcoding verdicts based on fixture IDs.

This is important because the fixture identifier is used only to select deterministic mock provider behavior; it does not determine the consensus result itself.

---

# Real-Time Verification Activity

The supplied landing page displays actual verification progress.

The implementation uses short polling rather than simulated timers.

The browser:

1. submits the lead
2. receives the lead identifier
3. polls the activity endpoint
4. requests only events after the most recently received event
5. renders actual layer and verdict events emitted by the backend

The polling interval is approximately 750ms.

The endpoint follows the shape:

```text
GET /leads/:lead_id/activity?session_id=...&after_id=...
```

Activity is scoped to the PixelSession rather than exposing a lead's activity solely from a guessable lead identifier.

For a production implementation, I would replace the client-generated session identifier with a cryptographically random, short-lived polling token issued by the server.

Polling was chosen for this assignment because it provides real backend state with substantially less infrastructure than WebSockets while satisfying the real-time requirement.

A production version could use Server-Sent Events or Action Cable if scale or latency requirements justified it.

---

# CRM

The CRM provides account-scoped lead visibility.

Users can:

- list leads
- search leads
- filter by verdict
- inspect a lead
- view verification layers
- view activity
- access certificate information

The API supports pagination and tenant-aware queries.

Super admins can access leads across accounts, while normal users remain restricted to their account.

---

# Consent / Verification Certificates

A certificate is created after the verification run reaches its final state.

The certificate stores a snapshot rather than dynamically rebuilding evidence from mutable application records.

This is important because later changes to a lead or provider data should not silently change what the certificate claims happened at verification time.

The evidence is canonicalized and signed using:

```text
HMAC-SHA256
```

The signing secret comes from the Rails application secret.

When a certificate is retrieved, the application recalculates the signature from the stored evidence and compares it using a constant-time secure comparison.

If the stored evidence is altered, signature validation fails.

The model also prevents normal application-level update and destroy operations.

This provides application-level immutability.

For a production compliance system, stronger guarantees could include:

- database-level append-only permissions
- database triggers
- external immutable/audit storage
- key rotation/versioning
- dedicated signing keys or KMS/HSM-backed signing

---

# Certificate Privacy

The internal certificate contains detailed evidence including lead information and raw provider results.

That full evidence is intentionally not returned from the public verification endpoint.

The public endpoint exposes the information needed to understand and verify the result while withholding sensitive lead PII and raw provider payloads.

The signature is still validated against the complete internal evidence snapshot.

This separates:

```text
internal forensic evidence
```

from:

```text
public verification representation
```

---

# Super Admin Dashboard

The Super Admin dashboard provides cross-account operational visibility.

For each account it displays information including:

- company
- plan
- account status
- monthly credit allowance
- credits consumed
- credits remaining
- average daily burn
- estimated days remaining
- nearly-out status

The nearly-out indicator uses both remaining balance and burn rate rather than relying only on a fixed balance threshold.

The dashboard also provides aggregate account/credit information.

---

# Security Considerations

The implementation includes several security-oriented decisions.

## Server-Side Authorization

Tenant isolation is enforced by backend queries and controllers rather than frontend visibility.

## Pixel Module Entitlements

A pixel cannot enable modules unavailable to its account.

## Allowed Landing Pages

Both visits and lead submissions validate the landing-page configuration.

## Activity Isolation

Lead activity requires the corresponding pixel session rather than only the public lead identifier.

## Credit Concurrency

Credit consumption uses account locking to prevent concurrent overspending.

## Certificate Integrity

Certificates use signed immutable evidence snapshots.

## Certificate Privacy

Public certificate retrieval does not expose full lead PII or raw provider evidence.

---

# Background Processing

Lead verification runs through a Rails background job.

This keeps lead ingestion responsive and separates:

```text
accepting the lead
```

from:

```text
performing potentially slow provider verification
```

In a production deployment, provider calls would include explicit:

- timeouts
- retries
- circuit breakers
- observability
- provider-specific error handling
- idempotency guarantees

---

# Testing

The automated test suite covers the core business and security behavior.

Important tested areas include:

- authentication
- role authorization
- account isolation
- Pixel CRUD
- Pixel module entitlement validation
- ingestion
- landing-page restrictions
- lead activity access
- consensus rules
- expected fixture verdicts
- certificate creation
- certificate idempotency
- certificate signature verification
- certificate tampering
- certificate immutability
- certificate privacy
- credit consumption
- insufficient-credit behavior
- voice not-applicable behavior
- duplicate recency
- duplicate tenant isolation
- Super Admin account visibility

The test suite is intentionally configured with:

```ruby
parallelize(workers: 1)
```

The application was developed/tested on Windows with PostgreSQL, where Rails' threaded parallel test runner caused PostgreSQL connection-level instability once the suite crossed Rails' parallelization threshold.

The suite is small, so deterministic serial execution was preferred over parallel execution for the take-home.

---

# Running the Application

## Requirements

The application requires:

- Ruby
- Rails
- PostgreSQL

The submitted implementation was developed with:

```text
Ruby 3.4.x
Rails 8.1.x
PostgreSQL 17.x
```

---

## Database Configuration

Configure PostgreSQL credentials for the Rails application.

For example, in PowerShell:

```powershell
$env:POSTGRES_USER="postgres"
$env:POSTGRES_PASSWORD="YOUR_PASSWORD"
```

Then prepare the database:

```powershell
bundle install
bundle exec rails db:create
bundle exec rails db:migrate
bundle exec rails db:seed
```

---

## Start Rails

```powershell
bundle exec rails server
```

The application will normally be available at:

```text
http://localhost:3000
```

---

# Seeded Login Credentials

The seed data includes accounts and users for demonstration.

## Super Admin

```text
Email: admin@superpixel.test
Password: password123
```

## Account Admin

```text
Email: admin@solarpro.test
Password: password123
```

## Member

```text
Email: member@solarpro.test
Password: password123
```

---

# Running Tests

Run the full test suite with:

```powershell
bundle exec rails test
```

The submitted solution should complete with zero failures and zero errors.

---

# Demo Flow

A useful reviewer flow is:

### Account Admin

1. Log in as the SolarPro account administrator.
2. Open Pixel Management.
3. Create or inspect a Pixel.
4. Configure modules and allowed landing pages.
5. Copy the installation snippet.
6. Submit a lead through the supplied landing page.
7. Observe actual backend verification activity.
8. Open the CRM.
9. Inspect the resulting lead, layer results, verdict, and certificate.

### Super Admin

1. Log out.
2. Log in as the Super Admin.
3. Open the Super Admin dashboard.
4. Review accounts, plans, credit balances, burn rates, and nearly-out warnings.

---

# Key Design Decisions

The most important design decisions in this solution are:

1. **Tenant ownership is enforced through database queries**, not frontend filtering.
2. **Provider responses are normalized** before entering consensus logic.
3. **Hard stops and weighted risk are separate concepts.**
4. **Incomplete verification cannot silently ACCEPT a lead.**
5. **Credits are consumed atomically per initiated layer.**
6. **Unaffordable checks are recorded explicitly instead of hiding missing evidence.**
7. **Duplicate detection is account scoped and time bounded.**
8. **Real-time UI uses actual backend events rather than simulated progress.**
9. **Certificates snapshot evidence at decision time.**
10. **Certificate integrity is verified cryptographically.**
11. **Public certificate retrieval is separated from private forensic evidence.**
12. **The implementation favors simple, defensible mechanisms over unnecessary infrastructure.**

---

# Production Improvements

Given additional production time, I would prioritize:

### Provider Reliability

- HTTP timeouts
- retries with backoff
- circuit breakers
- provider health monitoring
- idempotent provider requests

### Async Infrastructure

Use a production job backend and introduce stronger retry/dead-letter handling.

### Real-Time Delivery

Consider Server-Sent Events or Action Cable if polling load or latency becomes significant.

### Pixel Authentication

Replace the browser-generated session identifier used for polling authorization with a server-issued cryptographically random short-lived token.

### Certificate Security

Move signing to a dedicated secret/key with rotation support or managed key infrastructure.

### Immutable Evidence

Use stronger database/storage-level append-only guarantees.

### Observability

Add structured logging, metrics, tracing, provider latency monitoring, consensus decision metrics, and credit anomaly alerts.

### Rate Limiting

Apply rate limits to public ingestion, activity, authentication, and certificate endpoints.

### Deployment

Serve the embeddable Super Pixel from a versioned CDN URL and configure production CORS/origin policies appropriately.

---

# Final Notes

The solution intentionally prioritizes the assignment's core verification pipeline over building a large framework around it.

The central path is fully represented:

```text
Pixel
  -> Visit
  -> Lead
  -> Verification
  -> Layer Results
  -> Consensus
  -> Verdict
  -> Certificate
  -> CRM / Real-Time Activity
```

The implementation also explicitly models important failure and edge states such as insufficient credits, unavailable checks, non-applicable modules, hard stops, duplicate isolation, tenant boundaries, and certificate tampering.

These behaviors are implemented as domain rules and covered by tests rather than being hardcoded into the demonstration UI.
