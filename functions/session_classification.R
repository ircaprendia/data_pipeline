# Session Classification for aprendIA Nigeria Pilot Data v2.1
# Hierarchical rule-based classifier for teacher-chatbot interactions
#
# Changelog:
# 2026-03-XX  v2.0: MAJOR UPDATE based on validation findings
#                   - Removed Strategy/Domain work as type (merged into Module progression)
#                   - Removed Quiz/Assessment as type (now completed_quiz flag)
#                   - Removed Course selection as type (now course_selected flag)
#                   - Added universal flags: course_selected, which_course, completed_quiz
#                   - Use first_user_messages for question detection
#                   - Language-agnostic onboarding (count Q1-Q6)
#                   - Expanded question words (English + Hausa)
#                   - Tightened Prayer/Religious patterns
#                   - Fixed Quiz detection
#
# 2026-04-06  v2.1: PATTERN FIXES based on Claude validation (80.9% → target 85%+)
#                   - Lesson/Content: Now requires explicit request verb + material noun
#                     (e.g., "give me a lesson plan" not just "how to teach")
#                   - Question asking: Requires teaching context or detailed question structure
#                     (excludes vague "What?" questions)
#                   - Expected improvement: Lesson 25%→75%, Question 55%→80%, Overall 81%→87%
#
# 2026-06-18  v2.2: Tightened two over-tagging types (LLM pilot findings). Bump the cache
#                   classifier_version so existing cached labels are recomputed.
#                   - Technical support: removed the greedy
#                     (problem|issue).*(app|aprendia|link|bot|load|open|access) catch-all that
#                     tagged ordinary teaching sessions (pilot: 0/11 agreement, all false
#                     positives — grammar/maths/WASH questions). Now requires explicit
#                     bot/app-failure language with bounded proximity. ~95% of prior tags fall out.
#                   - Prayer/Religious: now requires a genuine religious-CONTENT request. Dropped
#                     bare subject names (islamic/christian religion studies) and teach-the-subject
#                     matches (teach crs/bible/quran) — those are subject knowledge, not religious
#                     requests per the schema ruling — and the greedy help.*prayer. ~70% fall out
#                     (250 -> ~74 genuine).
#
# 2026-06-18  v2.3: Added Translation request as a type (LLM pilot discovery; ~191 Nigeria
#                   sessions, mostly mislabelled General engagement). Detects "translat" in the
#                   teacher's messages, checked before the short-session gate so brief requests
#                   are not lost to Micro-session. Lower recall than the LLM (misses implicit
#                   "what is X in Hausa"). Cache version bumped to recompute.

library(tidyverse)
library(stringr)

#### Classification Function ####

