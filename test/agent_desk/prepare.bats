#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load ../test_helper
load helpers
load shell
load prepare_helpers

setup() {
  setup_desk_test
  setup_shell_mock
}

@test "agent:desk:prepare dry-run plans an existing desk without mutation" {
  desk="$BATS_TEST_TMPDIR/desks/probe"
  mkdir -p "$desk/.desk"
  printf '{"id":"probe"}\n' > "$desk/.desk/registry.json"
  desk_path="$desk"

  run fold_task agent:desk:prepare quick \
    --desk "$desk" \
    --repo quick-ricon/home \
    --shell quick-probe \
    --packet /tmp/packet.md

  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent desk prepare"* ]]
  [[ "$output" == *"mode:    dry-run"* ]]
  [[ "$output" == *"desk:    $desk_path"* ]]
  [[ "$output" == *"home:    $desk_path/home"* ]]
  [[ "$output" == *"repo:    quick-ricon/home"* ]]
  [[ "$output" == *"dry-run: rerun with --yes"* ]]
  [[ "$output" == *"check auth prerequisites: mise run homes:auth quick --home $HOME --json --check"* ]]
  [[ "$output" == *"setup email: mise run homes:email:setup quick --home $desk_path/home --yes"* ]]
  [[ "$output" == *"mise run agent:desk:wake quick --desk $desk_path --shell quick-probe --packet /tmp/packet.md --model '<model>' --yes"* ]]
  [ ! -e "$desk/home" ]
}

@test "agent:desk:prepare --yes provisions an existing desk through homes primitives" {
  desk="$BATS_TEST_TMPDIR/desks/probe"
  mkdir -p "$desk/.desk"
  printf '{"id":"probe"}\n' > "$desk/.desk/registry.json"
  desk_path="$desk"
  write_fake_mise_for_prepare

  run fold_task agent:desk:prepare quick \
    --desk "$desk" \
    --repo quick-ricon/home \
    --shell quick-probe \
    --packet /tmp/packet.md \
    --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"== check auth prerequisites =="* ]]
  [[ "$output" == *"== adopt home =="* ]]
  [[ "$output" == *"== setup home email =="* ]]
  [[ "$output" == *"== verify home readiness =="* ]]
  [[ "$output" == *"Ready. Next wake command:"* ]]
  auth_line=$(
    grep -nF "mise run homes:auth quick --home $HOME --json --check" "$MISE_LOG" |
      cut -d: -f1
  )
  adopt_line=$(
    grep -nF \
      "mise run homes:adopt-remote quick --home $desk_path/home --branch main --yes --repo quick-ricon/home" \
      "$MISE_LOG" | cut -d: -f1
  )
  email_line=$(
    grep -nF "mise run homes:email:setup quick --home $desk_path/home --yes" "$MISE_LOG" |
      cut -d: -f1
  )
  status_line=$(
    grep -nF "mise run homes:status quick --home $desk_path/home --json --check" "$MISE_LOG" |
      cut -d: -f1
  )
  [ "$auth_line" -lt "$adopt_line" ]
  [ "$adopt_line" -lt "$email_line" ]
  [ "$email_line" -lt "$status_line" ]
  [ ! -e "$desk/.gitconfig" ]
  ! grep -q 'homes:auth:setup' "$MISE_LOG"
  [ -d "$desk/home/.git" ]
  [ -f "$desk/home/.emails/himalaya.toml" ]
  if [ -f "$SHELL_LOG" ]; then
    ! grep -q 'shell run' "$SHELL_LOG"
  fi
}

@test "agent:desk:prepare checks activated email inputs before creating a desk" {
  write_fake_mise_for_prepare
  write_fake_desks
  export FAKE_EMAIL_INPUTS_FAIL=true

  run fold_task agent:desk:prepare quick \
    --desk-id email-incomplete \
    --repo quick-ricon/home \
    --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *'incomplete email inputs'* ]]
  [ ! -s "$DESKS_LOG" ]
  ! grep -q 'homes:adopt-remote' "$MISE_LOG"
}

@test "agent:desk:prepare stops before creating a desk if persona activation fails" {
  write_fake_mise_for_prepare
  write_fake_desks
  export FAKE_PERSONA_FAIL=true

  run fold_task agent:desk:prepare quick \
    --desk-id persona-failed \
    --repo quick-ricon/home \
    --yes

  [ "$status" -ne 0 ]
  [ ! -s "$DESKS_LOG" ]
  ! grep -q 'homes:adopt-remote' "$MISE_LOG"
}

@test "agent:desk:prepare --skip-email excludes mail from the dry-run plan" {
  desk="$BATS_TEST_TMPDIR/desks/no-mail"
  mkdir -p "$desk"
  write_fake_mise_for_prepare

  run fold_task agent:desk:prepare quick \
    --desk "$desk" \
    --repo quick-ricon/home \
    --skip-email

  [ "$status" -eq 0 ]
  [[ "$output" == *"skip email: no mailbox provisioning or validation"* ]]
  [[ "$output" != *"homes:email:setup"* ]]
  [ ! -s "$MISE_LOG" ]
  [ ! -e "$desk/home" ]
}

