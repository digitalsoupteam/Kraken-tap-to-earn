export APP_PASSWORD=123 REPLICATOR_PASSWORD=456 STORAGE_PASSWORD=789 
killall -9 tt tarantool
tt stop cluster 

rm -rf /opt/tt/var/
tt start cluster
sleep 1
echo 'fixture()' | tt connect cluster:router-a-001
tt log -n 20 cluster
tt connect cluster:router-a-001
