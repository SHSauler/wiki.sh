#!/bin/bash

# Read wiki articles in your favorite text editor or via `less` or `more`.
# 2017-02 by Steffen Sauler

#### SETTINGS ####

DEBUG=0
PROTOCOL="https://"
LANG="en"
DOMAIN="wikipedia.org"
QUERY="/w/api.php?action=query&titles=ARTICLE&prop=revisions&rvprop=content&format=xml"

TMP_FOLDER="/tmp"

# By default files are cached under /tmp/wikish/articlename-lang-2017-02-11 
CACHE="${TMP_FOLDER}/wikish"

# Line width
WIDTH=100
#### /SETTINGS ####

USAGE=\
"\n wiki.sh articlename [OPTIONS]\n\n\
    OPTIONS\n\
        -l, --language  Wiki language, default 'en'; all valid country codes (e.g. 'fr', 'de' etc.)\n\
        -d, --debug     Debug mode\n\
        -n, --nocache   Disable article caching (not recommended)\n\
        -r, --raw       Display raw article instead of cleaned up one\n\
        -o, --onlydl    Only download, don't display. Useful to read cached article later\n\
        -n, --nofollow  Don't follow redirects automatically
        -w, --linewidth integer for line width (default: 100)"

debug()
{
    if [[ $DEBUG -eq 1 ]]
    then
        echo "$1"
    fi
}

if [ "$#" == "0" ]
then
    echo -e "$USAGE"
    exit 1
fi

# Get article name
if [ -z "$1" ]
then
    echo "No article name provided"
    exit 1
fi
ARTICLE=$1
shift

if [[ $ARTICLE == "random" || $ARTICLE == "r" ]]
then
    ARTICLE=$(curl -s "https://en.wikipedia.org/w/api.php?action=query&list=random&rnlimit=1&rnnamespace=0&format=xml" | grep -Po "(?<=title\=\").*?(?=\")")
fi

# Parse command line arguments
while [[ $# -gt 0 ]]
do
    key="$1"
    debug "Key is $key"

    case $key in
        -d|--debug)
        DEBUG=1
        shift
        ;;
        -n|--nocache)
        NO_CACHE=1
        shift
        ;;
        -r|--raw)
        RAW=1
        shift
        ;;
        -l|--language)
        LANG=$2
        shift 2
        ;;
        -n|--nofollow)
        NOFOLLOW=1
        ;;
        -o|--onlydl)
        ONLY_DL=1
        shift
        ;;
        -w|--linewidth)
        if [[ $2 =~ ^-?[0-9]+$ ]]; then WIDTH=$2; fi
        shift 2
        ;;
        *)
        echo -e "$USAGE"
        exit 1
        ;;
    esac
done


# Check if cache folder exists
if [ ! -d $CACHE ]
then
    debug "No cache folder '${CACHE}'. Creating."
    mkdir ${CACHE}
else
    debug "Cache folder '${CACHE}' exists."
fi


download_cmd()
{   
    if $(type wget 1>&2 2>/dev/null)
    then
        DL_CMD="wget -qO- ${URL} -O ${CACHE_FILE}"
        return
    fi
    
    if $(type curl 1>&2 2>/dev/null)
    then
        DL_CMD="curl ${URL} -o ${CACHE_FILE}"
        return
    fi
    
    echo "Neither curl nor wget available. Aborting"
    exit 1
}

cleanup()
{
    # Removal of all lines beginning with curly braces
    CONTENT=$(echo -e "${CONTENT}" | sed '/^{{.*/d')
    
    # Removal of renamed linked article
    #CONTENT=$(echo -e  "${CONTENT}" | sed 's/\[[a-zA-Z\s]*\|([a-zA-Z\s]*\)/\1/')
    
    # Removal of linked article
    CONTENT=$(echo -e "${CONTENT}" | sed 's#|\w+]]'##g)
    
    # Removal of [[ and ]]
    CONTENT=$(echo -e "${CONTENT}" | sed 's/\[\[//g' | sed 's/\]\]//g')
    
    # Replacement of multiple ''' by simple '
    CONTENT=$(echo -e "${CONTENT}" | sed "s/'''/'/g")
 
    # Replacement &quot; with ',  &lt; with <, &gt; with >
    CONTENT=$(echo -e "${CONTENT}" | sed "s/\&quot;/'/g" | sed "s/\&lt;/</g" | sed "s/\&gt;/>/g" )  
}

get_article()
{
    # Assemble download URL and cache file location
    # Escape space and apostrophe
    ESC_ARTICLE=${ARTICLE// /%20}
    ESC_ARTICLE=${ESC_ARTICLE//\'/%27}

    #Remove round brackets from filename
    ESC_FILENAME=$(echo "$ESC_ARTICLE" | sed 's/(//' | sed 's/)//')

    URL="${PROTOCOL}${LANG}.${DOMAIN}${QUERY/ARTICLE/$ESC_ARTICLE}"
    DATE=$(date +%Y-%m-%d)
    CACHE_FILE="${CACHE}/${ESC_FILENAME}-${LANG}-${DATE}"

    #DL_CMD will be overwritten by download_cmd()
    DL_CMD=''

    #Content of the article
    CONTENT=''

    # Download article if there's no cache file for today
    if [[ ! -e ${CACHE_FILE} || ${NO_CACHE} -eq 1 ]]
    then
        download_cmd
        debug "Downloading file with $DL_CMD"
        $DL_CMD
    else
        debug "Article already cached."
    fi
    
    CONTENT=$(cat -s "${CACHE_FILE}" | grep -Pazo "(?s)(?<=preserve\">).*?(?=<\/rev>)")
    debug "Content starts with ${CONTENT:0:10}"

}

get_article

# Redirect is sometimes written weirdly (e.g. REDIRect)
REDIRECT=$(echo "${CONTENT}" | grep -Paizo "(?s)(?<=REDIRECT \[\[).*?(?=\]\])")

if [[ ! -z "$REDIRECT" && "$REDIRECT" != " " ]]
then
    if [[ $NOFOLLOW -eq 1 ]]
    then
        debug "Manual redirect mode"
        read -p "Do you wish to be redirected to ${REDIRECT}?" yn
        case $yn in
            [Yy]* ) ARTICLE="$REDIRECT";get_article;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
        esac
    else
        debug "Automatic redirect to ${REDIRECT}"
        ARTICLE="$REDIRECT"
        get_article
    fi
fi

if [[ ! ${RAW} -eq 1 ]]
then
    cleanup
fi


if [[ ! ${ONLY_DL} -eq 1 ]]
then
    echo -e "You are reading article $ARTICLE from ${LANG}.${DOMAIN}"
    echo -e "#########################################################"
    echo -e "${CONTENT}\n" | fmt -w $WIDTH
fi
