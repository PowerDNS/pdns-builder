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
    echo 'This line is only printed if $foo = "bar"'
    echo '@ENDIF'
    echo 'Other lines are printed unchanged.'
    echo
    echo "Environment variables:"
    echo "  tmpl_debug:   If set, markers are printed around included files"
    echo "  tmpl_comment: Characters to use to start the marker comments (default: #)"
    echo "  tmpl_prefix:  Regexp to match processing directive prefixes (default: @)"
    exit 1
fi

tmpl_comment=${tmpl_comment:-#}
tmpl_prefix=${tmpl_prefix:-@}

include() {
    [ "$tmpl_debug" != "" ] && echo "$tmpl_comment $1"
    # Current level of @IF we are in
    local iflevel=0
    # Set to the @IF level that disabled the current block, if any
    local ifdisablelevel=0
    local line
    local condition
    ( cat "$1" && echo ) | while IFS= read -r line; do

        if [[ $line =~ ^${tmpl_prefix}\ *IF\ (.*) ]]; then
            [ "$tmpl_debug" != "" ] && echo "$tmpl_comment $line"
            iflevel=$((iflevel+1))
            if ! [ $ifdisablelevel -gt 0 ]; then
                # Only if not already in a disabled IF statement
                condition="${BASH_REMATCH[1]}"
                if ! eval "$condition" ; then
                    # Disabled at the current IF level
                    ifdisablelevel=$iflevel
                fi
            fi

        elif [[ $line =~ ^${tmpl_prefix}\ *ENDIF ]]; then
            [ "$tmpl_debug" != "" ] && echo "$tmpl_comment $line"
            if [ $iflevel = 0 ] ; then
                echo "ERROR: @ENDIF without matching @IF in file $1" > /dev/stderr
                exit 30
            fi
            iflevel=$((iflevel-1))
            if [ $ifdisablelevel -gt $iflevel ]; then
                # We left the IF block level that was disabled
                ifdisablelevel=0
            fi

        elif [ $ifdisablelevel -gt 0 ]; then
            # nothing, in IF that evaluated to false
            [ "$tmpl_debug" != "" ] && echo "$tmpl_comment     $line"
            

        elif [[ $line =~ ^${tmpl_prefix}\ *INCLUDE\ +([^ ]*) ]]; then
            include="${BASH_REMATCH[1]}"
            include $include

        elif [[ $line =~ ^${tmpl_prefix}\ *EVAL\ (.*) ]]; then
            line="${BASH_REMATCH[1]}"
            eval echo "\"$line\""
        
        elif [[ $line =~ ^${tmpl_prefix}\ *EXEC\ (.*) ]]; then
            line="${BASH_REMATCH[1]}"
            eval "$line"
        
        else
            echo "$line"
        fi
    
    done
    [ "$tmpl_debug" != "" ] && echo "$tmpl_comment /$1"
}

include "$1"

exit 0
