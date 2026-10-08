# aprendIA colour palette — usage guide

## Dashboard v2 palette (from 2026-09-21)

The second version of the dashboard draws its data colours from **Sanzo Wada combination 281** (Pale Lemon Yellow, Benzol Green, Cobalt Green, Antwarp Blue). The code for that version is not in this repository. The sections below describe the brand ramps and the first dashboard's assignments. Where the two differ for a second-version chart, this section applies.

| Wada name | Hex | Used for |
|---|---|---|
| Antwarp Blue | `#007190` | Cluster 1, "Power users". Waterfall bar "Started, didn't complete". |
| Cobalt Green | `#96D1AA` | Cluster 2, "Occasional users". Waterfall bar "Completed". Icon strokes. |
| Benzol Green | `#00978D` | "All users" single series. Waterfall bar "All contacts". High end of the two-point gradient. |
| Pale Lemon Yellow | `#FFEFAE` | Waterfall bar "Never started". Low end of the two-point gradient. |

**Rules in use**
- Darker means more. Antwarp Blue goes to the smaller, more engaged cluster and Cobalt Green to the larger, lighter-touch one.
- The two most contrasting colours (Antwarp Blue, Cobalt Green) go to the two clusters.
- Pale Lemon Yellow is too light to use as a solid fill on a white or card background. It appears only as a waterfall bar and as the low end of a gradient.
- Wada 281 has no red and green loss-and-gain scheme. Cobalt Green marks "Completed" as the positive-feeling tone, without a strict good / bad encoding.

**Supporting inks:** page background `#F8F9FA`, panel fill `#F3F5F7`, gridline `#D9E2EA`, body slate `#1F303F`, muted text `#7C8894`, stat label `#14524B`, stat descriptor `#2E4A3D`, churned `#E03A3A`.

**Validation.** Checked against a colour-separation validator on a white surface, all pairs. Wada 281 does not pass as a four-colour categorical set. Benzol Green and Antwarp Blue are 12.0 apart in normal vision, and the floor is 15. Cobalt Green and Pale Lemon Yellow fall below the chroma floor and outside the lightness band, so they read as light grey beside the darker pair. In practice, use at most two Wada colours per chart, label directly, and give any third colour a secondary cue. Do not use Benzol Green and Antwarp Blue side by side as the only distinction between two series.

---

## Brand palette

The ramps, colour roles and general rules below are the aprendIA brand palette. They apply to product and other materials. Dashboard v2 uses the Wada colours above for its data, so the cluster, pilot and lifecycle assignments further down do not apply to it.

## The palette at a glance

Six hue ramps, each running ten stops from near-white (50) to near-black (900), plus Black and White as fixed anchors. Each ramp has a **base stop** — the primary use value, shown in bold below — and lighter or darker stops for backgrounds, borders, and type.

| Ramp | Base | Role |
|----|----|----|
| Green | 400 · `#3CC98A` | Brand primary. Positive outcomes, completion, growth. |
| Teal | 400 · `#17B8CC` | Digital/exploratory. Pilot phase, progress, active states. |
| Violet | 400 · `#6A5CE8` | Learning depth. Modules, clusters, institutional weight. |
| Amber | 400 · `#F5A623` | Energy and urgency. Streaks, engagement alerts, highlights. |
| Slate | 700 · `#1F303F` | Dark neutral. Body text, borders, UI chrome. |
| Red | 400 · `#E03A3A` | Danger. Errors, critical states, drop-out flags. |
| Black | `#000000` | Headings, primary text on light backgrounds. |
| White | `#FFFFFF` | Backgrounds, text on dark surfaces. |

------------------------------------------------------------------------

## Semantic roles

### Green — the brand colour

Green is the reward colour. Use it to signal completion, success, and achievement. It should not appear as a neutral background or generic label; its presence should mean something positive has happened or is in progress.

