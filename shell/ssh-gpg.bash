# shellcheck shell=bash

SSH_ENV="$HOME/.ssh/agent-environment"

start_agent() {
  /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
  chmod 600 "${SSH_ENV}"
  . "${SSH_ENV}" > /dev/null
}

if [ -f "${SSH_ENV}" ]; then
  . "${SSH_ENV}" > /dev/null
  if [ -z "${SSH_AGENT_PID:-}" ] || ! kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
    start_agent
  fi
else
  start_agent
fi

export GPG_TTY
GPG_TTY=$(tty)
