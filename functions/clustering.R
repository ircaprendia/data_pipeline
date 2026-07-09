# Clustering functions for AprendIA

# Run k-means clustering on contact-level data
# Arguments:
#   data: Contacts data frame (already filtered to desired group)
#   exclude_vars: Variables to exclude
#   k_range: Range of k values to test
#   seed: Random seed
#   iter_max: Maximum iterations
#   runs: Number of runs
# Returns: List with cluster assignments and fit object
run_user_clustering <- function(data, exclude_vars, k_range = 2:7, seed = 506, 
                                iter_max = 50, runs = 10) {
  
  library(tidymodels)
  library(fpc)
  
  # Prepare data using recipe
  contacts_prepped <- recipe(~ ., data = data) %>%
    step_rm(any_of(exclude_vars)) %>%
    step_rm(contains("_start")) %>%
    step_normalize(all_numeric_predictors()) %>%
    prep() %>%
    bake(new_data = NULL)
  
  # Run k-means clustering
  set.seed(seed)
  clusters_fit <- kmeansruns(
    data = contacts_prepped, 
    krange = k_range, 
    iter.max = iter_max, 
    runs = runs
  )
  
  return(list(
    fit = clusters_fit,
    assignments = clusters_fit$cluster
  ))
}

# Create cluster profile summary
# Arguments:
#   data: Contacts data with cluster assignments
# Returns: Summary data frame
summarise_cluster_profiles <- function(data) {
  
  data %>%
    group_by(cluster) %>%
    summarise(
      n = n(),
      female_perc = mean(female == 1, na.rm = TRUE),
      msgs = mean(num_messages, na.rm = TRUE),
      wk_1_msgs = mean(week_one_message_count, na.rm = TRUE),
      wk_1_sessions = mean(week_one_session_count, na.rm = TRUE),
      wk_1_days_active = mean(week_one_days_active, na.rm = TRUE),
      day_1_msgs = mean(day_one_message_count, na.rm = TRUE),
      day_1_sessions = mean(day_one_session_count, na.rm = TRUE),
      first_session_length = mean(first_session_length, na.rm = TRUE),
      sessions = mean(num_sessions, na.rm = TRUE),
      emojis_rcvd = mean(avg_rcvd_emojis, na.rm = TRUE),
      emojis_sent = mean(avg_sent_emojis, na.rm = TRUE),
      msg_length = mean(avg_msg_length, na.rm = TRUE),
      msg_length_rcvd = mean(avg_rcvd_msg_length, na.rm = TRUE),
      msg_length_sent = mean(avg_sent_msg_length, na.rm = TRUE),
      interaction_ratio = mean(interaction_ratio, na.rm = TRUE),
      select_course = mean(select_course, na.rm = TRUE),
      select_question = mean(select_question, na.rm = TRUE),
      churn_count = mean(churn_count > 0, na.rm = TRUE),
      reactive_count = mean(reactivate_count > 0, na.rm = TRUE),
      .groups = "drop"
    )
}

apply_cluster_factor <- function(df) {
  df %>%
    mutate(
      cluster_label = factor(
        cluster_label,
        levels = cluster_lookup %>% arrange(cluster_order) %>% pull(cluster_label) %>% unique(),
        ordered = TRUE
      ),
      cluster_group_label = factor(
        cluster_group_label,
        levels = cluster_group_lookup %>% arrange(cluster_group_order) %>% pull(cluster_group_label) %>% unique(),
        ordered = TRUE
      )
    )
}

apply_cluster_labels <- function(df) {
  df %>%
    left_join(cluster_lookup,       by = "cluster") %>%
    left_join(cluster_group_lookup, by = c("group", "cluster_group")) %>%
    mutate(
      cluster_label = factor(
        cluster_label,
        levels = cluster_lookup %>% arrange(cluster_order) %>% pull(cluster_label) %>% unique(),
        ordered = TRUE
      ),
      cluster_group_label = factor(
        cluster_group_label,
        levels = cluster_group_lookup %>% arrange(cluster_group_order) %>% pull(cluster_group_label) %>% unique(),
        ordered = TRUE
      )
    )
}