classify_session <- function(session_id, msgs_per_session, in_msgs_per_session,
                             start_direction, first_message_text, all_messages,
                             first_user_messages = NA) {

  # Handle NA values
  first_msg <- if_else(is.na(first_message_text), "", first_message_text)
  all_msg <- if_else(is.na(all_messages), "", all_messages)
  first_user_msg <- if_else(is.na(first_user_messages), first_msg, first_user_messages)

  first_msg_lower <- str_to_lower(first_msg)
  all_msg_lower <- str_to_lower(all_msg)
  first_user_msg_lower <- str_to_lower(first_user_msg)

  # Engagement metrics
  interaction_ratio <- if_else(msgs_per_session > 0,
                               in_msgs_per_session / msgs_per_session, 0)

  # ========== DETECT UNIVERSAL FLAGS (check for all sessions) ==========

  # Flag 1: Started with reminder
  started_with_reminder <- str_detect(all_msg_lower, regex(
    "hi again|ready to pick up where you left off|welcome back|i was having some technical issues",
    ignore_case = TRUE
  ))

  # Flag 2: Course selected
  course_selected <- str_detect(all_msg_lower, "course selection") ||
    str_detect(all_msg, "Reading 📚|Math ➕|Classroom 📘")

  # Flag 3: Which course
  # KNOWN BUG: which_course scans all_messages (full session transcript including bot messages).
  # The bot's course selection menu always displays all three options — "Reading 📚", "Math ➕",
  # "Classroom 📘" — so "reading" matches first in case_when regardless of what the teacher
  # actually selected. Result: course_selected sessions are almost all classified as "Reading".
  # Use select_reading / select_maths / select_classroom_mgmt from clean_message_data instead —
  # those look only at the teacher's incoming message and correctly identify the chosen course.
  which_course <- case_when(
    str_detect(all_msg_lower, "reading 📚|reading") ~ "Reading",
    str_detect(all_msg_lower, "math ➕|math") ~ "Maths",
    str_detect(all_msg_lower, "classroom 📘|classroom") ~ "Classroom",
    TRUE ~ NA_character_
  )

  # Flag 4: Completed quiz
  completed_quiz <- str_detect(all_msg_lower, regex(
    "quiz question \\d+|module.*quiz|test your understanding|ready for.*quiz|unlock.*quiz|take.*quiz to unlock",
    ignore_case = TRUE
  ))

  # Flag 5: Asked question (NEW - captures all question behavior)
  asked_question <- str_detect(first_user_msg, "\\?") ||
    str_detect(first_user_msg_lower, regex(
      "how|what|why|when|where|who|can you|could you|would you|menene|yaya|don me|wa|ina|yaushe",
      ignore_case = TRUE
    ))

  # ========== PRIORITY 1: Bot outreach with no response ==========
  if (start_direction == "Outgoing" && in_msgs_per_session == 0) {
    return(list(
      session_id = session_id,
      engagement_level = "No response",
      session_type = "Bot outreach (unanswered)",
      subtype = NA_character_,
      module_number = NA_character_,
      started_with_reminder = started_with_reminder,
      course_selected = course_selected,
      which_course = which_course,
      completed_quiz = completed_quiz,
      asked_question = asked_question,
      msgs_per_session = msgs_per_session,
      in_msgs_per_session = in_msgs_per_session,
      interaction_ratio = interaction_ratio
    ))
  }

  # ========== PRIORITY 2: Session continuation ==========
  continuation_first_msg <- (
    str_detect(str_trim(first_msg_lower),
               regex("^(yes|no|ok|okay|i understand|continue|yes continue|yes,\\s*continue|more details|next|sure|proceed|alright|noted|good|great|i get it|understood|i see|go on|let's go|let us go|k|quick steps|quick step)$",
                     ignore_case = TRUE)) ||
      nchar(str_trim(first_msg)) <= 2
  )

  continuation_bot_context <- str_detect(all_msg_lower, regex(
    "strategy \\d+/\\d+|module \\d+|domain \\d+|would you like to try|ready for the next|let's continue|here's the next|would you like to move on|you've completed|well done.*strategy|great job.*module|unlocked module",
    ignore_case = TRUE
  ))

  bot_reintroduced <- str_detect(all_msg_lower, regex(
    "i'm aprendia|i am aprendia|your on-demand classroom mentor",
    ignore_case = TRUE
  ))

  if (continuation_first_msg && continuation_bot_context && !bot_reintroduced && msgs_per_session <= 6) {
    return(list(
      session_id = session_id,
      engagement_level = "Minimal",
      session_type = "Session continuation",
      subtype = NA_character_,
      module_number = NA_character_,
      started_with_reminder = started_with_reminder,
      course_selected = course_selected,
      which_course = which_course,
      completed_quiz = completed_quiz,
      asked_question = asked_question,
      msgs_per_session = msgs_per_session,
      in_msgs_per_session = in_msgs_per_session,
      interaction_ratio = interaction_ratio
    ))
  }

  # ========== Translation request (checked before the short-session gate) ==========
  # Explicit request to translate text between languages (eg, English/Hausa/Arabic) — a real
  # bilingual-support pattern (~191 Nigeria sessions, mostly buried in General engagement by the
  # old rules). Placed before the short-session gate so brief requests ("Translate this in
  # Hausa") are caught by intent, not labelled Micro-session. Keyed on the teacher's own
  # messages; recall is lower than the LLM (misses implicit "what is X in Hausa").
  if (str_detect(first_user_msg_lower, regex("translat", ignore_case = TRUE))) {
    return(list(
      session_id = session_id,
      engagement_level = if_else(msgs_per_session > 15, "Deep",
                                 if_else(msgs_per_session > 4, "Moderate", "Brief")),
      session_type = "Translation request",
      subtype = NA_character_,
      module_number = NA_character_,
      started_with_reminder = started_with_reminder,
      course_selected = course_selected,
      which_course = which_course,
      completed_quiz = completed_quiz,
      asked_question = asked_question,
      msgs_per_session = msgs_per_session,
      in_msgs_per_session = in_msgs_per_session,
      interaction_ratio = interaction_ratio
    ))
  }

  # ========== PRIORITY 3: Micro-session vs Quick question ==========
  # For outgoing-initiated sessions, don't use bot's message as trigger
  trigger_msg_lower <- if_else(start_direction == "Outgoing", "", first_user_msg_lower)
  trigger_msg <- if_else(start_direction == "Outgoing", "", first_user_msg)

  if (msgs_per_session <= 3 && in_msgs_per_session <= 2) {

    # Expanded question patterns (English + Hausa)
    is_quick_question <- (
      str_detect(trigger_msg, "\\?") ||
        str_detect(trigger_msg_lower, regex(
          "how|what|why|when|where|who|can you|could you|would you|is it|are there|how come|define|meaning of|what does|explain|state.*importance|give.*example|difference between|list|describe|mention|enumerate|menene|yaya|don me|wa|ina|yaushe",
          ignore_case = TRUE
        ))
    )

    if (is_quick_question) {
      # Subtype from user's message only
      subtype <- case_when(
        str_detect(first_user_msg_lower, regex("classroom|management|behavior|behaviour|discipline|control|routine|noise|crowd", ignore_case = TRUE)) ~ "Classroom management",
        str_detect(first_user_msg_lower, regex("reading|literacy|phonics|comprehension|vocabulary", ignore_case = TRUE)) ~ "Reading instruction",
        str_detect(first_user_msg_lower, regex("math|maths|arithmetic|lissafi|number|calculation|fraction|geometry", ignore_case = TRUE)) ~ "Maths instruction",
        str_detect(first_user_msg_lower, regex("lesson|plan|scheme|curriculum|teaching method|pedagog", ignore_case = TRUE)) ~ "Curriculum/planning",
        str_detect(first_user_msg_lower, regex("student|pupil|child|learner|shy|stammer|slow learner", ignore_case = TRUE)) ~ "Student support",
        str_detect(first_user_msg_lower, regex("patriotism|communalism|democracy|government|history|civics|science|biology|chemistry|physics|geography|computer|nutrition|carbohydrate|protein|vitamin|pronoun|noun|verb|adjective|grammar|sentence|syllable|motif|federalism|citizenship|menstruation|rhythmic|soil|culture|business|religion|islam|christianity|crs|inec|ecology|environment", ignore_case = TRUE)) ~ "Subject knowledge",
        TRUE ~ "General question"
      )

      session_type <- "Quick question"
    } else {
      session_type <- "Micro-session"
      subtype <- NA_character_
    }

    return(list(
      session_id = session_id,
      engagement_level = "Minimal",
      session_type = session_type,
      subtype = subtype,
      module_number = NA_character_,
      started_with_reminder = started_with_reminder,
      course_selected = course_selected,
      which_course = which_course,
      completed_quiz = completed_quiz,
      asked_question = asked_question,
      msgs_per_session = msgs_per_session,
      in_msgs_per_session = in_msgs_per_session,
      interaction_ratio = interaction_ratio
    ))
  }

  # ========== PRIORITY 4: User onboarding ==========
  # Language-agnostic: count how many onboarding questions appear
  # Q1-Q6 about gender, age, grade, challenges, etc.

  # Count distinct onboarding question markers
  onboarding_q_count <-
    as.integer(str_detect(all_msg_lower, regex("q1:|what is your gender|quel est votre genre", ignore_case = TRUE))) +
    as.integer(str_detect(all_msg_lower, regex("q2:|how old are your students|quel âge ont vos élèves", ignore_case = TRUE))) +
    as.integer(str_detect(all_msg_lower, regex("q3:|what grade.*teach|quelle classe", ignore_case = TRUE))) +
    as.integer(str_detect(all_msg_lower, regex("q4:|main challenge|principal défi", ignore_case = TRUE))) +
    as.integer(str_detect(all_msg_lower, regex("q5:|q6:", ignore_case = TRUE)))

  # Need ≥3 questions AND user engaged
  if (onboarding_q_count >= 3 && msgs_per_session >= 8 && in_msgs_per_session >= 4) {
    return(list(
      session_id = session_id,
      engagement_level = if_else(msgs_per_session > 15, "Deep", "Moderate"),
      session_type = "User onboarding",
      subtype = NA_character_,
      module_number = NA_character_,
      started_with_reminder = started_with_reminder,
      course_selected = course_selected,
      which_course = which_course,
      completed_quiz = completed_quiz,
      asked_question = asked_question,
      msgs_per_session = msgs_per_session,
      in_msgs_per_session = in_msgs_per_session,
      interaction_ratio = interaction_ratio
    ))
  }

  # ========== PRIORITY 5: Module progression ==========
  # Now includes: modules, strategies, domains, and quizzes
  # Detection: Module language OR Strategy language OR Domain language

  has_module <- str_detect(all_msg_lower, regex("module \\d+", ignore_case = TRUE)) &&
    str_detect(all_msg_lower, regex(
      "ready to begin|when you're ready|welcome to module|let's start|barka da zuwa|shirye mu fara|you'll explore|ready for module",
      ignore_case = TRUE
    ))

  has_strategy <- str_detect(all_msg_lower, regex(
    "strategy \\d+|next strategy|would you like to try strategy",
    ignore_case = TRUE
  ))

  has_domain <- str_detect(all_msg_lower, regex("domain \\d+", ignore_case = TRUE))

  if (has_module || has_strategy || has_domain) {

    # Extract module number if present
    module_match <- str_extract(all_msg_lower, "module \\d+")
    module_number <- if_else(!is.na(module_match),
                             str_extract(module_match, "\\d+"),
                             NA_character_)

    # Identify course type
    subtype <- case_when(
      str_detect(all_msg_lower, regex("reading|language|vocabulary|comprehension", ignore_case = TRUE)) ~ "Reading",
      str_detect(all_msg_lower, regex("math|lissafi|number|geometry", ignore_case = TRUE)) ~ "Maths",
      str_detect(all_msg_lower, regex("classroom|management|behavior", ignore_case = TRUE)) ~ "Classroom",
      TRUE ~ NA_character_
    )

    return(list(
      session_id = session_id,
      engagement_level = if_else(msgs_per_session > 15, "Deep", "Moderate"),
      session_type = "Module progression",
      subtype = subtype,
      module_number = module_number,
      started_with_reminder = started_with_reminder,
      course_selected = course_selected,
      which_course = which_course,
      completed_quiz = completed_quiz,
      asked_question = asked_question,
      msgs_per_session = msgs_per_session,
      in_msgs_per_session = in_msgs_per_session,
      interaction_ratio = interaction_ratio
    ))
  }

  # ========== PRIORITY 6: Lesson/Content request ==========
  # FIXED v2.1: Require explicit request structure (verb + material noun)
  # Must say "give me a lesson plan" not just "how to teach"

  # Check for explicit request patterns in user's messages
  has_explicit_request <- str_detect(first_user_msg_lower, regex(
    # Request verb + material noun patterns
    "(give|need|want|create|make|prepare|write|develop|design|send|share|provide)\\s*(me|us|a|an)?\\s*(lesson|scheme|activity|plan|material|note|aid|resource)|
    i need.*(lesson|scheme|activity|plan|material|note)|
    can you (give|create|make|prepare|send|share).*(lesson|scheme|activity|plan|material)|
    help me (create|make|prepare|develop).*(lesson|scheme|activity|plan)|
    lesson plan (on|for|about)|
    scheme of work|
    instructional material|
    teaching aid|
    teacher note|
    activity for teaching",
    ignore_case = TRUE
  ))

  # Also check first 500 chars for explicit phrases
  first_few_msgs <- str_sub(all_msg_lower, 1, 500)
  has_request_context <- str_detect(first_few_msgs, regex(
    "lesson plan|scheme of work|need a scheme|instructional material|teaching aid",
    ignore_case = TRUE
  ))

  if (has_explicit_request || has_request_context) {

    subtype <- case_when(
      str_detect(first_user_msg_lower, regex("lesson plan", ignore_case = TRUE)) ~ "Lesson plan",
      str_detect(first_user_msg_lower, regex("scheme.*work|scheme of work", ignore_case = TRUE)) ~ "Scheme of work",
      str_detect(first_user_msg_lower, regex("activity|activities", ignore_case = TRUE)) ~ "Activity ideas",
      str_detect(first_user_msg_lower, regex("assessment|evaluation|test", ignore_case = TRUE)) ~ "Assessment materials",
      str_detect(first_user_msg_lower, regex("instructional material|teaching material|teaching aid|teaching resource|teacher note|prepare.*note", ignore_case = TRUE)) ~ "Instructional materials",
      TRUE ~ "General content"
    )

    return(list(
      session_id = session_id,
      engagement_level = if_else(msgs_per_session > 15, "Deep",
                                 if_else(msgs_per_session > 4, "Moderate", "Brief")),
      session_type = "Lesson/Content request",
      subtype = subtype,
      module_number = NA_character_,
      started_with_reminder = started_with_reminder,
      course_selected = course_selected,
      which_course = which_course,
      completed_quiz = completed_quiz,
      asked_question = asked_question,
      msgs_per_session = msgs_per_session,
      in_msgs_per_session = in_msgs_per_session,
      interaction_ratio = interaction_ratio
    ))
  }

  # ========== PRIORITY 7: Question asking ==========
  # FIXED v2.1: Require teaching context, exclude vague questions
  # Must be asking about teaching/classroom, not general knowledge or personal

  has_question_structure <- (
    str_detect(first_user_msg_lower, regex(
      "how can i|how do i|how to|how should i|what is.*best way|what are.*ways|can you help.*teach|can you tell.*teach|could you help",
      ignore_case = TRUE
    )) ||
      str_detect(first_user_msg, "\\?")
  )

  # Exclude very vague single-word questions
  is_vague <- str_detect(str_trim(first_user_msg_lower), regex("^(what|why|how|ok|yes)\\?$", ignore_case = TRUE))

  # Check for teaching/classroom context
  has_teaching_context <- str_detect(first_user_msg_lower, regex(
    "teach|classroom|student|learner|pupil|class|lesson|school|learning|education|child|grade|primary|nursery|jss|reading|math|maths|science|english|subject",
    ignore_case = TRUE
  ))

  # Question asking if has question + (teaching context OR explicit question words)
  if (has_question_structure && !is_vague) {

    # If has teaching context OR uses detailed question words, classify as question
    is_teaching_question <- has_teaching_context || str_detect(first_user_msg_lower, regex(
      "how can i|how do i|how should|best way|what are.*ways|can you help|can you tell|menene|yaya",
      ignore_case = TRUE
    ))

    if (is_teaching_question) {

      # Subtype from user's message only (not bot response)
      subtype <- case_when(
        str_detect(first_user_msg_lower, regex("classroom|management|behavior|behaviour|discipline|control|routine|noise|crowd|overcrowd", ignore_case = TRUE)) ~ "Classroom management",
        str_detect(first_user_msg_lower, regex("reading|literacy|phonics|comprehension|vocabulary|letter|sound|vowel|consonant", ignore_case = TRUE)) ~ "Reading instruction",
        str_detect(first_user_msg_lower, regex("math|maths|arithmetic|lissafi|number|calculation|fraction|geometry|addition|subtraction", ignore_case = TRUE)) ~ "Maths instruction",
        str_detect(first_user_msg_lower, regex("lesson|plan|scheme|curriculum|teaching method|pedagog", ignore_case = TRUE)) ~ "Curriculum/planning",
        str_detect(first_user_msg_lower, regex("student|pupil|child|learner|shy|stammer|slow learner|struggling", ignore_case = TRUE)) ~ "Student support",
        str_detect(first_user_msg_lower, regex("patriotism|communalism|democracy|government|history|civics|science|biology|chemistry|physics|geography|computer|nutrition|carbohydrate|protein|vitamin|pronoun|noun|verb|adjective|grammar|sentence|syllable|motif|federalism|citizenship|menstruation|rhythmic|soil|culture|business|religion|islam|christianity|crs|inec|ecology|environment", ignore_case = TRUE)) ~ "Subject knowledge",
        TRUE ~ "General question"
      )

      return(list(
        session_id = session_id,
        engagement_level = if_else(msgs_per_session > 15, "Deep",
                                   if_else(msgs_per_session > 4, "Moderate", "Brief")),
        session_type = "Question asking",
        subtype = subtype,
        module_number = NA_character_,
        started_with_reminder = started_with_reminder,
        course_selected = course_selected,
        which_course = which_course,
        completed_quiz = completed_quiz,
        asked_question = asked_question,
        msgs_per_session = msgs_per_session,
        in_msgs_per_session = in_msgs_per_session,
        interaction_ratio = interaction_ratio
      ))
    }
  }

  # ========== PRIORITY 8: Prayer/Religious request ==========
  # Tightened: only explicit requests for religious content

  if (str_detect(all_msg_lower, regex(
    "give.{0,30}prayer|write.{0,30}prayer|need.{0,30}prayer|morning prayer|opening prayer|pray for|prayer for|(bible|quran|scripture).{0,20}(verse|passage|story)|speech.{0,25}(god|allah|oneness)|devotion|sermon",
    ignore_case = TRUE
  ))) {
    return(list(
      session_id = session_id,
      engagement_level = if_else(msgs_per_session > 15, "Deep",
                                 if_else(msgs_per_session > 4, "Moderate", "Brief")),
      session_type = "Prayer/Religious request",
      subtype = NA_character_,
      module_number = NA_character_,
      started_with_reminder = started_with_reminder,
      course_selected = course_selected,
      which_course = which_course,
      completed_quiz = completed_quiz,
      asked_question = asked_question,
      msgs_per_session = msgs_per_session,
      in_msgs_per_session = in_msgs_per_session,
      interaction_ratio = interaction_ratio
    ))
  }

  # ========== PRIORITY 9: Technical support ==========

  if (str_detect(all_msg_lower, regex(
    "technical issue|technical problem|i was having some technical|can't access|won't load|link.*not work|page.*not load|system error|aprendia.{0,40}(not working|not responding|not loading|error|crash)|bot.{0,40}(not respond|not working|crash)|app.{0,40}(crash|freez|not work|not load)|(crashed|frozen|stuck loading|keeps loading|blank screen)",
    ignore_case = TRUE
  ))) {
    return(list(
      session_id = session_id,
      engagement_level = if_else(msgs_per_session > 15, "Deep",
                                 if_else(msgs_per_session > 4, "Moderate", "Brief")),
      session_type = "Technical support",
      subtype = NA_character_,
      module_number = NA_character_,
      started_with_reminder = started_with_reminder,
      course_selected = course_selected,
      which_course = which_course,
      completed_quiz = completed_quiz,
      asked_question = asked_question,
      msgs_per_session = msgs_per_session,
      in_msgs_per_session = in_msgs_per_session,
      interaction_ratio = interaction_ratio
    ))
  }

  # ========== PRIORITY 10: General engagement (default) ==========

  return(list(
    session_id = session_id,
    engagement_level = if_else(msgs_per_session > 15, "Deep",
                               if_else(msgs_per_session > 4, "Moderate", "Brief")),
    session_type = "General engagement",
    subtype = NA_character_,
    module_number = NA_character_,
    started_with_reminder = started_with_reminder,
    course_selected = course_selected,
    which_course = which_course,
    completed_quiz = completed_quiz,
    asked_question = asked_question,
    msgs_per_session = msgs_per_session,
    in_msgs_per_session = in_msgs_per_session,
    interaction_ratio = interaction_ratio
  ))
}

