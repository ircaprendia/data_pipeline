# Feature engineering functions for aprendIA

# Add message sequencing and session variables
# Arguments:
#   data: Cleaned message data
#   session_timeout: Time in seconds to define session boundaries (default 1200 = 20 min)
# Returns: Data with message sequencing, timing, and session variables
add_message_sequencing <- function(data, session_timeout = 1200) {
  
  data %>%
    arrange(contact_id, time_corrected) %>%
    group_by(contact_id) %>%
    mutate(
      message_num = row_number(),
      total_messages = n(),
      first_message = first(time_corrected),
      time_lapse = time_corrected - first(time_corrected),
      hrs_lapse = as.numeric(difftime(time_corrected, first(time_corrected), units = "hours")),
      day_lapse = as.numeric(difftime(time_corrected, first(time_corrected), units = "days")),
      wk_lapse = as.numeric(difftime(time_corrected, first(time_corrected), units = "weeks")),
      message_day = if_else(day_lapse == 0, 1, ceiling(day_lapse)),
      message_week = if_else(wk_lapse == 0, 1, ceiling(wk_lapse)),
      last_message = row_number() == n(),
      time_btwn_msgs = c(0, as.numeric(diff(time_corrected), units = "secs")),
      new_session = time_btwn_msgs > session_timeout | row_number() == 1,
      session_id = cumsum(new_session)
    ) %>%
    group_by(contact_id, message_day) %>%
    mutate(
      msgs_per_day = n()
    ) %>%
    ungroup() %>%
    group_by(contact_id, message_week) %>%
    mutate(
      msgs_per_wk = n()
    ) %>%
    ungroup() %>%
    group_by(contact_id, message_week) %>%
    mutate(
      sessions_per_wk = n_distinct(session_id)
    ) %>%
    ungroup() %>%
    group_by(contact_id, session_id) %>%
    mutate(
      session_length = max(time_corrected) - min(time_corrected)
    ) %>%
    ungroup()
}


# Add group variable for within-country cohort grouping
# Arguments:
#   data: Message data with first_message variable already added
#   group_definitions: List of group definitions with name and start datetime (optional)
# Returns: Data with group variable added (defaults to "Default" if no groups specified)
add_group_variable <- function(data, group_definitions = NULL) {
  
  # If no group definitions provided, everyone gets "Default"
  if (is.null(group_definitions) || length(group_definitions) == 0) {
    return(data %>% mutate(group = "Default"))
  }
  
  # Sort definitions by start time (most recent first) for proper assignment
  group_definitions <- group_definitions[order(sapply(group_definitions, function(x) x$start), decreasing = TRUE)]
  
  # Create the group assignment, defaulting to "Default"
  result <- data %>%
    mutate(group = "Default")
  
  # Assign groups based on first_message time
  for (group_def in group_definitions) {
    result <- result %>%
      mutate(
        group = if_else(
          group == "Default" & first_message >= group_def$start,
          group_def$name,
          group
        )
      )
  }
  
  return(result)
}


