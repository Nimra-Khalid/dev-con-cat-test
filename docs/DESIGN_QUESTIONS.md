# Design Questions

## Domain modeling

### 1. What are your core models and how do leads, layer-results, verdicts, and certificates relate? Where does a "verification run" live?

The core models are:

```text
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
```

The main relationship is:

```text
Account
  -> Pixel
      -> PixelSession
          -> Lead
              -> VerificationRun
                  -> LayerResult(s)
                  -> Verdict
                  -> ConsentCertificate
                  -> CreditTransaction(s)
```

A `VerificationRun` is a first-class persisted model rather than temporary service state.

That gives each verification attempt its own lifecycle, timestamps, policy version, layer results, verdict, credit usage, and certificate.

This also means the system could support re-verification later without overwriting the history of a previous run.

---

### 2. A layer can be not-enabled, not-applicable, or returned-a-verdict. How does your schema keep these distinct?

`LayerResult` has a separate `execution_status` from its verdict.

Execution states include:

```text
pending
completed
failed
not_enabled
not_applicable
insufficient_credits
```

The layer verdict itself is separate:

```text
pass
warn
fail
```

So these cases remain semantically different:

```text
not_enabled
```

means the account/pixel did not run the layer.

```text
not_applicable
```

means the layer was enabled but did not apply to this lead.

```text
completed + pass/warn/fail
```

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

```text
risk < 25      -> ACCEPT
risk 25..59    -> REVIEW
risk >= 60     -> REJECT
```

A hard stop overrides the numeric score and produces:

```text
REJECT
```

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

```text
REVIEW
```

This is a middle-ground policy:

```text
provider failure != PASS
provider failure != automatic REJECT
provider failure => REVIEW
```

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

```text
super_admin     -> admin dashboard
account_admin   -> account CRM / pixel management
member          -> CRM only
```

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

```text
execution_status = insufficient_credits
```

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

```text
HMAC-SHA256
```

When the certificate is retrieved, the server recomputes the signature from the stored evidence and compares it using a constant-time secure comparison.

If the evidence is changed, verification returns:

```text
valid: false
```

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

```text
POST /leads
   |
   | 202 Accepted
   v
VerificationJob
   |
   v
VerificationRunner
```

For production, I would use a durable job backend with retry policies, dead-letter handling, and idempotency around provider calls.

---

### 13. Which real-time transport did you pick for the live landing page, and what did you trade away?

I used short polling at approximately 750ms.

The browser requests:

```text
GET /leads/:lead_id/activity?session_id=...&after_id=...
```

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