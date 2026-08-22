def json-records [stdout: string] {
  $stdout
  | lines
  | where {|line| ($line | str trim) != "" }
  | each {|line|
      let parsed = ($line | from json)
      if ($parsed | describe --detailed | get type) != "record" {
        error make {msg: "expected one JSON object per line"}
      }
      $parsed
    }
}


def add-diagnostic [stderr: string message: string] {
  [$stderr $message]
  | where {|line| ($line | str trim) != "" }
  | str join "\n"
}


def mentions [body: string identity: string] {
  let suffixes = ($body | split row $"@($identity)" | skip 1)
  $suffixes | any {|suffix|
    if $suffix == "" {
      true
    } else {
      let next = ($suffix | split chars | first)
      not ($next =~ '^[A-Za-z0-9_.-]$')
    }
  }
}


def relevant-chat-message [message: record match: record] {
  let sender = $message.sender
  let body = $message.body
  if (
    ($sender | describe --detailed | get type) != "string"
    or ($body | describe --detailed | get type) != "string"
  ) {
    error make {msg: "Chat message sender and body must be strings"}
  }

  let unrestricted = (
    ($match.senders | is-empty)
    and ($match.mentions | is-empty)
  )
  let sender_matches = ($match.senders | any {|expected| $sender == $expected })
  let mention_matches = (
    $match.mentions
    | any {|identity| mentions $body $identity }
  )

  $sender != $match.identity and (
    $unrestricted
    or $sender_matches
    or $mention_matches
  )
}


# Batch only results already queued when the first source settles.
# A quiet source remains cancellable without adding a timing grace period.
export def collect-ready-results [first: record] {
  mut results = [$first]
  mut receiving = true

  while $receiving {
    let next = try {
      {received: true result: (job recv --timeout 0sec)}
    } catch {
      {received: false}
    }

    if $next.received {
      $results = ($results | append $next.result)
    } else {
      $receiving = false
    }
  }

  $results
}


def complete-waiter [waiter: record] {
  let result = try {
    run-external ...$waiter.command | complete
  } catch {|error|
    {
      stdout: ""
      stderr: $error.msg
      exit_code: 127
    }
  }
  {
    source: $waiter.source
    cursor_file: $waiter.cursor_file
    command: $waiter.command
    stdout: $result.stdout
    stderr: $result.stderr
    exit_code: $result.exit_code
  }
}


def complete-relevant-chat [waiter: record] {
  loop {
    let result = (complete-waiter $waiter)
    if $result.exit_code != 0 {
      return $result
    }

    let parsed = try {
      {valid: true records: (json-records $result.stdout)}
    } catch {
      {valid: false records: []}
    }
    if (not $parsed.valid) or ($parsed.records | is-empty) {
      return $result
    }

    let selected = try {
      {
        valid: true
        records: (
          $parsed.records
          | where {|message| relevant-chat-message $message $waiter.match }
        )
      }
    } catch {|error|
      {valid: false records: [] error: $error.msg}
    }
    if not $selected.valid {
      return (
        $result
        | upsert stdout ""
        | upsert stderr (
            add-diagnostic $result.stderr $"invalid Chat message: ($selected.error)"
          )
        | upsert exit_code 1
      )
    }

    if ($selected.records | is-not-empty) {
      let stdout = (
        $selected.records
        | each {|record| $record | to json -r }
        | str join "\n"
      )
      return ($result | upsert stdout $stdout)
    }
  }
}


def spawn-waiter [parent_id: int waiter: record] {
  let source = $waiter.source
  job spawn --description $source {
    let result = if $waiter.kind == "chat" {
      complete-relevant-chat $waiter
    } else {
      complete-waiter $waiter
    }
    $result | job send $parent_id
  } | ignore
}


def result-event [result: record] {
  let parsed = try {
    {valid: true records: (json-records $result.stdout)}
  } catch {|error|
    {valid: false records: [] error: $error.msg}
  }

  mut exit_code = $result.exit_code
  mut stderr = $result.stderr

  if not $parsed.valid {
    if $exit_code == 0 {
      $exit_code = 1
    }
    $stderr = (add-diagnostic $stderr $"invalid JSON from ($result.source): ($parsed.error)")
  } else if $exit_code == 0 and ($parsed.records | is-empty) {
    $exit_code = 1
    $stderr = (
      add-diagnostic $stderr $"($result.source) exited successfully without a JSON record"
    )
  }

  {
    source: $result.source
    cursor_file: $result.cursor_file
    exit_code: $exit_code
    records: $parsed.records
    stderr: $stderr
  }
}


def spawn-deadline [parent_id: int deadline] {
  if $deadline == null {
    return
  }

  job spawn --description "wait deadline" {
    loop {
      let remaining = $deadline - (date now)
      if $remaining <= 0sec {
        {coordinator_timeout: true} | job send $parent_id
        break
      }

      let pause = if $remaining < 1sec { $remaining } else { 1sec }
      sleep $pause
    }
  } | ignore
}


def timeout-event [timeout_seconds] {
  {
    source: "wait"
    cursor_file: null
    exit_code: 124
    records: [{event: "timeout" timeout_seconds: $timeout_seconds}]
    stderr: ""
  }
}


export def run-waiters [waiters: list<record> state_dir: string timeout: record] {
  mkdir $state_dir

  let parent_id = (job id)
  for waiter in $waiters {
    spawn-waiter $parent_id $waiter
  }
  spawn-deadline $parent_id $timeout.deadline

  let ready = (collect-ready-results (job recv))
  let results = (
    $ready
    | where {|result| not ($result.coordinator_timeout? | default false) }
  )
  if ($results | is-empty) {
    return {
      events: [(timeout-event $timeout.seconds)]
      exit_code: 0
    }
  }

  let events = ($results | each {|result| result-event $result })
  let failures = ($events | where exit_code != 0)
  let exit_code = if ($failures | is-empty) {
    0
  } else {
    $failures | first | get exit_code
  }

  {
    events: $events
    exit_code: $exit_code
  }
}
