# Data aggregation functions for AprendIA
# These create session-level and person-level datasets from message data

# Create session-level data
# Arguments:
#   data: Cleaned message data with session_id already added
#   churn_threshold: Seconds of inactivity to define churn (from config)
# Returns: Session-level dataset with all_messages column for classification
create_session_data <- function(data, churn_threshold) {
  
  # Get date range for final gap calculation
  data_start_date <- min(data$time_corrected)
  data_end_date <- max(data$time_corrected)

  # Country-aware grain: when the combined data carries a country column, country joins the
  # session key so a dual-country contact's activity stays separate per country (their Niger
  # session 1 does not merge with their Nigeria session 1). When country is absent, the key
  # falls back to contact_id + session_id, so the old per-country pipeline runs unchanged.
  has_country <- "country" %in% names(data)
  session_key <- if (has_country) c("contact_id", "country", "session_id") else c("contact_id", "session_id")

  # Create concatenated messages for classification
  # CRITICAL: Must group by BOTH contact_id and session_id since session_id is not unique!
  messages_concatenated <- data %>%
    filter(nzchar(message_corrected)) %>%  # NEW: Remove empty messages/stickers
    arrange(contact_id, session_id, time_corrected) %>%
    group_by(across(any_of(c("contact_id", "country", "session_id")))) %>%
    summarise(
      all_messages = paste(message_corrected, collapse = " | "),
      .groups = "drop"
    )
  
  # NEW: Get first 3 user (Incoming) messages for better question detection
  first_user_messages <- data %>%
    filter(direction == "Incoming", nzchar(message_corrected)) %>%
    arrange(contact_id, session_id, time_corrected) %>%
    group_by(across(any_of(c("contact_id", "country", "session_id")))) %>%
    slice_head(n = 3) %>%
    summarise(
      first_user_messages = paste(message_corrected, collapse = " | "),
      .groups = "drop"
    )
  
  # Create basic session data
  session_data <- data %>%
    arrange(contact_id, time_corrected) %>%
    group_by(across(any_of(c("contact_id", "country", "group", "session_id")))) %>%
    summarise(
      session_start = min(time_corrected),
      session_end = max(time_corrected),
      start_direction = first(direction),
      first_message_text = first(message_corrected),
      user_phone_country = first(user_phone_country),  # constant within a contact
      impl_day = min(impl_day),
      impl_week = min(impl_week),
      message_day = min(message_day),
      message_week = min(message_week),
      msgs_per_session = n_distinct(message_id),
      in_msgs_per_session = n_distinct(message_id[direction == "Incoming"]),
      out_msgs_per_session = n_distinct(message_id[direction == "Outgoing"]),
      interaction_ratio = in_msgs_per_session / msgs_per_session,
      session_length = session_end - session_start,
      .groups = "drop"
    ) %>%
    # Add concatenated messages
    left_join(
      messages_concatenated,
      by = session_key
    ) %>%
    # NEW: Add first user messages
    left_join(
      first_user_messages,
      by = session_key
    ) %>%
    arrange(contact_id, session_start) %>%
    group_by(across(any_of(c("contact_id", "country")))) %>%
    mutate(
      time_since_prev_session = session_start - lag(session_end)
    ) %>%
    ungroup()
  
  # Create final gap rows for churn calculation
  final_gap_rows <- session_data %>%
    group_by(across(any_of(c("contact_id", "country", "group")))) %>%
    summarise(
      session_start = data_end_date,
      session_end = data_end_date,
      .groups = "drop"
    ) %>%
    mutate(session_id = NA)

  # Create long format with churn/reactivation indicators
  session_data_long <- bind_rows(session_data, final_gap_rows) %>%
    arrange(contact_id, session_start) %>%
    group_by(across(any_of(c("contact_id", "country")))) %>%
    mutate(
      gap_secs = as.numeric(difftime(session_start, lag(session_end), units = "secs")),
      churned = gap_secs > churn_threshold,
      churned_time = case_when(
        churned == TRUE ~ dplyr::lag(session_end + days(14)),
        TRUE ~ NA_POSIXct_
      ),
      churned_msg_day = case_when(
        churned == TRUE ~ dplyr::lag(message_day + 14),
        TRUE ~ NA_integer_
      ),
      churned_msg_week = case_when(
        churned == TRUE ~ dplyr::lag(message_week + 2),
        TRUE ~ NA_integer_
      ),
      reactivated = dplyr::lag(!is.na(gap_secs) & gap_secs > churn_threshold, default = FALSE)
    ) %>%
    ungroup()
  
  return(list(
    session_data = session_data,
    session_data_long = session_data_long
  ))
}


