#Need to get the most recent rolling average for each player 
get_recent_averages <- function(player, rolling_averages) {
  #Filter rows where the player appears in player_1 or player_2
  player_data <- rolling_averages[
    rolling_averages$name_P_1 == player | rolling_averages$name_P_2 == player, 
  ]
  
  #If no data exists for the player
  if (nrow(player_data) == 0) {
    stop(paste("No data available for player ", player))
  }
  
  # Identify if the player is in player_1 or player_2 and extract their rolling averages
  player_data <- player_data %>%
    mutate(
      rank = ifelse(name_P_1 == player, rank_P_1, rank_P_2),
      height = ifelse(name_P_1 == player, ht_P_1, ht_P_2),
      age = ifelse(name_P_1 == player, age_P_1, age_P_2),
      set_tot_av = ifelse(name_P_1 == player, set_tot_av_P_1, set_tot_av_P_2),
      ace_av = ifelse(name_P_1 == player, ace_av_P_1, ace_av_P_2),
      df_av = ifelse(name_P_1 == player, df_av_P_1, df_av_P_2),
      svpt_av = ifelse(name_P_1 == player, svpt_av_P_1, svpt_av_P_2),
      X1stIn_av = ifelse(name_P_1 == player, X1stIn_av_P_1, X1stIn_av_P_2),
      X1stWon_av = ifelse(name_P_1 == player, X1stWon_av_P_1, X1stWon_av_P_2),
      X2ndWon_av = ifelse(name_P_1 == player, X2ndWon_av_P_1, X2ndWon_av_P_2),
      SvGms_av = ifelse(name_P_1 == player, SvGms_av_P_1, X2ndWon_av_P_2),
    )
  
  # Get the most recent row based on match_date
  recent_data <- player_data[which.max(player_data$tourney_date_P_1), ]
  
  # Return only the rolling averages for the player
  return(recent_data[, c("rank", 
                         "height", 
                         "age", 
                         "set_tot_av", 
                         "ace_av", 
                         "df_av", 
                         "svpt_av", 
                         "X1stIn_av",
                         "X1stWon_av",
                         "X2ndWon_av",
                         "SvGms_av"
  )])
}

#Preparing the features for the model
prepare_features <- function(player1, player2, rolling_averages) {
  # Check if the player names are the same
  if (player1 == player2) {
    stop("Player 1 and Player 2 cannot be the same.")
  }
  # Get rolling averages for both player
  player1_data <- get_recent_averages(player1, rolling_averages)
  player2_data <- get_recent_averages(player2, rolling_averages)
  
  # Create a data frame with the features required by the model
  features <- data.frame(
    player1_rank = player1_data$rank,
    player2_rank = player2_data$rank,
    
    ht_P_1 = player1_data$height,
    ht_P_2 = player2_data$height,
    
    age_P_1 = player1_data$age,    
    age_P_2 = player2_data$age,
    
    set_tot_av_P_1 = player1_data$set_tot_av,
    set_tot_av_P_2 = player2_data$set_tot_av,
    
    ace_av_P_1 = player1_data$ace_av,
    ace_av_P_2 = player2_data$ace_av,
    
    df_av_P_1 = player1_data$df_av,
    df_av_P_2 = player2_data$df_av,
    
    svpt_av_P_1 = player1_data$svpt_av,
    svpt_av_P_2 = player2_data$svpt_av,
    
    X1stIn_av_P_1 = player1_data$X1stIn_av,
    X1stIn_av_P_2 = player2_data$X1stIn_av,
    
    X1stWon_av_P_1 = player1_data$X1stWon_av,
    X1stWon_av_P_2 = player2_data$X1stWon_av,
    
    X2ndWon_av_P_1 = player1_data$X2ndWon_av,
    X2ndWon_av_P_2 = player2_data$X2ndWon_av,
    
    SvGms_av_P_1 = player1_data$SvGms_av,
    SvGms_av_P_2 = player2_data$SvGms_av
  )
  
  features <- features %>%  mutate(rank_diff = player1_rank - player2_rank) %>% select(-c("player1_rank", "player2_rank")) %>% relocate(rank_diff)
  rank_diff_mean = mean(input_data$rank_diff)
  rank_diff_sd = sd(input_data$rank_diff)
  features$rank_diff <- (features$rank_diff - rank_diff_mean) / rank_diff_sd
  
  return(data.frame(features))
}

#Prediction function

predict_winner <- function(player1, player2, input_data, model) {
  # Prepare features for prediction
  features <- prepare_features(player1, player2, input_data)
  print(features)
  features <- data.matrix(features)
  # Predict using the model
  prediction <- predict(model, newdata = features, probability=TRUE)
  # Return the prediction
  return(prediction)
}