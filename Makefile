.PHONY: demo-drone

demo-drone:
	docker build --tag toolbox:local --build-arg platform=amd64 -f toolbox/Dockerfile toolbox/
	./scripts/drone.sh
