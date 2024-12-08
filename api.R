library(plumber)
library(dplyr)

#Filter
#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*") 
  res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
  res$setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
  
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$status <- 200
    return(list())
  } else {
    plumber::forward()
  }
}



#Load model 
model_path <- "/Users/mona/Dropbox/Desktop/Tennis_Analytics/tennis_preds/mlruns/553438081521013443/602c02abd9d84d8aa1cb4b9a5612d087/artifacts/model.rds"
model <- readRDS(file = model_path)

#Load input data
data_ids <- read.csv("/Users/mona/Dropbox/Desktop/Tennis_Analytics/tennis_preds/data/data_ids.csv")
data_train <- read.csv("/Users/mona/Dropbox/Desktop/Tennis_Analytics/tennis_preds/data/data_train.csv")

full_data <- cbind(data_ids, data_train)

to_keep <- c("rank_diff", 
             "rank_P_1",
             "rank_P_2",
             "ht_P_1", 
             "ht_P_2", 
             "age_P_1", 
             "age_P_2", 
             "set_tot_av_P_1", 
             "set_tot_av_P_2", 
             "ace_av_P_1", 
             "ace_av_P_2", 
             "df_av_P_1", 
             "df_av_P_2", 
             "svpt_av_P_1", 
             "svpt_av_P_2", 
             "X1stIn_av_P_1", 
             "X1stIn_av_P_2", 
             "X1stWon_av_P_1", 
             "X1stWon_av_P_2", 
             "X2ndWon_av_P_1", 
             "X2ndWon_av_P_2", 
             "SvGms_av_P_1",
             "SvGms_av_P_2",
             "id_P_1", 
             "id_P_2", 
             "name_P_1", 
             "name_P_2",
             "tourney_date_P_1",
             "Win_P_1")

input_data <- full_data %>% select(c(to_keep, "Win_P_1"))

cols_to_scale <- c("ht_P_1", 
                   "ht_P_2", 
                   "age_P_1", 
                   "age_P_2", 
                   "set_tot_av_P_1", 
                   "set_tot_av_P_2", 
                   "ace_av_P_1", 
                   "ace_av_P_2", 
                   "df_av_P_1", 
                   "df_av_P_2", 
                   "svpt_av_P_1", 
                   "svpt_av_P_2", 
                   "X1stIn_av_P_1", 
                   "X1stIn_av_P_2", 
                   "X1stWon_av_P_1", 
                   "X1stWon_av_P_2", 
                   "X2ndWon_av_P_1", 
                   "X2ndWon_av_P_2", 
                   "SvGms_av_P_1",
                   "SvGms_av_P_2")

#Scale
input_data[cols_to_scale] <- scale(input_data[cols_to_scale])


source("prepare_features.R") # Ensure prepare_features & predict_winner are defined

# Define endpoint for prediction
#* @param player1 Character: Name of Player 1
#* @param player2 Character: Name of Player 2
#Throw error if player not found
#* @post /predict
function(player1, player2) {
  tryCatch({
    prediction <- predict_winner(player1, player2, input_data, model)
    list(winner_prediction = prediction)
  }, error = function(e) {
    # Return error as JSON
    res <- list(error = e$message)
    return(res)
  })
}
