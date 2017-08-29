#!/bin/sh
# Cleanup docker files: untagged containers and images.
#
# Use `docker-cleanup -n` for a dry run to see what would be deleted.

untagged_containers() {
	# Print containers using untagged images: $1 is used with awk's print: 0=line, 1=column 1.
	docker ps -a -f status=exited | awk '$2 ~ "[0-9a-f]{12}" {print $'$1'}'
}

compose_run_containers() {
	docker ps -a -f status=exited | egrep '_run_[0-9]{1,2}' | sed 's/ .*//'
}

non_compose_containers() {
        # random name foo_bar, like pedantic_euclid
	# extra filter to make sure we don't remove compose containers like nginx_nginx_1
	docker ps -a -f status=exited | egrep ' [a-z]+_[a-z]+$'  | egrep -v '_[0-9]{1,2}' | sed 's/ .*//'
}

untagged_images() {
	# Print untagged images: $1 is used with awk's print: 0=line, 3=column 3.
	# NOTE: intermediate images (via -a) seem to only cause
	# "Error: Conflict, foobarid wasn't deleted" messages.
	# Might be useful sometimes when Docker messed things up?!
	# docker images -a | awk '$1 == "<none>" {print $'$1'}'
	docker images | tail -n +2 | awk '$1 == "<none>" {print $'$1'}'
}

# Dry-run.
if [ "$1" = "-n" ]; then
	echo "=== Containers with uncommitted images: ==="
	untagged_containers 0
	echo

	echo "=== Uncommitted images: ==="
	untagged_images 0

	exit
fi

# Remove containers with untagged images.
echo "Removing untagged containers:" >&2
untagged_containers 1 | xargs docker rm --volumes=true
echo "Removing compose run containers:" >&2
compose_run_containers 1 | xargs docker rm --volumes=true
echo "Removing non-compose containers:" >&2
non_compose_containers 1 | xargs docker rm --volumes=true

# Remove untagged images
echo "Removing images:" >&2
untagged_images 3 | xargs docker rmi
