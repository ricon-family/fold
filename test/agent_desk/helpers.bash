setup_desk_test() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"
  export PATH="$TMPBIN:$PATH"
}

make_repo() {
  local repo="$1" name="$2"

  mkdir -p "$repo"
  git init -q -b main "$repo"

  if [ "$name" = home ]; then
    git -C "$repo" config user.name quick
    git -C "$repo" config user.email quick@ricon.family
  else
    git -C "$repo" config user.name fixture
    git -C "$repo" config user.email fixture@example.test
  fi
  git -C "$repo" config user.signingkey AABBCCDDEEFF0011
  git -C "$repo" config commit.gpgsign false

  printf '%s\n' "$name" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial $name"

  if [ "$name" = home ]; then
    git -C "$repo" config commit.gpgsign true
    git -C "$repo" remote add origin https://github.com/quick-ricon/home.git
  fi
}
