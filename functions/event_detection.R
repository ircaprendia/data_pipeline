# event_schema detectors for aprendIA
#
# R-based (regex) detectors, for the events confirmed reliable enough to detect this
# way -- either because the source text is authored verbatim (course_selected), or
# because the pattern has been exhaustively reviewed and locked in as a high-recall
# pre-filter for a later LLM pass (course_complete). See the event schema design note
# and the event schema's fixed-string sourcing record for the full sourcing/verification record
# behind each pattern below -- do not edit a regex here without updating those docs to
# match, since they're what makes the regex trustworthy rather than guessed.
#
# The harder course-milestone events (module_start, quiz_pass/fail, deep_dive_viewed,
# etc.) need an LLM pass, not regex -- see event_schema_design.md §4. This file only
# holds the R-viable tier.
#
# Output contract: each detect_*() function returns one row per detected event, in the
# event_schema shape: contact_id, event_type, event_date, value, detection_method,
# confidence, source_version_id, source_message_id, session_id.
#
# Note on session_id: it is only a counter WITHIN a contact (session_id = 1 is the first
# session for every contact, 2 the second, etc.) -- it is NOT globally unique on its own.
# Use contact_id + session_id together as the composite key when joining to session_data
# or session_data_long; never join on session_id alone.

library(tidyverse)

# Course name variants -> canonical lineage_id (research/course_taxonomy/course_lineage.csv).
# requires_proximity flags the generic-sounding names ("Reading", "Reading Skills") that
# show up in ordinary teacher-education text unrelated to course selection -- eg "students'
# reading skills" -- so they only count when directly adjacent to "selected", not just
# co-occurring anywhere in the message the way the distinctive proper-noun course names can.
# Found 2026-07-02: "Reading Skills" matched a research-topic-drafting message purely by
# coincidence (the word "selected" appeared unrelated, in "a selected school district").
course_name_lookup <- tibble::tribble(
  ~pattern,                                          ~lineage_id,        ~requires_proximity,
  "Math for Every Learner",                          "maths",            FALSE,
  "Building Strong Readers",                         "reading",          FALSE,
  "Teacher Wellbeing",                                "wellbeing",       FALSE,
  "Classroom Management( ?: ?Healing Classrooms)?",   "classroom_sel",   FALSE,
  "Active\\s*(&|and)\\s*Inclusive Learning",          "active_inclusive",FALSE,
  # "your [course] course" -- an informal in-conversation reference distinct from the
  # formal course-name phrases above, added 2026-07-03. Found via quiz_interaction context
  # resolution: a Wellbeing-course quiz question using a "reading class" scenario ("your
  # wellbeing course! ... A teacher feels overwhelmed before the start of reading class...")
  # was wrongly resolved to the reading lineage via the generic proximity-required "Reading"
  # pattern below, since none of the formal reliable patterns matched "wellbeing course" as
  # phrased. Placed ahead of the proximity-required rows so it wins on a genuine conflict --
  # quantified impact was small (1/352 checked quiz_interaction resolutions) but the fix is
  # cheap and the pattern is clean, so it's fixed rather than left as an accepted leak.
  "your math(s)? course",                            "maths",            FALSE,
  "your reading course",                             "reading",          FALSE,
  "your wellbeing course",                           "wellbeing",        FALSE,
  "your classroom management course",                "classroom_sel",    FALSE,
  "your active.{0,10}inclusive.{0,10}(learning )?course", "active_inclusive", FALSE,
  "Reading Skills",                                   "reading",         TRUE,
  "Reading",                                          "reading",         TRUE
)

reliable_pattern   <- paste(course_name_lookup$pattern[!course_name_lookup$requires_proximity], collapse = "|")
proximity_pattern  <- paste(course_name_lookup$pattern[course_name_lookup$requires_proximity], collapse = "|")
course_pattern     <- paste(course_name_lookup$pattern, collapse = "|")

# Internal: map a message's matched course-name text to its canonical lineage_id.
# Returns NA when no known course name is present (eg course_complete messages that
# just say "this course" without naming it -- left for the LLM stage to resolve).
lookup_lineage_id <- function(message_text) {
  hit <- course_name_lookup %>%
    filter(str_detect(message_text, regex(pattern, ignore_case = TRUE)))
  if (nrow(hit) == 0) return(NA_character_)
  hit$lineage_id[1]
}


# Detect course_selected events
# Sourced from pathway-selection-agent.md: "Great -- you've selected [course].
# Let's begin!" -- authored verbatim, not reverse-engineered. Exhaustively reviewed
# against all 271 real candidate messages in the Nigeria data (2026-07-02): 238/238
# recall, 0 false positives. See event_schema_fixed_strings.md for the full review.
# Arguments:
#   data: clean_message_data, Nigeria, both directions
# Returns: one row per detected course_selected event, in the event_schema shape
detect_course_selected <- function(data) {

  hard_exclusion <- paste(c(
    "haven.?t (yet )?selected", "have not yet selected",
    "which is not one of the available", "not one of the available",
    "selected .Classroom Toolkit.", "selected .Learn a skill.", "selected .Solve a challenge.",
    "you chose .*but you already selected", "start with one course at a time",
    "selected .option", "selected .\\d.", "selected .Take a s2.", "selected .Many students."
  ), collapse = "|")

  menu_exclusion <- paste(c(
    "Here are (the|your) (available )?course", "choose a course to start", "Now choose a course",
    "Which (course|skill area) would you like", "which course would you like",
    "Please (pick|choose|reply with (your|the)) (which|choice|course)",
    "I've got (three|four) short courses", "got \\d short courses"
  ), collapse = "|")

  confirmation_phrase <- paste0("you.?ve selected (", reliable_pattern, ")")
  proximity_confirmation <- paste0("you.{0,15}selected (the )?(", proximity_pattern, ")\\b")

  data %>%
    filter(direction == "Outgoing", country == "nigeria") %>%
    mutate(
      has_confirmation = str_detect(message, regex(confirmation_phrase, ignore_case = TRUE)),
      reliable_match = str_detect(message, regex(reliable_pattern, ignore_case = TRUE)) &
        str_detect(message, regex("selected", ignore_case = TRUE)) &
        !str_detect(message, regex(hard_exclusion, ignore_case = TRUE)) &
        (has_confirmation | !str_detect(message, regex(menu_exclusion, ignore_case = TRUE))),
      proximity_match = str_detect(message, regex(proximity_confirmation, ignore_case = TRUE)) &
        !str_detect(message, regex(hard_exclusion, ignore_case = TRUE)),
      is_match = reliable_match | proximity_match
    ) %>%
    filter(is_match) %>%
    rowwise() %>%
    mutate(lineage_id = lookup_lineage_id(message)) %>%
    ungroup() %>%
    transmute(
      contact_id,
      event_type = "course_selected",
      event_date = date,
      value = lineage_id,
      detection_method = "R",
      confidence = NA_real_,
      source_version_id = paste0(lineage_id, "_v2_current"),
      source_message_id = message_id,
      session_id
    )
}


