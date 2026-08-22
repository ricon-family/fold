def chat-cursor-file [request: record match: record] {
  let key = {
    room: $request.chat.room
    identity: $request.chat.identity
    kind: $match.kind
    value: $match.value
  }
  let digest = ($key | to json -r | hash sha256 | str substring 0..15)
  [$request.state_dir $"chat-($match.kind)-($digest).cursor"] | path join
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
      source: "sessions"
      cursor_file: $cursor_file
      command: $command
    })
  }

  if $request.chat.room != "" {
    let matches = if (
      ($request.chat.senders | is-empty)
      and ($request.chat.mentions | is-empty)
    ) {
      [{kind: "any" value: ""}]
    } else {
      let senders = (
        $request.chat.senders
        | each {|sender| {kind: "from" value: $sender} }
      )
      let mentions = (
        $request.chat.mentions
        | each {|identity| {kind: "mention" value: $identity} }
      )
      $senders | append $mentions
    }

    for match in $matches {
      let cursor_file = (chat-cursor-file $request $match)
      let filter = match $match.kind {
        "from" => ["--by" $match.value]
        "mention" => ["--mention" $match.value]
        _ => []
      }
      let command = (
        [$executables.chat "wait" $request.chat.room "--as" $request.chat.identity]
        | append $filter
        | append ["--cursor-file" $cursor_file "--timeout" "0" "--json"]
      )
      let source = if $match.kind == "any" {
        "chat:any"
      } else {
        $"chat:($match.kind):($match.value)"
      }
      $waiters = ($waiters | append {
        source: $source
        cursor_file: $cursor_file
        command: $command
      })
    }
  }

  $waiters
}
