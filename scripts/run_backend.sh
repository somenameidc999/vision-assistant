#!/bin/sh
set -eu
cd "$(dirname "$0")/../backend"
if [ "$(node -p 'process.versions.node.split(".")[0]')" != 22 ]; then
  task_node_bin="$HOME/.nvm/versions/node/v22.22.3/bin"
  if [ ! -x "$task_node_bin/node" ]; then
    echo 'Select Node.js 22 with nvm use before running the backend.' >&2
    exit 1
  fi
  PATH="$task_node_bin:$PATH"
  export PATH
fi
exec npm start
