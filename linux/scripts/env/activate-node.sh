if [ "${BASH_SOURCE-}" = "$0" ]; then
    echo "You must source this script: \$ source $0" >&2
    exit 33
fi

export PATH=$PATH:"$(realpath $(dirname ${BASH_SOURCE[0]}))"/.bin/
