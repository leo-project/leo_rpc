#!/bin/sh

make doc
rm -rf doc/rst && mkdir doc/rst

for Mod in leo_rpc \
           leo_rpc_client_conn \
           leo_rpc_client_manager \
           leo_rpc_client_utils \
           leo_rpc_protocol \
           leo_rpc_server \
           leo_rpc_server_listener
do
    read_file="doc/$Mod.html"
    write_file="doc/rst/$Mod.rst"

    pandoc --read=html --write=rst "$read_file" -o "$write_file"

    sed -ie "1,6d" "$write_file"
    sed -ie "1s/\Module //" "$write_file"
    LINE_1=`cat $write_file | wc -l`
    LINE_2=`expr $LINE_1 - 10`
    sed -ie "$LINE_2,\$d" "$write_file"
done
rm -rf doc/rst/*.rste