- Module completion badges
- "Correct" states in quizzes
- Positive engagement metrics in dashboards
- The primary CTA button

### Teal — the exploratory colour

Teal sits adjacent to Green but reads as cooler and more provisional. It is the natural colour for things that are underway but not yet resolved — pilots, active sessions, progress indicators.

- Active/in-progress states
- Pilot-phase labelling (see below)
- Progress bars and step trackers
- Links and interactive affordances

### Violet — the depth colour

Violet carries institutional weight without feeling corporate. Use it for content that represents structured learning — modules, courses, formal categories — and anywhere you want to signal rigour rather than energy.

- Course and module labels
- Cluster or cohort identifiers (see below)
- Secondary navigation categories
- Data series requiring visual separation from Green/Teal

### Amber — the urgency colour

Amber should be used sparingly: it is the colour that demands attention. In a dashboard context it signals something that needs action; in a gamification context it signals streak or reward states. Overuse destroys its signal value.

- Reminder nudges and re-engagement prompts
- Streak counters and engagement milestones
- "At risk" flags (before escalating to Red)
- Highlight/annotation states in data views

### Slate — the neutral

Slate replaces brown as the dark neutral. Its cool undertone harmonises with the green/teal family rather than fighting it. Use Slate for UI scaffolding, body text, and anything that needs to recede.

- Body text: Slate 700 (`#1F303F`) on white
- Light borders and dividers: Slate 200 (`#B8C3CE`)
- Background fills on secondary panels: Slate 50 (`#F3F5F7`)
- Footer / nav chrome

### Red — the danger colour

Red is reserved for states that require intervention. It should never appear as decoration.

- Error states and validation failures
- Drop-out or disengagement flags in analytics
- Critical threshold alerts
- Destructive actions (delete, remove)

------------------------------------------------------------------------

## First dashboard (v1, archived): specific pairings

These assignments describe the first dashboard (`app.R`), now archived. Dashboard v2 does not use them. They are kept for reference and for reading older charts. One discrepancy: in the lifecycle table below, Reactivated is Teal, but the first dashboard's code colours reactivated users Violet.

### Pilot vs scale-up

Use **Teal for pilot** and **Green for scale-up**. The logic: Teal reads as exploratory and in-progress; Green — the brand's foundational colour — is reserved for the state that has arrived, been proven, and belongs. This creates a natural visual narrative of maturation.

| Phase    | Colour | Stop for filled labels | Stop for text on white |
|----------|--------|------------------------|------------------------|
| Pilot    | Teal   | 400 · `#17B8CC`        | 600 · `#0D9AAB`        |
| Scale-up | Green  | 400 · `#3CC98A`        | 600 · `#218D5B`        |

For backgrounds (e.g. a highlighted row or card), use the 50 or 100 stop with 800-stop text from the same ramp. Never use Teal 400 as a background with black text — the contrast is insufficient.

**On charts:** when plotting pilot and scale-up as two data series on the same axis, use solid Teal and solid Green at the 400 stop for lines or bars. Add a secondary visual cue (dashed vs solid line, or circle vs square marker) so the distinction does not rely on colour alone.

------------------------------------------------------------------------

### Clusters — by number

The cluster palette builds incrementally, with each added colour chosen to maximise perceptual distance from those already in use. The assignments below are fixed — use them consistently so that "Teal" always means the same cluster across every chart, slide, and report.

#### 2 clusters — Teal + Violet

Hold Amber back entirely at two clusters. Two hues that are maximally distinct without introducing urgency connotations — you do not want readers inferring that one cluster is inherently more alarming than another.

| Cluster   | Colour | 400 base  | Label bg               | Label text             |
|-----------|--------|-----------|------------------------|------------------------|
| Cluster 1 | Teal   | `#17B8CC` | Teal 100 · `#BCEDF4`   | Teal 800 · `#065B67`   |
| Cluster 2 | Violet | `#6A5CE8` | Violet 100 · `#DDD9FB` | Violet 800 · `#2A2282` |

