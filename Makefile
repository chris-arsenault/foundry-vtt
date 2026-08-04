.PHONY: ci lint fmt test terraform-fmt-check build deploy

# Mirrors the shared workflow at chris-arsenault/ahara/.github/workflows/ci.yml.
ci: lint fmt test terraform-fmt-check

lint:
	cd backend && CARGO_TARGET_DIR=target-clippy cargo clippy --release -- -D warnings -W clippy::cognitive_complexity

fmt:
	cd backend && cargo fmt -- --check

test:
	cd backend && CARGO_TARGET_DIR=target-cov cargo test --release

terraform-fmt-check:
	terraform fmt -check -recursive infrastructure/terraform/

build:
	cd backend && cargo lambda build --release

deploy:
	scripts/deploy.sh
