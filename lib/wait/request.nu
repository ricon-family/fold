def usage-text [value: string]: nothing -> string {
  let trimmed = ($value | str trim)
  if $trimmed in ["" "''"] {
    ""
  } else {
    $trimmed
  }
}


def usage-values [value: string]: nothing -> list<string> {
  let normalized = (usage-text $value)
  if $normalized == "" {
    []
  } else {
    $normalized | split row --regex '\s+' | uniq
  }
}


def invalid [message: string] {
  error make {msg: $message}
}


export def build-request [raw: record] {
  let sessions = (usage-values $raw.sessions)
  let chat_room = (usage-text $raw.chat.room)
  let chat_identity = (usage-text $raw.chat.identity)
  let chat_senders = (usage-values $raw.chat.senders)
  let chat_mentions = (usage-values $raw.chat.mentions)
  let state_dir = (usage-text $raw.state_dir)
  let timeout_seconds = try {
    $raw.timeout_seconds | into int
  } catch {
    invalid "--timeout must be a non-negative integer"
  }

  let has_chat_options = (
    $chat_identity != ""
    or ($chat_senders | is-not-empty)
    or ($chat_mentions | is-not-empty)
  )

  if $chat_room == "" and $has_chat_options {
    invalid "--as, --from, and --mention require --chat"
  }
  if $chat_room != "" and $chat_identity == "" {
    invalid "--chat requires an explicit --as identity"
  }
  if ($sessions | is-empty) and $chat_room == "" {
    invalid "provide at least one --session or --chat source"
  }
  if $state_dir == "" {
    invalid "--state-dir is required"
  }
  if $timeout_seconds < 0 {
    invalid "--timeout must be a non-negative integer"
  }

  let state_path = ($state_dir | path expand --no-symlink)
  if ($state_path | path exists) and (($state_path | path type) != "dir") {
    invalid "--state-dir must be a directory"
  }

  {
    sessions: $sessions
    chat: {
      room: $chat_room
      identity: $chat_identity
      senders: $chat_senders
      mentions: $chat_mentions
    }
    state_dir: $state_path
    timeout_seconds: $timeout_seconds
  }
}
