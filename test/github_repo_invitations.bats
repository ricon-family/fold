#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  setup_github_invite_mocks
}

@test "github:repo:invite dry-run resolves agent targets without mutating" {
  run fold_task github:repo:invite rikonor/ideas --to rho --permission write
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run. Rerun with --yes"* ]]
  [[ "$output" == *"rho (rho-ricon)"* ]]
  run ! grep -q -- '-X PUT' "$MOCK_GH_LOG"
}

@test "github:repo:invite --yes sends collaborator invitation with normalized permission" {
  run fold_task github:repo:invite rikonor/ideas --to rho --permission write --yes
  [ "$status" -eq 0 ]
  grep -q 'ARGS=api -X PUT /repos/rikonor/ideas/collaborators/rho-ricon -f permission=push' "$MOCK_GH_LOG"
  [[ "$output" == *"rho"*"rho-ricon"*"ok"* ]]
}

@test "github:repo:invite can use an agent token as actor" {
  run fold_task github:repo:invite rikonor/ideas --as rho --to quick --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"actor:     rho-ricon"* ]]
  grep -q 'GH_TOKEN=token-rho ARGS=api -X PUT /repos/rikonor/ideas/collaborators/quick-ricon -f permission=push' "$MOCK_GH_LOG"
}

@test "github:repo:accept-invite dry-run shows pending exact repo invitation" {
  run fold_task github:repo:accept-invite rikonor/ideas --as rho
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run. Rerun with --yes"* ]]
  [[ "$output" == *"rho"*"rho-ricon"*"pending"* ]]
  run ! grep -q -- '-X PATCH' "$MOCK_GH_LOG"
}

@test "github:repo:accept-invite --yes accepts exact repo invitation" {
  run fold_task github:repo:accept-invite rikonor/ideas --as rho --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"rho"*"rho-ricon"*"accepted"*"WRITE"* ]]
  grep -q 'GH_TOKEN=token-rho ARGS=api -X PATCH /user/repository_invitations/321' "$MOCK_GH_LOG"
  run ! grep -q 'repository_invitations/322' "$MOCK_GH_LOG"
  run ! grep -q 'repository_invitations/323' "$MOCK_GH_LOG"
}

@test "github:repo:accept-invite reports no matching invite and current permission" {
  run fold_task github:repo:accept-invite rikonor/ideas --as quick --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"quick"*"quick-ricon"*"none-found"*"no-access"* ]]
  run ! grep -q -- '-X PATCH' "$MOCK_GH_LOG"
}