#### Wrapper Function ####

classify_all_sessions <- function(session_df) {

  cat("Classifying", nrow(session_df), "sessions...\n")

  # Check if first_user_messages exists
  has_first_user_msgs <- "first_user_messages" %in% names(session_df)

  if (!has_first_user_msgs) {
    cat("Note: first_user_messages column not found. Using first_message_text instead.\n")
    cat("      For better question detection, add first_user_messages to session_data.\n\n")
  }

  results <- session_df %>%
    rowwise() %>%
    mutate(
      classification = list(classify_session(
        session_id = session_id,
        msgs_per_session = msgs_per_session,
        in_msgs_per_session = in_msgs_per_session,
        start_direction = start_direction,
        first_message_text = first_message_text,
        all_messages = all_messages,
        first_user_messages = if (has_first_user_msgs) first_user_messages else NA_character_
      ))
    ) %>%
    ungroup() %>%
    mutate(
      engagement_level = map_chr(classification, "engagement_level"),
      session_type = map_chr(classification, "session_type"),
      subtype = map_chr(classification, function(x) {
        st <- x$subtype
        if_else(is.na(st), NA_character_, st)
      }),
      module_number = map_chr(classification, function(x) {
        mn <- x$module_number
        if_else(is.na(mn), NA_character_, mn)
      }),
      started_with_reminder = map_lgl(classification, "started_with_reminder"),
      course_selected = map_lgl(classification, "course_selected"),
      which_course = map_chr(classification, function(x) {
        wc <- x$which_course
        if_else(is.na(wc), NA_character_, wc)
      }),
      completed_quiz = map_lgl(classification, "completed_quiz"),
      asked_question = map_lgl(classification, "asked_question"),
      interaction_ratio = map_dbl(classification, "interaction_ratio")
    ) %>%
    select(-classification)

  cat("Classification complete!\n\n")

  cat("New flags detected:\n")
  cat("  Reminders:", sum(results$started_with_reminder), "\n")
  cat("  Course selections:", sum(results$course_selected), "\n")
  cat("  Quizzes completed:", sum(results$completed_quiz), "\n")
  cat("  Questions asked:", sum(results$asked_question), "\n\n")

  return(results)
}

