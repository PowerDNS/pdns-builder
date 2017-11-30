#!/usr/bin/env bash
# Very simple template language

if [ "$1" = "" ]; then
    echo "USAGE: $0 <template-file>"
    echo 
    echo "Template syntax:"
    echo
    echo 'Lines can start with @INCLUDE, @EVAL or @EXEC for special processing:'
    echo '@INCLUDE foo.txt'
    echo '@EVAL My home dir is $HOME'
    echo '@EXEC uname -a'
    echo '@EXEC [ "$foo" = "bar" ] && include bar.txt'
    echo '@IF [ "$foo" = "bar" ]'
    echo 'This line is only printed if $foo = "bar" (cannot be nested)'
    echo '@ENDIF'
    echo 'Other lines are printed unchanged.'
    echo
    echo "Environment variables:"
    echo "  tmpl_debug:   If set, markers are printed around included files"
    echo "  tmpl_comment: Characters to use to start the marker comments (default: #)"
    echo "  tmpl_prefix:  Characters to start processing directives (default: @)"
    exit 1
fi

tmpl_comment=${tmpl_comment:-#}
tmpl_prefix=${tmpl_prefix:-@}

include() {
    [ "$tmpl_debug" != "" ] && echo "$tmpl_comment $1"
    local skip
    local line
    local condition
    ( cat "$1" && echo ) | while IFS= read -r line; do
        if [[ $line = ${tmpl_prefix}ENDIF* ]]; then
            skip=
            [ "$tmpl_debug" != "" ] && echo "$tmpl_comment $line"

        elif [ ! -z "$skip" ]; then
            # nothing, in IF that evaluated to false
            [ "$tmpl_debug" != "" ] && echo "$tmpl_comment     $line"
            

        elif [[ $line = ${tmpl_prefix}INCLUDE\ * ]]; then
            include=${line#* }
            include $include

        elif [[ $line = ${tmpl_prefix}EVAL\ * ]]; then
            line=${line#* }
            eval echo "\"$line\""
        
        elif [[ $line = ${tmpl_prefix}EXEC\ * ]]; then
            line=${line#* }
            eval "$line"
        
        elif [[ $line = ${tmpl_prefix}IF\ * ]]; then
            condition=${line#* }
            [ "$tmpl_debug" != "" ] && echo "$tmpl_comment $line"
            eval "$condition" || skip=1

        else
            echo "$line"
        fi
    done
    [ "$tmpl_debug" != "" ] && echo "$tmpl_comment /$1"
}

include "$1"
