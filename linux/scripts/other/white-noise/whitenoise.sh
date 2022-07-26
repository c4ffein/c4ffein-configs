#!/bin/bash


cd "$(dirname "$(readlink -f "$0")")"
. venv/bin/activate
./whitenoise.py
