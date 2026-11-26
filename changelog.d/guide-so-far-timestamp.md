### Fixed

- `/plinth:guide`'s "so far" picks the newest five events by their whole
  timestamp, not by the order GitHub returned them: when more than five
  events share a day, the earliest of that day is the one left out (#1076).
  A tag's date with a time-zone offset is read in UTC, like every other
  event's, so near midnight it may show the day before or after it did.
