#!/bin/bash

CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/cli" && pwd)"

source "$CLI_DIR/common.sh"
source "$CLI_DIR/shell.sh"
source "$CLI_DIR/lifecycle.sh"
source "$CLI_DIR/status.sh"
source "$CLI_DIR/script.sh"
source "$CLI_DIR/docker.sh"
source "$CLI_DIR/git.sh"
source "$CLI_DIR/diagnose.sh"
source "$CLI_DIR/help.sh"