# Detect course_start events -- coarse, contact-level "did they ever start this course"
# Built 2026-07-03 after tracing real contact histories found course_selected massively
# undercounts actual course starts (81% of contacts shown the course menu produce no
# course_selected event -- see event_schema_fixed_strings.md). Deliberately coarse per
# The project lead's scoping: the goal is "did this contact start course X," not precise per-module
# timing -- so candidate messages don't need the same exclusion rigor a true module_start
# detector would (offers, deferred mentions, etc. are left in, since they still corroborate
# real engagement with that course at a coarse grain). The one exclusion that DOES matter
# even here is completion messages, which would otherwise trivially satisfy a bare title
# match without any real evidence of a start.
#
# Per-course title patterns and exclusions were derived by reading real message samples for
# EACH course independently, not by assuming the product team's canonical titles are sufficient or
# uniformly reliable -- they are not (see bot_flow_reference.md §3a, §6). Two courses needed
# real fixes beyond a bare title match, found by checking real 15-message samples:
#   - Classroom Management: "Sense of Control" alone is an ordinary phrase that appears in
#     generic classroom-tip content, quiz feedback, and image-description messages
#     unrelated to the module. Requiring "Module 1" co-occurrence fixed this (title alone:
#     4,218 messages, badly diluted; title + Module 1: 2,856, clean in a 15-row spot-check).
#   - Reading: two genuine false-positive categories found -- a lesson plan generated FOR
#     the teacher's own students that happens to reuse the module title ("Lesson Plan: How
#     We Learn to Read"), and a course-structure tangent ("you're asking about the
#     different levels or stages in one of the courses"). Excluding both narrowly (not the
#     broader "you can use" pattern, which wrongly excludes genuine module intros that use
#     the same phrase describing real classroom strategies) took Reading from 13/15 to
#     15/15 clean.
# Maths and Wellbeing needed no additional exclusions beyond completion -- their titles
# ("Exploring Math Domains," "Understanding Teacher Wellbeing") are distinctive enough on
# their own; 15/15 clean in each course's spot-check.
#
# Classroom Management covers both "Sense of Control" (v1 title, still the dominant one in
# real data) and "Creating Safety and Predictability" (current v2 title) -- either is
# genuine evidence the contact engaged with this course, regardless of which script
# generation delivered it.
#
# CORRECTED 2026-07-03, caught by a recall check the project lead asked for (checking precision alone,
# which is all the initial 15-row spot-checks did per course, is not enough -- a clean
# sample says nothing about what a pattern MISSES entirely). Cross-validated each course's
# course_start count against independent evidence (a quiz_interaction resolved to that
# course, or a module/deep_dive completion naming one of that course's titles) and found
# Reading's pattern was missing the DOMINANT real title entirely: "How We Learn to Read"
# (module_title_lookup's canonical v2 title, 80 messages / 57 contacts) is actually the
# MINORITY phrasing in real data -- "Module 1 - Welcome to What is Reading?" is far more
# common (882 messages / 683 contacts) and was never in the original pattern, despite
# appearing in the very first contact trace that motivated building course_start at all.
# Fixed by adding it to the title pattern; Reading's contact count rose from 55 to 732 (a
# ~13x increase), 15/15 clean on a fresh spot-check of the combined pool.
#
# The same recall check on Maths, Classroom, and Wellbeing found small residual gaps (1, 7,
# and 1 contacts respectively) that traced back to contacts with NO real engagement in that
# course at all -- their only "evidence" was a single quiz_interaction resolved to that
# course on thin contextual grounds, which looks like an upstream quiz-resolution
# mis-classification, not a course_start miss. course_start correctly does not flag these
# contacts. Not chased further -- flagged as a known, separate, small-scale limitation in
# quiz course resolution, out of scope for this fix.
#
# FURTHER BROADENED 2026-07-03: cross-validating against independent evidence only catches
# misses where SOME other course-tier event already exists for the contact -- it can't find
# a contact whose ONLY trace of a course is the start itself. Ran a second, more aggressive
# check at the project lead's request: loose component-word co-occurrence (eg "explor" + "math" +
# "domain" anywhere in a message, any order, not the exact phrase) to surface title variants
# the exact-phrase pattern couldn't have found by construction.
#   - Maths: surfaced a genuine small tail of alternate Module 1 titles beyond "Exploring
#     Math Domains" -- "Exploring Number Sense" (11 contacts, added to the pattern above),
#     plus three singleton variants ("Foundations of Effective Math Teaching," "Measurement
#     Basics," "Foundations of Math: Number Sense" -- 1 contact each) and one two-contact
#     variant ("Number Sense & Place Value"), left undocumented as noise. Union of every
#     variant found: 660 contacts vs the original pattern's 655 -- confirms the original
#     single-title pattern was already catching ~99% of what exhaustive searching finds.
#   - Classroom Management and Wellbeing: this technique doesn't work well for either,
#     because their natural vocabulary (safety, routine, stress, behavior) is generic enough
#     to be shared with OTHER courses' real content -- the loose search mostly returned
#     cross-course contamination (eg Reading/Wellbeing messages that happen to mention
#     "safety" or "stress"), not genuine misses. One genuinely distinct Classroom title was
#     found this way ("Organizing Space for Large Classes") but only 1 contact -- not worth
#     adding. Both courses' original patterns are confirmed adequate as-is.
# Net effect of this whole exercise: one real, large fix (Reading, 55->732 contacts, a ~13x
# increase), one small worthwhile addition (Maths), two courses confirmed solid without
# changes. The lesson generalized in bot_flow_reference.md and applied as standing practice
# going forward: a clean precision spot-check on one assumed title says nothing about
# recall, and the size of the gap (negligible for Maths, ~13x for Reading) isn't
# predictable in advance -- it has to be checked per pattern, not assumed either way.
#
# SENSE-CHECKED 2026-07-03: does the blunt completion exclusion ("completed|congratulations")
# wrongly throw out any genuine start message? Checked every excluded candidate across all
# four courses (80 total) -- found exactly 1 real false exclusion, out of scope for the
# broader recall work above but still a genuine bug: "Great choice! Classroom Management is
# all about... Before we begin, have you already completed the onboarding questions..." --
# "completed" here refers to ONBOARDING status, not module completion, and this message was
# the contact's only candidate (confirmed: this contact had zero classroom_sel course_start
# event at all as a result). Fixed with a narrow exception rather than loosening the
# exclusion generally -- see completion_exclusion below.
# Arguments:
#   data: clean_message_data, Nigeria, both directions
# Returns: one row per contact per course -- the EARLIEST matching message only, since the
#   goal is "did they start" (a single fact), not every mention. A contact who shows
#   evidence for more than one course produces one row per course.
course_start_patterns <- tibble::tribble(
  ~lineage_id,        ~title_pattern,                                              ~requires_module1, ~resource_exclusion,           ~tangent_exclusion,
  "maths",            "Exploring Math Domains|Exploring Number Sense",             FALSE,             NA_character_,                  NA_character_,
  "reading",          "How We Learn to Read|What is Reading",                      FALSE,             "^.{0,60}lesson plan|Lesson Plan:", "different levels or stages|levels or modules in one of the courses",
  "classroom_sel",    "Sense of Control|Creating Safety and Predictability",       TRUE,              NA_character_,                  NA_character_,
  "wellbeing",        "Understanding Teacher Wellbeing",                          FALSE,             NA_character_,                  NA_character_
)

detect_course_start <- function(data) {

  base <- data %>% filter(direction == "Outgoing", country == "nigeria")

  results <- map_dfr(seq_len(nrow(course_start_patterns)), function(i) {
    row <- course_start_patterns[i, ]

    candidates <- base %>%
      filter(str_detect(message, regex(row$title_pattern, ignore_case = TRUE))) %>%
      # cross-course comparison summaries (eg "which course do you mean by 'different
      # levels'? here's a general summary for each course...") name every course's title
      # in one message to answer a structural question -- found 2026-07-03 as a genuine
      # false positive producing 3 course_start rows from one message for one contact.
      # Rare (1 message in the whole dataset) but a clean, distinguishing signature, so
      # excluded outright rather than left as an accepted 1-contact leak.
      filter(!str_detect(message, regex("general summary for each course", ignore_case = TRUE)))

    if (row$requires_module1) {
      candidates <- candidates %>% filter(str_detect(message, regex("Module 1", ignore_case = TRUE)))
    }

    # "completed the onboarding" is a status check ahead of Module 1, not a module
    # completion -- exempted so it doesn't wrongly exclude a genuine start (found 2026-07-03
    # sense-checking this exclusion: one contact's only candidate message was exactly this
    # phrasing, and excluding it left them with zero course_start event at all).
    candidates <- candidates %>%
      filter(
        !str_detect(message, regex("completed|congratulations", ignore_case = TRUE)) |
        str_detect(message, regex("completed (the )?onboarding", ignore_case = TRUE))
      )

    if (!is.na(row$resource_exclusion)) {
      candidates <- candidates %>% filter(!str_detect(message, regex(row$resource_exclusion, ignore_case = TRUE)))
    }
    if (!is.na(row$tangent_exclusion)) {
      candidates <- candidates %>% filter(!str_detect(message, regex(row$tangent_exclusion, ignore_case = TRUE)))
    }

    candidates %>%
      arrange(date) %>%
      group_by(contact_id) %>%
      slice_head(n = 1) %>%
      ungroup() %>%
      transmute(
        contact_id,
        event_type = "course_start",
        event_date = date,
        value = row$lineage_id,
        detection_method = "R_prefilter",
        confidence = NA_real_,
        source_version_id = paste0(row$lineage_id, "_v2_current"),
        source_message_id = message_id,
        session_id
      )
  })

  results
}


