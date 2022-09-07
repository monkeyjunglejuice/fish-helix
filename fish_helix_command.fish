# FIXME this can't be called in sequence in general case,
# because of unsynchronized `commandline -f` and `commandline -C`

function fish_helix_command
    argparse 'h/help' -- $argv
    or return 1
    if test -n "$_flag_help"
        echo "Helper function to handle modal key bindings mostly outside of insert mode"
        return
    end

    # TODO only single command allowed really yet,
    #     because `commandline -f` queues actions, while `commandline -C` is immediate
    for command in $argv
        set -f count (fish_bind_count -r)

        switch $command
            case {move,extend}_char_left
                commandline -C (math max\(0, (commandline -C) - $count\))
                __fish_helix_extend_by_command $command
            case {move,extend}_char_right
                commandline -C (math (commandline -C) + $count)
                __fish_helix_extend_by_command $command

            case {move,extend}_{next,prev}_{long_,}word_{start,end}
                if string match -gr _long_ $command
                    set -f longword
                else
                    set -f longword '[:alnum:]_'
                end
                if string match -gr _next_ $command
                    set -f dir "1"
                else
                    set -f dir "-1"
                end
                __fish_helix_word_motion (string split : (string replace -r '_.*_' : $command)) \
                    $dir $count '[:space:]' $longword

            case goto_line_start
                commandline -f beginning-of-line
                __fish_helix_extend_by_mode
            case goto_line_end
                commandline -f end-of-line
                __fish_helix_extend_by_mode
            case goto_first_nonwhitespace
                commandline -f beginning-of-line forward-bigword backward-bigword
                __fish_helix_extend_by_mode

            case '*'
                echo "[fish-helix]" Unknown command $command >&2
        end
    end
end

function __fish_helix_extend_by_command -a piece
    if not string match -gr extend_ $piece
        commandline -f begin-selection
    end
end

function __fish_helix_extend_by_mode
    if test $fish_bind_mode = default
        commandline -f begin-selection
    end
end

function __fish_helix_char_category -a char
    set -f patterns $argv[2..-1]
    for index in (seq 1 (count $patterns))
        if test "$char" = \n
            echo N
            return
        end
        if test -z "$(echo "$char" | tr -d "$patterns[$index]")"
            echo $index
            return
        end
    end
    echo 0
end

function __fish_helix_word_motion -a mode side dir count
    set -f patterns $argv[5..-1]
    set -f buffer "$(commandline)"
    set -f cursor (math (commandline -C) + 1) # convert to `cut` format
    set -f char1
    set -f char2
    set -f category1
    set -f category2
    set -f begin_selection
    for i in (seq 1 $count)
        # skip starting newlines
        while test "$(echo "$buffer" | cut -zc(math max\(0, $cursor + $dir\)))" = \n
            set cursor (math $cursor + $dir)
        end

        set begin_selection $cursor

        set -l first yes
        while true
            test $cursor = 1 -a $dir = "-1"; and break
            set -l pair "$(echo "$buffer" | cut -zc$cursor,(math $cursor + $dir))"
            set char1 "$(echo "$pair" | cut -zc1)"
            set char2 "$(echo "$pair" | cut -zc2)"
            test "$char2" = ""; and break

            set category1 (__fish_helix_char_category "$char1" $patterns)
            set category2 (__fish_helix_char_category "$char2" $patterns)

            if test $side = start
                set -f my_cat $category2
            else
                set -f my_cat $category1
            end
            if test $category1 != $category2 -a $my_cat != 1
                if test -n $first
                    set begin_selection (math $cursor + $dir)
                else
                    break
                end
            end
            set cursor (math $cursor + $dir)
            set first ""
        end
    end

    if test $mode = move
        commandline -C (math $begin_selection - 1)
        commandline -f begin-selection

        for j in (seq $begin_selection (math $cursor - 1))
            commandline -f forward-char
        end
        for j in (seq $begin_selection -1 (math $cursor + 1))
            commandline -f backward-char
        end
    else
        commandline -C (math $cursor - $dir)
    end
end
