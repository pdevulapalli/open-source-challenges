#!/usr/bin/env bash

get_repository_url() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    printf 'https://github.com/%s.git\n' "$GITHUB_REPOSITORY"
    return
  fi

  local origin_url
  origin_url="$(git remote get-url origin)"

  if [[ "$origin_url" =~ ^git@github\.com:(.+)$ ]]; then
    printf 'https://github.com/%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "$origin_url"
  fi
}