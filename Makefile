.PHONY: build tag release

build:
	crystal build src/main.cr --release -o bin/faro

# Bump shard.yml version, tag, and push.
# Usage: make tag VERSION=x.y.z
#
# Steps:
#   1. Validates you're on master branch
#   2. Validates the new version > latest tag
#   3. Updates shard.yml with the new version
#   4. Runs specs
#   5. Commits, tags v$(VERSION) + latest, pushes
tag:
	@set -eu; \
	branch=$$(git branch --show-current); \
	if [ "$$branch" != "master" ]; then \
	  echo "ERROR: must be on master branch (current: $$branch)"; exit 1; \
	fi; \
	if ! git diff --quiet; then \
	  echo "ERROR: working tree has uncommitted changes"; exit 1; \
	fi; \
	\
	version="$(VERSION)"; \
	if [ -z "$$version" ]; then \
	  echo "Usage: make tag VERSION=x.y.z"; exit 1; \
	fi; \
	\
	latest_tag=$$(git tag -l 'v*' --sort=-version:refname | head -1); \
	latest_ver=""; \
	if [ -n "$$latest_tag" ]; then \
	  latest_ver=$${latest_tag#v}; \
	fi; \
	if [ -n "$$latest_ver" ]; then \
	  sorted=$$(printf '%s\n' "$$latest_ver" "$$version" | sort -V | head -1); \
	  if [ "$$sorted" != "$$latest_ver" ]; then \
	    echo "ERROR: new version v$$version is not greater than latest tag $$latest_tag"; exit 1; \
	  fi; \
	fi; \
	\
	sed -i "s/^version: .*/version: $$version/" shard.yml; \
	git add shard.yml; \
	git commit -m "Release v$$version"; \
	crystal spec; \
	git tag "v$$version"; \
	git tag -f latest; \
	git push origin master "v$$version" latest --force; \
	echo "Released v$$version"

release: build tag
