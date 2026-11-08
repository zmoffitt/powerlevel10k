typeset -grA __p9k_pb_cmd_skip=(
  '}'         'always'  # handled specially
  '{'         ''
  '|'         ''
  '||'        ''
  '&'         ''
  '&&'        ''
  '|&'        ''
  '&!'        ''
  '&|'        ''
  ')'         ''
  '('         ''
  '()'        ''
  '!'         ''
  ';'         ''
  $'\n'       ''  # newline that precedes here-document bodies; see _p9k_parse_buffer
  'if'        ''
  'fi'        ''
  'elif'      ''
  'else'      ''
  'then'      ''
  'while'     ''
  'until'     ''
  'do'        ''
  'done'      ''
  'esac'      ''
  'end'       ''
  'coproc'    ''
  'nocorrect' ''
  'noglob'    ''
  'time'      ''
  '[['        '\]\]'
  '(('        '\)\)'
  'case'      '\)|\(*\)|esac'
  ';;'        '\)|\(*\)|esac'
  ';&'        '\)|\(*\)|esac'
  ';|'        '\)|\(*\)|esac'
  'foreach'   '\)'
  'repeat'    '*'
)

typeset -grA __p9k_pb_precommand=(
  '-'         ''
  'builtin'   ''
  'command'   ''
  'exec'      '-[^a]#[a]'
  'nohup'     ''
  'setsid'    ''
  'eatmydata' ''
  'catchsegv' ''
  'pkexec'    '--user'
  'doas'      '-[^aCu]#[aCu]'
  'env'       '-[^uCSP]#[uCSP]|--(unset|chdir|split-string)'  # NAME=value words are skipped specially
  'nice'      '-[^n]#[n]|--adjustment'
  'stdbuf'    '-[^ioe]#[ioe]|--(input|output|error)'
  'sudo'      '-[^aghpuUCcrtTDR]#[aghpuUCcrtTDR]|--(close-from|group|host|prompt|role|type|other-user|command-timeout|user|chdir|chroot)'
  'ssh-agent' '-[^aEPt]#[aEPt]'
  'tabbed'    '-[^gnprtTuU]#[gnprtTuU]'
  'chronic'   ''
  'ifne'      ''
)

typeset -grA __p9k_pb_redirect=(
  '&>'   ''
  '>'    ''
  '>&'   ''
  '<'    ''
  '<&'   ''
  '<>'   ''
  '&>|'  ''
  '>|'   ''
  '&>>'  ''
  '>>'   ''
  '>>&'  ''
  '&>>|' ''
  '>>|'  ''
  '<<<'  ''
)

typeset -grA __p9k_pb_term=(
  '|'  ''
  '||' ''
  ';'  ''
  $'\n' ''
  '&'  ''
  '&&' ''
  '|&' ''
  '&!' ''
  '&|' ''
  ';;' ''
  ';&' ''
  ';|' ''
  '('  ''
  ')'  ''
  '()' ''  # handled specially
  '}'  ''  # handled specially
)

typeset -grA __p9k_pb_term_skip=(
  '('  '\)'
  ';;' '\)|\(*\)|esac'
  ';&' '\)|\(*\)|esac'
  ';|' '\)|\(*\)|esac'
)

