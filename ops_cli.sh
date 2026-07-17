#!/bin/bash

CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/cli" && pwd)"

# shellcheck source=./cli/common.sh
source "$CLI_DIR/common.sh"
# shellcheck source=./cli/shell.sh
source "$CLI_DIR/shell.sh"
# shellcheck source=./cli/lifecycle.sh
source "$CLI_DIR/lifecycle.sh"
# shellcheck source=./cli/status.sh
source "$CLI_DIR/status.sh"
# shellcheck source=./cli/script.sh
source "$CLI_DIR/script.sh"
# shellcheck source=./cli/docker.sh
source "$CLI_DIR/docker.sh"
# shellcheck source=./cli/git.sh
source "$CLI_DIR/git.sh"
# shellcheck source=./cli/diagnose.sh
source "$CLI_DIR/diagnose.sh"
# shellcheck source=./cli/help.sh
source "$CLI_DIR/help.sh"
# shellcheck source=./cli/version.sh
source "$CLI_DIR/version.sh"

