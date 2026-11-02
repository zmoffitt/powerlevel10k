# Powerlevel10k fork review — findings

Reviewed: `zmoffitt/powerlevel10k` at `c1f5ee51` (branch `docs/fork-links`, at parity with upstream `romkatv/powerlevel10k` master `d05a1b00` plus 10 fork commits). Date: 2026-11-01.

Method: 39 independent reviewer passes (two lenses over each of 11 regions of `internal/p10k.zsh`, one pass per other file group, 6 passes cross-referencing the 132 open upstream issues, 3 passes over the 21 open upstream PRs), producing 192 candidate findings (150 unique). Each unique finding was scheduled for three adversarial verifiers with different lenses (code reading, reproduction, maintainer intent). Verification was stopped on request after 279 votes: 76 findings were fully voted (71 confirmed by at least 2 of 3, 1 contested, 5 refuted) and 74 received no votes. I spot-checked the high/medium unverified items by hand; the rest are listed as unverified.

Everything already fixed in this fork's earlier review (missing `$` in `[[ _p9k__ret == *%* ]]`, `_p9__ip_timestamp`, dotnet init name, `for path` in nvm, node_version `$?`, aws `[sso-session]`, VCS latency clamp, package.json numbers, duplicate phpenv helper) was excluded, as were the upstream fixes already merged (#2961, #2887, #2935, #2860, #2919, #2916, #2813).

`zsh -n` passes on every file. There are no duplicate function definitions and no remaining `_p9__`-style prefix typos.

## 1. Highest-value fixes

These are real, reproduced (by a finder and/or verifier, or by me), and user-visible.