# Usage: _p9k_parse_buffer <buffer> [token-limit]
#
# Parses the specified command line buffer and populates array P9K_COMMANDS
# with commands from it. Terminates early and returns 1 if there are more
# tokens than the specified limit.
#
# Broken:
#
#   ---------------
#   : $(x)
#   ---------------
#   : `x`
#   ---------------
#   ${x/}
#   ---------------
#   - -- x
#   ---------------
#   command -p -p x
#   ---------------
#   *
#   ---------------
#   x=$y; $x
#   ---------------
#   alias x=y; y
#   ---------------
#   Setup:
#     setopt interactive_comments
#     alias x='#'
#   Punchline:
#     x; y
#   ---------------
#
# More brokenness with non-standard options (ignore_braces, ignore_close_braces, etc.).
function _p9k_parse_buffer() {
  local rcquotes
  [[ -o rcquotes ]] && rcquotes=rcquotes

  eval "$__p9k_intro"
  setopt no_nomatch $rcquotes

  # Must run after `eval "$__p9k_intro"`: with SH_GLOB set in the caller's shell, `<->`
  # would not be recognized as a pattern.
  [[ ${2:-0} == <-> ]] || return 2

  typeset -ga P9K_COMMANDS=()

  local -r id='(<->|[[:alpha:]_][[:IDENT:]]#)'
  local -r var="\$$id|\${$id}|\"\$$id\"|\"\${$id}\""

  local -i e ic i j c=${2:-'1 << 62'}
  local skip n s r state token cmd prev
  local -a aln alp alf v hd

  if [[ -o interactive_comments ]]; then
    ic=1
    local tokens=(${(Z+C+)1})
  else
    local tokens=(${(z)1})
  fi

  if [[ $1 == *'<<'* ]]; then
    # (z) turns newlines into `;` but here-document bodies start after the first newline
    # following `<<`. Mark newlines as $'\n' by aligning with a tokenization that treats
    # them as whitespace. Aligning from the end marks the first `;` of a run as newline.
    local -a nl
    (( ic )) && nl=(${(Z+Cn+)1}) || nl=(${(Z+n+)1})
    for (( i = $#tokens, j = $#nl; i > 0; --i )); do
      if (( j )) && [[ $tokens[i] == "$nl[j]" ]]; then
        (( --j ))
      elif [[ $tokens[i] == ';' ]]; then
        tokens[i]=$'\n'
      fi
    done
  fi

  {
    while (( $#tokens )); do
      (( e = $#state ))

      while (( $#tokens == alp[-1] )); do
        aln[-1]=()
        alp[-1]=()
        if (( $#tokens == alf[-1] )); then
          alf[-1]=()
          (( e = 0 ))
        fi
      done

      while (( c-- > 0 )) || return; do
        token=$tokens[1]
        tokens[1]=()
        if (( $+galiases[$token] )); then
          (( $aln[(eI)p$token] )) && break
          s=$galiases[$token]
          n=p$token
        elif (( e )); then
          break
        elif (( $+aliases[$token] )); then
          (( $aln[(eI)p$token] )) && break
          s=$aliases[$token]
          n=p$token
        elif [[ $token == ?*.?* ]] && (( $+saliases[${token##*.}] )); then
          r=${token##*.}
          (( $aln[(eI)s$r] )) && break
          s=${saliases[$r]%% #}
          n=s$r
        else
          break
        fi
        aln+=$n
        alp+=$#tokens
        [[ $s == *' ' ]] && alf+=$#tokens
        (( ic )) && tokens[1,0]=(${(Z+C+)s}) || tokens[1,0]=(${(z)s})
      done

      if [[ $token == $'\n' ]] && (( $#hd )); then
        # Skip the bodies of pending here-documents in order. Each body ends with a line
        # that consists of its delimiter.
        for (( j = 1; j <= $#hd; ++j )); do
          (( j > 1 )) && [[ $tokens[1] == $'\n' ]] && tokens[1]=()
          for (( i = 1; i <= $#tokens; ++i )); do
            [[ $tokens[i] == "$hd[j]" ]] || continue
            (( i == 1 )) || [[ $tokens[i-1] == $'\n' ]] || continue
            (( i == $#tokens )) || [[ $tokens[i+1] == $'\n' ]] || continue
            break
          done
          tokens[1,i]=()
        done
        hd=()
        while (( $#alp && alp[-1] > $#tokens )); do
          aln[-1]=()
          alp[-1]=()
        done
        while (( $#alf && alf[-1] > $#tokens )); do
          alf[-1]=()
        done
      fi

      case $token in
        '<<'(|-)|<0-255>'<<'(|-))
          state+=h
          continue
          ;;
        *('`'|['<>=$']'(')*)
          # Strip the assignment prefix, if any: x=$(cmd).
          n=${(S)token/#(<->|([[:alpha:]_][[:IDENT:]]#(|'['*[^\\](\\\\)#']')))(|'+')=}
          if [[ $n == ('`'[^'`']##'`'|'"`'[^'`']##'`"'|'$('[^')']##')'|'"$('[^')']##')"'|['<>=']'('[^')']##')') ]]; then
            s=${${n##('"'|)(['$<>']|)?}%%?('"'|)}
            # Separate with a newline rather than ';' so that a here-document delimiter on the
            # last line of the buffer is still followed by a newline token.
            (( ic )) && v=($'\n' ${(Z+C+)s}) || v=($'\n' ${(z)s})
            tokens+=("${v[@]}")
            # Tokens appended at the end shift the positions recorded for aliases.
            for (( i = 1; i <= $#alp; ++i )); do
              (( alp[i] += $#v ))
            done
            for (( i = 1; i <= $#alf; ++i )); do
              (( alf[i] += $#v ))
            done
          fi
          ;;
      esac

      case $state in
        *r)
          state[-1]=
          continue
          ;;
        *h)
          # The body is skipped at the next newline.
          hd+=("${(Q)token}")
          state[-1]=
          continue
          ;;
        a)
          if [[ $token == $skip ]]; then
            if [[ $token == '{' ]]; then
              P9K_COMMANDS+=$cmd
              cmd=
              state=
            else
              skip='{'
            fi
            continue
          else
            state=t
          fi
          ;&  # fall through
        t|p*)
          if (( $+__p9k_pb_term[$token] )); then
            if [[ $token == '()' ]]; then
              state=
            else
              P9K_COMMANDS+=$cmd
              if [[ $token == '}' ]]; then
                state=a
                skip=always
              else
                skip=$__p9k_pb_term_skip[$token]
                state=${skip:+s}
              fi
            fi
            cmd=
            continue
          elif [[ $state == t ]]; then
            continue
          elif [[ $state == *x ]]; then
            if (( $+__p9k_pb_redirect[$token] )); then
              prev=
              state[-1]=r
              continue
            else
              state[-1]=
            fi
          fi
          ;;
        s)
          if [[ $token == $~skip ]]; then
            state=
          fi
          continue
          ;;
      esac

      if (( $+__p9k_pb_redirect[${token#<0-255>}] )); then
        state+=r
        continue
      fi

      if [[ $token == *'$'* ]]; then
        if [[ $token == $~var ]]; then
          n=${${token##[^[:IDENT:]]#}%%[^[:IDENT:]]#}
          [[ $token == *'"' ]] && v=("${(P)n}") || v=(${(P)n})
          tokens[1,0]=(${(@qq)v})
          continue
        fi
      fi

      case $state in
        '')
          if (( $+__p9k_pb_cmd_skip[$token] )); then
            skip=$__p9k_pb_cmd_skip[$token]
            [[ $token == '}' ]] && state=a || state=${skip:+s}
            continue
          fi
          # `while (( x )) { y }`: arithmetic evaluation keeps the command position.
          [[ $token == '(('*'))' ]] && continue
          if [[ $token == *=* ]]; then
            v=${(S)token/#(<->|([[:alpha:]_][[:IDENT:]]#(|'['*[^\\](\\\\)#']')))(|'+')=}
            if (( $#v < $#token )); then
              if [[ $v == '(' ]]; then
                state=s
                skip='\)'
              fi
              continue
            fi
          fi
          : ${token::=${(Q)${~token}}}
          ;;
        p2)
          if [[ -n $prev ]]; then
            prev=
          else
            : ${token::=${(Q)${~token}}}
            if [[ $token == '{'$~id'}' ]]; then
              state=p2x
              prev=$token
            else
              state=p
            fi
            continue
          fi
          ;&  # fall through
        p)
          if [[ -n $prev ]]; then
            token=$prev
            prev=
          else
            : ${token::=${(Q)${~token}}}
            case $token in
              '{'$~id'}') prev=$token; state=px; continue;;
              [_[:alpha:]][[:IDENT:]]#=*)
                [[ $cmd == (|*$'\0')env$'\0' ]] && continue;;
              [^-]*)                                     ;;
              --)                      state=p1; continue;;
              $~skip)                  state=p2; continue;;
              *)                                 continue;;
            esac
          fi
          ;;
        p1)
          if [[ -n $prev ]]; then
            token=$prev
            prev=
          else
            : ${token::=${(Q)${~token}}}
            if [[ $token == '{'$~id'}' ]]; then
              state=p1x
              prev=$token
              continue
            fi
            [[ $token == [[:alpha:]_][[:IDENT:]]#=* && $cmd == (|*$'\0')env$'\0' ]] && continue
          fi
          ;;
      esac

      if (( $+__p9k_pb_precommand[$token] )); then
        prev=
        state=p
        skip=$__p9k_pb_precommand[$token]
        cmd+=$token$'\0'
      else
        state=t
        [[ $token == ('(('*'))'|'`'*'`'|'$'*|['<>=']'('*')'|*$'\0'*) ]] || cmd+=$token$'\0'
      fi
    done
  } always {
    [[ $state == (px|p1x) ]] && cmd+=$prev
    P9K_COMMANDS+=$cmd
    P9K_COMMANDS=(${(u)P9K_COMMANDS%$'\0'})
  }
}
