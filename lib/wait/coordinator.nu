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


def spawn-waiter [parent_id: int waiter: record] {
  let source = $waiter.source
  let cursor_file = $waiter.cursor_file
  let command = $waiter.command
  job spawn --description $source {
    let result = try {
      run-external ...$command | complete
    } catch {|error|
      {
        stdout: ""
        stderr: $error.msg
        exit_code: 127
      }
    }
    {
      source: $source
      cursor_file: $cursor_file
      command: $command
      stdout: $result.stdout
      stderr: $result.stderr
      exit_code: $result.exit_code
    } | job send $parent_id
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


def receive-first [timeout: record] {
  if $timeout.duration == null {
    {timed_out: false result: (job recv)}
  } else {
    try {
      {timed_out: false result: (job recv --timeout $timeout.duration)}
    } catch {
      {timed_out: true}
    }
  }
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

  let received = (receive-first $timeout)
  if $received.timed_out {
    {
      events: [(timeout-event $timeout.seconds)]
      exit_code: 0
    }
  } else {
    let results = (collect-ready-results $received.result)
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
}