# Create person-level (contacts) data
# Arguments:
#   data: Cleaned message data
#   session_data_long: Long-format session data with churn indicators
#   reg_data: Optional registration data with phone_num_match column
# Returns: Person-level dataset
create_contacts_data <- function(data, session_data_long, reg_data = NULL, phone_lookup = NULL) {

  # Country-aware grain (see create_session_data): contacts are summarised per country when
  # the column is present, so a dual-country contact gets one row per country. The churn join
  # below uses the same key. Falls back to contact_id alone when country is absent.
  has_country <- "country" %in% names(data)
  contact_key <- if (has_country) c("contact_id", "country") else "contact_id"

  # Basic person-level aggregation
  contacts_data <- data %>%
    group_by(across(any_of(c("contact_id", "country", "group")))) %>%
    summarise(
      female = sum(female),
      start_time = min(time_corrected),
      start_week = min(impl_week),
      user_phone_country = first(user_phone_country),  # constant within a contact

      num_messages = n(),
      num_sessions = max(session_id),
      avg_time_btwn_msgs = mean(time_btwn_msgs),
      interaction_ratio = mean(direction == "Incoming"),
      avg_emojis = mean(msg_emoji_count),
      avg_rcvd_emojis = mean(msg_rcvd_emoji_count),
      avg_sent_emojis = mean(msg_sent_emoji_count),
      avg_msg_length = mean(msg_length),
      avg_rcvd_msg_length = mean(msg_length_rcvd),
      avg_sent_msg_length = mean(msg_length_sent),
      given_options = sum(given_options),
      select_course = sum(select_course),
      select_classroom_mgmt = sum(select_classroom_mgmt),
      classroom_mod1_start = sum(classroom_mod1_start),
      classroom_mod2_start = sum(classroom_mod2_start),
      classroom_mod3_start = sum(classroom_mod3_start),
      classroom_mod4_start = sum(classroom_mod4_start),
      select_maths = sum(select_maths),
      maths_mod1_start = sum(maths_mod1_start),
      maths_mod2_start = sum(maths_mod2_start),
      maths_mod3_start = sum(maths_mod3_start),
      maths_mod4_start = sum(maths_mod4_start),
      maths_mod5_start = sum(maths_mod5_start),
      select_reading = sum(select_reading),
      reading_mod1_start = sum(reading_mod1_start),
      reading_mod2_start = sum(reading_mod2_start),
      reading_mod3_start = sum(reading_mod3_start),
      reading_mod4_start = sum(reading_mod4_start),
      reading_mod5_start = sum(reading_mod5_start),
      select_question = sum(select_question),
      # Week one engagement features
      week_one_message_count = sum(message_week == 1),
      week_one_session_count = n_distinct(session_id[message_week == 1]),
      week_one_days_active = n_distinct(as.Date(time_corrected[message_week == 1])),
      first_session_length = as.numeric(first(session_length), units = "secs"),
      asked_question_week_one = as.integer(max(select_question[message_week == 1], na.rm = TRUE) > 0),
      selected_course_week_one = as.integer(max(select_course[message_week == 1], na.rm = TRUE) > 0),
      avg_interaction_ratio_week_one = mean(if_else(direction == "Incoming", 1, 0)[message_week == 1], na.rm = TRUE),
      # Day one engagement features
      day_one_message_count = sum(message_day == 1),
      day_one_session_count = n_distinct(session_id[message_day == 1]),
      returned_within_week = as.integer(any(message_day >= 2 & message_day <= 7)),
      days_until_second_session = if_else(
        n_distinct(session_id) >= 2,
        {
          session_2_times <- time_corrected[session_id == 2]
          session_1_times <- time_corrected[session_id == 1]
          if (length(session_2_times) > 0 && length(session_1_times) > 0) {
            as.numeric(difftime(min(session_2_times), max(session_1_times), units = "days"))
          } else {
            NA_real_
          }
        },
        NA_real_
      ),
      
      .groups = "drop"
    ) %>%
    mutate(
      end_first_week = start_time + days(7),
      classroom_modules = classroom_mod1_start + classroom_mod2_start + classroom_mod3_start + classroom_mod4_start,
      maths_modules = maths_mod1_start + maths_mod2_start + maths_mod3_start + maths_mod4_start + maths_mod5_start,
      reading_modules = reading_mod1_start + reading_mod2_start + reading_mod3_start + reading_mod4_start + reading_mod5_start
    ) %>%
    # Add churn/reactivation counts from session data
    left_join(
      session_data_long %>%
        group_by(across(any_of(c("contact_id", "country")))) %>%
        summarise(
          churn_count = sum(churned, na.rm = TRUE),
          reactivate_count = sum(reactivated, na.rm = TRUE),
          .groups = "drop"
        ),
      by = contact_key
    )
  
  # Add registration flag if phone lookup provided
  # Flow: load phone_lookup.csv offline, join with reg_data on phone_num_match,
  # pass resulting contact_id -> registered mapping here as phone_lookup
  if (!is.null(phone_lookup)) {
    contacts_data <- contacts_data %>%
      left_join(phone_lookup, by = "contact_id") %>%
      mutate(registered = replace_na(registered, 0))
  }
  
  # Clean up female variable
  contacts_data <- contacts_data %>%
    mutate(
      female = case_when(
        female == 0 ~ 0,
        female > 0 ~ 1
      )
    )
  
  return(contacts_data)
}
