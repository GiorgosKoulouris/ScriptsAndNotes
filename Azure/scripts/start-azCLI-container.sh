#!/bin/bash

cd "$(dirname "$0")"

docker run -it --rm \
    --name az-cli \
    -v ${PWD}/scripts:/scripts \
    mcr.microsoft.com/azure-cli:latest
