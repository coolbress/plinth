### Fixed

- `/plinth:new-project` in text mode (`claude -p`) asks the last question as "type 0 to create it as shown, or the numbers of the rows to change", and never numbers Create as a choice, so `1` cannot mean both "create" and "change row 1"; with "I don't know" as the description it suggests plain names for the kind instead of none (#1067).
