# ATP Match Predictions Model

## Overview
The ATP Match Predictions Model predicts the outcomes (winner vs. loser) of tennis matches played by professional players on the ATP tour between 2018 and 2022, as well as on a separate unseen test set consisting of 2023 matches.

## Data
The data was collected from January 2018 to December 2022, sourced from Jeff Sackman, who compiles comprehensive ATP match data. The dataset consists of **12,815 observations** with **49 columns**, covering match statistics such as match location, surface, points won, rankings, and player statistics.

## Key Findings from Exploratory Data Analysis (EDA)
- **Top Players**: The top 20 players with the most match wins in the past five years include well-known names like Novak Djokovic, Rafael Nadal, and Roger Federer.
- **Surface Impact**: Win percentages vary by surface (hard court, grass, clay), with different players excelling on different surfaces.
- **Player Height**: Taller players tend to have stronger serves, though there is a tradeoff in terms of agility.

## Preprocessing
- **Data Removal**: Matches from the NextGen Finals and Laver Cup were removed as these are exhibition matches and differ in scoring rules and player selection.
- **Missing Data**: Missing values were imputed for variables like seed and player height, and unhelpful columns were dropped, leaving **11,998 observations**.
- **Feature Extraction**: Variables such as Elo ratings, serve statistics, break points, and match outcomes were created for each player.

## Feature Selection
- **Random Forest** and **Principal Component Analysis (PCA)** were used to select the top 20 features for model training.
- **PCA Scree Plot**: An elbow was identified around 10 components, suggesting the optimal number of features.

## Model Development
### Preliminary Models Tested
- Random Forest with SVM (Radial Kernel)
- Random Forest with XGBoost

### Hyperparameter Tuning with MLflow
Hyperparameters such as **C**, **Gamma**, **Max Depth**, and **Eta** were optimized for different models using MLflow.

### Final Models
- **Random Forest + SVM (Radial Kernel)**
  - F1 Score: 0.738, AUC: 0.825, Accuracy: 0.75
- **Random Forest + XGBoost**
  - F1 Score: 0.817, AUC: 0.907, Accuracy: 0.828

### Metrics Collected
The model's performance was evaluated using metrics such as **F1-score**, **AUC**, **Precision**, **Recall**, and **Test Accuracy**.

## Results
- The model’s performance on the 2023 test set showed a **F1 score** range of **0.648 to 0.817** for different model configurations.
- **Top performing model**: Random Forest + XGBoost with optimal hyperparameters achieved an **AUC of 0.907** and **Test Accuracy of 0.828**.

## Model Limitations
- **Data Drift**: The model may face performance degradation over time due to the emergence of new players and the aging of older players, necessitating model retraining.

## Deployment
The XGBoost model was deployed using the "plumber" package to create an API endpoint. The index.html file has the front end interface where two player names are entered and a winner is predicted.

## Authors
- **Mona Ascha** (Author)

## Last Updated
- **November 7, 2024**