# Detect course_complete CANDIDATES (pre-filter, not a final detector)
# Not authored anywhere in the product team's files -- the Course Instruction files specify the
# completion *logic* ("Course completes when both Deep Dives are done") but never the
# message text, which is generated and varies. This is a high-recall pre-filter for an
# LLM pass, not a standalone detector. Exhaustively reviewed against all 86 raw
# candidates (2026-07-02): 78 messages / 52 contacts pass after excluding module-level
# false positives ("completed all strategies/quizzes in Module N") and "nearly
# completed". See event_schema_fixed_strings.md for the full review, including the
# known duplication (repeated confirmation messages for the same event) and the
# resolved {{final_score}} template bug that the LLM stage still needs to handle.
#
# RECALL-CHECKED 2026-07-03: broadened search for alternate course-completion phrasing
# found the original "completed all...modules?" pattern was already catching almost
# everything -- a broad net using looser course-name matching mostly returned MODULE-level
# completions ("completed Module 1 of Math for Every Learner") as false leads, not genuine
# misses. One real, distinct phrasing found: "Congratulations on completing the [Course]
# course!" (no "all modules" language at all). Two rounds of false positives found and
# fixed adding it: (1) "course" is an ordinary English word -- "completing the full course
# of TB medicine/treatment" (the bot answering an unrelated health question) matched purely
# by coincidence, fixed by excluding "course of" generically rather than enumerating every
# possible noun after it; (2) messages where the bot drafts an announcement or reminder for
# the teacher to send to THEIR OWN team/colleagues about course completion generally --
# not a report of the teacher's own completion -- fixed by excluding that framing
# specifically. Final: 78 -> 85 candidates, 52 -> 54 contacts (~4% increase), 7/7 genuine
# on the newly-added messages after both fixes.
# Arguments:
#   data: clean_message_data, Nigeria, both directions
# Returns: one row per pre-filtered candidate message, detection_method = "R_prefilter"
#   to make clear this is not yet a confirmed course_complete event -- value is NA
#   when the message doesn't name a specific course (left for the LLM stage to resolve
#   from context)
detect_course_complete_candidates <- function(data) {

  data %>%
    filter(direction == "Outgoing", country == "nigeria") %>%
    filter(
      (
        str_detect(message, regex("completed all.{0,15}modules?", ignore_case = TRUE)) |
        str_detect(message, regex("completing the.{0,30}course", ignore_case = TRUE))
      ) &
        !str_detect(message, regex("nearly completed", ignore_case = TRUE)) &
        !str_detect(message, regex("completed all.{0,15}(strategies|quizzes)", ignore_case = TRUE)) &
        !str_detect(message, regex("course of", ignore_case = TRUE)) &
        !str_detect(message, regex("message (you can send|to send|for) (your|to) (team|colleagues|educators)|official announcement|reminder to all educators", ignore_case = TRUE))
    ) %>%
    rowwise() %>%
    mutate(lineage_id = lookup_lineage_id(message)) %>%
    ungroup() %>%
    transmute(
      contact_id,
      event_type = "course_complete",
      event_date = date,
      value = lineage_id,
      detection_method = "R_prefilter",
      confidence = NA_real_,
      source_version_id = if_else(is.na(lineage_id), NA_character_, paste0(lineage_id, "_v2_current")),
      source_message_id = message_id,
      session_id
    )
}


