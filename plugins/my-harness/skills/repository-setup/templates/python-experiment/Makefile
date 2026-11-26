IMAGE ?= <image>
NAME ?= <package>-dev
RUN = docker run --rm -e PYTHONPATH=src -v "$(CURDIR)":/app -w /app $(IMAGE)

.PHONY: build up down test experiment

build:
	docker build -t $(IMAGE) .

up:
	docker run -d --name $(NAME) -e PYTHONPATH=src -v "$(CURDIR)":/app -w /app $(IMAGE) sleep infinity

down:
	docker rm -f $(NAME)

test:
	$(RUN) python -m pytest

experiment:
	$(RUN) python -m <package>.run $(wildcard research/*/experiments/$(EXP).yaml)
