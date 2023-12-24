.PHONY: demo-drone

demo-drone:
	docker build --tag toolbox:local --build-arg platform=amd64 .
	./scripts/drone.sh