# Add module signpost indicators
# Arguments:
#   data: Message data
# Returns: Data with module start indicators added
add_module_signposts <- function(data) {
  
  data %>%
    mutate(
      # Common patterns for start indicators
      has_start_phrase = str_detect(message, regex(
        "ready to begin|when you're ready|we'll explore|let's start|welcome to|barka da zuwa|shirye mu fara|shirya|za mu koyi|you'll explore|ready for module",
        ignore_case = TRUE
      )),
      has_completion = str_detect(message, regex(
        "completed|congratulations|end of|you've finished",
        ignore_case = TRUE
      )),
      has_quiz = str_detect(message, regex(
        "quiz question|test your understanding|let's test|let's start the.*quiz|start the.*quiz|question \\d+:",
        ignore_case = TRUE
      )),
      
      # Reading module signposts
      reading_mod1_start = case_when(
        str_detect(message, regex("Module 1", ignore_case = TRUE)) &
          str_detect(message, regex("Reading|What is Reading", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      reading_mod2_start = case_when(
        str_detect(message, regex("Module 2", ignore_case = TRUE)) &
          str_detect(message, regex("Building the Foundation|Language.*Sounds.*Print", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      reading_mod3_start = case_when(
        str_detect(message, regex("Module 3", ignore_case = TRUE)) &
          str_detect(message, regex("Growing Meaning|Vocabulary.*Comprehension", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      reading_mod4_start = case_when(
        str_detect(message, regex("Module 4", ignore_case = TRUE)) &
          str_detect(message, regex("Joyful.*Healing.*Reading|Joy.*Connection.*Reading", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      reading_mod5_start = case_when(
        str_detect(message, regex("Module 5", ignore_case = TRUE)) &
          str_detect(message, regex("Supporting All Learners|Reaching Every Learner", ignore_case = TRUE)) &
          str_detect(message, regex("Reading", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      
      # Maths module signposts
      maths_mod1_start = case_when(
        str_detect(message, regex("Module 1", ignore_case = TRUE)) &
          str_detect(message, regex("Math|Exploring Math Domains|lissafi", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      maths_mod2_start = case_when(
        str_detect(message, regex("Module 2", ignore_case = TRUE)) &
          str_detect(message, regex("Shifting Math Mindsets|Math Mindsets", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      maths_mod3_start = case_when(
        str_detect(message, regex("Module 3", ignore_case = TRUE)) &
          str_detect(message, regex("Math Process Skills|Fasahar Sarrafa Lissafi", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      maths_mod4_start = case_when(
        str_detect(message, regex("Module 4", ignore_case = TRUE)) &
          str_detect(message, regex("Making Math Hands.On|Math Hands.On", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      maths_mod5_start = case_when(
        str_detect(message, regex("Module 5", ignore_case = TRUE)) &
          str_detect(message, regex("Reaching Every Learner|Supporting All Learners", ignore_case = TRUE)) &
          str_detect(message, regex("Math", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      
      # Classroom management signposts
      classroom_mod1_start = case_when(
        str_detect(message, regex("Module 1", ignore_case = TRUE)) &
          str_detect(message, regex("Sense of Control|(?<![a-zA-Z])Jin ", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      classroom_mod2_start = case_when(
        str_detect(message, regex("Module 2", ignore_case = TRUE)) &
          str_detect(message, regex("Positive.*Relationships|Sense of Belonging", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      classroom_mod3_start = case_when(
        str_detect(message, regex("Module 3", ignore_case = TRUE)) &
          str_detect(message, regex("Engagement.*Self.Worth", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      ),
      classroom_mod4_start = case_when(
        str_detect(message, regex("Module 4", ignore_case = TRUE)) &
          str_detect(message, regex("Healing Classroom|Assessing Classroom Dynamics", ignore_case = TRUE)) &
          direction == "Outgoing" &
          has_start_phrase & !has_completion & !has_quiz ~ 1,
        TRUE ~ 0
      )
    )
}


# Add implementation timing variables (days/weeks since project start)
# Arguments:
#   data: Message data with time_corrected variable
#   project_start: Start datetime (optional, defaults to min of data)
# Returns: Data with impl_day and impl_week variables
add_implementation_timing <- function(data, project_start = NULL) {
  
  # If no start provided, use the earliest message in the data
  if (is.null(project_start)) {
    project_start <- min(data$time_corrected, na.rm = TRUE)
  }
  
  data %>%
    mutate(
      impl_day = as.numeric(difftime(time_corrected, project_start, units = "days")),
      impl_day = ifelse(impl_day == 0, 1, ceiling(impl_day)),
      impl_week = as.numeric(difftime(time_corrected, project_start, units = "weeks")),
      impl_week = ifelse(impl_week == 0, 1, ceiling(impl_week))
    )
}
