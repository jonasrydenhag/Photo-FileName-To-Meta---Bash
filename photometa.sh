#!/bin/bash

overwriteOriginalFile=true
deleteTagsMode=false
forceUpdateTitle=false
forceUpdateDate=false
onlyUpdateTitle=false
onlyUpdateDate=false
updatedFiles=0
exiftoolPath="exiftool"


while getopts ":dkfp:-:" opt; do
    case $opt in
        d)
            deleteTagsMode=true
            ;;
        k)
            overwriteOriginalFile=false
            ;;
        f)
            forceUpdateTitle=true
            forceUpdateDate=true
            ;;
        p)
            exiftoolPath="${OPTARG}"
            ;;
        -)
            case "${OPTARG}" in
                title)
                    onlyUpdateTitle=true
                    ;;
                date)
                    onlyUpdateDate=true
                    ;;
                *)
                    if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                        echo "Unknown option --${OPTARG}" >&2
                    fi
                    ;;
            esac;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done
shift $(( OPTIND - 1 ))

command -v $exiftoolPath >/dev/null 2>&1 || { echo >&2 "Requires exiftool but it's not installed.  Aborting."; exit 1; }

if [ -z "$@" ]
then
    echo "Please provide path" >&2
    exit 1
fi
path=$@

function start {
    local f=

    report $path;
    if [[ -d $path ]]; then
        #@todo Find real recursive method
        for f in "$path"/* "$path"/**/* "$path"/**/**/* "$path"/**/**/**/* "$path"/**/**/**/**/*; do
            if [ -f "$f" ]
            then
                local files=("${files[@]}" "$f")
            elif ! [[ -d $path ]]; then
                report "$f is not a file, skipped"
            fi
        done
    elif [[ -f $path ]]; then
        local files=("${files[@]}" "$path")
    else
        echo "$path is not valid"
        exit 1
    fi
    
    processFiles "${files[@]}"

    if [[ -n "${haveTitle[@]}" ]] && [ ${#haveTitle[@]} -ne 0 ]
    then
        report "$(getFileStr ${#haveTitle[@]}) already have a title. Do you want to overwrite [yes or no]: "
        read yno
        case $yno in

            [yY] | [yY][Ee][Ss] )
                onlyUpdateTitle=true
                forceUpdateTitle=true
                processFiles "${haveTitle[@]}"
                onlyUpdateTitle=false
                forceUpdateTitle=false
                ;;

            [nN] | [nN][Oo] )
                ;;
            *) echo "Invalid input, not overwriting."
                ;;
        esac
    fi

    if [[ -n "${haveDate[@]}" ]] && [ ${#haveDate[@]} -ne 0 ]
    then
        report "$(getFileStr ${#haveDate[@]}) already have a date. Do you want to overwrite [yes or no]: "
        read yno
        case $yno in

            [yY] | [yY][Ee][Ss] )
                onlyUpdateDate=true
                forceUpdateDate=true
                processFiles "${haveDate[@]}"
                onlyUpdateDate=false
                forceUpdateDate=false
                ;;

            [nN] | [nN][Oo] )
                ;;
            *) echo "Invalid input, not overwriting."
                ;;
        esac
    fi
}

function processFiles {
    updatedFiles=0
    local files=("${@}")
    local f=

    for f in "${files[@]}"; do
        processFile "$f"
    done

    report "-----------------------------------"
    report "$(getFileStr $updatedFiles) updated"
    report ""
}

function getFileStr {
    local nrOfFiles=$1
    if [ $nrOfFiles = 1 ]
    then
        echo "$nrOfFiles file"
    else
        echo "$nrOfFiles files"
    fi
}


function processFile {
    local filePath=$1

    filetype=$(file -b "$filePath")
    if [ "${filetype:0:4}" == "JPEG" ] || [ "${filetype:0:3}" == "GIF" ] || [ "${filetype:0:4}" == "TIFF" ]
    then
        if [ "$deleteTagsMode" = true ]
        then
            deleteTags "$filePath"
        else
            writeTags "$filePath"
        fi
    else
        report "$filePath is not a JPEG, GIF or TIFF file, skipped"
    fi
}

function deleteTags {
    local filePath=$1
    local overwriteCmd=
    if [ "$overwriteOriginalFile" = true ]
    then
        overwriteCmd="-overwrite_original"
    fi

    local result=$("$exiftoolPath" "$overwriteCmd" -title= -dateTimeOriginal= "$filePath" 2>&1)

    if ! [[ "$result" == *"1 image files updated"* ]]
    then
        report "$result"
    fi

    ((updatedFiles++))
}

function writeTags {
    local filePath=$1
    local fileName=$(basename "$filePath")
    local fullTitle=${fileName%%.*}
    local titleOption=
    local writeTitle=false
    local dateOption=
    local writeDate=false

    # Get update title cmd
    if ! $onlyUpdateDate
    then
        if ! $forceUpdateTitle
        then
            local existingTitle="$($exiftoolPath -m -title "$filePath")"
            if [ -z "$existingTitle" ]
            then
                writeTitle=true
            else
                haveTitle=("${haveTitle[@]}" "$filePath")
            fi
        else
            writeTitle=true
        fi

        if $writeTitle
        then
            titleOption=$(getTitleOption "$fullTitle")
        fi
    fi


    # Get update date cmd
    if ! $onlyUpdateTitle
    then
        if ! $forceUpdateDate
        then
            local existingDate="$($exiftoolPath -m -dateTimeOriginal "$filePath")"
            if [ -z "$existingDate" ]
            then
                writeDate=true
            else
                haveDate=("${haveDate[@]}" "$filePath")
            fi
        else
            writeDate=true
        fi

        if $writeDate
        then
            dateOption=$(getDateOption "$fileName")
        fi
    fi


    # Report exceptions
    if ! $writeTitle || ! $writeDate
    then
        if ! $writeTitle && ! $writeDate && ! $onlyUpdateTitle && ! $onlyUpdateDate
        then
            report "-- $fileName already has a title and a datestamp, existing data kept."
            report "$existingTitle"
            report "$existingDate"
        # Don't out put this message about the title if the user is only updating the date
        elif ! $writeTitle && ! $onlyUpdateDate
        then
            report "-- $fileName already has a title, existing title kept."
            report "$existingTitle"
        # Don't out put this message about the date if the user is only updating the title
        elif ! $writeDate && ! $onlyUpdateTitle
        then
            report "-- $fileName already has a datestamp, existing date kept."
            report "$existingDate"
        fi
    fi

    # Update tags
    if [ -n "$titleOption" ] || [ -n "$dateOption" ]
    then
        local overwriteCmd=
        if [ $overwriteOriginalFile ]
        then
            overwriteCmd="-overwrite_original"
        fi

        ((updatedFiles++))

        if [ -n "$titleOption" ] && [ -n "$dateOption" ]
        then
            local result=$($exiftoolPath "$overwriteCmd" "$titleOption" "$dateOption" "$filePath" 2>&1)
            report "${updatedFiles}. $fileName - Title and Date updated"
        elif [ -n "$titleOption" ]
        then
            local result=$($exiftoolPath "$overwriteCmd" "$titleOption" "$filePath" 2>&1)
            report "${updatedFiles}. $fileName - Title updated"
        elif [ -n "$dateOption" ]
        then
            local result=$($exiftoolPath "$overwriteCmd" "$dateOption" "$filePath" 2>&1)
            report "${updatedFiles}. $fileName - Date updated"
        fi

        if ! [[ "$result" == *"1 image files updated"* ]]
        then
            report "$result"
        fi
    fi
}

function getTitleOption {
    local fullTitle=$1
    echo "-title="$fullTitle""
}

function getDateOption {
    local filename=$1
    local date=$(getDate "$filename")
    if [ -n "$date" ]
    then
        echo "-dateTimeOriginal="$date""
    else
        report "!! $filename doesnt have a valid date in the filename"
    fi
}

function getDate {
    local fileName=$1
    local fullDate=$(echo "$fileName" | grep -o "[0-9][0-9?][0-9?][0-9?]-[0-1?][0-9?]-[0-3?][0-9?]-*[0-9]*[0-9]*")
    if [ -n "$fullDate" ]
    then
        echo "$(getYear $fullDate)-$(getMonth $fullDate)-$(getDay $fullDate) 00:00:$(getAdditional $fullDate)" 
    fi
}

function getYear {
    local fullDate=$1
    local yearCand=${fullDate:0:4}

    if isUnknown "$yearCand" 0
    then
        yearCand=$(echo "$yearCand" | sed s/./1/1)
    fi
    if isUnknown "$yearCand" 1
    then
        yearCand=$(echo "$yearCand" | sed s/./9/2)
    fi
    if isUnknown "$yearCand" 2
    then
        yearCand=$(echo "$yearCand" | sed s/./0/3)
    fi
    if isUnknown "$yearCand" 3
    then
        yearCand=$(echo "$yearCand" | sed s/./0/4)
    fi

    echo "$yearCand"
}

function getMonth {
    local fullDate=$1
    local monthCand=${fullDate:5:2}

    if isUnknown "$monthCand" 0
    then
        monthCand=$(echo "$monthCand" | sed s/./0/1)
    fi
    if isUnknown "$monthCand" 1
    then
        monthCand=$(echo "$monthCand" | sed s/./1/2)
    elif [ ${monthCand:1:1} == "0" ]
    then
        monthCand=$(echo "$monthCand" | sed s/./1/2)
    fi

    echo "$monthCand"
}

function getDay {
    local fullDate=$1
    local dayCand=${fullDate:8:2}

    if isUnknown "$dayCand" 0
    then
        dayCand=$(echo "$dayCand" | sed s/./0/1)
    fi
    if isUnknown "$dayCand" 1
    then
        dayCand=$(echo "$dayCand" | sed s/./1/2)
    elif [ ${dayCand:1:1} == "0" ]
    then
        dayCand=$(echo "$dayCand" | sed s/./1/2)
    fi

    echo "$dayCand"
}

function getAdditional {
    local fullDate=$1
    local addCand=${fullDate:11:2}

    if [ -z "$addCand" ]
    then
        echo "00"
    else
        if isUnknown "$addCand" 0
        then
            addCand=$(echo "$addCand" | sed s/./0/1)
        fi
        if isUnknown "$addCand" 1
        then
            addCand=$(echo "$addCand" | sed s/./0/2)
        fi

        echo "$addCand"
    fi
}

function isUnknown {
    local sourceStr=$1
    local position=$2

    if [ ${sourceStr:$2:1} == "?" ]
    then
        return 0
    else
        return 1
    fi
}

function report {
    echo "$1" >&2
}

start
