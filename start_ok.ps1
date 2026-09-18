#npm install -g @inkeep/open-knowledge
$env:OK_RECLAIM_DISABLE = "1"
$env:OK_ALLOW_EXTERNAL = "1"
ok start -p 61894 --bind 192.168.68.63 --only server --idle-shutdown off
#ok start -p 61894 --only server --idle-shutdown off