# Detect quiz CANDIDATES (pre-filter, not a final detector)
# Not authored anywhere in the product team's files -- quiz feedback is confirmed generated, not
# templated (system_prompt.2.0.md §10 mandates rubric-based feedback and forbids
# near-verbatim reuse). This is a high-recall pre-filter for the LLM pass, which still
# needs to: extract the actual score/pass-fail result, resolve which course/module the
# quiz belongs to, and separate genuine quiz interactions from passing mentions in
# unrelated content (eg a Solve-a-Challenge lesson-plan response that happens to
# mention "quiz questions"). Volume (2,169 raw candidates) is too large for the
# exhaustive per-message review course_selected/course_complete got -- validated by
# spot-check sample instead (2026-07-02): 14/15 genuine in a random sample of 15.
# Arguments:
#   data: clean_message_data, Nigeria, both directions
# Returns: one row per pre-filtered candidate message, detection_method = "R_prefilter"
detect_quiz_candidates <- function(data) {

  # Widened 2026-07-02 after auditing the excluded pool (7,038 "quiz"-mentioning
  # messages that didn't pass the original filter): found genuine misses --
  # "You've completed the quiz and Module 1!" (no question/correct language at all),
  # first-question messages with no prior feedback to anchor on ("Quiz: Module 2..."
  # instead of "Question 1"), and quiz-start invitations wrongly caught by an
  # over-broad "unlock module" exclusion that was meant only for pure module-intro
  # descriptions ("Completing a reflection and quiz here unlocks Module 2"), not
  # genuine "ready for the quiz?" invitations.
  #
  # Tried and reverted: bare emoji-numbering (1️⃣2️⃣3️⃣) as an inclusion trigger caused a
  # precision drop (7/12 false positives in a spot-check) -- Solve-a-Challenge lesson
  # plans routinely use the same emoji-numbered-steps formatting for unrelated content
  # (activity steps, tips), not just quiz options. Lettered options (A) B) C)) didn't
  # cause the same noise, so that one stayed.
  inclusion <- paste(c(
    "question\\s*\\d", "quiz question", "the correct answer is", "correct!", "not quite", "almost!",
    "completed the quiz", "quiz time", "start the quiz", "ready for (the |another )?quiz",
    "take a.{0,10}quiz", "quiz:", "[A-D]\\)\\s"
  ), collapse = "|")

  description_exclusion <- paste(c(
    "completing a reflection and quiz", "after these,? reflect and quiz",
    "reflect and quiz to unlock", "after the last,? .{0,10}(you'll )?(reflect and )?take a quiz to unlock"
  ), collapse = "|")

  # Split off classroom-resource generation from genuine bot-delivered quizzes (found
  # 2026-07-02 auditing the unresolved quiz_interaction pool): the bot routinely generates
  # quiz content FOR a teacher to use with their own students (a Solve-a-Challenge/lesson-
  # plan request), phrased almost identically to the bot delivering its own course quiz.
  # 12/12 precision spot-check on messages matching this pattern -- all genuine resource
  # generation, none were the bot's own course quiz. Recall is NOT complete: a spot-check
  # of the *unflagged* pool found at least one miss ("Here's a simple plan for your Human
  # Body Quiz Game...") that this pattern doesn't catch -- expected to leave some residual
  # for the LLM stage to still resolve, same as any other high-recall pre-filter here.
  # WIDENED 2026-07-03: "here's a [adjective] quiz" originally only recognised
  # quick/simple/set of, missing real deliveries using other adjectives ("here's a short
  # quiz to follow up your alphabet lessons") -- confirmed by manual review of the
  # quiz_interaction pool's resource-shaped messages that this was an enumerable-adjective
  # gap, not a structurally different phrasing. Loosened to any single word (or none)
  # between the opener and "quiz"/"interactive". Also added "activity sheet and quiz" /
  # "worksheet and quiz" as a distinct resource-delivery shape found in the same review.
  resource_pattern <- paste(c(
    "you can use", "for your (own )?(class|students|pupils|learners)",
    "here('s| is| are) (a |some )?(\\w+\\s)?(quiz|interactive)",
    "quiz questions (and|for)", "try asking these", "oral quiz",
    "(activity sheet|worksheet) and quiz"
  ), collapse = "|")

  # RECALL-CHECKED AND WIDENED 2026-07-03: the "quiz" word requirement above misses genuine
  # mid-quiz continuation messages that never say "quiz" at all -- "Correct! ... Next
  # question: ..." or "Correct! ... 2. Two learners work together..." are real quiz turns,
  # confirmed by detect_quiz_question_feedback() already independently validating this
  # opener pattern (20/20 + 15/15 precision, 2026-07-02). Checked how much this costs
  # quiz_interaction specifically: 635 messages / 186 contacts share this exact gap, 12
  # contacts entirely missing any quiz_interaction/quiz_content_generated event as a
  # result (the other 174 already have some other quiz message caught, so this was mostly
  # an undercount of volume, not contact-level misses). 15/15 clean on a fresh spot-check
  # of the newly-added messages. Added the same feedback-opener pattern as an alternate
  # entry point, independent of the "quiz" word requirement.
  # Known small residual: 4/635 (0.6%) of these new candidates also trip the
  # is_resource_generated check below and land as quiz_content_generated instead of
  # quiz_interaction -- genuine quiz turns where the question text itself happens to
  # contain resource-sounding phrases ("what's a signal you can use..."). Comparable in
  # scale to the 0.5% toolkit_content_delivered leak already accepted elsewhere in this
  # project; not chased further.
  feedback_opener <- "^\\s*(correct|not quite|almost)!"

  data %>%
    filter(direction == "Outgoing", country == "nigeria") %>%
    filter(
      (
        (str_detect(message, regex("quiz", ignore_case = TRUE)) &
           str_detect(message, regex(inclusion, ignore_case = TRUE))) |
        str_detect(message, regex(feedback_opener, ignore_case = TRUE))
      ) &
        !str_detect(message, regex(description_exclusion, ignore_case = TRUE))
    ) %>%
    rowwise() %>%
    mutate(
      # Resolve course/module from the message itself where possible -- checking course
      # names alone only resolves 11% of candidates (2026-07-02), because most mid-quiz
      # messages say "Quiz Question 2", not the course name. Falling back to the
      # module/deep-dive title lookup (same one module_complete uses) catches messages
      # like "Module 3 Quiz Question 1", which name the module but not the course.
      # module_number is captured independently as a last-resort signal for the LLM
      # stage to resolve using the surrounding session when neither lookup matches.
      course_lineage = lookup_lineage_id(message),
      module_role = list(lookup_module_role(message)),
      module_lineage = module_role$lineage_id,
      module_title = str_extract(message, regex(module_pattern, ignore_case = TRUE)),
      module_number = str_extract(message, regex("(?<=Module )\\d", ignore_case = TRUE)),
      lineage_id = coalesce(course_lineage, module_lineage),
      is_resource_generated = str_detect(message, regex(resource_pattern, ignore_case = TRUE))
    ) %>%
    ungroup() %>%
    transmute(
      contact_id,
      event_type = if_else(is_resource_generated, "quiz_content_generated", "quiz_interaction"),
      event_date = date,
      value = coalesce(lineage_id, module_number),
      detection_method = "R_prefilter",
      confidence = NA_real_,
      source_version_id = if_else(is.na(lineage_id), NA_character_, paste0(lineage_id, "_v2_current")),
      source_message_id = message_id,
      session_id,
      # Exposed separately from value/source_version_id so consolidate_quiz_context()
      # can tell "resolved from this message" (non-NA here) apart from "resolved by
      # borrowing session context" (NA here, filled in later) -- see that function.
      # NA'd out for quiz_content_generated: course/module context from the user's OWN
      # progression shouldn't be attached to a resource generated for their students --
      # unrelated concepts that happen to share a detector.
      course_lineage_id = if_else(event_type == "quiz_interaction", lineage_id, NA_character_),
      module_number = if_else(event_type == "quiz_interaction", module_number, NA_character_)
    )
}

# Detect per-question quiz feedback (correct / almost / not_quite) -- a genuine pass/fail
# signal, but per QUESTION, not per quiz: there is no single-message final score anywhere
# in the data (checked 2026-07-02 against all quiz_interaction candidates -- messages that
# merely mention "score" turned out to be unrelated resource-generation content, not an
# actual result summary). A quiz attempt's overall result is a downstream count of these
# rows within a session, not something extractable from any one message.
# 20/20 precision spot-check (2026-07-02) -- not exhaustively reviewed like course_selected,
# hence detection_method stays "R_prefilter" rather than "R".
# CORRECTED 2026-07-09 (QF-1): the earlier note that the bot never phrases wrong answers as
# anything but "Almost!" was wrong. A recall scan found ~146+ genuine incorrect-answer turns
# opening "Good try!", "Nice try!", "Good effort!", "Close!", "Almost there!", "Not exactly!"
# -- roughly doubling the true incorrect count. Anchoring only on correct/almost/not-quite
# biased any pass/fail rate ~2x toward "correct". Widened the opener set; all wrong-answer
# variants map to `not_quite` (the generic incorrect bucket) so a downstream pass/fail count
# is unbiased. Precision re-checked on the newly-caught rows before trusting -- see
# event_schema_validation_results.md.
# Arguments:
#   data: clean_message_data, Nigeria, both directions
# Returns: one row per pre-filtered candidate message. A message can produce BOTH this event
#   AND a quiz_interaction event (eg "Correct! ... 🧪 Quiz Question 2: ...") -- two distinct
#   facts from one message, not a conflict.
detect_quiz_question_feedback <- function(data) {

  data %>%
    filter(direction == "Outgoing", country == "nigeria") %>%
    filter(str_detect(message, regex("^\\s*(correct|not quite|not exactly|almost|almost there|good try|good effort|nice try|close)!", ignore_case = TRUE))) %>%
    transmute(
      contact_id,
      event_type = "quiz_question_feedback",
      event_date = date,
      value = case_when(
        str_detect(message, regex("^\\s*correct!", ignore_case = TRUE)) ~ "correct",
        str_detect(message, regex("^\\s*almost!", ignore_case = TRUE)) ~ "almost",
        str_detect(message, regex("^\\s*(not quite|not exactly|good try|good effort|nice try|close|almost there)!?", ignore_case = TRUE)) ~ "not_quite",
        TRUE ~ NA_character_
      ),
      detection_method = "R_prefilter",
      confidence = NA_real_,
      source_version_id = NA_character_,
      source_message_id = message_id,
      session_id
    )
}