#### 3 clusters — Teal + Violet + Amber

The core three-way split. Teal, Violet and Amber are perceptually distinct across the full ramp, hold up under greyscale conversion, and are separable for the most common forms of colour blindness (deuteranopia, protanopia). None of the three duplicates Green, so cluster colours do not compete with positive-outcome signalling.

| Cluster   | Colour | 400 base  | Label bg               | Label text             |
|-----------|--------|-----------|------------------------|------------------------|
| Cluster 1 | Teal   | `#17B8CC` | Teal 100 · `#BCEDF4`   | Teal 800 · `#065B67`   |
| Cluster 2 | Violet | `#6A5CE8` | Violet 100 · `#DDD9FB` | Violet 800 · `#2A2282` |
| Cluster 3 | Amber  | `#F5A623` | Amber 100 · `#FCE5BE`  | Amber 800 · `#784B07`  |

#### 4 clusters — add Green

Green enters here as the fourth cluster colour. This is the brand colour, and its presence in a cluster chart carries a mild risk of conflation with "positive outcome" states. The mitigation: on any chart that simultaneously shows an outcome variable (completion rate, quiz scores), encode the outcome differently — a line rather than a filled bar, or a separate panel — so that Green-the-cluster and Green-the-achievement cannot be confused.

| Cluster   | Colour | 400 base  | Label bg               | Label text             |
|-----------|--------|-----------|------------------------|------------------------|
| Cluster 1 | Teal   | `#17B8CC` | Teal 100 · `#BCEDF4`   | Teal 800 · `#065B67`   |
| Cluster 2 | Violet | `#6A5CE8` | Violet 100 · `#DDD9FB` | Violet 800 · `#2A2282` |
| Cluster 3 | Amber  | `#F5A623` | Amber 100 · `#FCE5BE`  | Amber 800 · `#784B07`  |
| Cluster 4 | Green  | `#3CC98A` | Green 100 · `#CBEFDF`  | Green 800 · `#156944`  |

#### 5 clusters — add Slate

At five clusters, colour alone is no longer sufficient. Slate is the fifth hue, but it reads as neutral or "reference group" to most readers, which may inadvertently suggest that one cluster is the baseline. For this reason, five-cluster visualisations must use a secondary encoding alongside colour: always label each cluster directly on the chart with its number or name, and if the output may be printed or photocopied, add a pattern fill or marker shape so the distinction survives greyscale.

| Cluster | Colour | 400 base | Label bg | Label text | Secondary cue |
|----|----|----|----|----|----|
| Cluster 1 | Teal | `#17B8CC` | Teal 100 · `#BCEDF4` | Teal 800 · `#065B67` | Circle marker / solid line |
| Cluster 2 | Violet | `#6A5CE8` | Violet 100 · `#DDD9FB` | Violet 800 · `#2A2282` | Square marker / dashed line |
| Cluster 3 | Amber | `#F5A623` | Amber 100 · `#FCE5BE` | Amber 800 · `#784B07` | Triangle marker / dotted line |
| Cluster 4 | Green | `#3CC98A` | Green 100 · `#CBEFDF` | Green 800 · `#156944` | Diamond marker / dash-dot line |
| Cluster 5 | Slate | `#628098` | Slate 100 · `#DCE1E8` | Slate 800 · `#1F303F` | Cross marker / long-dash line |

If a sixth cluster is ever needed, the palette has been exhausted for cluster use. At that point, reconsider whether the segmentation is too granular for visual communication, or use a sequential single-hue ramp (e.g. Violet 200 through 800) and label every segment explicitly.

#### Naming convention

Use the colour as a mnemonic in internal documentation ("the Teal cluster", "Amber users") only when cluster labels are stable across analyses. If cluster assignments change between model runs, refer to clusters by number only and regenerate colour assignments consistently from this table — do not reassign colours ad hoc.

