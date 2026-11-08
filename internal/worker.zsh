# invoked in worker: _p9k_worker_main <pgid>
function _p9k_worker_main() {
  local -i reset poll
  local -F t
  local req fd
  local -a ready
  local _p9k_worker_request_id
  local -A _p9k_worker_fds       # fd => id$'\x1f'callback
  local -A _p9k_worker_jobs      # fd => start-time$'\x1f'pid
  local -A _p9k_worker_inflight  # id => inflight count
  # Async jobs running longer than this are presumed hung. The realtime time job sleeps for up to one interval.
  local -i _p9k_worker_timeout=$(( 60 + ${_POWERLEVEL9K_EXPERIMENTAL_TIME_REALTIME_INTERVAL_SEC:-0} ))

  function _p9k_worker_reply() {
    print -nr -- e${(pj:\n:)@}$'\x1e' || kill -- -$_p9k_worker_pgid
  }

  # usage: _p9k_worker_async <work> <callback>
  function _p9k_worker_async() {
    local fd async=$1
    sysopen -r -o cloexec -u fd <(() { eval $async; } </dev/null && print -n '\x1e') || return
    (( ++_p9k_worker_inflight[$_p9k_worker_request_id] ))
    _p9k_worker_fds[$fd]=$_p9k_worker_request_id$'\x1f'$2
    _p9k_worker_jobs[$fd]=$EPOCHSECONDS$'\x1f'$sysparams[procsubstpid]
  }

  # usage: _p9k_worker_kill_tree <pid>
  #
  # Sends SIGTERM to <pid> and all its descendants. The pid of an async job is its process
  # substitution subshell; the commands doing the actual work are its children, which a plain
  # `kill <pid>` would leave running (reparented to init) after a timeout.
  function _p9k_worker_kill_tree() {
    local -a pids=($1) lines words
    local -A children
    local line
    lines=(${(f)"$(command ps -A -o pid= -o ppid= 2>/dev/null)"})
    for line in $lines; do
      words=(${=line})
      (( $#words == 2 )) && children[$words[2]]+=" $words[1]"
    done
    # Collect the whole tree before killing anything: killed processes get reparented.
    local -i i=1
    while (( i <= $#pids && $#pids < 1000 )); do
      pids+=(${=children[$pids[i]]})
      (( ++i ))
    done
    kill -- $pids 2>/dev/null
  }

  trap '' PIPE

  {
    command mkfifo -m 600 -- $_p9k__worker_file_prefix.fifo || return
    echo -nE - s$_p9k_worker_pgid$'\x1e'             || return
    exec <$_p9k__worker_file_prefix.fifo             || return
    zf_rm -- $_p9k__worker_file_prefix.fifo          || return

    while true; do
      for fd in ${(k)_p9k_worker_jobs}; do
        (( EPOCHSECONDS - ${_p9k_worker_jobs[$fd]%%$'\x1f'*} >= _p9k_worker_timeout )) || continue
        _p9k_worker_kill_tree ${_p9k_worker_jobs[$fd]#*$'\x1f'}
        _p9k_worker_request_id=${_p9k_worker_fds[$fd]%%$'\x1f'*}
        unset "_p9k_worker_fds[$fd]" "_p9k_worker_jobs[$fd]"
        exec {fd}>&-
        poll=1
        if (( --_p9k_worker_inflight[$_p9k_worker_request_id] == 0 )); then
          unset "_p9k_worker_inflight[$_p9k_worker_request_id]"
          print -rn -- d$_p9k_worker_request_id$'\x1e' || return
        fi
      done
      if (( poll || $#_p9k_worker_fds )); then
        # Wake up periodically while jobs are running to enforce the timeout, and once more after
        # a job finishes: zsh reaps exited children only after zselect returns.
        poll=0
        t=$EPOCHREALTIME
        zselect -t 100 -a ready 0 ${(k)_p9k_worker_fds} || {
          # Status 1 means timeout or error. Only a timeout takes this long.
          (( $? == 1 && EPOCHREALTIME - t >= 0.5 )) || return
          continue
        }
      else
        zselect -a ready 0 || return
      fi
      [[ $ready[1] == -r ]] || return
      for fd in ${ready:1}; do
        if [[ $fd == 0 ]]; then
          local buf=
          [[ -t 0 ]]  # https://www.zsh.org/mla/workers/2020/msg00207.html
          if sysread -t 0 'buf[$#buf+1]'; then
            while [[ $buf != *$'\x1e' ]]; do
              sysread 'buf[$#buf+1]' || return
            done
          else
            (( $? == 4 )) || return
          fi
          for req in ${(ps:\x1e:)buf}; do
            _p9k_worker_request_id=${req%%$'\x1f'*}
            () { eval $req[$#_p9k_worker_request_id+2,-1] }
            (( $+_p9k_worker_inflight[$_p9k_worker_request_id] )) && continue
            print -rn -- d$_p9k_worker_request_id$'\x1e' || return
          done
        else
          local REPLY=
          while true; do
            if sysread -i $fd 'REPLY[$#REPLY+1]'; then
              [[ $REPLY == *$'\x1e' ]] || continue
            else
              (( $? == 5 ))            || return
              break
            fi
          done
          local cb=$_p9k_worker_fds[$fd]
          _p9k_worker_request_id=${cb%%$'\x1f'*}
          unset "_p9k_worker_fds[$fd]" "_p9k_worker_jobs[$fd]"
          exec {fd}>&-
          poll=1
          if [[ $REPLY == *$'\x1e' ]]; then
            REPLY[-1]=""
            () { eval $cb[$#_p9k_worker_request_id+2,-1] }
          fi
          if (( --_p9k_worker_inflight[$_p9k_worker_request_id] == 0 )); then
            unset "_p9k_worker_inflight[$_p9k_worker_request_id]"
            print -rn -- d$_p9k_worker_request_id$'\x1e' || return
          fi
        fi
      done
    done
  } always {
    kill -- -$_p9k_worker_pgid
  }
}

# invoked in master: _p9k_worker_invoke <request-id> <list>
function _p9k_worker_invoke() {
  [[ -n $_p9k__worker_resp_fd ]] || return
  local req=$1$'\x1f'$2$'\x1e'
  if [[ -n $_p9k__worker_req_fd && $+_p9k__worker_request_map[$1] == 0 ]]; then
    _p9k__worker_request_map[$1]=
    print -rnu $_p9k__worker_req_fd -- $req
  else
    _p9k__worker_request_map[$1]=$req
  fi
}

function _p9k_worker_cleanup() {
  # __p9k_intro bugs out here in some cases for some reason.
  emulate -L zsh
  [[ $_p9k__worker_shell_pid == $sysparams[pid] ]] && _p9k_worker_stop
  return 0
}

function _p9k_worker_stop() {
  # See comments in _p9k_worker_cleanup.
  emulate -L zsh
  add-zsh-hook -D zshexit _p9k_worker_cleanup
  [[ -n $_p9k__worker_resp_fd     ]] && zle -F $_p9k__worker_resp_fd
  [[ -n $_p9k__worker_resp_fd     ]] && exec {_p9k__worker_resp_fd}>&-
  [[ -n $_p9k__worker_req_fd      ]] && exec {_p9k__worker_req_fd}>&-
  [[ -n $_p9k__worker_pid         ]] && kill -- -$_p9k__worker_pid 2>/dev/null
  [[ -n $_p9k__worker_file_prefix ]] && zf_rm -f -- $_p9k__worker_file_prefix.fifo
  _p9k__worker_pid=
  _p9k__worker_req_fd=
  _p9k__worker_resp_fd=
  _p9k__worker_shell_pid=
  _p9k__worker_request_map=()
  return 0
}

function _p9k_worker_receive() {
  eval "$__p9k_intro"

  [[ -z $_p9k__worker_resp_fd ]] && return

  {
    (( $# <= 1 )) || return

    local buf resp

    [[ -t $_p9k__worker_resp_fd ]]  # https://www.zsh.org/mla/workers/2020/msg00207.html
    if sysread -i $_p9k__worker_resp_fd -t 0 'buf[$#buf+1]'; then
      while [[ $buf == *[^$'\x05\x1e']$'\x05'# ]]; do
        sysread -i $_p9k__worker_resp_fd 'buf[$#buf+1]' || return
      done
    else
      (( $? == 4 )) || return
    fi

    local -i reset max_reset
    for resp in ${(ps:\x1e:)${buf//$'\x05'}}; do
      local arg=$resp[2,-1]
      case $resp[1] in
        d)
          local req=$_p9k__worker_request_map[$arg]
          if [[ -n $req ]]; then
            _p9k__worker_request_map[$arg]=
            print -rnu $_p9k__worker_req_fd -- $req                                   || return
          else
            unset "_p9k__worker_request_map[$arg]"
          fi
        ;;
        e)
          () { eval $arg }
          (( reset > max_reset )) && max_reset=reset
        ;;
        s)
          [[ -z $_p9k__worker_req_fd ]]                                               || return
          [[ $arg == <1->        ]]                                                   || return
          _p9k__worker_pid=$arg
          sysopen -w -o cloexec -u _p9k__worker_req_fd $_p9k__worker_file_prefix.fifo || return
          local req=
          for req in $_p9k__worker_request_map; do
            print -rnu $_p9k__worker_req_fd -- $req                                   || return
          done
          _p9k__worker_request_map=({${(k)^_p9k__worker_request_map},''})
        ;;
        *)
          return 1
        ;;
      esac
    done

    if (( max_reset == 2 )); then
      _p9k__refresh_reason=worker
      _p9k_set_prompt
      _p9k__refresh_reason=''
    fi
    (( max_reset )) && _p9k_reset_prompt
    return 0
  } always {
    (( $? )) && _p9k_worker_stop
  }
}

function _p9k_worker_start() {
  setopt monitor || return
  {
    [[ -n $_p9k__worker_resp_fd ]] && return

    # The worker runs in /, so a relative TMPDIR must be made absolute.
    local tmpdir=$TMPDIR
    [[ $tmpdir == /* ]] || tmpdir=${tmpdir:a}
    if [[ -z $TMPDIR || ( ! ( -d $tmpdir && -w $tmpdir ) && -d /tmp && -w /tmp ) ]]; then
      tmpdir=/tmp
    fi
    _p9k__worker_file_prefix=$tmpdir/p10k.worker.$EUID.$sysparams[pid].$EPOCHSECONDS.$RANDOM$RANDOM

    sysopen -r -o cloexec -u _p9k__worker_resp_fd <(
      exec 0</dev/null
      if [[ -n $_POWERLEVEL9K_WORKER_LOG_LEVEL ]]; then
        local -i log_fd
        sysopen -w -m 600 -o creat,excl,nofollow -u log_fd -- $_p9k__worker_file_prefix.log || return
        exec 2>&$log_fd {log_fd}>&-
        setopt xtrace
      else
        exec 2>/dev/null
      fi
      builtin cd -q /                    || return
      zmodload zsh/zselect               || return
      ! { zselect -t0 || (( $? != 1 )) } || return
      local _p9k_worker_pgid=$sysparams[pid]
      _p9k_worker_main &
      {
        trap '' PIPE
        while syswrite $'\x05'; do zselect -t 1000; done
        zf_rm -f $_p9k__worker_file_prefix.fifo
        kill -- -$_p9k_worker_pgid
      } &
      exec =true) || return
    _p9k__worker_pid=$sysparams[procsubstpid]
    zle -F $_p9k__worker_resp_fd _p9k_worker_receive
    _p9k__worker_shell_pid=$sysparams[pid]
    add-zsh-hook zshexit _p9k_worker_cleanup
  } always {
    (( $? )) && _p9k_worker_stop
  }
}