# Consolidate quiz_interaction course context using session position, not more regex
# A single quiz message often can't name its own course ("Quiz Question 2: How does
# reading support...") -- verified 2026-07-02 that this is safe to solve by carrying
# forward the last known course within a session, NOT by resolving each message in
# isolation: among the 243 sessions with a message naming an actual course (as opposed
# to a bare module number, which isn't course-specific), every single one names exactly
# one course. Nigeria users do not interleave courses within a session. So the last
# course_selected or module_complete event before a given quiz message, within the same
# contact_id + session_id, is a reliable source for that quiz's course -- no LLM needed
# for this part. (Cross-session interleaving is a non-issue by construction: session_id
# resets the timeline, so forward-fill never crosses a session boundary.)
# Arguments:
#   quiz_events: output of detect_quiz_candidates()
#   course_events: output of detect_course_selected()
#   module_events: output of detect_module_complete_candidates()
# Returns: quiz_events with value/source_version_id backfilled wherever course context
#   was recoverable from earlier in the same session; unchanged where it wasn't (still
#   left for the LLM stage, same as before -- eg the very first message in a session).
consolidate_quiz_context <- function(quiz_events, course_events, module_events) {

  context <- bind_rows(
    course_events %>%
      transmute(contact_id, session_id, event_date, course_lineage_id = value),
    module_events %>%
      filter(!is.na(course_lineage_id)) %>%
      transmute(contact_id, session_id, event_date, course_lineage_id)
  )

  quiz_events %>%
    mutate(quiz_row_id = row_number()) %>%
    bind_rows(context) %>%
    arrange(contact_id, session_id, event_date) %>%
    group_by(contact_id, session_id) %>%
    fill(course_lineage_id, .direction = "down") %>%
    ungroup() %>%
    filter(!is.na(quiz_row_id)) %>%
    arrange(quiz_row_id) %>%
    mutate(
      value = coalesce(value, course_lineage_id, module_number),
      source_version_id = if_else(
        is.na(source_version_id) & !is.na(course_lineage_id),
        paste0(course_lineage_id, "_v2_current"),
        source_version_id
      )
    ) %>%
    select(-quiz_row_id, -course_lineage_id, -module_number)
}


# Consolidate completion course context using the session's single course -- same validated
# safety property as consolidate_quiz_context() above, applied at session grain rather than
# by forward-fill. Many genuine completion messages name only a module number, or nothing at
# all ("Congratulations! You've completed Module 3 and unlocked Module 4"), so the title
# lookup in detect_module_complete_candidates() / detect_course_complete_candidates() leaves
# source_version_id NA on a large share of real completions -- 84% of module_complete and
# ~half of course_complete before this step (2026-07-09 check). Because Nigeria users do not
# interleave courses within a session (verified for the quiz backfill, 2026-07-02), any
# course-bearing event anywhere in the same contact+session identifies the course for every
# untagged completion in it -- position within the session doesn't matter, only that the
# session resolves to exactly ONE course. Sessions whose course-bearing events disagree (2+
# distinct courses -- ~13% of the untagged pool, real cross-course sessions that break the
# single-course assumption) are left NA rather than guessed, as are sessions with no course
# anchor at all (left for the LLM stage or a later cross-session pass).
# Arguments:
#   completion_events: bound course_complete + module_complete candidate rows (9-col shape;
#     module rows must already have had their internal course_lineage_id column dropped)
#   context_events: any course-bearing events to anchor on -- course_start, course_selected,
#     consolidated quiz_interaction rows -- each carrying source_version_id where known.
#     completion_events' own already-tagged rows are self-seeded in addition to these.
# Returns: completion_events with source_version_id backfilled wherever the session resolved
#   to exactly one course (and value backfilled for course_complete rows, which carry the
#   lineage in value); module_complete value is never touched (it holds the module
#   title/number, not a course).
consolidate_completion_context <- function(completion_events, context_events) {

  # Per contact+session, the single course if all course-bearing events agree, else NA.
  session_course <- bind_rows(
    context_events %>% select(contact_id, session_id, source_version_id),
    completion_events %>% select(contact_id, session_id, source_version_id)
  ) %>%
    filter(!is.na(source_version_id)) %>%
    distinct(contact_id, session_id, source_version_id) %>%
    group_by(contact_id, session_id) %>%
    summarise(
      session_version = if (n() == 1) source_version_id[1] else NA_character_,
      .groups = "drop"
    )

  completion_events %>%
    left_join(session_course, by = c("contact_id", "session_id")) %>%
    mutate(
      source_version_id = coalesce(source_version_id, session_version),
      # course_complete carries the lineage in value too -- keep it self-consistent
      value = if_else(
        event_type == "course_complete" & is.na(value) & !is.na(session_version),
        str_remove(session_version, "_v2_current$"),
        value
      )
    ) %>%
    select(-session_version)
}


# Module/deep-dive title -> (course, role) lookup, sourced from the product team's canonical module
# and deep-dive files (research/aprendia_knowledge_base_catalog.md). "role" distinguishes
# core modules (required, sequential) from deep dives (unlock together after the core is
# done, any order) -- v2 courses are semi-sequential: a small sequential core, then all
# deep dives unlock at once, except Teacher Wellbeing, which has no deep-dive tier at all
# and is fully sequential throughout (2026-07-02 design discussion).
# NB: "Math for Every Learner" appears twice in the source material -- once as the course
# name, once as the title of its own Module 2 (MATH_M2_MEL). A message saying "completed
# Math for Every Learner" is genuinely ambiguous between "finished the whole course" and
# "finished this specific module" -- left for the LLM stage to resolve from context, not
# something regex can safely disambiguate.
#
# CORRECTED 2026-07-02: "Shifting Math Mindsets," "Math Process Skills," and "Making Math
# Hands-On" were originally listed as deep_dive per the product team's course-instruction spec, which
# describes v2 courses as small sequential core + simultaneously-unlocking deep dives. Real
# data contradicts this for these three titles specifically: checked ALL 93
# collision-title deep_dive_complete rows in the live data (not a sample) -- every single
# one shows sequential single-module-unlock framing ("completed Module N and unlocked
# Module N+1," "Ready to start Module N+1 now?"), and ZERO show non-linear framing ("any
# order," "simultaneously," "explore any of these"). A 30-row LLM test batch independently
# corrected 15/15 sampled instances the same direction before this full-population check
# confirmed it wasn't sampling noise. Whatever the product team's spec intends, the deployed Math
# course delivers these three titles as sequential core modules 2-4, not free-order deep
# dives -- worth a bug report to the product team (design-vs-delivery mismatch), not treated as a
# taxonomy fact to build further detection logic around. Corrected to "core" here rather
# than routed through the module_role LLM job, since the evidence is unambiguous across the
# full population, not a per-message judgment call -- same discipline as every other
# regex-over-LLM decision made this session (module completion, quiz classroom-resource
# split). NOT yet resolved: whether this reflects a genuinely different (v1-style
# fully-sequential) Math generation, or a v2 Math course that's simply implemented
# sequentially despite the spec -- open question for research/course_taxonomy/, not needed
# to fix detection here.
module_title_lookup <- tibble::tribble(
  ~title,                                                          ~lineage_id,         ~role,
  "Exploring Math Domains",                                        "maths",             "core",
  "Math for Every Learner",                                        "maths",             "core",
  "Shifting Math Mindsets",                                        "maths",             "core",
  "Math Process Skills",                                           "maths",             "core",
  "Making Math Hands-On",                                          "maths",             "core",
  "Inclusive Math Instruction",                                    "maths",             "deep_dive",
  "Assessment for Math Learning",                                  "maths",             "deep_dive",
  "How We Learn to Read",                                          "reading",           "core",
  "Making Reading Engaging",                                       "reading",           "core",
  "The Building Blocks of Word Reading",                           "reading",           "deep_dive",
  "Making Meaning with Vocabulary",                                "reading",           "deep_dive",
  "Creating Joyful and Healing Reading Experiences",                "reading",           "deep_dive",
  "Supporting All Learners",                                       "reading",           "deep_dive",
  "Texts (&|and) Materials for Reading Instruction",                "reading",           "deep_dive",
  "Creating Safety and Predictability",                            "classroom_sel",     "core",
  "Building Belonging",                                            "classroom_sel",     "core",
  "Relationships (&|and) Peer Support",                            "classroom_sel",     "deep_dive",
  "Engagement, Inclusion",                                         "classroom_sel",     "deep_dive",
  # v1 Classroom-Management titles, added 2026-07-09 as course ANCHORS (BF-1 fix). These
  # were absent, so Classroom completions arrived with source_version_id = NA and were
  # invisible to consolidate_completion_context()'s single-course guard -- letting a
  # co-session Maths/Reading completion wrongly stamp its course onto them. Sourced by
  # extracting "Module N: Title" phrases from 60k messages of pure-Classroom contacts;
  # "Sense of Control" alone appears 1,541 times. Role = core (v1 courses were sequential);
  # role for these matters little since the DD-1 linear override now governs role anyway.
  "Sense of Control",                                              "classroom_sel",     "core",
  "Positive Social Relationships",                                 "classroom_sel",     "core",
  "Sense of Belonging",                                            "classroom_sel",     "core",
  "Engagement (&|and) Self-Worth",                                 "classroom_sel",     "core",
  "Creating a Healing Classroom",                                  "classroom_sel",     "core",
  "Co-Create Rules",                                               "classroom_sel",     "core",
  "Praise Progress (&|and) Effort",                                "classroom_sel",     "core",
  "Understanding Teacher Wellbeing",                               "wellbeing",         "core",
  "Building Resilience",                                           "wellbeing",         "core",
  "Building Positive Relationships",                               "wellbeing",         "core",
  "Creating a Wellbeing Plan",                                     "wellbeing",         "core",
  "The Three Elements of Active Learning",                         "active_inclusive",  "core",
  "Active Learning in Action",                                     "active_inclusive",  "core",
  "Active Learning for Every Child",                                "active_inclusive",  "core",
  "Hands-On Learning with Low-Cost Materials",                     "active_inclusive",  "deep_dive",
  "Drama, Role Play",                                              "active_inclusive",  "deep_dive",
  "Planning an Active Lesson",                                     "active_inclusive",  "deep_dive"
)

