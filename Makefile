.PHONY: ci lint terraform-fmt-check deploy

# Mirrors the shared workflow at chris-arsenault/ahara/.github/workflows/ci.yml.
ci: lint terraform-fmt-check

lint:
	node --check infrastructure/terraform/lambda/discord/index.mjs

terraform-fmt-check:
	terraform fmt -check -recursive infrastructure/terraform/

deploy:
	scripts/deploy.sh
