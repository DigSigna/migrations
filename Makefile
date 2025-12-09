DATABASE_URL=mysql://root:password@tcp(localhost:3306)/hsm

up:
	@DATABASE_URL=$(DATABASE_URL) ./scripts/migrate.sh up

down:
	@DATABASE_URL=$(DATABASE_URL) ./scripts/migrate.sh down

force:
	@DATABASE_URL=$(DATABASE_URL) migrate -path=migrations -database=$(DATABASE_URL) force $(version)

new:
	@test $(name)
	migrate create -ext sql -dir migrations -seq $(name)


# Build and push Docker image to GitHub Container Registry
# recibe version number as argument
#use: make build-push version=1.0.0
build-push:
	@echo "Building and pushing to GitHub Container Registry..."
	
	docker build -t ghcr.io/digsigna/migrations/migrations:${version} .
	docker push ghcr.io/digsigna/migrations/migrations:${version}
	@echo "Done."
