# Subscription Analytics — findings

Dataset: seed-20261023-cd60788c5eca

**Synthetic scenario; not real business performance.**

- 2025-01 to 2025-12: registrations 215 → 600; mature 7-day conversion 26.51% → 20.36% (-6.15 percentage points).
- Collected cash changed from EUR 579.49 in 2025-01 to EUR 5380.36 in 2025-12. This includes renewals, so it does not measure new-user conversion alone.
- Referral has the highest observed channel conversion (36.12%); Social has the lowest (11.46%). These are scenario-specific associations, not causal marketing effects.
- 47.44% of January registrants returned to view content in February. This measures activity, not paid renewal.

## Growth and conversion are different questions

**Evidence.** Registrations changed from 215 to 600 between 2025-01 and 2025-12. Mature 7-day conversion changed from 26.51% to 20.36%: -6.15 percentage points.

**Interpretation.** Registrations measure acquisition volume. Conversion measures how often sufficiently observed new users make a first successful payment. More registrations do not automatically mean a stronger conversion rate.

**Next check.** Compare conversion within signup month, country and acquisition channel. Use counts together with rates; do not average channel percentages without their denominators.

**Boundary.** The monthly endpoints are a descriptive comparison, not a trend-significance test or a causal result.

## Separate cash from new-customer acquisition

**Evidence.** First successful payments contributed EUR 12868.81; subsequent successful payments contributed EUR 25448.18 (66.41% of collected cash). Monthly cash changed from EUR 579.49 to EUR 5380.36.

**Interpretation.** Cash includes payments from the accumulated audience. The first-versus-renewal split shows why total cash and new-user conversion need not move together. It does not by itself attribute the entire monthly change to renewals.

**Next check.** Use SQL question 12 to verify the split. To explain monthly growth further, break first-payment and renewal cash down by payment month.

**Boundary.** Cash excludes failed attempts and is not profit, MRR, accrual revenue or a renewal probability.

## Channel differences need context

**Evidence.** Referral converted 259 of 717 eligible users (36.12%), versus 173 of 1509 for Social (11.46%). The difference is 24.66 percentage points.

**Interpretation.** This describes the acquisition mix in the current dataset. It identifies a comparison worth investigating; it does not establish that shifting budget to the highest-rate channel will improve outcomes.

**Next check.** Inspect country and signup-month composition and obtain acquisition spend before considering budget changes.

**Boundary.** Channel assignment is not randomized, and channel quality differs by construction in the generator. Individual 95% intervals are not a multiple-comparison or causal test.

## Read retention as return-to-content activity

**Evidence.** 102 of 215 January registrants returned in February: 47.44% calendar-month M1 activity retention.

**Interpretation.** The cohort denominator includes everyone who registered in that month, including non-payers. A return event means at least one content view; it says nothing about daily frequency or paid renewal.

**Next check.** Compare cohorts at the same month offset. On real data, validate events and compare users with similar follow-up before recommending engagement changes.

**Boundary.** M0 is 100% because of signup-day events. Late-month signups have shorter first-month exposure. Unobserved future cells are NULL, not zero.

## Next checks
- Compare channels within country and signup month.
- Separate first payments from renewals.
- Obtain spend, refunds and costs before estimating CAC, LTV or profit.