module_pattern <- paste(module_title_lookup$title, collapse = "|")

# Internal: look up (lineage_id, role) for a message's matched module/deep-dive title.
# Returns a length-2 list (lineage_id, role), both NA if no known title is present --
# left for the LLM stage to resolve from surrounding session context (many real
# completion messages just say "Module 3" with no title at all).
lookup_module_role <- function(message_text) {
  hit <- module_title_lookup %>%
    filter(str_detect(message_text, regex(title, ignore_case = TRUE)))
  if (nrow(hit) == 0) return(list(lineage_id = NA_character_, role = NA_character_))
  list(lineage_id = hit$lineage_id[1], role = hit$role[1])
}


# Detect module_complete / deep_dive_complete CANDIDATES (pre-filter, not a final detector)
# Sourced from the same "completed all strategies/quizzes in Module N" phrasing found
# and deliberately excluded from course_complete_candidates() (2026-07-02) -- these ARE
# genuine completion events, just at module/deep-dive grain rather than course grain.
# Role (core vs deep dive) is resolved by title lookup, not message phrasing -- a real-data
# check found the bot almost never says "deep dive" during actual content delivery (75
# messages total contain the phrase, nearly all of them the bot explaining the course
# structure in the abstract, not completing one) -- so genuine deep-dive completions are
# phrased identically to core-module completions and can only be told apart by looking up
# which role the completed title has.
# Arguments:
#   data: clean_message_data, Nigeria, both directions
# Returns: one row per pre-filtered candidate message. event_type is "module_complete" or
#   "deep_dive_complete" when the title resolves a role; "module_or_deepdive_complete" when
#   the message names a module number but no title (eg "completed all strategies in Module
#   3!") -- left for the LLM stage to resolve using the surrounding session.
#
# CORRECTED 2026-07-02: the first draft of this regex only matched "completed all
# strategies/quizzes in Module N" -- the one phrasing already sitting in
# course_complete's excluded set. It missed a whole separate, very common phrasing,
# "Congratulations! You've completed Module N [: Title] and unlocked Module N+1" --
# a 42x undercount (22 candidates vs 932 once both phrasings are included). Caught
# because the candidate count looked implausibly low next to quiz_interaction's 3,032
# -- a reminder to do the same "read real examples first" pass for every detector,
# not just the ones that felt obviously hard.
#
# KNOWN LIMITATION, still applies: most raw candidates carry genuinely v1-only titles
# ("Sense of Control") that correctly fail to resolve against this v2-only lookup and
# land in module_or_deepdive_complete -- expected, not a bug. But Math's title collision
# (documented in course_taxonomy/) means a role of "deep_dive" for "Shifting Math
# Mindsets" / "Math Process Skills" / "Making Math Hands-On" is NOT reliable -- these
# exact titles are used by both v1 (as sequential modules 2-4) and v2 (as deep dives).
# A "deep_dive_complete" result for one of these three specific titles should be treated
# as unresolved, same as a bare module number, until the LLM stage checks the
# surrounding message for linear ("unlocked Module N+1") vs non-linear (deep-dive)
# framing -- do not trust this lookup's role for those three titles without that check.

# Second, title-independent role signal: a message completing Module N that also names
# Module N+1 anywhere else in the same message is linear/core by construction -- only
# core modules unlock one at a time; deep dives all unlock simultaneously, so a
# deep-dive completion has no single "next module" to reference. Checking numeric
# adjacency (not a fixed phrase list) resolves 94% of the previously-unresolved pool
# (2026-07-02 check against real data), not just the 82% caught by "unlocked Module N+1"
# alone -- real phrasing varies ("ready to start", "ready for", "move on to", "would you
# like to start ... now"), and it isn't worth enumerating every verb when the numbers
# already say the same thing. Excludes multi-module progress-summary messages (eg "You've
# completed Module 1, 2, 3, and 4") -- those list several modules retrospectively and
# don't map to a single completion event the way the others do. The remaining ~6% are
# mostly final-core-module completions with no next module to reference (nothing to be
# numerically adjacent to) -- genuinely harder, correctly left for the LLM stage.
has_linear_next_module_reference <- function(message) {
  completed_n <- str_match(message, regex(
    "completed (all .{0,20}(strategies|quizzes) (in|of) )?module (\\d+)",
    ignore_case = TRUE
  ))[, 5]
  is_summary <- str_detect(message, regex(
    "summary of your (course )?progress|completed Module \\d.{0,5},\\s*\\d",
    ignore_case = TRUE
  ))
  if_else(
    is.na(completed_n) | is_summary,
    FALSE,
    str_detect(message, regex(paste0("module\\s*", as.integer(completed_n) + 1, "\\b"), ignore_case = TRUE))
  )
}

detect_module_complete_candidates <- function(data) {

  data %>%
    filter(direction == "Outgoing", country == "nigeria") %>%
    filter(
      str_detect(message, regex("completed Module \\d|completed all.{0,20}(strategies|quizzes).{0,15}module", ignore_case = TRUE)) &
        !str_detect(message, regex("nearly completed", ignore_case = TRUE))
    ) %>%
    rowwise() %>%
    mutate(
      module_role = list(lookup_module_role(message)),
      lineage_id = module_role$lineage_id,
      role = module_role$role,
      module_number = str_extract(message, regex("(?<=Module )\\d", ignore_case = TRUE))
    ) %>%
    ungroup() %>%
    mutate(
      # Linear single-next-module framing means core BY CONSTRUCTION -- only core modules
      # unlock one at a time; deep dives unlock simultaneously, so a deep-dive completion has
      # no single "next module" to reference. This overrides a title-lookup `deep_dive` role,
      # not just fills a missing one (DD-1 fix, 2026-07-09): the Reading deep-dive titles
      # ("Supporting All Learners", "Creating Joyful and Healing Reading Experiences") are
      # delivered sequentially in the live product and were being mislabelled deep_dive on
      # 24/27 rows -- the same delivery-vs-spec mismatch already hard-corrected for the three
      # Maths collision titles, now handled generally by the linear signal.
      role = if_else(has_linear_next_module_reference(message), "core", role)
    ) %>%
    transmute(
      contact_id,
      event_type = case_when(
        role == "core" ~ "module_complete",
        role == "deep_dive" ~ "deep_dive_complete",
        TRUE ~ "module_or_deepdive_complete"
      ),
      event_date = date,
      value = coalesce(str_extract(message, regex(module_pattern, ignore_case = TRUE)), module_number),
      detection_method = "R_prefilter",
      confidence = NA_real_,
      source_version_id = if_else(is.na(lineage_id), NA_character_, paste0(lineage_id, "_v2_current")),
      source_message_id = message_id,
      session_id,
      # Exposed (not just baked into source_version_id) so consolidate_quiz_context()
      # can reuse it as session-timeline context -- see that function for why.
      course_lineage_id = lineage_id
    )
}


