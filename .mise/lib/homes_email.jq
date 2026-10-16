# Project the caller's activated email environment. Never print the result.
def required($name):
  .[$name] as $value
  | if ($value | type) == "string" and ($value | length) > 0
      and ($value | explode | all(. >= 32 and . != 127))
    then $value else error("incomplete email environment") end;

def transport($prefix):
  {
    host: required($prefix + "_HOST"),
    port: (required($prefix + "_PORT") | tonumber),
    encryption: required($prefix + "_ENCRYPTION"),
    username: required($prefix + "_USERNAME"),
    password: required($prefix + "_PASSWORD")
  }
  | if (.port == (.port | floor) and .port >= 1 and .port <= 65535)
      and (.encryption == "tls" or .encryption == "starttls")
    then . else error("invalid email transport") end;

env as $environment
| $environment
| (required("EMAIL_ACCOUNTS") | split(" ")) as $labels
| required("EMAIL_DEFAULT_ACCOUNT") as $default
| if ($labels | length) == ($labels | unique | length)
    and all($labels[]; test("^[a-z][a-z0-9_]*$"))
    and ($labels | index($default)) != null
  then . else error("invalid email account selection") end
| [
    $labels[] as $label
    | ("EMAIL_" + ($label | ascii_upcase)) as $prefix
    | $environment
    | {
        label: $label,
        address: required($prefix + "_ADDRESS"),
        display_name: required($prefix + "_DISPLAY_NAME"),
        signer: required($prefix + "_SIGNING_FINGERPRINT"),
        default: ($label == $default),
        imap: transport($prefix + "_IMAP"),
        smtp: transport($prefix + "_SMTP")
      }
    | if (.signer | test("^([A-F0-9]{40}|[A-F0-9]{64})$"))
      then . else error("invalid email signing fingerprint") end
  ]
