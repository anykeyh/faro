.PHONY: build tag release docker-build

build:
	crystal build src/main.cr --release -o bin/faro

docker-build:
	docker build --target builder -t faro-builder .
	id=$$(docker create faro-builder); \
	docker cp $$id:/build/faro bin/faro; \
	docker rm $$id > /dev/null

# Tag a release.
# Usage: make tag VERSION=x.y.z
#
# Steps:
#   1. Checks you're on master branch
#   2. Checks working tree is clean
#   3. Checks shard.yml version matches VERSION
#   4. Validates new version > latest tag
#   5. Runs specs
#   6. Tags v$(VERSION) + latest, pushes
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
	file_ver=$$(grep '^version:' shard.yml | sed 's/^version: *"//;s/"//'); \
	if [ "$$file_ver" != "$$version" ]; then \
	  echo "ERROR: shard.yml version is \"$$file_ver\" but VERSION is \"$$version\""; \
	  echo "Update shard.yml to match and commit first."; \
	  exit 1; \
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
	    echo "ERROR: version v$$version is not greater than latest tag $$latest_tag"; exit 1; \
	  fi; \
	fi; \
	\
	crystal spec; \
	git tag "v$$version"; \
	git tag -f latest; \
	git push origin master "v$$version" latest --force; \
	echo "Released v$$version"

release: tag
