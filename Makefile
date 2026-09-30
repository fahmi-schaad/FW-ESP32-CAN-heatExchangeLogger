# Build chain for the ESP32 CAN heat exchanger logger. Run `make help`.

VENV      ?= .venv
PY        := $(VENV)/bin/python
ESPHOME   := $(VENV)/bin/esphome
CONFIG    ?= heat-exchanger-logger.yaml
# CONFIG=heat-exchanger-logger-discovery.yaml for the commissioning variant.
# Upload/log target: serial port (/dev/ttyUSB0), IP/hostname, or OTA (default: ask).
DEVICE    ?=
DEVICE_ARG = $(if $(DEVICE),--device $(DEVICE),)
BUILD_DIR := build

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}'
	@echo ""
	@echo "  Variables: CONFIG=$(CONFIG)  DEVICE=<port|ip>"

$(VENV)/.installed: requirements.txt
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r requirements.txt
	touch $@

.PHONY: setup
setup: $(VENV)/.installed esphome/secrets.yaml ## Create the Python venv with pinned ESPHome + secrets.yaml

esphome/secrets.yaml:
	sed "s|GENERATED_BY_make_secrets|$$(openssl rand -base64 32)|" esphome/secrets.yaml.example > $@
	@echo ">> Created $@ with a random API key - now fill in your WiFi credentials."

.PHONY: secrets
secrets: esphome/secrets.yaml ## Create esphome/secrets.yaml from the example (random API key)

.PHONY: config
config: setup ## Validate the ESPHome configuration
	cd esphome && ../$(ESPHOME) config $(CONFIG) > /dev/null && echo "$(CONFIG): valid"

.PHONY: compile
compile: setup ## Build the firmware (binary copied to build/)
	cd esphome && ../$(ESPHOME) compile $(CONFIG)
	@mkdir -p $(BUILD_DIR)
	@cp esphome/.esphome/build/heat-exchanger-logger/build/firmware.factory.bin $(BUILD_DIR)/heat-exchanger-logger.factory.bin
	@cp esphome/.esphome/build/heat-exchanger-logger/build/firmware.ota.bin $(BUILD_DIR)/heat-exchanger-logger.ota.bin
	@echo ">> $(BUILD_DIR)/heat-exchanger-logger.factory.bin (serial/web flasher), .ota.bin (OTA)"

.PHONY: upload
upload: setup ## Build + flash via USB (first time) or OTA: make upload DEVICE=/dev/ttyUSB0
	@# `esphome upload` alone flashes the LAST build (possibly with stale secrets): always rebuild.
	cd esphome && ../$(ESPHOME) run --no-logs $(CONFIG) $(DEVICE_ARG)

.PHONY: run
run: setup ## Compile, flash and follow logs
	cd esphome && ../$(ESPHOME) run $(CONFIG) $(DEVICE_ARG)

.PHONY: logs
logs: setup ## Follow device logs
	cd esphome && ../$(ESPHOME) logs $(CONFIG) $(DEVICE_ARG)

.PHONY: capture
capture: setup ## Record the device log to captures/ (for protocol debugging, see docs)
	@mkdir -p captures
	@f=captures/log-$$(date +%Y%m%d-%H%M%S).log; echo ">> Logging to $$f - Ctrl+C to stop"; \
	cd esphome && ../$(ESPHOME) logs $(CONFIG) $(DEVICE_ARG) | tee ../$$f

.PHONY: dashboard
dashboard: setup ## Start the ESPHome web dashboard on http://localhost:6052
	$(ESPHOME) dashboard esphome

.PHONY: lint
lint: setup ## yamllint + Home Assistant template/entity consistency check
	$(VENV)/bin/yamllint -s .
	$(PY) tools/check_ha_config.py

.PHONY: vendor
vendor: ## Regenerate esphome/components/toptronic (upstream@ref + patches/toptronic)
	tools/vendor_toptronic.sh

.PHONY: vendor-check
vendor-check: ## Verify the vendored toptronic is exactly upstream@ref + patches
	tools/vendor_toptronic.sh --check

.PHONY: check
check: lint vendor-check config ## Everything CI runs except the (slow) compile
	cd esphome && ../$(ESPHOME) config heat-exchanger-logger-discovery.yaml > /dev/null && echo "discovery: valid"

.PHONY: clean
clean: ## Remove build output (keeps venv and secrets)
	rm -rf $(BUILD_DIR) esphome/.esphome/build

.PHONY: distclean
distclean: clean ## Remove everything generated incl. venv and PlatformIO cache in esphome/.esphome
	rm -rf $(VENV) esphome/.esphome