# Detect challenge_delivered CANDIDATES (pre-filter, not a final detector)
# Sourced from quick-help-agent.md's "Output Format (Use Exactly)" -- the first of four
# mandatory slot labels ("I hear you:" / "Do this now:" / "If that's hard:" / "Quick
# check:"). Requiring "I hear you:" alone, not all four together, because the reply is
# often split across multiple outgoing WhatsApp messages -- a naive all-four-in-one-
# message check found only 196 candidates against 226 messages containing at least
# "I hear you:" anywhere. Anchoring at the start of the message (as opposed to anywhere
# in it) undercounts further still (161 vs 226): real deliveries routinely open with a
# personalized acknowledgement sentence before the slot label ("Thank you for sharing
# that you want support for your pupils' wellbeing.\n\nI hear you: ..."), consistent
# with system_prompt.2.0.md's per-teacher personalization mandate. Spot-checked
# 30/30 genuine (2026-07-02) -- not exhaustively reviewed (226 candidates, evenly split
# between genuine action-plan deliveries and a smaller set of "please describe your
# challenge" gate prompts that also use the same opening slot label).
#
# RECALL-CHECKED AND WIDENED 2026-07-03, per the standing practice established building
# course_start (a precision-only check tells you nothing about what's missed). Two real
# gaps found in the original "I hear you:" (colon required) pattern:
#   - Punctuation variants: real deliveries also use "I hear you!" and "I hear you—" (no
#     colon). Checked messages combining these variants with "Do this now" as a structural
#     confirmation they're genuine action-plan deliveries, not just casual empathy phrases.
#   - A second slot label alone: 32 messages have "Do this now:" with real, structured,
#     numbered action-plan content (matching quick-help-agent.md's output format exactly)
#     but NO "I hear you" anywhere -- the opening slot was apparently sent in an earlier
#     message not caught by a single-message search, or personalized past recognition. All
#     32 spot-checked genuine.
# Net effect: 11 new contacts found (177 -> 188, a 6.2% increase) who had zero
# "I hear you:"-pattern match at all despite genuine challenge engagement. Widened to
# "I hear you" (any punctuation) OR "Do this now:" alone as a fallback trigger.
# Arguments:
#   data: clean_message_data, Nigeria, both directions
# Returns: one row per pre-filtered candidate message, detection_method = "R_prefilter".
#   No course/module dimension -- Solve a Challenge has no course-like sub-structure --
#   so value is always NA; this event only marks that a challenge interaction happened.
detect_challenge_delivered <- function(data) {

  data %>%
    filter(direction == "Outgoing", country == "nigeria") %>%
    filter(str_detect(message, regex("I hear you|Do this now:", ignore_case = TRUE))) %>%
    transmute(
      contact_id,
      event_type = "challenge_delivered",
      event_date = date,
      value = NA_character_,
      detection_method = "R_prefilter",
      confidence = NA_real_,
      source_version_id = NA_character_,
      source_message_id = message_id,
      session_id
    )
}


# Detect energizer_delivered / wellbeing_moment_delivered CANDIDATES (pre-filter, not a
# final detector)
# Sourced from classroom-toolkit.md's structural output shape: both content branches
# (Energizers and Wellbeing moments) are delivered as a Title: / Steps: / Notice: block,
# distinct from Solve a Challenge's four-slot format -- confirmed zero message overlap
# between the two detectors' inclusion filters (2026-07-02). Precision-checked 10/10
# genuine on a random sample, and confirmed clean of course/module content (0 messages
# in the combo also matching "Module N" or "quiz", 9/248 coincidentally matching a course
# or module title string, most plausibly just word overlap rather than real course
# content).
#
# Role (energizer vs. wellbeing) is resolved from the FRAMING SENTENCE only (the text
# before "Title:"), not the whole message -- checking the whole message for "reflect" /
# "energiz" etc. produced false dual-matches, because energizer deliveries often close
# with an unrelated "would you like to reflect on how that went?" question that
# coincidentally contains a wellbeing keyword. Restricting to the framing sentence fixed
# this (0 dual-matches after the fix) but leaves most candidates (193/248) unresolved,
# because many deliveries open directly with "Title: ..." and never state which branch
# they're from in the message itself.
#
# KNOWN LIMITATION, different in kind from module_title_lookup: course/module titles
# come from the product team's canonical course files, a genuinely closed set worth building a
# lookup table for. Energizer/wellbeing titles ("Shake It Out", "Feeling Check-in") are
# generated per-response, not drawn from a fixed spec -- some recur across messages but
# there's no canonical source list, so a title-based lookup isn't buildable the way it
# was for courses. Resolving the unresolved 78% is genuinely LLM-stage work (read the
# framing/menu-selection earlier in the session), not a regex gap to close later.
# Arguments:
#   data: clean_message_data, Nigeria, both directions
# Returns: one row per pre-filtered candidate message. event_type is "energizer_delivered"
#   or "wellbeing_moment_delivered" when the framing sentence names the branch;
#   "toolkit_content_delivered" otherwise. value is the extracted content title (eg
#   "Shake It Out"), present regardless of whether the branch resolved.
detect_toolkit_content_delivered <- function(data) {

  data %>%
    filter(direction == "Outgoing", country == "nigeria") %>%
    filter(
      str_detect(message, regex("title:", ignore_case = TRUE)) &
        str_detect(message, regex("steps?:", ignore_case = TRUE)) &
        str_detect(message, regex("notice:", ignore_case = TRUE))
    ) %>%
    mutate(
      framing = str_extract(message, regex("^.*?(?=title:)", ignore_case = TRUE, dotall = TRUE)),
      is_energizer = str_detect(framing, regex("energiz|energy shifter", ignore_case = TRUE)),
      is_wellbeing = str_detect(framing, regex("wellbeing moment", ignore_case = TRUE)),
      title = str_trim(str_extract(message, regex("(?<=title:)[^\\n]+", ignore_case = TRUE)))
    ) %>%
    transmute(
      contact_id,
      event_type = case_when(
        is_energizer & !is_wellbeing ~ "energizer_delivered",
        is_wellbeing & !is_energizer ~ "wellbeing_moment_delivered",
        TRUE ~ "toolkit_content_delivered"
      ),
      event_date = date,
      value = title,
      detection_method = "R_prefilter",
      confidence = NA_real_,
      source_version_id = NA_character_,
      source_message_id = message_id,
      session_id
    )
}


