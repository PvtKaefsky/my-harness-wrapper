IMAGE ?= <image>
NAME ?= <package>-dev
RUN = docker run --rm -e PYTHONPATH=src -v "$(CURDIR)":/app -w /app $(IMAGE)
HYP ?= *
EXP_FILES = $(wildcard research/$(HYP)/experiments/$(EXP).yaml)

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
	$(if $(filter 1,$(words $(EXP_FILES))),,$(error EXP=$(EXP) HYP=$(HYP) matches $(words $(EXP_FILES)) override files: [$(EXP_FILES)]; pass HYP=<hypothesis directory>))
	$(RUN) python -m <package>.run $(EXP_FILES)