------------------------------------------------------------------------

### Lifecycle and funnel states

aprendIA sessions can be understood as a lifecycle: teachers enter, engage, disengage, and sometimes return. This creates a distinct set of semantic colour needs that sit alongside — but do not replace — the cluster and pilot/scale-up pairings.

| State | Colour | Stop | Meaning |
|----|----|----|----|
| Activated | Green | 400 · `#3CC98A` | Positive entry — a teacher has joined and engaged for the first time. |
| Reactivated | Teal | 400 · `#17B8CC` | Positive return — a previously inactive teacher has re-engaged. |
| At-risk | Amber | 400 · `#F5A623` | Warning — extended inactivity, unresponded reminders, intervention still possible. |
| Churned | Red | 400 · `#E03A3A` | Terminal exit — the at-risk state was not resolved. |

**Why Red for churn and not Amber.** Amber in this palette means warning — action is still possible. Churn is the event that the warning failed to prevent. Using Amber for churn would collapse the distinction between the precursor and the outcome, undermining both signals. Amber belongs on the at-risk teacher; Red belongs on the one who has already left.

**Why Teal for reactivation.** Green and Teal are adjacent on the hue wheel and read as a family. A reader will naturally perceive activation and reactivation as related positive events set against the Red, without needing to be told. The palette is doing semantic work that would otherwise require annotation.

**The full danger ladder, restated in lifecycle terms:**

| Stage | Colour | Trigger example |
|----|----|----|
| Engaged | Green | Active in last 7 days |
| Drifting | Amber 300 · `#F9CC8A` | No activity in 8–14 days |
| At-risk | Amber 500 · `#D48710` | No activity in 15–30 days, reminder unresponded |
| Churned | Red 400 · `#E03A3A` | No activity in 30+ days, threshold crossed |
| Reactivated | Teal | Returned after churn threshold |

The two Amber stops give you a graduated at-risk signal without introducing a fifth hue. Use Amber 300 backgrounds with Amber 800 text for the lighter warning state; use a solid Amber 500 fill for the more urgent one.

**A note on dashboard collisions.** Teal carries three roles in this system: pilot phase, Cluster 1, and reactivation. These should never appear simultaneously in the same visualisation. On a dashboard that combines lifecycle charts and cluster charts on a single page, label each chart's legend explicitly rather than relying on colour memory across panels. The guide's colour system is consistent within a visualisation, not necessarily across an entire page.

------------------------------------------------------------------------

## General rules

**Contrast.** For text on a coloured background, always use the 800 or 900 stop from the same ramp. Never use Slate or Black on a mid-stop (300–500) background — mid-stops are for fills only, not text backgrounds.

**One signal at a time.** A single element should carry one semantic colour. A "completed module" card that is simultaneously Green (completion) and Teal (pilot phase) sends a contradictory message. Decide which signal is primary.

**Use light stops for backgrounds.** The 50 and 100 stops exist for backgrounds, hover states, and section fills. The 400 base is for icons, borders, and small filled elements. The 700–900 stops are for type on light backgrounds.

**Reserve Amber and Red for data-driven states.** They should appear because the data warrants them, not as decorative choices. A dashboard with Amber everywhere is a dashboard nobody trusts.

**Accessibility minimum.** All text/background pairings must meet WCAG AA (4.5:1 for body text, 3:1 for large text). The 800-on-50 combinations across all ramps meet this threshold. The base 400 stops do not have sufficient contrast against white for small text — use them for fills, icons, and large display text only.

------------------------------------------------------------------------

## What this palette is not for

- **Photography and illustration:** the palette governs UI and data. Photographic content should not be tinted or filtered with these colours.
- **Decorative variety:** do not use multiple ramps simply to make a layout more colourful. Each colour should be earning its presence by carrying meaning.
- **Brand extensions outside aprendIA:** this palette is specific to the aprendIA product. IRC's broader brand identity may have different requirements.
