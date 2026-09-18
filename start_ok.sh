#!/bin/bash
export OK_RECLAIM_DISABLE="1"
export OK_ALLOW_EXTERNAL="1"
#ok start -p 61894 --bind 0.0.0.0 --only server --idle-shutdown off
ok start -p 61894 --only server --idle-shutdown off