# Onboarding question -> fixed-text trigger lookup. Sourced from a combination of the
# v1 onboarding-agent.md script (Q1/Q2/Q3/Q4/Q5/Q6: gender, ages, grade, main challenge,
# materials, priority outcome) and live message data showing a second, v2-era phrasing
# generation in use (materials_tier and learner_level as closed multiple-choice
# questions, class_size as a new free-text question) -- confirmed 2026-07-02 that BOTH
# generations of question text appear in real Nigeria data, not just one. The design
# doc (event_schema_design.md §3a) originally claimed student_ages/main_challenge/
# priority_outcome were "confirmed dropped, no trace in current onboarding flow" --
# that was wrong, or at best stale: all three are asked verbatim in messages dated as
# recently as 2026-04-30. Per 2026-07-02 decision, built against everything that's ever
# actually been asked rather than picking one generation -- v1/v2 status per field is a
# "nice to know if it comes up," not something worth gating detection on.
onboarding_question_lookup <- tibble::tribble(
  ~event_type,                 ~question_pattern,
  "gender_reported",           "what is your gender",
  "student_ages_reported",     "what ages are your students",
  "grade_level_reported",      "what grade (level )?are your students|what grade do you teach",
  "main_challenge_reported",   "what is the main challenge.{0,10}you face",
  "materials_reported",        "which learning materials are available",
  "materials_tier_reported",   "which best describes the instructional materials",
  "priority_outcome_reported", "which student outcome matters most",
  "class_size_reported",       "how many students are in your class",
  "learner_level_reported",    "which best describes the level of learners"
)


# Universal onboarding acknowledgment/button replies -- appear at the Step 1/2/3 gates
# ("Ready to begin?", "I understand", the "Let's get started!" intro) and never answer
# any onboarding question. Needed because some onboarding messages bundle a gate and the
# next question into one combined message (eg "Let's get started!... Q1: What is your
# gender?"), so the FIRST question occurrence for some contacts is that combined
# message, and the very next Incoming reply is really answering the gate ("Ready ✅"),
# not the question riding along in the same message.
onboarding_junk_reply_pattern <- "^(yes|no|ready|ok|okay|continue|i understand|got it)[\\s✅❌👍🙏]*$"

# The bot's own rejection signal, sourced from onboarding-agent.md's retry copy ("I
# didn't catch that...", "Please answer using a valid option...") plus each question's
# specific retry message ("Please give one grade...", "Please describe one main
# challenge...", "Please list the materials...", "Please name one priority outcome...").
# If the message immediately after a candidate reply matches this, the bot itself
# rejected that reply as invalid -- this is more reliable than trying to independently
# guess whether a piece of free text "looks like" a valid answer, since it uses the
# live system's own validation decision rather than approximating it.
onboarding_retry_message_pattern <- "i didn't catch that|please answer using a valid option|^please (give|describe|list|name|reply)"


# Detect onboarding profile-fact CANDIDATES (pre-filter, not a final detector)
# For each fixed onboarding question, finds the first time a contact was ever asked it,
# then walks forward through their replies to find the one that actually answers it --
# skipping junk acknowledgments and any reply the bot itself rejected via a retry
# message -- rather than naively pairing with "the next incoming message".
#
# CORRECTED 2026-07-02: an earlier version paired each question with the literal next
# Incoming message, which breaks whenever the first reply is invalid and the bot retries
# -- eg a real case found in the data: bot asks gender, user replies "Yes ✅" (an
# accidental button click), bot says "I didn't catch that. Could you tell me your
# gender?", user then replies "Female ♀️" -- the naive version recorded "Yes ✅" as the
# gender. A second attempt tried "take the last reply before the bot asks a DIFFERENT
# question" as the boundary, which also broke: when a question gets asked twice (the
# combined gate+question message, then the question again standalone), that boundary
# logic mistook the second occurrence of the SAME question for "the bot moved on",
# stranding the gate's own "Ready ✅" reply as the answer. The fix that held up: walk
# forward through candidate replies (skipping junk acknowledgments) and accept the first
# one that the bot did NOT respond to with a retry message -- using the bot's own
# validation decision instead of an R heuristic guessing at it.
#
# Restricted to the FIRST time a contact was ever asked each question, not every
# occurrence and not "session 1 only". Several onboarding question strings are reused
# verbatim outside onboarding -- eg Solve a Challenge's lesson-plan intake also asks
# "what grade level are your students" -- so taking every match pairs some answers with
# the wrong question entirely. Restricting to session_id == 1 was considered and
# rejected: onboarding sometimes spills into session 2 as a WhatsApp session-boundary
# artifact, so that would drop genuine cases, not just contamination.
# First-occurrence-per-contact is the safer proxy, since onboarding happens exactly once
# per contact ever, while the same question text being reused elsewhere always happens
# later, after that first exchange.
#
# KNOWN LIMITATION, not fixable with more R logic: a small number of genuinely off-topic
# replies ("What is dino" for a gender question) get accepted by the bot itself without
# triggering a retry -- the live bot doesn't always enforce its own validation rules.
# These correctly pass through to event_schema as the recorded "answer"; catching them
# is exactly what the LLM enum-resolution stage's `null` output is for (see
# the onboarding enum schema note), not something to solve here.
# Arguments:
#   data: clean_message_data, Nigeria, both directions
# Returns: one row per contact per onboarding field (at most one row per contact per
#   event_type). value is NA when the question was asked but every reply was rejected or
#   the contact never replied at all -- a real, distinct outcome from not being asked.
detect_onboarding_facts <- function(data) {

  nigeria_ordered <- data %>%
    filter(country == "nigeria") %>%
    arrange(contact_id, date) %>%
    mutate(row_id = row_number())

  by_contact <- split(nigeria_ordered, nigeria_ordered$contact_id)

  purrr::map_dfr(seq_len(nrow(onboarding_question_lookup)), function(i) {
    event_type_i <- onboarding_question_lookup$event_type[i]
    question_pattern_i <- onboarding_question_lookup$question_pattern[i]

    first_asks <- nigeria_ordered %>%
      filter(direction == "Outgoing", str_detect(message, regex(question_pattern_i, ignore_case = TRUE))) %>%
      group_by(contact_id) %>%
      slice_min(date, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      select(contact_id, ask_row_id = row_id)

    if (nrow(first_asks) == 0) return(tibble())

    purrr::pmap_dfr(first_asks, function(contact_id, ask_row_id) {
      convo <- by_contact[[as.character(contact_id)]] %>%
        filter(row_id > ask_row_id) %>%
        arrange(row_id)

      candidates <- convo %>%
        filter(direction == "Incoming") %>%
        filter(!str_detect(message, regex(onboarding_junk_reply_pattern, ignore_case = TRUE)))

      if (nrow(candidates) == 0) {
        return(tibble(contact_id = contact_id, value = NA_character_, answer_date = as.POSIXct(NA), answer_message_id = NA_character_, session_id = NA_integer_))
      }

      for (r in seq_len(nrow(candidates))) {
        reply <- candidates %>% slice(r)
        next_out <- convo %>%
          filter(row_id > reply$row_id, direction == "Outgoing") %>%
          slice_min(row_id, n = 1, with_ties = FALSE)
        rejected <- nrow(next_out) > 0 &&
          isTRUE(str_detect(next_out$message, regex(onboarding_retry_message_pattern, ignore_case = TRUE)))
        if (!rejected) {
          return(tibble(contact_id = contact_id, value = str_trim(reply$message), answer_date = reply$date, answer_message_id = reply$message_id, session_id = reply$session_id))
        }
      }
      # every candidate reply was rejected by the bot -- fall back to the last attempt
      # rather than NA, since the contact did try to answer; a genuine unresolved case,
      # left for the LLM stage same as an off-topic accepted reply would be.
      last_attempt <- candidates %>% slice_max(row_id, n = 1, with_ties = FALSE)
      tibble(contact_id = contact_id, value = str_trim(last_attempt$message), answer_date = last_attempt$date, answer_message_id = last_attempt$message_id, session_id = last_attempt$session_id)
    }) %>%
      transmute(
        contact_id,
        event_type = event_type_i,
        event_date = answer_date,
        value,
        detection_method = "R_prefilter",
        confidence = NA_real_,
        source_version_id = NA_character_,
        source_message_id = answer_message_id,
        session_id
      )
  })
}
