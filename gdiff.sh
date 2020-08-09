#!/bin/sh

git diff --color=always $1 | less -r
