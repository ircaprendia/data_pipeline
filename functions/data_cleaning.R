# Data cleaning functions for aprendIA message data

# Clean raw message data from Telerivet
# Arguments:
#   raw_data: Raw message data from Telerivet CSV
#   test_users: Character vector of test user names to exclude
#   female_options: Character vector of responses that indicate female gender
#   source_timezone: Timezone of the data source (default "America/Mexico_City")
#   target_timezone: Target timezone for analysis (default "Africa/Lagos")
# Returns: Cleaned and processed message data
clean_messages <- function(
    raw_data,
    phone_num_from,
    phone_num_to,
    test_users = NULL,
    test_user_ids = NULL,
    female_options,
    redundant_cols = NULL,
    source_timezone = "America/Mexico_City",
    target_timezone = "Africa/Lagos"
  ) {
  
  library(tidyverse)
  library(janitor)
  
  # Define default redundant columns if not provided
  if (is.null(redundant_cols)) {
    redundant_cols <- c("parts", "call_duration", "labels", "currency", "price", 
                        "reaction_to", "whats_app_flow_id", "whats_app_template", 
                        "whats_app_template_language")
  }
  
  cleaned <- raw_data %>%
    clean_names() %>%
    # Remove unnecessary columns
    dplyr::select(-any_of(redundant_cols)) %>%
    # Filter out test users and failed messages
    filter(
      status != "Failed",
      message_type == "chat",
      from == phone_num_from | to == phone_num_to,
      if (!is.null(test_users) && "contact_name" %in% names(.)) !contact_name %in% test_users else TRUE,
      if (!is.null(test_user_ids)) !contact_id %in% test_user_ids else TRUE
    ) %>%
    unique() %>%
    # Text cleaning and feature engineering
    mutate(
      # Standardize apostrophes
      message = str_replace_all(message, "[\u2018\u2019\u201C\u201D]", "'"),
      
      # Gender identification
      female = if_else(message %in% female_options, 1, 0),
      male = if_else(message %in% c("Male ♂️", "Male"), 1, 0),
      
      # Timezone conversion
      date = dmy_hms(date, tz = source_timezone) %>% with_tz(target_timezone),
      time_sent = dmy_hms(time_sent, tz = source_timezone) %>% with_tz(target_timezone),
      last_updated = dmy_hms(last_updated, tz = source_timezone) %>% with_tz(target_timezone),
      time_corrected = if_else(is.na(time_sent), date, time_sent),
      
      # Temporal features
      hour_num = as.numeric(hour(time_corrected)),
      weekday = wday(time_corrected, label = TRUE),
      
      # Phone number matching
      phone_num_match = str_trunc(to, 8, side = "left", ellipsis = ""),

      # User's phone country — derived from the TEACHER's number (the non-bot side: `from` on
      # Incoming, `to` on Outgoing), so it reflects where the user is, distinct from `country`
      # (which bot they used). Only the dialing-code → country mapping is kept; the raw number is
      # dropped below, so no new PII is retained. A leading "00" international prefix is stripped.
      # The code list is easily extended; "Other" = a recognised-but-unlisted code, NA = unparseable
      # (eg, a local-format number with no country code). Validate the distribution after a run.
      user_phone_digits = str_remove(
        str_remove_all(if_else(direction == "Incoming", from, to), "[^0-9]"),
        "^00"
      ),
      user_phone_country = case_when(
        str_starts(user_phone_digits, "234") ~ "Nigeria",
        str_starts(user_phone_digits, "227") ~ "Niger",
        str_starts(user_phone_digits, "593") ~ "Ecuador",
        str_starts(user_phone_digits, "1")   ~ "US/Canada",
        is.na(user_phone_digits) | user_phone_digits == "" ~ NA_character_,
        TRUE ~ "Other"
      ),

      # Message characteristics
      msg_sticker = if_else(is.na(message) & is.na(media_ur_ls), 1, 0),
      message_corrected = if_else(is.na(message), "", message),
      
      # Emoji counts
      msg_emoji_count = str_count(message_corrected, "[\\p{Emoji_Presentation}\\p{Extended_Pictographic}]"),
      msg_rcvd_emoji_count = case_when(
        direction == "Outgoing" ~ str_count(message_corrected, "[\\p{Emoji_Presentation}\\p{Extended_Pictographic}]"),
        direction == "Incoming" ~ 0,
        TRUE ~ NA_integer_
      ),
      msg_sent_emoji_count = case_when(
        direction == "Outgoing" ~ 0,
        direction == "Incoming" ~ str_count(message_corrected, "[\\p{Emoji_Presentation}\\p{Extended_Pictographic}]"),
        TRUE ~ NA_integer_
      ),
      
      # URL counts
      msg_url_count = str_count(message_corrected, "https?://\\S+"),
      
      # Text cleaning for analysis
      message_corrected = str_replace_all(message_corrected, "\\n", " "),
      message_corrected = str_replace_all(message_corrected, "https?://\\S+", ""),
      message_corrected = str_replace_all(message_corrected, "[\\p{Emoji_Presentation}\\p{Extended_Pictographic}]", ""),
      message_corrected = str_squish(message_corrected),
      
      # Message length
      msg_length = str_length(message_corrected),
      msg_length_rcvd = case_when(
        direction == "Outgoing" ~ str_length(message_corrected),
        direction == "Incoming" ~ 0
      ),
      msg_length_sent = case_when(
        direction == "Outgoing" ~ 0,
        direction == "Incoming" ~ str_length(message_corrected)
      )
    ) %>%
    select(-any_of(c("from", "to", "contact_name", "phone_num_match", "user_phone_digits")))

  return(cleaned)
}

# Add course and question selection indicators
# Arguments:
#   data: Cleaned message data
# Returns: Data with selection indicator columns added
add_selection_indicators <- function(data) {
  
  data %>%
    mutate(
      # Identify where courses or questions are initiated
      given_options = if_else(
        is.na(str_detect(message, "Can I support you with something specific?")), 
        0, 
        str_detect(message, "Can I support you with something specific?")
      ),
      select_course = if_else(
        is.na(str_starts(message, "Course Selection")), 
        0, 
        str_starts(message, "Course Selection")
      ),
      select_classroom_mgmt = case_when(
        str_detect(message, "Classroom 📘") & direction == "Incoming" ~ 1,
        TRUE ~ 0
      ),
      select_maths = case_when(
        str_detect(message, "Math ➕") & direction == "Incoming" ~ 1,
        TRUE ~ 0
      ),
      select_reading = case_when(
        str_detect(message, "Reading 📚") & direction == "Incoming" ~ 1,
        TRUE ~ 0
      ),
      select_question = if_else(
        is.na(str_starts(message, "Specific Question")), 
        0, 
        str_starts(message, "Specific Question")
      )
    )
}