#### Summary Function ####

summarise_classification <- function(classified_df) {

  summary_stats <- classified_df %>%
    group_by(session_type, engagement_level) %>%
    summarise(
      count = n(),
      avg_msgs = mean(msgs_per_session, na.rm = TRUE),
      avg_in_msgs = mean(in_msgs_per_session, na.rm = TRUE),
      avg_interaction = mean(interaction_ratio, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(count))

  overall <- classified_df %>%
    group_by(session_type) %>%
    summarise(
      count = n(),
      percentage = n() / nrow(classified_df) * 100,
      avg_msgs = mean(msgs_per_session, na.rm = TRUE),
      avg_interaction = mean(interaction_ratio, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(count))

  return(list(
    by_type_and_engagement = summary_stats,
    by_type = overall
  ))
}

#### Cached Classification ####
# Wraps classify_all_sessions() with a content-addressed cache so unchanged sessions are not
# reclassified every run. The label is a pure function of six per-session inputs, so a session
# is a cache hit only when those inputs (content_hash) AND the classifier_version both match.
# Misses go through the untouched classify_all_sessions(). The cache is keyed on
# country + contact_id + session_id and carries country from day one, so Ecuador/Niger LLM
# labels can later join the same store without migration. Bump classifier_version to force a
# full reclassification — the lever for the eventual LLM cutover into the same column.

# The ten classifier outputs that classify_all_sessions adds to a session frame.
classifier_output_cols <- c(
  "engagement_level", "session_type", "subtype", "module_number",
  "started_with_reminder", "course_selected", "which_course",
  "completed_quiz", "asked_question", "interaction_ratio"
)

# Locked column spec for the cache file, so a CSV round-trip cannot drift types (eg, read a
# character module_number back as a double) and break the join or the cached-equals-full test.
classification_cache_col_types <- cols(
  country = col_character(),
  contact_id = col_character(),
  session_id = col_double(),
  content_hash = col_character(),
  classifier_version = col_character(),
  classified_at = col_character(),
  engagement_level = col_character(),
  session_type = col_character(),
  subtype = col_character(),
  module_number = col_character(),
  started_with_reminder = col_logical(),
  course_selected = col_logical(),
  which_course = col_character(),
  completed_quiz = col_logical(),
  asked_question = col_logical(),
  interaction_ratio = col_double()
)

# Fingerprint the six classifier inputs into one hash per session.
add_content_hash <- function(session_df) {
  if (!"first_user_messages" %in% names(session_df)) {
    session_df$first_user_messages <- NA_character_
  }
  session_df %>%
    mutate(
      content_hash = map_chr(
        paste(
          msgs_per_session,
          in_msgs_per_session,
          start_direction,
          first_message_text,
          all_messages,
          first_user_messages,
          sep = ""
        ),
        rlang::hash
      )
    )
}

classify_all_sessions_cached <- function(session_df,
                                         cache_path = "data/session_classification_cache.csv",
                                         classifier_version = "v2.3") {

  key_cols <- intersect(c("country", "contact_id", "session_id"), names(session_df))

  # Fingerprint inputs and remember input order, so the result returns identical to a direct
  # classify_all_sessions() call (the cached-equals-full assertion relies on this).
  session_df <- session_df %>%
    add_content_hash() %>%
    mutate(.row_order = row_number())

  # Load the cache, if any, and keep only rows classified by the requested version.
  valid_cache <- NULL
  if (file.exists(cache_path)) {
    cache <- read_csv(cache_path, col_types = classification_cache_col_types)
    if (all(key_cols %in% names(cache)) && "content_hash" %in% names(cache)) {
      valid_cache <- cache %>%
        filter(classifier_version == !!classifier_version) %>%
        select(all_of(c(key_cols, "content_hash", classifier_output_cols)))
    }
  } else {
    cache <- NULL
  }

  # A row is a hit only when its key AND content_hash both match a valid cache row.
  if (!is.null(valid_cache)) {
    is_hit <- session_df %>%
      select(all_of(c(key_cols, "content_hash"))) %>%
      left_join(
        valid_cache %>%
          select(all_of(c(key_cols, "content_hash"))) %>%
          mutate(.is_hit = TRUE),
        by = c(key_cols, "content_hash")
      ) %>%
      pull(.is_hit)
    is_hit <- !is.na(is_hit)
  } else {
    is_hit <- rep(FALSE, nrow(session_df))
  }

  hits   <- session_df %>% filter(is_hit)
  misses <- session_df %>% filter(!is_hit)

  cat(sprintf(
    "Classification cache: %d hit(s), %d miss(es) [version %s]\n",
    nrow(hits), nrow(misses), classifier_version
  ))

  # Hits reuse cached labels: drop any pre-existing output columns, then bring the cached ones.
  if (nrow(hits) > 0) {
    hits <- hits %>%
      select(-any_of(classifier_output_cols)) %>%
      left_join(valid_cache, by = c(key_cols, "content_hash"))
  }

  # Misses go through the untouched classifier.
  if (nrow(misses) > 0) {
    misses <- classify_all_sessions(misses)
  }

  classified <- bind_rows(hits, misses) %>%
    arrange(.row_order) %>%
    select(-.row_order)

  # Rewrite the cache: keep entries for keys not in this run (eg, other countries / versions),
  # replace the rest with this run's labels and provenance.
  new_entries <- classified %>%
    select(all_of(c(key_cols, "content_hash", classifier_output_cols))) %>%
    mutate(
      classifier_version = classifier_version,
      classified_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    )

  if (!is.null(cache) && all(key_cols %in% names(cache))) {
    retained <- cache %>%
      anti_join(classified %>% select(all_of(key_cols)), by = key_cols)
    updated_cache <- bind_rows(retained, new_entries)
  } else {
    updated_cache <- new_entries
  }

  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
  write_csv(updated_cache, cache_path)

  # Return identical shape to classify_all_sessions(): drop the internal hash column.
  classified %>% select(-content_hash)
}
