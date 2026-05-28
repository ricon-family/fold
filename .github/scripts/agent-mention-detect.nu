#!/usr/bin/env nu
# Experimental Nushell port of agent-mention-detect.py.
#
# Keep this alongside the Python detector while we compare readability and CI
# setup cost. Run locally with:
#   mise exec aqua:nushell/nushell@0.111.0 -- nu .github/scripts/agent-mention-detect.nu

const mention_regex = '(?<![\w/.-])@(?P<name>[A-Za-z0-9][A-Za-z0-9-]*)\b'


def csv-env [name: string, default: string] {
  $env
  | get --optional $name
  | default $default
  | split row ','
  | each { |item| $item | str trim | str downcase }
  | where { |item| not ($item | is-empty) }
}


def strip-non-waking-text [body: string] {
  mut kept = []
  mut in_fence = false

  for line in ($body | lines) {
    let trimmed = ($line | str trim)
    let is_fence = (($trimmed | str starts-with '```') or ($trimmed | str starts-with '~~~'))

    if $is_fence {
      if $in_fence {
        $in_fence = false
      } else {
        $in_fence = true
      }
      continue
    }

    if $in_fence {
      continue
    }

    if ($line | str trim --left | str starts-with '>') {
      continue
    }

    $kept = ($kept | append $line)
  }

  $kept | str join (char newline)
}


def write-output [name: string, value: string] {
  let output_path = ($env.GITHUB_OUTPUT? | default '')

  if ($output_path | is-empty) {
    print $'($name)=($value)'
    return
  }

  if ($value | str contains '\n') {
    let delimiter = $'EOF_(random uuid | str replace --all "-" "")'
    $'($name)<<($delimiter)(char newline)($value)(char newline)($delimiter)(char newline)' | save --append $output_path
  } else {
    $'($name)=($value)(char newline)' | save --append $output_path
  }
}


def agent-output-name [agent: string] {
  $agent | str replace --all '-' '_'
}


def set-no-wake [reason: string, roster: list<string>] {
  write-output should_wake 'false'
  write-output reason $reason
  write-output matched_agents '[]'

  for agent in $roster {
    write-output $'agent_(agent-output-name $agent)' 'false'
  }

  write-output message ''
}


def mention-labels [mentions: list<string>] {
  $mentions | each { |mention| $'@($mention)' } | str join ', '
}


def build-message [event: record, matched_agents: list<string>, matched_mentions: list<string>] {
  let repo = $event.repository.full_name
  let issue = $event.issue
  let comment = $event.comment
  let thread_kind = (if ('pull_request' in $issue) { 'pull request' } else { 'issue' })
  let author = $comment.user.login
  let association = ($comment.author_association? | default 'UNKNOWN')
  let body = ($comment.body? | default '')

  [
    $'You were mentioned in a GitHub ($thread_kind) comment.'
    ''
    $'Repository: ($repo)'
    $'Thread: ($repo)#($issue.number) — ($issue.title? | default "")'
    $'Thread URL: ($issue.html_url? | default "")'
    $'Triggering comment: ($comment.html_url? | default "")'
    $'Comment author: @($author) (($association))'
    $'Matched mentions: (mention-labels $matched_mentions)'
    $'Matched agents: ($matched_agents | str join ", ")'
    ''
    'Please orient normally, inspect the GitHub thread yourself before responding, and reply on the thread if useful. Do not rely solely on this wake packet for context.'
    ''
    'Triggering comment body:'
    '---'
    $body
    '---'
  ] | str join (char newline)
}


def main [] {
  let event_path = ($env.GITHUB_EVENT_PATH? | default '')
  if ($event_path | is-empty) {
    print --stderr 'GITHUB_EVENT_PATH is required'
    exit 2
  }

  let event = (open $event_path)
  let roster = (csv-env AGENT_ROSTER quick)
  let aliases = (csv-env TEAM_ALIASES agents)
  let allowed_associations = (csv-env ALLOWED_ASSOCIATIONS 'OWNER,MEMBER,COLLABORATOR' | each { |item| $item | str upcase })
  let association = ($event.comment.author_association? | default 'UNKNOWN' | str upcase)

  if not ($association in $allowed_associations) {
    set-no-wake $'comment author association ($association) is not allowed' $roster
    return
  }

  let body = ($event.comment.body? | default '')
  let stripped_body = (strip-non-waking-text $body)
  let mentions = ($stripped_body | parse --regex $mention_regex | get name | each { |name| $name | str downcase })

  mut matched_agents = []
  mut matched_mentions = []

  for mention in $mentions {
    if ($mention in $roster) {
      $matched_agents = ($matched_agents | append $mention | uniq)
      $matched_mentions = ($matched_mentions | append $mention)
    } else if ($mention in $aliases) {
      $matched_agents = ($matched_agents | append $roster | uniq)
      $matched_mentions = ($matched_mentions | append $mention)
    }
  }

  let ordered_agents = ($roster | where { |agent| $agent in $matched_agents })
  if ($ordered_agents | is-empty) {
    set-no-wake 'no agent mention found outside quotes/code' $roster
    return
  }

  for agent in $roster {
    write-output $'agent_(agent-output-name $agent)' (if ($agent in $matched_agents) { 'true' } else { 'false' })
  }

  write-output should_wake 'true'
  write-output reason 'matched agent mention'
  write-output matched_agents ($ordered_agents | to json -r)
  write-output message (build-message $event $ordered_agents $matched_mentions)
}
