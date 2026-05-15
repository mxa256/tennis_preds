# Refresh ATP match data from Jeff Sackmann's upstream repo.
#
# Usage (from the tennis_preds project root):
#   source("R/refresh_data.R")
#
# Behaviour:
#   - If ../tennis_atp-master/ is already a git clone, pulls latest.
#   - If the directory does not exist, performs a fresh shallow clone.
#   - If the directory exists but is not a git clone, stops with an
#     error rather than silently destroying unknown contents.

DATA_DIR <- file.path("..", "tennis_atp-master")
REPO_URL <- "https://github.com/JeffSackmann/tennis_atp.git"

is_git_clone <- dir.exists(file.path(DATA_DIR, ".git"))

if (is_git_clone) {
  message("Pulling latest ATP data into ", DATA_DIR)
  exit_code <- system2("git", c("-C", DATA_DIR, "pull", "--ff-only"))
} else if (dir.exists(DATA_DIR)) {
  stop(
    DATA_DIR, " exists but is not a git clone.\n",
    "Delete it manually if you want to re-clone from upstream."
  )
} else {
  message("Cloning fresh ATP data into ", DATA_DIR)
  exit_code <- system2(
    "git",
    c("clone", "--depth", "1", REPO_URL, DATA_DIR)
  )
}

if (exit_code != 0L) {
  stop("git command failed with exit code ", exit_code)
}

last_commit <- system2(
  "git",
  c("-C", DATA_DIR, "log", "-1", shQuote("--format=%h %s, %cr")),
  stdout = TRUE
)
message("\nLatest upstream commit: ", last_commit)
