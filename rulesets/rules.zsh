#!/usr/bin/env zsh
# Compare the ruleset files in this directory with GitHub, and optionally
# bring one side into step with the other.
#
#   rulesets/rules.zsh [--apply | --update-local] [--allow-bypass-removal] [dir ...]
#
# Each directory here is named for a repository in the LFDT-Paladin org and
# holds one JSON file per ruleset. `_org` holds the organization rulesets.
# With no directory arguments every directory is processed.
#
# With no mode flag nothing is written: the script prints, per file, whether
# the live ruleset is the same, differs (with a diff of live against the file)
# or is missing, and reports any live ruleset that has no file.
#
#   --apply         write these files to GitHub: create a missing ruleset,
#                   update a differing one.
#   --update-local  write GitHub to these files: update a differing file, add
#                   a file for a live ruleset that has none and, when no
#                   directory arguments are given, add a directory for a
#                   repository whose rulesets are not recorded here.
#
# Rulesets are matched by name. Neither mode deletes: --apply leaves a live
# ruleset that has no file alone, --update-local leaves a file whose ruleset
# is gone from GitHub alone. Delete those by hand.
#
# A caller that cannot read bypass actors is shown `bypass_actors: []` on
# every ruleset, so a write in either direction can silently drop them. Any
# write that would empty a non-empty list is skipped; use a token that can
# read bypass actors, or pass --allow-bypass-removal if the removal is meant.
#
# Needs gh (authenticated as a repository admin, or an org owner for _org)
# and jq.

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob

ORG=LFDT-Paladin
here=${0:A:h}

apply=0
update=0
allow_bypass_removal=0
dirs=()
for arg in "$@"; do
  case $arg in
    --apply) apply=1 ;;
    --update-local) update=1 ;;
    --allow-bypass-removal) allow_bypass_removal=1 ;;
    -h|--help) sed -n '2,/^$/s/^# \{0,1\}//p' $0; exit 0 ;;
    -*) print -u2 "unknown option: $arg"; exit 2 ;;
    *) dirs+=(${arg:t}) ;;
  esac
done
if (( apply && update )); then
  print -u2 -- "--apply and --update-local are opposites; pick one"
  exit 2
fi
explicit=$#dirs
(( explicit )) || dirs=($here/*(/N:t) $here/.[^.]*(/N:t))

# Reduce a ruleset to the fields the API accepts on write, so a live ruleset
# can be written to a file. The two pull_request fields dropped here are
# returned by the API but are not in its published schema.
strip='
  del(.id, .source, .source_type, .node_id, ._links, .created_at,
      .updated_at, .current_user_can_bypass)
  | (.rules[]? | select(.type == "pull_request") | .parameters)
      |= del(.dismissal_restriction,
             .require_extra_approval_for_unattributed_changes)
'
# The same, with the rules in a stable order, for comparison only: the API
# does not keep rule order stable. Used with jq -S; the files themselves keep
# the order and key order GitHub returns.
normalize="$strip | .rules |= sort_by(.type)"

count_bypass='.bypass_actors // [] | length'

# With --update-local and no directory arguments, pick up any repository that
# has rulesets of its own but no directory here.
if (( update && ! explicit )); then
  for repo in ${(f)"$(gh api --paginate orgs/$ORG/repos --jq '.[].name')"}; do
    [[ -n $repo && ! -d $here/$repo ]] || continue
    if (( $(gh api "repos/$ORG/$repo/rulesets?includes_parents=false&per_page=100" \
              --jq 'length') )); then
      dirs+=($repo)
    fi
  done
fi

changed=0
newdirs=()
for dir in $dirs; do
  if [[ ! -d $here/$dir ]]; then
    (( update )) || { print -u2 "no such directory: rulesets/$dir"; exit 2 }
    mkdir -p $here/$dir
    newdirs+=($dir)
    print "created  rulesets/$dir/"
  fi
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
      elif (( update )); then
        print "no live  $label: no ruleset of this name on GitHub, file left alone"
      else
        print "missing  $label"
      fi
      continue
    fi

    id=$ids[$name]
    raw=$(gh api $base/$id)
    have=$(jq -S $normalize <<< $raw)
    if [[ $have == $want ]]; then
      print "same     $label"
      continue
    fi

    changed=1
    print "differs  $label"
    diff -u --label live --label ${file:t} <(print -r -- $have) <(print -r -- $want) || true

    # Guard a write that would empty a non-empty bypass_actors list.
    nlive=$(jq $count_bypass <<< $raw)
    nfile=$(jq $count_bypass $file)
    if (( apply )); then
      if (( ! allow_bypass_removal && nlive > 0 && nfile == 0 )); then
        print "skipped  $label: applying would remove $nlive bypass actor(s); pass --allow-bypass-removal if that is meant"
      else
        gh api -X PUT $base/$id --input - <<< $want > /dev/null
        print "updated  $label"
      fi
    elif (( update )); then
      if (( ! allow_bypass_removal && nfile > 0 && nlive == 0 )); then
        print "skipped  $label: live bypass_actors is empty and the file lists $nfile; use a token that can read bypass actors, or pass --allow-bypass-removal"
      else
        jq $strip <<< $raw > $file
        print "wrote    $label"
      fi
    fi
  done

  for name in ${(k)ids}; do
    (( ${+seen[$name]} )) && continue
    changed=1
    if (( ! update )); then
      print "no file  $dir: live ruleset \"$name\" (id $ids[$name]) left alone"
      continue
    fi
    # Name the new file after the ruleset: lower case, anything else a dash.
    slug=${${${${(L)name}//[^a-z0-9]##/-}#-}%-}
    [[ -n $slug ]] || slug=ruleset-$ids[$name]
    file=$here/$dir/$slug.json
    [[ -e $file ]] && file=$here/$dir/$slug-$ids[$name].json
    raw=$(gh api $base/$ids[$name])
    jq $strip <<< $raw > $file
    print "wrote    $dir/${file:t} ($name), new file"
  done
done

if (( changed && ! apply && ! update )); then
  print "\nNothing was changed. Re-run with --apply to write these files to"
  print "GitHub, or with --update-local to update these files from GitHub."
fi
if (( $#newdirs )); then
  print "\nNew: ${(j:, :)${newdirs/#/rulesets\/}}. Add a section to README.md."
fi
