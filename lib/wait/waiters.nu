def chat-cursor-file [request: record] {
  let key = {
    room: $request.chat.room
    identity: $request.chat.identity
  }
  let digest = ($key | to json -r | hash sha256 | str substring 0..15)
  [$request.state_dir $"chat-($digest).cursor"] | path join
}


export def build-waiters [request: record executables: record] {
  mut waiters = []

  if ($request.sessions | is-not-empty) {
    let cursor_file = ([$request.state_dir "sessions.json"] | path join)
    let command = (
      [$executables.sessions "wait-any"]
      | append $request.sessions
      | append ["--cursor-file" $cursor_file "--timeout" "0" "--json"]
    )
    $waiters = ($waiters | append {
      kind: "sessions"
      source: "sessions"
      cursor_file: $cursor_file
      command: $command
    })
  }

  if $request.chat.room != "" {
    let cursor_file = (chat-cursor-file $request)
    let command = (
      [
        $executables.chat
        "wait"
        $request.chat.room
        "--as"
        $request.chat.identity
        "--cursor-file"
        $cursor_file
        "--timeout"
        "0"
        "--json"
      ]
    )
    $waiters = ($waiters | append {
      kind: "chat"
      source: "chat"
      cursor_file: $cursor_file
      command: $command
      match: {
        identity: $request.chat.identity
        senders: $request.chat.senders
        mentions: $request.chat.mentions
      }
    })
  }

  $waiters
}