@test "agent:desk:prepare --skip-email still prepares and verifies without invoking mail" {
  desk="$BATS_TEST_TMPDIR/desks/no-mail"
  mkdir -p "$desk"
  write_fake_mise_for_prepare

  run fold_task agent:desk:prepare quick \
    --desk "$desk" \
    --repo quick-ricon/home \
    --skip-email \
    --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"Ready. Next wake command:"* ]]
  [[ "$output" != *"homes:email:setup"* ]]
  ! grep -q 'homes:email:setup' "$MISE_LOG"
  grep -F "homes:status quick --home $desk/home --json --check" "$MISE_LOG"
  [ ! -e "$desk/.gitconfig" ]
  [ -d "$desk/home/.git" ]
  [ ! -e "$desk/home/.emails" ]
  [ ! -e "$SHELL_RUN_MARKER" ]
}

@test "agent:desk:prepare --yes can create a desk through desks new" {
  write_fake_mise_for_prepare
  write_fake_desks
  export FOLD_AGENT_DESK_PREPARE_TIMESTAMP=20260620133700

  run fold_task agent:desk:prepare quick \
    --purpose rewind-investigation \
    --repo quick-ricon/home \
    --packet /tmp/packet.md \
    --yes

  [ "$status" -eq 0 ]
  desk_id="quick-rewind-investigation-20260620133700"
  desk="$FAKE_DESKS_ROOT/$desk_id"
  grep -F "desks new --id $desk_id" "$DESKS_LOG" >/dev/null
  grep -F "desks path $desk_id" "$DESKS_LOG" >/dev/null
  auth_line=$(
    grep -nF "mise run homes:auth quick --home $HOME --json --check" "$MISE_LOG" |
      cut -d: -f1
  )
  adopt_line=$(
    grep -nF \
      "mise run homes:adopt-remote quick --home $desk/home --branch main --yes --repo quick-ricon/home" \
      "$MISE_LOG" | cut -d: -f1
  )
  email_line=$(
    grep -nF "mise run homes:email:setup quick --home $desk/home --yes" "$MISE_LOG" |
      cut -d: -f1
  )
  [ "$auth_line" -lt "$adopt_line" ]
  [ "$adopt_line" -lt "$email_line" ]
  [[ "$output" == *"desk id: $desk_id"* ]]
  [[ "$output" == *"mise run agent:desk:wake quick --desk $desk --shell $desk_id --packet /tmp/packet.md --model '<model>' --yes"* ]]
  [ -f "$desk/.desk/registry.json" ]
  [ ! -e "$desk/.gitconfig" ]
  [ -d "$desk/home/.git" ]
}

@test "agent:desk:prepare refuses missing auth prerequisites before creating a desk or provisioning" {
  write_fake_mise_for_prepare
  write_fake_desks
  export FAKE_AUTH_PREREQUISITES_FAIL=true

  run fold_task agent:desk:prepare quick \
    --desk-id blocked \
    --repo quick-ricon/home \
    --yes

  [ "$status" -ne 0 ]
  grep -q 'homes:auth .* --json --check' "$MISE_LOG"
  ! grep -Eq 'homes:auth:setup|homes:adopt-remote|homes:email:setup|homes:status' "$MISE_LOG"
  [ ! -s "$DESKS_LOG" ]
  [ ! -e "$FAKE_DESKS_ROOT/blocked" ]
}

@test "agent:desk:prepare preserves an existing workspace Git config" {
  desk="$BATS_TEST_TMPDIR/desks/existing-config"
  mkdir -p "$desk"
  printf '# existing workspace settings\n' > "$desk/.gitconfig"
  cp "$desk/.gitconfig" "$BATS_TEST_TMPDIR/before.gitconfig"
  write_fake_mise_for_prepare

  run fold_task agent:desk:prepare quick \
    --desk "$desk" \
    --repo quick-ricon/home \
    --yes

  [ "$status" -eq 0 ]
  cmp -s "$desk/.gitconfig" "$BATS_TEST_TMPDIR/before.gitconfig"
  ! grep -q 'homes:auth:setup' "$MISE_LOG"
}

@test "agent:desk:prepare refuses to mutate a missing explicit desk path" {
  write_fake_mise_for_prepare

  run fold_task agent:desk:prepare quick \
    --desk "$BATS_TEST_TMPDIR/missing-desk" \
    --repo quick-ricon/home \
    --yes

  [ "$status" -ne 0 ]
  [[ "${output}${stderr:-}" == *"explicit --desk path must already exist"* ]]
  [ ! -s "$MISE_LOG" ]
}