| # | Where | Problem | Upstream |
|---|-------|---------|----------|
| 1 | `internal/p10k.zsh:7439` | `POWERLEVEL9K_INSTANT_PROMPT=off` is lost when the cached state is restored. `_p9k__instant_prompt_disabled` is only derived inside `_p9k_init_params`, which the `_p9k_restore_state` path skips, so from the third shell start the instant prompt file is re-dumped and shown despite `off`. Fix: derive the flag after `_p9k_restore_state || _p9k_init_cacheable` in `_p9k_init` (or guard `_p9k_do_dump` on `_POWERLEVEL9K_DISABLE_INSTANT_PROMPT`). | unreported; matches the folk fix "delete ~/.cache/p10k-*" |
| 2 | `gitstatus/install:333` | `check_sha256` fails open: `[ "$1" = 1 -a -z "$hash" -o "$hash" = "$sha256" ]` accepts mirror 1 with no digest utility present, so an unverified `gitstatusd` is installed and executed. Fix: `[ -n "$hash" ] && [ "$hash" = "$sha256" ]` and refuse to download when no digest tool exists. | #2970 (closed won't-fix upstream) |
| 3 | `gitstatus/install:348` | Download uses `curl -kfsSL` (TLS verification disabled). Combined with #2 this is an unauthenticated code download. Fix: drop `-k`; keep the gitee mirror as a fallback only. | #2970, #2953 |
| 4 | `internal/p10k.zsh:6487-6495`, `:8081`, `gitstatus/gitstatus.plugin.zsh:610`, `gitstatus/install:255`, `internal/wizard.zsh:1619` | Predictable temp paths in shared `/tmp` created with truncating, symlink-following redirections (`: > $tmpdir/p10k-instant-prompt-output-$USER-$$`, then `exec 1>` the same path, later `cat` back into the terminal). Fix: `sysopen -o creat,excl,nofollow -m 600` with a random suffix, or use `$XDG_RUNTIME_DIR` / the existing `~/.cache` dir, and redirect via the opened fd. | #2972 (open) |
| 5 | `internal/p10k.zsh:6189`, `:6635` | `_p9k_do_dump` is a `zle -F` handler running under `__p9k_intro` (`no_prompt_subst`); it forks external `mkdir -p`, which makes zle redraw the prompt with prompt_subst off and prints the raw multi-kilobyte `${...}` PROMPT template on first run / after clearing the cache. Fix: `zmodload -F zsh/files b:zf_mkdir` next to `zf_mv`/`zf_rm` and use `zf_mkdir -p`; also `setopt prompt_subst` inside `_p9k_do_dump`. | #2956 (open) |
| 6 | `internal/p10k.zsh:8443`, `:6517` | `$terminfo[cuu1]` / `$terminfo[ed]` are embedded verbatim; on `TERM=vt100`/`vt102` they carry padding (`\E[A$<2>`, `\E[J$<50>`) which is printed literally. Fix: strip `$<...>` padding (`${str//\$<[0-9]##(|.[0-9]#)(|[*\/])#>/}`) or use `echoti`. | #2943 (open) |
| 7 | `internal/p10k.zsh:8615`, `:8622` | Transient prompt splices `PROMPT_CHAR_*_CONTENT_EXPANSION` raw into a `%(?..)` ternary, so any `)` in the content (e.g. `¯\_(ツ)_/¯`) terminates the ternary and leaks text. Fix: replace `)` with `%)` when splicing. | #2719 (open) |
| 8 | `internal/p10k.zsh:722` | SH_GLOB branch of the separator rule writes `x\$${_p9k__bg:-0}`: only the `$` is escaped, so the build-time value of `_p9k__bg` is baked into the cached template. Sibling line 724 is correct. Fix: `x\${_p9k__bg:-0}`. | related to #2887 |
| 9 | `internal/parser.zsh:141` | `[[ ${2:-0} == <-> ]]` runs before `eval "$__p9k_intro"`, so with `setopt sh_glob` in the user shell it never matches and `_p9k_parse_buffer` returns 2, disabling every `*_SHOW_ON_COMMAND`. Fix: move the check after the `eval`. | same class as #2887 |
| 10 | `internal/p10k.zsh:1833` | `truncate_absolute` dir strategy: when the budget is exhausted exactly, `$dir[-0,-1]` is the whole string, so a full extra component is shown. Fix: guard `n == 0`. | unreported |
| 11 | `internal/p10k.zsh:1917` | `truncate_to_unique` keys the cache on each component's own mtime, but uniqueness depends on the parent's listing; creating a sibling leaves a stale, non-unique abbreviation. Fix: include the parent mtime in the stamp. | unreported |
| 12 | `internal/p10k.zsh:4269` | `instant_prompt_chezmoi_shell` gates on `$CHEZMOI_ICON` (never a shell variable) instead of `$CHEZMOI`; the instant-prompt chezmoi segment never shows. | unreported |
| 13 | `internal/p10k.zsh:1430`, `:1433`, `:1438` | Battery sysfs file is chosen by glob sort order (`charge_counter` beats `charge_full`, `current_now` beats `power_now`) because `_p9k_read_file` reads only `$1`. Fix: iterate candidates in priority order. | PRs #1020, #2862 touch the same area |
| 14 | `internal/p10k.zsh:5926` | `ip` segment on macOS/BSD sums every `netstat -inbI` row; each row repeats the same counters, so bytes and rates are N× too high and spike when the row count changes. Fix: use only the `<Link#` row. | unreported |
| 15 | `internal/p10k.zsh:345` | `_p9k_human_readable_bytes` uses `printf '%.1f'`, which honours `LC_NUMERIC`, producing `10,K` / `1,76K` under comma locales (ram, swap, ip rates). Fix: `local LC_NUMERIC=C` or integer math. | unreported |
| 16 | `internal/p10k.zsh:2854` and siblings (2612, 2686, 2913, 2971, 3032, 3093, 3154, 3173, 3186, 3275) | *env segments render `.ruby-version`-style file / env contents with only `%` escaped; control sequences reach the terminal. Upstream fixed only `package` (#2961) with `${(V)...}`. Fix: same `(V)` treatment (or sanitize in `_p9k_read_word`). | #2961 |
| 17 | `internal/p10k.zsh:8784`, `:8801` | `for line in $_p9k_line_segments_left` drops empty lines, so `_p9k_vcs_line_index` is off by one whenever a prompt line before `vcs` is empty; `p10k display N/left/vcs=hide` and `VCS_SHOW_ON_COMMAND` then target the wrong line. Fix: iterate by index. | #2129 (open) |
| 18 | `internal/p10k.zsh:5264` | Taskwarrior data signature has an extra NUL when `~/.taskrc` does not exist, so the cache never matches and `task` runs on every prompt. | unreported |
| 19 | `internal/p10k.zsh:2282` | `detect_virt` reports `chroot` whenever the root inode is not 2, which is every btrfs/XFS/ZFS root. | #2100 (open) |
| 20 | `internal/wizard.zsh:1694`, `:1970` | `cp -p ... || quit -c` with no fallback; on filesystems that cannot preserve permissions the wizard aborts at the final step with a stack trace. Fix: `cp -p ... 2>/dev/null || cp ... || quit -c`. | #2896, #2955 (open) |
| 21 | `internal/worker.zsh:22` | Async children spawned via `sysopen <(...)` are never reaped; one `<defunct>` zsh per in-flight request lingers until the worker's next fork (reproduced on this Mac). Upstream PR #2857 addresses it but drops the actual work, so do not merge it as written. | PR #2857, #2951 |
| 22 | `internal/p10k.zsh:4586` | GKE context pattern omits the `me-*` and `africa-*` region prefixes, so `KUBECONTEXT_SHORTEN=(gke)` fails for those clusters. | unreported |
| 23 | `internal/p10k.zsh:2695` | dotnet project glob says `packet.dependencies`; Paket's file is `paket.dependencies`. Also lacks `*.slnx`. | PR #2948 |
| 24 | `internal/p10k.zsh:9109` | `_p9k_deinit` unsets `P9K_*` except an allow-list that omits `P9K_VERSION`; after `p10k reload` / `p10k configure` the variable is gone (it is only set at source time, line 9533) and the cache signature at line 8550 changes. Fix: add `P9K_VERSION` to the exclusion. | unreported |
| 25 | `internal/p10k.zsh:2777` | BSD `ram` segment reads a boot-time constant from `/var/run/dmesg.boot`; on OpenBSD the string is `avail mem`, so the segment never appears. | unreported |
| 26 | `internal/icons.zsh:368`, `:442` | `awesome-mapped-fontconfig` lacks `WINDOWS_ICON`, `ANDROID_ICON`, `GO_ICON`, `GOLANG_ICON` (145 keys vs 149 in every other mode). | unreported |

## 2. Config / wizard / docs mismatches

| Where | Problem |
|-------|---------|
| `config/p10k-{lean,lean-8colors,classic,rainbow}.zsh` (`POWERLEVEL9K_HASKELL_STACK_ALWAYS_SHOW`) | Code reads `_POWERLEVEL9K_HASKELL_STACK_PROMPT_ALWAYS_SHOW` (p10k.zsh:7720); the config line is a no-op. |
| `config/p10k-lean.zsh:178`, `p10k-classic.zsh:158`, `p10k-rainbow.zsh` | `POWERLEVEL9K_EMPTY_LINE_LEFT_PROMPT_FIRST_SEGMENT_END_SYMBOL` is read nowhere in p10k.zsh (only `*LAST_SEGMENT_END_SYMBOL` exists). Dead line since 5dd3ecab. |
| `internal/wizard.zsh:1755-1756` | Wizard patches `AZURE_VISUAL_IDENTIFIER_EXPANSION`, but templates have `AZURE_OTHER_VISUAL_IDENTIFIER_EXPANSION` since 07849757; `sub`/`uncomment` are silent no-ops, so compatible/powerline mode keeps the ☁ glyph. |
| `internal/wizard.zsh:1767`, `:1788`, `:1794` | `uncomment POWERLEVEL9K_PYTHON_ICON` (no template has it), `sub VCS_LOADING_FOREGROUND` (absent from classic), `sub RULER_FOREGROUND` in the classic/rainbow branch (only lean has it) are also silent no-ops. |
| `internal/wizard.zsh:2037` | `check_zshrc_integration` treats `#source ~/.p10k.zsh` (comment with no space) as live integration (tested). |
| `internal/wizard.zsh:652` | `exit 1` inside a `{ } always { }` block: zsh does not run the `always` block on `exit` (tested), so `stty echo` / cursor restore are skipped. |
| `internal/wizard.zsh:464` | `[[ -f ~/Library/Fonts ]]` followed by `-d` check: intended `-e`. |
| `config/p10k-lean-8colors.zsh:1178` | `POWERLEVEL9K_PERLBREW_FOREGROUND=67` in the 8-color config. |
| `config/p10k-lean-8colors.zsh:326` | Stray `#` after `..._ANCHOR_FOREGROUND=4#`. |
| `config/p10k-lean.zsh:658` (and siblings) | Example uses `ASDF_DOTNET_SHOW_ON_UPGLOB`; the plugin is `dotnet-core`, so the real name is `ASDF_DOTNET_CORE_SHOW_ON_UPGLOB`. |
| `config/p10k-classic.zsh:506` | Typo `reposotiry`. |
| `README.md:1667` | Anchor `#zsh-character-not-in-range` does not exist (section slug is `#error-character-not-in-range`). |
| `internal/configure.zsh:42` | Error text `"$__p9k_zshrc_u a special file"` is missing "is". |
| `internal/p10k.zsh:6802`, `:6818` | `prompt_cr` error message: "gets sets", "quckly". |

## 3. Upstream issues confirmed present in this fork

Open upstream issues whose root cause is in this code (beyond those in section 1): #2912 (`SHOW_ON_COMMAND` resets the prompt during menu-select, p10k.zsh:8037), #2771 (OpenBSD gets `FREEBSD_ICON`, NetBSD gets nothing, p10k.zsh:8650), #2689 and PRs #2823/#2855 (Pop!_OS, Zorin, Kali fall to the generic Linux icon, p10k.zsh:8697), #2595/#2894 (macOS wifi backend relies on the removed `airport` tool, p10k.zsh:5335), #2860 (nordvpn status read can block forever, p10k.zsh:4849; segment is disabled upstream), #2890 (haskell_stack runs `stack` synchronously, p10k.zsh:5718), #2889 (svn format omits `%b`, so a clean checkout renders no segment, p10k.zsh:3803; unverified), #2947 (gitstatus `RepoCache` keyed by gitdir returns a stale repo after `git worktree move`, `gitstatus/src/repo_cache.cc:108`; unverified), #2959 (init cache signature omits `TERM_PROGRAM_VERSION`, which gates the OSC 133 output, p10k.zsh:8551).

Open PRs that fix real defects here: #2857 (worker zombies; fix is wrong as written), #2948 (`*.slnx`, plus the `packet` typo), #1020/#2862 (battery sysfs selection), #2710/#2774 (ssh detection in WSL; the finders judged #2774 a valid optimisation and #2710 a real gap). The remaining open PRs are feature additions.

Refuted by all verifiers (do not act on): swift_version "driver version" (p10k.zsh:4526), SHOW_ON_UPGLOB word-splitting (:847), dotnet_version `%` escaping (:2701), `VIRTUAL_ENV_PROMPT` 3.13 format (:4321), README PS2 claim (README.md:1016). I also dropped two unverified claims as incorrect after reading the code: the `(#i)` scoping in `VCS_GIT_REMOTE_ICONS` (:7504) and `$+commands[git]` being baked into `_p9k_preinit` (:8862, covered by the cache key).

## 4. All confirmed findings (≥2 of 3 verifier votes), low severity not covered above

| Where | Finding | Refs |
|---|---|---|
| `internal/p10k.zsh:6818` | Typo "quckly" in the prompt_cr error message |  |
| `internal/p10k.zsh:1981` | `$#parts[-i]` compares a length to a pattern; the `continue` is unreachable |  |
| `internal/p10k.zsh:4361` | _p9k_read_pyenv_like_version_file keeps a trailing CR from CRLF version files |  |
| `internal/p10k.zsh:396` | Comment claims _p9k_cache_set with no args makes _p9k_cache_get fail; it does not |  |
| `internal/p10k.zsh:6130` | DIR_MIN_COMMAND_COLUMNS_PCT is evaluated at _p9k_set_prompt time with a stale _p9k__clm |  |
| `internal/p10k.zsh:6243` | Loader resolves a fallback `locale` path but then runs bare `locale -a`, defeating the fallback |  |
| `internal/p10k.zsh:758` | SHOW_ON_COMMAND hide variable name derived from $1 diverges from the setter for some segment names |  |
| `internal/p10k.zsh:1703` | _p9k_custom_prompt uppercases segment name without the Turkish İ workaround |  |
| `internal/p10k.zsh:5335` | wifi (macOS): airport backend no longer exists; segment is non-functional on current macOS | issue #2595, issue #2894 |
| `internal/p10k.zsh:1653` | POWERLEVEL9K_USER_TEMPLATE is ignored in the DEFAULT state of the user segment |  |
| `internal/p10k.zsh:8599` | Dead local `cmds` in right-side SHOW_ON_COMMAND loop (copy-paste leftover) |  |
| `README.md:1667` | Broken internal anchor #zsh-character-not-in-range (section slug is #error-character-not-in-range) |  |
| `internal/wizard.zsh:1143` | Duplicate `*raspbian*` case arm is unreachable |  |
| `internal/p10k.zsh:2620` | _p9k_nodeenv_version_transform is a nodenv helper misnamed as nodeenv |  |
| `internal/p10k.zsh:6802` | Grammar typo "gets sets" in the prompt_cr error message |  |
| `internal/p10k.zsh:8487` | Subshell fork used where a brace group was intended in _p9k_init_prompt |  |
| `internal/p10k.zsh:4822` | google_app_cred renders JSON-derived text without escaping `%` |  |
| `internal/p10k.zsh:6223` | Instant-prompt key uses SSH_* env vars while the dump key uses P9K_SSH, which can also come from `who` |  |
| `internal/p10k.zsh:8081` | Predictable temp file in /tmp written with plain redirection (zsh < 5.3 widget wrapping) | issue #2972 |
| `internal/p10k.zsh:5080` | terraform workspace name is not `%`-escaped before prompt expansion |  |
| `internal/p10k.zsh:7558` | _p9k_segment_in_use checks in _p9k_init_params run before *_DISABLED elements are removed |  |
| `internal/p10k.zsh:1287` | disk_usage parses `df -P` by word index; filesystem names with spaces shift the Capacity field |  |
| `internal/p10k.zsh:2778` | BSD ram segment shows boot-time 'avail memory' from dmesg.boot, never current free RAM |  |
| `internal/p10k.zsh:3346` | instant_prompt_status ignores STATUS_VERBOSE / OK_IN_NON_VERBOSE, unlike prompt_status |  |
| `internal/p10k.zsh:4725` | gcloud segment ignores CLOUDSDK_ACTIVE_CONFIG_NAME (and CLOUDSDK_CORE_* overrides) |  |
| `internal/p10k.zsh:6202` | Early `return` inside the first try-block of _p9k_dump_instant_prompt skips the temp-file cleanup |  |
| `internal/p10k.zsh:8650` | OpenBSD gets FREEBSD_ICON although an OpenBSD glyph exists; other BSDs get no OS at all | issue #2771 |
| `internal/p10k.zsh:1065` | Right-prompt alternate foreground for fg==bg is computed but always overridden (dead logic) |  |
| `internal/p10k.zsh:6254` | Instant-prompt cache key uses env-only ssh flag while dump signature uses $P9K_SSH; who-based detection makes them never match |  |
| `internal/icons.zsh:711` | nerdfont-complete uses font-logos 1.x glyph F325 for Guix while falling back to F17C for its siblings | commit be4c68fd (#2424), commit ec1702ca (#2033) |
| `internal/p10k.zsh:207` | _p9k_read_word uses `read` without -r, mangling backslashes in version files |  |
| `internal/p10k.zsh:5090` | terraform_version cache never invalidates on tfenv's global version file |  |
| `internal/p10k.zsh:5222` | taskwarrior: XDG config (~/.config/task/taskrc) is never watched, so meta cache goes stale |  |
| `internal/p10k.zsh:5417` | wifi (Linux): /proc/net/wireless noise -256 sentinel makes P9K_WIFI_BARS always 4 |  |
| `internal/p10k.zsh:1233` | aws_eb_env runs `eb list` synchronously in the prompt path with no timeout | issue #2935 |
| `internal/p10k.zsh:2640` | nodenv 'shell' source skips the version transform applied to local/global versions |  |
| `internal/p10k.zsh:5798` | cpu_arch init condition disables the /proc/sys/kernel/arch path the segment body supports |  |
| `internal/p10k.zsh:8037` | SHOW_ON_COMMAND resets the prompt during menu-select, clearing the completion menu | issue #2912 |
| `internal/p10k.zsh:1462` | Remaining-time estimate never shown when the driver reports negative current_now while discharging |  |
| `internal/p10k.zsh:2497` | _p9k_nvm_ls_default: `$seen[(I)$target]` treats the alias target as a glob pattern |  |
| `internal/p10k.zsh:3245` | rust_version: late worker reply re-sets P9K_RUST_VERSION after prefetch unset it |  |
| `internal/p10k.zsh:3325` | status text is empty for exit codes above 255 (zsh function `return N` is not truncated) |  |
| `internal/p10k.zsh:3754` | `echo "$svn_status"` interprets backslash escapes in svn output |  |
| `internal/p10k.zsh:5189` | timewarrior tag extraction also captures the interval annotation |  |
| `internal/p10k.zsh:5940` | ip segment shows negative rates after interface counter reset |  |
| `internal/p10k.zsh:932` | Right prompt: fg==bg alternate-foreground logic is overridden before the sub-separator is drawn |  |
| `internal/p10k.zsh:1434` | Battery: negative current_now (kernel discharge sign convention) disables time-remaining |  |
| `internal/p10k.zsh:3238` | rust_version runs `rustc --version` inside the project dir, which lets rustup auto-install toolchains from the prompt |  |
| `internal/p10k.zsh:7126` | Fast-path gitstatus wait ignores the per-repo timeout computed in _p9k_vcs_gitstatus |  |
| `internal/p10k.zsh:3620` | $? checked after `local var="$(...)"` is always 0 (dead check) |  |
| `internal/p10k.zsh:1708` | Custom segment command is rejected unless its first word is a function or external command |  |
| `internal/p10k.zsh:4150` | Fast-path vcs timeout (0 for slow repos / first prompt) is stored then discarded | commit 0d8e001f (bug fixes in the gitstatus fastpath) |
| `internal/icons.zsh:335` | Mapped-fontconfig icons derived from CODEPOINT_OF_* are baked into the state cache with no invalidation |  |
| `internal/p10k.zsh:8697` | Pop!_OS and Zorin fall to generic LINUX_ICON although both have Nerd Fonts glyphs | PR #2823, PR #2855, issue #2689 |

Contested (1 of 3): `internal/p10k.zsh:2334` laravel_version runs the repository's own `artisan` with php (code execution from an untrusted checkout; verifiers split on whether this is accepted behaviour).

## 5. Unverified findings (no verifier vote; not in sections 1-2)

Finder confidence in parentheses. Treat as leads.

| Where | Finding | Refs |
|---|---|---|
| `gitstatus/gitstatus.plugin.zsh:659` | gitstatus_start leaks a global `req_fd` variable into the user's shell (0.95) |  |
| `internal/p10k.zsh:9371` | Two blank lines of the `p10k segment` error message go to stdout instead of stderr (0.95) |  |
| `gitstatus/install:292` | run_cmd: `ret="$?"` after a background `&` is always 0, making the spawn-failure branch dead (0.9) |  |
| `config/p10k-lean.zsh:988` | PYENV_CONTENT_EXPANSION appends a trailing space when P9K_PYENV_PYTHON_VERSION is empty (0.9) | PR #2449 |
| `internal/p10k.zsh:8773` | status segment maps exit codes 160/161 to pseudo-signals ZERR/DEBUG (0.9) |  |
| `internal/p10k.zsh:9435` | `p10k display part` without `=state` stores an empty state and later breaks `p10k display -a` into an associative reply (0.9) |  |
| `internal/parser.zsh:38` | `foreach` skip pattern can never match a (z) token, so everything after `foreach` is swallowed (0.9) |  |
| `internal/parser.zsh:4` | Duplicate `'{'` key in `__p9k_pb_cmd_skip` literal (0.9) |  |
| `internal/icons.zsh:341` | awesome-mapped-fontconfig mode lacks WINDOWS_ICON, ANDROID_ICON, GO_ICON, GOLANG_ICON (0.85) |  |
| `internal/p10k.zsh:7411` | _p9k__dotnet_stat_cache is declared but never read or written (dead leftover) (0.85) |  |
| `internal/p10k.zsh:9091` | _p9k_deinit does not remove _p9k_async_segments_compute; stale function keeps running after hot reload (0.85) |  |
| `internal/p10k.zsh:9444` | p10k display / SHOW_ON_COMMAND hide variable name differs from the one the prompt reads for segments ending in digit/uppercase (0.85) |  |
| `internal/parser.zsh:213` | Appending substitution contents to `tokens` corrupts the alias-expansion stack (remaining-count bookkeeping) (0.85) |  |
| `config/p10k-lean-8colors.zsh:1674` | Commented EXAMPLE_FOREGROUND=208 contradicts the 8-color example segment (-f 2, 'green text') (0.8) |  |
| `internal/p10k.zsh:7153` | __p9k_new_pipestatus=($pipestatus) keeps only the first element under KSH_ARRAYS (0.8) |  |
| `internal/p10k.zsh:9381` | `p10k segment` help says empty -f means %f/default-empty, but code substitutes _p9k_color1 (0.8) |  |
| `internal/parser.zsh:206` | Here-document detection ignores fd-prefixed `N<<`, so the heredoc body is parsed as commands (0.8) |  |
| `gitstatus/build:121` | `&>/dev/null` is a bash/zsh-ism inside a `#!/bin/sh` script; misparses under dash/ash (0.75) |  |
| `gitstatus/gitstatus.plugin.sh:364` | gitstatus_query getopts accepts `-c ARG` but has no handler, so it silently returns 1 (0.7) |  |
| `gitstatus/gitstatus.plugin.sh:473` | gitstatus_check and the TMPDIR test break under `set -u` unlike the rest of the file (0.7) |  |
| `gitstatus/install:215` | User-facing installer errors go to fd 2 instead of -e ERRFD, so the shell shows only a generic failure (0.7) |  |
| `internal/p10k.zsh:9424` | p10k display accepts an empty state-list and corrupts _p9k__display_v, breaking later `display -a` (0.7) |  |
| `internal/wizard.zsh:226` | show_cursor pattern uses single-quoted '\e' (literal backslash-e), never matches a trailing escape (0.7) |  |
| `gitstatus/build:552` | Big-endian `ppc64` is mapped to the little-endian CPU flag and Docker image (0.6) |  |
| `internal/configure.zsh:81` | `69) return 0;;` in p9k_configure is dead: nothing in wizard.zsh exits/returns 69 (0.6) |  |
| `internal/wizard.zsh:513` | Termux font install downloads directly over the existing ~/.termux/font.ttf (no tmp+mv) (0.6) |  |
| `internal/worker.zsh:3` | mkfifo/exec failure returns outside the `always` block, leaving the worker group alive and the master waiting forever (0.6) |  |
| `gitstatus/build:414` | Post-build self-test assumes `master` but only neutralizes HOME and the system gitconfig (0.55) |  |
| `gitstatus/install.info:27` | cygwin_nt-* i686 fallback entry: version v1.5.2 paired with the sha256 of the v1.5.4 asset (0.55) |  |
| `internal/wizard.zsh:628` | ask_remove_font compares `:A`-resolved font paths against an unresolved `~/...` pattern (0.55) |  |
| `gitstatus/gitstatus.plugin.sh:88` | Outer `local tmpdir` is shadowed by the inner `local tmpdir`, so the mktemp dir is never cleaned up on early failure (0.5) |  |
| `internal/p10k.zsh:8190` | Gap/ruler char is embedded verbatim in ${(pl...)} so '}', '"' or '`' break prompt expansion (0.5) |  |
| `internal/wizard.zsh:236` | `[[ -t 2 ]]` in consume_input is a no-op (result discarded, and stderr is /dev/null anyway) (0.5) |  |
| `internal/p10k.zsh:2435` | _p9k_cached_cmd persists failed command results forever (php segment vanishes until cache wipe) (0.45) | issue #1651 |
| `internal/p10k.zsh:7093` | _POWERLEVEL9K_VCS_DISABLED_DIR_PATTERN is never declared; only WORKDIR_PATTERN is documented (0.45) |  |
| `internal/p10k.zsh:8646` | uname values other than the listed ones (e.g. NetBSD) leave _p9k_os empty (0.45) | issue #2771 |
| `internal/p10k.zsh:1113` | _p9k_python_version ignores python3; version disappears on hosts without a `python` executable (0.4) | issue #2933 |

Spot-checked by hand and confirmed from this group: `internal/parser.zsh:4` duplicate `'{'` key; `gitstatus/gitstatus.plugin.zsh:659` `req_fd` leaks as a global (not in `local -i lock_fd resp_fd stderr_fd`); `internal/p10k.zsh:9371` two blank lines of the error message go to stdout; `internal/p10k.zsh:7411` `_p9k__dotnet_stat_cache` declared and never used; `gitstatus/build:121` `&>/dev/null` in a `#!/bin/sh` script; `gitstatus/install:292` `ret="$?"` after `&` is always 0.

Raw data: all 150 aggregated findings with verifier reasoning are in `/private/tmp/claude-501/-Users-zmoffitt--claude-spares-spare-Dy3a6C/4e61e8c8-ad62-4ba6-adac-759476c5d5a1/scratchpad/aggregated.json`.
