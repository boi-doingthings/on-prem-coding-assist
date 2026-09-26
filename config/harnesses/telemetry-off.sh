# Source in lab images / student shells: turns off harness product telemetry
# and auto-update phone-home. Review after each harness upgrade.
export OPENCODE_DISABLE_AUTOUPDATE=true OPENCODE_DISABLE_SHARE=true OPENCODE_DISABLE_MODELS_FETCH=true
export KILO_TELEMETRY_LEVEL=off
export CRUSH_DISABLE_METRICS=1 CRUSH_DISABLE_PROVIDER_AUTO_UPDATE=1 DO_NOT_TRACK=1
export QWEN_USAGE_STATISTICS_ENABLED=false
export GOOSE_TELEMETRY_ENABLED=false
export PI_TELEMETRY=0 PI_OFFLINE=1
export TABBY_DISABLE_USAGE_COLLECTION=1
export HARBOR_TELEMETRY=off
# Not env-controlled: aider --analytics-disable; Codex [analytics] enabled=false;
# Zed telemetry.metrics/diagnostics=false; Cline/VS Code telemetry.telemetryLevel=off.
