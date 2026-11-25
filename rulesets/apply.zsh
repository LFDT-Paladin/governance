#!/usr/bin/env zsh
# Compare the ruleset files in this directory with GitHub, and optionally
# apply them.
#
#   rulesets/apply.zsh [--apply] [dir ...]
#
# Each directory here is named for a repository in the LFDT-Paladin org and
# holds one JSON file per ruleset. `_org` holds the organization rulesets.
# With no directory arguments every directory is processed.
#
# Without --apply nothing is written: the script prints, per file, whether
# the live ruleset is the same, differs (with a diff) or is missing.
# With --apply a missing ruleset is created and a differing one is updated.
# Rulesets are matched by name. A live ruleset with no file is reported and
# left alone; delete those by hand.
#
# Needs gh (authenticated as a repository admin, or an org owner for _org)
# and jq.

emulate -L zsh
setopt err_return no_unset pipe_fail

ORG=LFDT-Paladin
here=${0:A:h}

apply=0
dirs=()
for arg in "$@"; do
  case $arg in
    --apply) apply=1 ;;
    -h|--help) sed -n '2,/^$/s/^# \{0,1\}//p' $0; exit 0 ;;
    -*) print -u2 "unknown option: $arg"; exit 2 ;;
    *) dirs+=(${arg:t}) ;;
  esac
done
(( $#dirs )) || dirs=($here/*(/N:t) $here/.[^.]*(/N:t))

# Reduce a ruleset to the fields the API accepts on write, in a stable order,
# so a file and a live ruleset can be diffed. The two pull_request fields
# dropped here are returned by the API but are not in its published schema.
normalize='
  del(.id, .source, .source_type, .node_id, ._links, .created_at,
      .updated_at, .current_user_can_bypass)
  | (.rules[] | select(.type == "pull_request") | .parameters)
      |= del(.dismissal_restriction,
             .require_extra_approval_for_unattributed_changes)
  | .rules |= sort_by(.type)
'

changed=0
for dir in $dirs; do
  [[ -d $here/$dir ]] || { print -u2 "no such directory: rulesets/$dir"; exit 2 }
  if [[ $dir == _org ]]; then
    base=orgs/$ORG/rulesets
  else
    base=repos/$ORG/$dir/rulesets
  fi

  # name<TAB>id for every ruleset defined at this level (not inherited).
  live=$(gh api --paginate "$base?includes_parents=false&per_page=100" \
           --jq '.[] | [.name, .id] | @tsv')
  typeset -A ids=()
  while IFS=$'\t' read -r name id; do
    [[ -n $name ]] && ids[$name]=$id
  done <<< $live

  typeset -A seen=()
  for file in $here/$dir/*.json(N); do
    name=$(jq -r .name $file)
    seen[$name]=1
    label="$dir/${file:t} ($name)"
    want=$(jq -S $normalize $file)

    if (( ! ${+ids[$name]} )); then
      changed=1
      if (( apply )); then
        gh api -X POST $base --input - <<< $want > /dev/null
        print "created  $label"
      else
        print "missing  $label"
      fi
      continue
    fi

    id=$ids[$name]
    have=$(gh api $base/$id | jq -S $normalize)
    if [[ $have == $want ]]; then
      print "same     $label"
      continue
    fi

    changed=1
    print "differs  $label"
    diff -u --label live --label ${file:t} <(print -r -- $have) <(print -r -- $want) || true
    if (( apply )); then
      gh api -X PUT $base/$id --input - <<< $want > /dev/null
      print "updated  $label"
    fi
  done

  for name in ${(k)ids}; do
    (( ${+seen[$name]} )) || print "no file  $dir: live ruleset \"$name\" (id $ids[$name]) left alone"
  done
done

if (( changed && ! apply )); then
  print "\nNothing was changed. Re-run with --apply to write the differences."
fi
